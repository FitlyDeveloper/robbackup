import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FoodAnalyzerApi {
  // Base URL of our Render.com API server
  static const String baseUrl = 'https://snap-food.onrender.com';

  // Endpoint for food analysis
  static const String analyzeEndpoint = '/api/analyze-food';

  // Method to analyze a food image
  static Future<Map<String, dynamic>> analyzeFoodImage(
      Uint8List imageBytes) async {
    try {
      // Convert image bytes to base64
      final String base64Image = base64Encode(imageBytes);
      final String dataUri = 'data:image/jpeg;base64,$base64Image';

      print('Calling API endpoint: $baseUrl$analyzeEndpoint');

      // Call our secure API endpoint
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
              'per_ingredient_breakdown': true,
              'nutrition_threshold': 0.4,
              'include_additional_nutrition': true,
              'include_vitamins_minerals': true,
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
      if (responseData.containsKey('success') &&
          responseData['success'] != true) {
        throw Exception('API error: ${responseData['error']}');
      }

      // Extract the data from the response
      Map<String, dynamic> data;
      if (responseData.containsKey('data') && responseData['data'] is Map) {
        data = Map<String, dynamic>.from(responseData['data']);
      } else {
        // If 'data' field is not present, use the entire response
        data = responseData;
      }

      // If we got here, confirm that we received the expected format
      print('API response format: ${data is Map ? 'Map' : 'Other type'}');
      if (data is Map) {
        print('Keys in data: ${data.keys.join(', ')}');

        // Log additional nutritional information when available
        if (data.containsKey('vitamins')) {
          print('Vitamins detected in API response: ${data['vitamins']}');
        }

        if (data.containsKey('minerals')) {
          print('Minerals detected in API response: ${data['minerals']}');
        }

        // Check for ingredient nutrients (new format)
        if (data.containsKey('ingredient_nutrients') &&
            data['ingredient_nutrients'] is List) {
          print(
              'Ingredients with nutrients detected: ${(data['ingredient_nutrients'] as List).length} ingredients');

          // Log the first ingredient as an example
          if ((data['ingredient_nutrients'] as List).isNotEmpty) {
            var firstIngredient = (data['ingredient_nutrients'] as List).first;
            print('Example ingredient structure: $firstIngredient');

            if (firstIngredient is Map &&
                firstIngredient.containsKey('nutrients')) {
              print(
                  'Nutrients in first ingredient: ${firstIngredient['nutrients']}');
            }
          }
        }
        // Check for ingredients (original format)
        else if (data.containsKey('ingredients') &&
            data['ingredients'] is List) {
          print(
              'Ingredients detected: ${(data['ingredients'] as List).length} ingredients');

          // Log the first ingredient as an example
          if ((data['ingredients'] as List).isNotEmpty) {
            var firstIngredient = (data['ingredients'] as List).first;
            print('Example ingredient structure: $firstIngredient');
          }
        }

        // Check for basic nutrition
        if (data.containsKey('calories')) {
          print('Basic nutrition detected: calories=${data['calories']}, ' +
              'protein=${data['protein']}, fat=${data['fat']}, carbs=${data['carbs']}');
        }
      }

      // Return the data directly
      return data;
    } catch (e) {
      print('Error analyzing food image: $e');
      rethrow;
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
