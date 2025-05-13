import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FoodAnalyzerApi {
  // Base URL of our Render.com API server
  static const String baseUrl = 'https://snap-food.onrender.com';

  // Endpoint for food analysis
  static const String analyzeEndpoint = '/api/analyze-food';

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

  // Method to analyze a food image
  static Future<Map<String, dynamic>> analyzeFoodImage(
      Uint8List imageBytes) async {
    try {
      // Convert image bytes to base64
      final String base64Image = base64Encode(imageBytes);
      final String dataUri = 'data:image/jpeg;base64,$base64Image';

      print('Calling API endpoint: $baseUrl$analyzeEndpoint');

      // Call our secure API endpoint with detailed nutritional requirements
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
              'include_additional_nutrition': true,
              'include_vitamins_minerals': true,
              'expected_nutrients': {
                'vitamins': vitaminUnits.keys.toList(),
                'minerals': mineralUnits.keys.toList(),
                'other': otherNutrientUnits.keys.toList(),
              },
              'nutrient_units': {
                'vitamins': vitaminUnits,
                'minerals': mineralUnits,
                'other': otherNutrientUnits,
              },
              'unit_requirements':
                  'strict', // Enforce using our specified units
              'nutrient_format':
                  'app_compatible', // Request app-compatible format
            }),
          )
          .timeout(const Duration(
              seconds:
                  180)); // Increased timeout to 3 minutes for render.com cold starts which can take 60-120+ seconds

      // Check for HTTP errors
      if (response.statusCode != 200) {
        print('API error: ${response.statusCode}, ${response.body}');
        throw Exception('Failed to analyze image: ${response.statusCode}');
      }

      // Parse the response
      final Map<String, dynamic> responseData = jsonDecode(response.body);

      // Check for API-level errors
      if (responseData['success'] != true) {
        throw Exception('API error: ${responseData['error']}');
      }

      // If we got here, confirm that we received the expected format
      print(
          'API response format: ${responseData['data'] is Map ? 'Map' : 'Other type'}');
      if (responseData['data'] is Map) {
        print('Keys in data: ${(responseData['data'] as Map).keys.join(', ')}');

        // Log additional nutritional information when available
        final data = responseData['data'] as Map<String, dynamic>;

        // Validate that nutrients match our expected units
        _validateNutrientUnits(data);
      }

      // Return the data
      return responseData['data'];
    } catch (e) {
      print('Error analyzing food image: $e');
      rethrow;
    }
  }

  // Helper method to validate that nutrients have correct units
  static void _validateNutrientUnits(Map<String, dynamic> data) {
    // Check vitamins
    if (data.containsKey('vitamins') && data['vitamins'] is Map) {
      print('Vitamins detected in API response - validating units');
      Map<String, dynamic> vitamins = data['vitamins'];

      // Check that vitamins use our expected units
      vitaminUnits.forEach((vitamin, expectedUnit) {
        if (vitamins.containsKey(vitamin)) {
          print('✓ $vitamin present in response');
          // Check if unit is included or needs to be added
          var value = vitamins[vitamin];
          if (value is num || value is String) {
            // Ensure value has unit attached
            vitamins[vitamin] = '$value $expectedUnit';
          }
        }
      });
    }

    // Check minerals
    if (data.containsKey('minerals') && data['minerals'] is Map) {
      print('Minerals detected in API response - validating units');
      Map<String, dynamic> minerals = data['minerals'];

      // Check that minerals use our expected units
      mineralUnits.forEach((mineral, expectedUnit) {
        if (minerals.containsKey(mineral)) {
          print('✓ $mineral present in response');
          // Check if unit is included or needs to be added
          var value = minerals[mineral];
          if (value is num || value is String) {
            // Ensure value has unit attached
            minerals[mineral] = '$value $expectedUnit';
          }
        }
      });
    }

    // Check other nutrients
    if (data.containsKey('other') && data['other'] is Map) {
      print('Other nutrients detected in API response - validating units');
      Map<String, dynamic> other = data['other'];

      // Check that other nutrients use our expected units
      otherNutrientUnits.forEach((nutrient, expectedUnit) {
        if (other.containsKey(nutrient)) {
          print('✓ $nutrient present in response');
          // Check if unit is included or needs to be added
          var value = other[nutrient];
          if (value is num || value is String) {
            // Ensure value has unit attached
            other[nutrient] = '$value $expectedUnit';
          }
        }
      });
    }
  }

  // Check if the API is available
  static Future<bool> checkApiAvailability() async {
    try {
      final response = await http
          .get(Uri.parse(baseUrl))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      print('API unavailable: $e');
      return false;
    }
  }
}
