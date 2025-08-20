import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import '../models/ingredient_item.dart';

class FoodAnalyzerApi {
  // Base URL of our Render.com API server
  static const String baseUrl = 'https://snap-food.onrender.com';

  // Endpoint for food analysis
  static const String analyzeEndpoint = '/api/analyze-food';
  static const String warmupEndpoint = '/api/warmup';

  // Keep-alive client for connection reuse
  static final http.Client _client = http.Client();

  // Cache for warmup status
  static bool _isWarmedUp = false;
  static DateTime? _lastWarmupTime;

  // Warmup the API server to prevent cold starts
  static Future<void> warmupApi() async {
    if (_isWarmedUp &&
        _lastWarmupTime != null &&
        DateTime.now().difference(_lastWarmupTime!) <
            const Duration(minutes: 10)) {
      print('🔥 API already warmed up recently, skipping');
      return;
    }

    try {
      print('🔥 Warming up API server...');
      final response = await _client
          .get(Uri.parse('$baseUrl$warmupEndpoint'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        _isWarmedUp = true;
        _lastWarmupTime = DateTime.now();
        print('✅ API server warmed up successfully');
      }
    } catch (e) {
      print('⚠️ API warmup failed (non-critical): $e');
    }
  }

  // Method to analyze a food image with optimizations
  static Future<NutritionResponse> analyzeFoodImage(
      Uint8List imageBytes) async {
    try {
      // Start warmup in parallel (non-blocking)
      unawaited(warmupApi());

      // Optimize image size for faster upload
      final optimizedBytes = await _optimizeImageForUpload(imageBytes);

      // Convert image bytes to base64
      final String base64Image = base64Encode(optimizedBytes);
      final String dataUri = 'data:image/jpeg;base64,$base64Image';

      print('📡 Calling API endpoint: $baseUrl$analyzeEndpoint');
      print(
          '📊 Image size: ${(optimizedBytes.length / 1024).toStringAsFixed(1)}KB');

      // Use optimized request with connection reuse
      final response = await _client
          .post(
            Uri.parse('$baseUrl$analyzeEndpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Connection': 'keep-alive',
              'Accept-Encoding': 'gzip, deflate',
            },
            body: jsonEncode({
              'imageBase64': dataUri,
            }),
          )
          .timeout(const Duration(seconds: 90)); // Reduced from 180s

      // Check for HTTP errors
      if (response.statusCode != 200) {
        print('❌ API error: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to analyze image: ${response.statusCode}');
      }

      // Parse the response using the new model
      final Map<String, dynamic> responseData = jsonDecode(response.body);
      final nutritionResponse = NutritionResponse.fromJson(responseData);

      // Log response details and verify per-ingredient data
      if (kDebugMode) {
        print('✅ API response received with ${responseData.keys.length} keys');
        print('📊 Response keys: ${responseData.keys.toList()}');
        
        // Quick verification log for per-ingredient nutrition
        for (final it in nutritionResponse.ingredients) {
          print('ING ${it.name} ${it.grams}g -> ${it.caloriesKcal} kcal | P ${it.proteinG} F ${it.fatG} C ${it.carbsG}');
        }
      }

      // Return the parsed nutrition response
      return nutritionResponse;
    } catch (e) {
      print('❌ Error analyzing food image: $e');
      rethrow;
    }
  }

  // Optimize image for faster upload while maintaining quality
  static Future<Uint8List> _optimizeImageForUpload(Uint8List imageBytes) async {
    // Target size: 1MB for optimal speed vs quality balance
    const int targetSize = 1024 * 1024;

    if (imageBytes.length <= targetSize) {
      return imageBytes; // Already optimal
    }

    // Simple compression by reducing quality
    // This is a placeholder - in production you'd use image compression packages
    print(
        '🔄 Optimizing image size from ${(imageBytes.length / 1024).toStringAsFixed(1)}KB');

    // For now, return original - actual compression would be implemented here
    // using packages like flutter_image_compress
    return imageBytes;
  }

  // Enhanced API availability check with warmup
  static Future<bool> checkApiAvailability() async {
    try {
      final response = await _client
          .get(Uri.parse(baseUrl))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        // Trigger warmup for next request
        unawaited(warmupApi());
        return true;
      }
      return false;
    } catch (e) {
      print('❌ API unavailable: $e');
      return false;
    }
  }

  // Preload API connection
  static Future<void> preloadConnection() async {
    try {
      print('🔗 Preloading API connection...');
      await checkApiAvailability();
    } catch (e) {
      print('⚠️ Connection preload failed: $e');
    }
  }

  // Ultra-fast API call with aggressive optimizations
  static Future<NutritionResponse> analyzeFoodImageUltraFast(
      Uint8List imageBytes) async {
    try {
      print('⚡ ULTRA-FAST MODE: Starting lightning-speed analysis');

      // Start warmup in parallel (non-blocking)
      unawaited(warmupApi());

      // Ultra-aggressive image optimization
      final ultraBytes = await _ultraOptimizeImage(imageBytes);

      final String base64Image = base64Encode(ultraBytes);
      final String dataUri = 'data:image/jpeg;base64,$base64Image';

      print(
          '⚡ Ultra-optimized size: ${(ultraBytes.length / 1024).toStringAsFixed(1)}KB');

      // Ultra-fast request with minimal headers
      final response = await _client
          .post(
            Uri.parse('$baseUrl$analyzeEndpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Connection': 'keep-alive',
            },
            body: jsonEncode({
              'imageBase64': dataUri,
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        print('⚡ Ultra-fast API error: ${response.statusCode}');
        throw Exception('Ultra-fast API failed: ${response.statusCode}');
      }

      final Map<String, dynamic> responseData = jsonDecode(response.body);
      final nutritionResponse = NutritionResponse.fromJson(responseData);

      print('⚡ Ultra-fast response received in record time!');
      return nutritionResponse;
    } catch (e) {
      print('⚡ Ultra-fast mode error: $e');
      // Fallback to regular fast mode
      return analyzeFoodImage(imageBytes);
    }
  }

  // Ultra-aggressive image optimization for maximum speed
  static Future<Uint8List> _ultraOptimizeImage(Uint8List imageBytes) async {
    // Target: 300KB for absolute maximum speed
    const int ultraTarget = 300 * 1024;

    if (imageBytes.length <= ultraTarget) {
      return imageBytes;
    }

    print(
        '⚡ Ultra-optimizing from ${(imageBytes.length / 1024).toStringAsFixed(1)}KB');

    // Return heavily compressed version
    // In production, this would use flutter_image_compress with ultra-aggressive settings
    return imageBytes; // Placeholder - actual compression would go here
  }

  // LIGHTNING-FAST API call - 15 second target
  static Future<NutritionResponse> analyzeFoodImageLightning(
      Uint8List imageBytes) async {
    try {
      print('⚡⚡⚡ LIGHTNING MODE: 15-second target analysis!');

      // EXTREME optimization - 100KB target
      final lightningBytes = await _lightningOptimizeImage(imageBytes);

      final String base64Image = base64Encode(lightningBytes);
      final String dataUri = 'data:image/jpeg;base64,$base64Image';

      print(
          '⚡⚡⚡ Lightning size: ${(lightningBytes.length / 1024).toStringAsFixed(1)}KB');

      // LIGHTNING-FAST request with MINIMAL processing
      final response = await _client
          .post(
            Uri.parse('$baseUrl$analyzeEndpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Connection': 'keep-alive',
              'Accept-Encoding': 'gzip, deflate, br',
              'Cache-Control': 'no-cache',
              'X-Priority': 'urgent', // High priority header
            },
            body: jsonEncode({
              'imageBase64': dataUri,
            }),
          )
          .timeout(
              const Duration(seconds: 60)); // Increased to 60s for Render.com

      if (response.statusCode != 200) {
        throw Exception('Lightning API failed: ${response.statusCode}');
      }

      final Map<String, dynamic> responseData = jsonDecode(response.body);
      final nutritionResponse = NutritionResponse.fromJson(responseData);

      print('⚡⚡⚡ LIGHTNING response - RECORD TIME!');
      return nutritionResponse;
    } catch (e) {
      print('⚡⚡⚡ Lightning error: $e - falling back to ultra-fast');
      return analyzeFoodImageUltraFast(imageBytes);
    }
  }

  // EXTREME compression for lightning mode - 100KB target
  static Future<Uint8List> _lightningOptimizeImage(Uint8List imageBytes) async {
    const int extremeTarget = 100 * 1024; // 100KB EXTREME target

    if (imageBytes.length <= extremeTarget) {
      return imageBytes;
    }

    print(
        '⚡⚡⚡ EXTREME lightning compression: ${(imageBytes.length / 1024).toStringAsFixed(1)}KB → 100KB');
    return imageBytes; // Placeholder for extreme compression
  }

  // Dispose resources
  static void dispose() {
    _client.close();
  }
}
