import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FoodAnalyzerApi {
  // Base URL of our Render.com API server
  static const String baseUrl = 'https://snap-food.onrender.com';

  // New endpoints for job-based architecture
  static const String jobsEndpoint = '/api/jobs';
  static const String jobStatusEndpoint = '/api/jobs/';

  // Legacy endpoint (kept for backward compatibility)
  static const String analyzeEndpoint = '/api/analyze-food';

  // Emergency client-side mode - set to false to use actual server
  static const bool EMERGENCY_CLIENT_MODE = false;

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

  // New method to analyze a food image using job queue
  static Future<Map<String, dynamic>> analyzeFoodImage(
      Uint8List imageBytes) async {
    // EMERGENCY CLIENT-SIDE MODE: Return hardcoded data immediately
    if (EMERGENCY_CLIENT_MODE) {
      throw Exception(
          'Emergency client mode is disabled - API analysis required');
    }

    try {
      // Convert image bytes to base64
      final String base64Image = base64Encode(imageBytes);
      final String dataUri = 'data:image/jpeg;base64,$base64Image';

      print('Submitting job to API endpoint: $baseUrl$jobsEndpoint');

      // Submit job to the queue
      final submitResponse = await http
          .post(
            Uri.parse('$baseUrl$jobsEndpoint'),
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
          .timeout(const Duration(seconds: 30));

      // Check for HTTP errors
      if (submitResponse.statusCode != 201) {
        print(
            'API job submission error: ${submitResponse.statusCode}, ${submitResponse.body}');

        // Try legacy endpoint as fallback
        print('Trying legacy endpoint as fallback...');
        final legacyResponse = await http
            .post(
              Uri.parse('$baseUrl$analyzeEndpoint'),
              headers: {
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'image': dataUri,
              }),
            )
            .timeout(const Duration(seconds: 30));

        if (legacyResponse.statusCode == 200) {
          try {
            final Map<String, dynamic> legacyData =
                jsonDecode(legacyResponse.body);
            if (legacyData['success'] == true && legacyData['data'] != null) {
              return legacyData['data'];
            }
          } catch (e) {
            print('Legacy endpoint JSON decode error: $e');
          }
        }

        // Throw error instead of returning emergency response
        throw Exception(
            'Failed to submit analysis job: ${submitResponse.statusCode}');
      }

      // Parse the job response
      final Map<String, dynamic> jobData;
      try {
        jobData = jsonDecode(submitResponse.body);
      } catch (e) {
        print('JSON decode error: $e');
        // Throw error instead of returning emergency response
        throw Exception('Invalid response format from server');
      }

      // Check for API-level errors
      if (jobData['success'] != true) {
        print('API reported error: ${jobData['error']}');
        // Throw error instead of returning emergency response
        throw Exception('API error: ${jobData['error']}');
      }

      // Get the jobId
      final String jobId = jobData['jobId'];
      print('Job submitted successfully, ID: $jobId');

      // Poll for job completion
      try {
        return await _pollForJobCompletion(jobId);
      } catch (e) {
        print('Error during job polling: $e');
        // Re-throw the error instead of returning emergency response
        throw Exception('Analysis failed: $e');
      }
    } catch (e) {
      print('Error analyzing food image: $e');
      // Re-throw the error instead of returning emergency response
      rethrow;
    }
  }

  // Poll for job completion
  static Future<Map<String, dynamic>> _pollForJobCompletion(
      String jobId) async {
    print('Polling for job completion: $jobId');

    final Completer<Map<String, dynamic>> completer = Completer();
    int attempts = 0;
    const maxAttempts = 30; // 30 attempts = 60 seconds max

    Timer.periodic(const Duration(seconds: 2), (timer) async {
      attempts++;

      try {
        // Query job status
        final statusResponse = await http.get(
          Uri.parse('$baseUrl$jobStatusEndpoint$jobId'),
          headers: {
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 10));

        if (statusResponse.statusCode != 200) {
          // Check if this is a 422 (job failed) - stop polling immediately
          if (statusResponse.statusCode == 422) {
            timer.cancel();
            print(
                "Stopped polling after $attempts attempts; job failed with status 422");

            // Try to parse the error response
            try {
              final errorData = jsonDecode(statusResponse.body);
              print('Job failed: ${errorData['error'] ?? "Unknown error"}');
              throw Exception(
                  'Analysis failed: ${errorData['error'] ?? "Unknown error"}');
            } catch (e) {
              print('Job failed but could not parse error response');
              throw Exception('Analysis failed with unknown error');
            }
          }

          print(
              'Job status check failed: ${statusResponse.statusCode}, ${statusResponse.body}');

          // If we've exceeded max attempts, stop and throw error
          if (attempts >= maxAttempts) {
            timer.cancel();
            print(
                "Stopped polling after $attempts attempts; status check failed");
            if (!completer.isCompleted) {
              completer.completeError(
                  Exception('Analysis timeout - status check failed'));
            }
          }
          return;
        }

        final Map<String, dynamic> statusData;
        try {
          statusData = jsonDecode(statusResponse.body);
        } catch (e) {
          print('JSON decode error in status check: $e');

          // If we've exceeded max attempts, stop and throw error
          if (attempts >= maxAttempts) {
            timer.cancel();
            print(
                "Stopped polling after $attempts attempts; JSON decode error");
            if (!completer.isCompleted) {
              completer.completeError(
                  Exception('Analysis timeout - JSON decode error'));
            }
          }
          return;
        }

        final String status = statusData['status'] ?? 'unknown';

        // If job is complete, return the data
        if (status == 'completed') {
          timer.cancel();
          print(
              "Stopped polling after $attempts attempts; final status: completed");

          // Make sure we have data
          if (statusData['data'] != null) {
            // Try to validate the data format
            try {
              final Map<String, dynamic> resultData = statusData['data'];

              // Validate basic structure
              if (!resultData.containsKey('meal_name') ||
                  !resultData.containsKey('ingredients')) {
                print('Invalid data format, missing required fields');
                if (!completer.isCompleted) {
                  completer.completeError(Exception(
                      'Invalid data format - missing required fields'));
                }
                return;
              }

              // If ingredients exists but is empty, use emergency data
              if (resultData['ingredients'] is List &&
                  (resultData['ingredients'] as List).isEmpty) {
                print('Empty ingredients list, using emergency data');
                if (!completer.isCompleted) {
                  completer.completeError(Exception(
                      'Empty ingredients list - using emergency data'));
                }
                return;
              }

              if (!completer.isCompleted) {
                completer.complete(resultData);
              }
              return;
            } catch (e) {
              print('Data validation failed: $e');
              if (!completer.isCompleted) {
                completer.completeError(Exception('Data validation failed'));
              }
              return;
            }
          } else {
            print('No data in completed job, using emergency response');
            if (!completer.isCompleted) {
              completer.completeError(Exception(
                  'No data in completed job - using emergency response'));
            }
            return;
          }
        }

        // If job failed, use emergency response
        if (status == 'failed' || status == 'error') {
          timer.cancel();
          print(
              "Stopped polling after $attempts attempts; final status: $status");
          print('Job failed: ${statusData['error'] ?? "Unknown error"}');

          if (!completer.isCompleted) {
            completer.completeError(Exception(
                'Job failed - ${statusData['error'] ?? "Unknown error"}'));
          }
          return;
        }

        // Job is still processing, report progress if available
        final int progress = statusData['progress'] ?? 0;
        final String message = statusData['message'] ?? 'Processing...';

        print(
            'Job in progress: $progress% - $message (attempt $attempts/$maxAttempts)');

        // If we've exceeded max attempts, stop and throw error
        if (attempts >= maxAttempts) {
          timer.cancel();
          print("Stopped polling after $attempts attempts; analysis timeout");
          if (!completer.isCompleted) {
            completer.completeError(
                Exception('Analysis timeout - max attempts reached'));
          }
        }
      } catch (e) {
        print('Error checking job status: $e');

        // If we've exceeded max attempts, stop and throw error
        if (attempts >= maxAttempts) {
          timer.cancel();
          print("Stopped polling after $attempts attempts; polling error");
          if (!completer.isCompleted) {
            completer
                .completeError(Exception('Analysis failed - polling error'));
          }
        }
      }
    });

    return completer.future;
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

  // Utility method for min (missing from Dart core)
  static int min(num a, num b) => a < b ? a.toInt() : b.toInt();
}
