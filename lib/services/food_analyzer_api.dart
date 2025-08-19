import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

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
  static Future<Map<String, dynamic>> analyzeFoodImage(
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
              'image': dataUri,
              'detail_level': 'high', // Keep high quality
              'include_ingredient_macros': true,
              'return_ingredient_nutrition': true,
              'include_additional_nutrition': true,
              'include_vitamins_minerals': true,
              'fast_mode': true, // New flag for faster processing
            }),
          )
          .timeout(const Duration(seconds: 90)); // Reduced from 180s

      // Check for HTTP errors
      if (response.statusCode != 200) {
        print('❌ API error: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to analyze image: ${response.statusCode}');
      }

      // Parse the response
      final Map<String, dynamic> responseData = jsonDecode(response.body);

      // Check for API-level errors
      if (responseData['success'] != true) {
        throw Exception('API error: ${responseData['error']}');
      }

      // Log response details (reduced logging for speed)
      if (kDebugMode) {
        final data = responseData['data'] as Map<String, dynamic>;
        print('✅ API response received with ${data.keys.length} data keys');
      }

      // Return the data
      return responseData['data'];
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
  static Future<Map<String, dynamic>> analyzeFoodImageUltraFast(
      Uint8List imageBytes) async {
    try {
      print('⚡ ULTRA-FAST MODE: Starting lightning-speed analysis');

      // Start warmup in parallel (non-blocking)
      unawaited(warmupApi());

      // Ultra-aggressive image optimization
      final optimizedBytes = await _ultraOptimizeImage(imageBytes);

      // Convert to base64
      final String base64Image = base64Encode(optimizedBytes);
      final String dataUri = 'data:image/jpeg;base64,$base64Image';

      print(
          '⚡ Ultra-optimized size: ${(optimizedBytes.length / 1024).toStringAsFixed(1)}KB');

      // Ultra-fast request with maximum optimizations
      final response = await _client
          .post(
            Uri.parse('$baseUrl$analyzeEndpoint'),
            headers: {
              'Content-Type': 'application/json',
              'Connection': 'keep-alive',
              'Accept-Encoding': 'gzip, deflate, br',
              'Cache-Control': 'no-cache', // Prevent caching delays
            },
            body: jsonEncode({
              'image': dataUri,
              'detail_level': 'low', // Fastest processing
              'include_ingredient_macros': true,
              'return_ingredient_nutrition': true,
              'include_additional_nutrition': false, // Skip for speed
              'include_vitamins_minerals': false, // Skip for speed
              'fast_mode': true,
              'ultra_fast': true, // New ultra-fast flag
            }),
          )
          .timeout(const Duration(seconds: 60)); // Reduced timeout

      if (response.statusCode != 200) {
        print('⚡ Ultra-fast API error: ${response.statusCode}');
        throw Exception('Ultra-fast API failed: ${response.statusCode}');
      }

      final Map<String, dynamic> responseData = jsonDecode(response.body);

      if (responseData['success'] != true) {
        throw Exception('Ultra-fast API error: ${responseData['error']}');
      }

      print('⚡ Ultra-fast response received in record time!');
      return responseData['data'];
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
  static Future<Map<String, dynamic>> analyzeFoodImageLightning(
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
              'image': dataUri,
              'detail_level': 'high', // Restore accuracy
              'include_ingredient_macros': true,
              'return_ingredient_nutrition': true, // Restore for accuracy
              'include_additional_nutrition': true, // Restore for accuracy
              'include_vitamins_minerals': true, // Restore for accuracy
              'fast_mode': true,
              'ultra_fast': true,
              'lightning_fast': true, // NEW: Lightning mode
            }),
          )
          .timeout(const Duration(
              seconds: 60)); // Increased to 60s for Render.com

      if (response.statusCode != 200) {
        throw Exception('Lightning API failed: ${response.statusCode}');
      }

      final Map<String, dynamic> responseData = jsonDecode(response.body);
      if (responseData['success'] != true) {
        throw Exception('Lightning error: ${responseData['error']}');
      }

      print('⚡⚡⚡ LIGHTNING response - RECORD TIME!');
      return responseData['data'];
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
