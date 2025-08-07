import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FoodAnalyzerApi {
  // Primary URL - try this first
  static const String primaryUrl = 'https://snap-food.onrender.com';

  // New endpoints for job-based architecture
  static const String jobsEndpoint = '/api/jobs';
  static const String jobStatusEndpoint = '/api/jobs/';

  // Legacy endpoint (kept for backward compatibility)
  static const String analyzeEndpoint = '/api/analyze-food';

  // No client-side emergency modes or alternate endpoints

  // Define vitamin units for API consistency
  static const Map<String, String> vitaminUnits = {
    'vitamin_a': 'mcg',
    'vitamin_c': 'mg',
    'vitamin_d': 'mcg',
    'vitamin_e': 'mg',
    'vitamin_k': 'mcg',
    'vitamin_b1': 'mg',
    'vitamin_b2': 'mg',
    'vitamin_b3': 'mg',
    'vitamin_b5': 'mg',
    'vitamin_b6': 'mg',
    'vitamin_b7': 'mcg',
    'vitamin_b9': 'mcg',
    'vitamin_b12': 'mcg',
  };

  // Define mineral units for API consistency
  static const Map<String, String> mineralUnits = {
    'calcium': 'mg',
    'chloride': 'mg',
    'chromium': 'mcg',
    'copper': 'mcg',
    'fluoride': 'mg',
    'iodine': 'mcg',
    'iron': 'mg',
    'magnesium': 'mg',
    'manganese': 'mg',
    'molybdenum': 'mcg',
    'phosphorus': 'mg',
    'potassium': 'mg',
    'selenium': 'mcg',
    'sodium': 'mg',
    'zinc': 'mg',
  };

  // Define other nutrient units for API consistency
  static const Map<String, String> otherNutrientUnits = {
    'fiber': 'g',
    'cholesterol': 'mg',
    'sugar': 'g',
    'saturated_fats': 'g',
    'omega_3': 'mg',
    'omega_6': 'g',
  };

  // Analyze a food image using only the primary API endpoint (no fallbacks)
  static Future<Map<String, dynamic>> analyzeFoodImage(
      Uint8List imageBytes) async {
    return await _tryAnalyzeWithEndpoint(primaryUrl, imageBytes);
  }

  // Helper method to try analysis with a specific endpoint
  static Future<Map<String, dynamic>> _tryAnalyzeWithEndpoint(
      String baseUrl, Uint8List imageBytes) async {
    try {
      // Convert image bytes to base64
      final String base64Image = base64Encode(imageBytes);
      final String dataUri = 'data:image/jpeg;base64,$base64Image';

      // Use the working /api/analyze-food endpoint directly
      final response = await http
          .post(
            Uri.parse('$baseUrl$analyzeEndpoint'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'image': dataUri,
              'detail_level': 'high',
              'include_ingredient_macros': true,
              'return_ingredient_nutrition': true,
            }),
          )
          .timeout(const Duration(seconds: 120));

      // Check for HTTP errors
      if (response.statusCode != 200) {
        throw Exception('Failed to analyze image: ${response.statusCode}');
      }

      // Parse the response
      final Map<String, dynamic> responseData;
      try {
        responseData = jsonDecode(response.body);
      } catch (e) {
        throw Exception('Invalid response format from server');
      }

      // Check for API-level errors
      if (responseData['success'] != true) {
        throw Exception('API error: ${responseData['error']}');
      }

      // Return the data directly (no job polling needed)
      final data = responseData['data'];
      if (data != null) {
        return data;
      } else {
        throw Exception('No data returned from API');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Job polling method removed - now using direct API endpoint

  // removed unused: _validateNutrientUnits
  // ignore: unused_element
  static void _validateNutrientUnits(Map<String, dynamic> data) {}

  // Check if the API is available
  static Future<bool> checkApiAvailability() async {
    try {
      final response = await http
          .get(Uri.parse(primaryUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return true;
      }
    } catch (e) {
      // swallow error and return false
    }
    return false;
  }

  // Utility method for min (missing from Dart core)
  static int min(num a, num b) => a < b ? a.toInt() : b.toInt();
}
