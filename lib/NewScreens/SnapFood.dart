import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart'
    as flutter_compress;
// Remove permission_handler temporarily
// import 'package:permission_handler/permission_handler.dart';

// Conditionally import dart:io only on non-web
import 'dart:io' if (dart.library.html) 'package:fitness_app/web_io_stub.dart';

// Import our web handling code
import 'web_impl.dart' if (dart.library.io) 'web_impl_stub.dart';

// Additional imports for mobile platforms
import 'web_image_compress_stub.dart' as img_compress;

// Conditionally import the image compress library
// We need to use a different approach to avoid conflicts
import 'image_compress.dart';

// Add import for our secure API service
import '../services/food_analyzer_api.dart';

// Import FoodCardOpen for navigation after analysis
import 'FoodCardOpen.dart';

class SnapFood extends StatefulWidget {
  const SnapFood({super.key});

  @override
  State<StatefulWidget> createState() => _SnapFoodState();
}

class _SnapFoodState extends State<SnapFood> {
  // Track the active button
  String _activeButton = 'Scan Food'; // Default active button
  bool _permissionsRequested = false;
  bool _isAnalyzing = false; // Track if analysis is in progress
  int _loadingDots = 0; // Add this to track loading animation state
  Timer? _dotsAnimationTimer;
  int _processingStep = 0; // Track which processing step to show
  int _dotCycles = 0; // Track how many dot cycles have completed
  List<int> _cycleThresholds = []; // Dynamic thresholds for step changes

  // Processing step messages to cycle through
  final List<String> _processingSteps = [
    "Reading Image",
    "Identifying Food Type",
    "Detecting Ingredients",
    "Estimating Portion Size",
    "Calculating Calories & Macros",
    "Analyzing Vitamins & Minerals",
    "Cross-checking with Nutrition Database",
    "Finalizing Meal Summary"
  ];

  // Food analysis result
  Map<String, dynamic>? _analysisResult;
  String? _formattedAnalysisResult;

  // Image related variables
  File? _imageFile;
  String? _webImagePath;
  Uint8List? _webImageBytes; // Add storage for web image bytes
  final ImagePicker _picker = ImagePicker();
  XFile? imageFile;
  XFile? _mostRecentImage;
  bool _pendingAnalysis = false;

  @override
  void initState() {
    super.initState();

    // Start animation timer
    _dotsAnimationTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {
          _loadingDots = (_loadingDots + 1) % 4;
          _dotCycles++;

          // Change processing step based on thresholds
          final thresholds = _generateStepThresholds();
          for (int i = 0; i < thresholds.length; i++) {
            if (_dotCycles == thresholds[i]) {
              _processingStep = (i + 1) % _processingSteps.length;
            }
          }
        });
      }
    });

    // Call the test function during development to verify parsing works
    _testNewApiFormatParsing();

    if (!kIsWeb) {
      // Simplified permission check - no permission_handler
      _checkPermissionsSimple();
    }
  }

  // Simplified permission check method that doesn't use permission_handler
  Future<void> _checkPermissionsSimple() async {
    if (kIsWeb) return; // Skip permission checks on web

    // For simplicity, we'll just try to use the image picker which will trigger permission prompts
    try {
      await _picker.pickImage(source: ImageSource.camera).then((_) => null);
    } catch (e) {
      if (mounted) {
        _showPermissionsDialog();
      }
    }
  }

  void _showPermissionsDialog() {
    _showCustomDialog("Permission Required",
        "Camera permission is needed to take pictures. Please grant permission in your device settings.");
  }

  Future<void> _requestCameraPermission() async {
    // This will trigger the actual iOS system permission dialog for camera
    try {
      // Just check availability, don't actually pick
      await _picker
          .pickImage(source: ImageSource.camera)
          .then((_) => _requestPhotoLibraryPermission());
    } catch (e) {
      _requestPhotoLibraryPermission();
    }
  }

  Future<void> _requestPhotoLibraryPermission() async {
    // This will trigger the actual iOS system permission dialog for photo library
    try {
      // Just check availability, don't actually pick
      await _picker.pickImage(source: ImageSource.gallery);
    } catch (e) {}
  }

  // Local fallback for image analysis when Firebase isn't working
  Future<Map<String, dynamic>> _analyzeImageLocally(
      Uint8List imageBytes) async {
    // This is a local fallback that doesn't require any Firebase connection
    // It returns mock data similar to what the real function would return

    // Simulate a processing delay
    await Future.delayed(Duration(seconds: 1));

    // Return mock food analysis data
    return {
      "success": true,
      "meal": [
        {
          "dish": "Local Analysis Result",
          "calories": 450,
          "macronutrients": {"protein": 25, "carbohydrates": 45, "fat": 18},
          "ingredients": [
            "This is a local analysis",
            "Firebase functions deployment had issues",
            "This is a fallback implementation",
            "Image size: ${imageBytes.length} bytes"
          ]
        }
      ]
    };
  }

  // Modify the _analyzeImage method to keep isAnalyzing true until redirection
  Future<void> _analyzeImage(XFile? image) async {
    if (_isAnalyzing || image == null) return;

    setState(() {
      _isAnalyzing = true;
      _processingStep = 0; // Reset to first step
      _dotCycles = 0; // Reset dot cycle counter
      _cycleThresholds =
          _generateCycleThresholds(); // Generate new random thresholds
    });

    // Start a timer to show a "still working" message after 90 seconds
    Timer? processingTimer = Timer(Duration(seconds: 90), () {
      if (mounted && _isAnalyzing) {
        setState(() {
          // Force the final step after 90 seconds of processing
          _processingStep = _processingSteps.length - 1;
        });
      }
    });

    try {
      Uint8List imageBytes;

      // Get bytes from the image - do this once and reuse
      if (kIsWeb && _webImageBytes != null) {
        // For web, use the bytes we already have
        imageBytes = _webImageBytes!;
      } else {
        // Read as bytes from the file
        imageBytes = await image.readAsBytes();
      }

      // Get image size in MB for logging
      final double originalSizeMB = imageBytes.length / (1024 * 1024);

      // Process image - compressImage now handles the target size of 0.7MB automatically
      Uint8List processedBytes;
      try {
        // Use our image compression function that targets 0.7MB for large images
        processedBytes = await compressImage(
          imageBytes,
          targetWidth: 1200, // Use a reasonable width that preserves details
        );

        final double compressedSizeMB = processedBytes.length / (1024 * 1024);
      } catch (e) {
        // Fall back to original bytes if compression fails
        processedBytes = imageBytes;
      }

      try {
        // Use our secure API service via Firebase
        final response = await FoodAnalyzerApi.analyzeFoodImage(processedBytes);

        // Cancel the processing timer as we got a response
        processingTimer.cancel();
        processingTimer = null;

        if (mounted) {
          setState(() {
            _analysisResult = response;
          });

          // Extract the food name from the response for scanId generation
          String foodName = '';
          if (response.containsKey('meal_name')) {
            foodName = response['meal_name'];
          } else if (response.containsKey('success') &&
              response['success'] == true &&
              response['meal'] is List &&
              response['meal'].isNotEmpty) {
            foodName = response['meal'][0]['dish'] ?? '';
          } else if (response.containsKey('food_name')) {
            foodName = response['food_name'];
          } else if (response.containsKey('name')) {
            foodName = response['name'];
          }

          // Generate a consistent scanId
          String scanId = _generateScanId(foodName);

          // Display the formatted results and navigate with the scanId
          _displayAnalysisResults(response, scanId);
        }
      } catch (e) {
        // Cancel the processing timer
        if (processingTimer != null) {
          processingTimer.cancel();
          processingTimer = null;
        }

        // Show an error dialog and go back to codia_page
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
          });

          // Show a more helpful error message based on the error type
          String errorMessage;
          if (e.toString().contains("TimeoutException")) {
            errorMessage =
                "The server is taking longer than expected to respond. This usually happens when the server is starting up after being idle. Please try again in a few minutes when the server is ready.";
          } else {
            errorMessage =
                "We couldn't analyze your food image. Please try again with a clearer photo or check your internet connection.";
          }

          // Show error dialog
          _showCustomDialog("Analysis Taking Too Long", errorMessage);

          // Pop back to codia_page
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      // Cancel the processing timer
      if (processingTimer != null) {
        processingTimer.cancel();
        processingTimer = null;
      }

      // Show error dialog
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });

        _showCustomDialog("Analysis Error",
            "We couldn't process your food image. Please try again with a clearer photo.");

        // Pop back to codia_page
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        // Disable video selection by using pickImage not pickVideo
        // Note: ImagePicker.pickImage already only selects images
      );

      if (pickedFile != null) {
        if (mounted) {
          if (kIsWeb) {
            // For web platform, read the bytes first
            final bytes = await pickedFile.readAsBytes();

            // Check file size - 15MB maximum
            if (bytes.length > 15 * 1024 * 1024) {
              _showCustomDialog("File Too Large",
                  "Image must be less than 15MB. Please select a smaller image.");
              return;
            }

            // Update state with both path and bytes
            setState(() {
              _webImagePath = pickedFile.path;
              _webImageBytes = bytes;
              _imageFile = null;
              _mostRecentImage = pickedFile;
            });

            // Only analyze after we have the bytes
            _analyzeImage(pickedFile);
          } else {
            // For mobile platforms
            final bytes = await pickedFile.readAsBytes();

            // Check file size - 15MB maximum
            if (bytes.length > 15 * 1024 * 1024) {
              _showCustomDialog("File Too Large",
                  "Image must be less than 15MB. Please select a smaller image.");
              return;
            }

            setState(() {
              _imageFile = File(pickedFile.path);
              _webImagePath = null;
              _webImageBytes = null;
              _mostRecentImage = pickedFile;
            });

            _analyzeImage(pickedFile);
          }
        }
      }
    } catch (e) {
      if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
        // For desktop or web
        _showUnsupportedPlatformDialog();
      }
    }
  }

  // Helper method to generate a consistent scanId
  String _generateScanId(String foodName) {
    // Normalize the food name - remove special characters, spaces, make lowercase
    final normalizedName = foodName.isEmpty
        ? 'analyzed_meal'
        : foodName
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]+'), '') // Remove special chars
            .replaceAll(RegExp(r'\s+'), '_'); // Replace spaces with underscores

    // Add timestamp for uniqueness
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    return '${normalizedName}_$timestamp';
  }

  Future<bool> _cameraOnly() async {
    try {
      await _checkPermissionsSimple();

      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxHeight: 1000,
        maxWidth: 1000,
        imageQuality: 85, // Improved compression to ensure smaller file sizes
      );

      if (photo != null) {
        setState(() {
          _mostRecentImage = photo;
        });

        // Analyze the image directly with the scanId generation happening inside _analyzeImage
        _analyzeImage(photo);
        return true;
      }
      return false;
    } catch (e) {
      if (mounted) {
        _showCustomDialog("Error", "Failed to access camera: ${e.toString()}");
      }
      return false;
    }
  }

  // Fix the _takePicture method to work properly with our new flow
  Future<void> _takePicture() async {
    try {
      // Check if camera is available using _cameraOnly method
      bool isCameraAvailable = await _cameraOnly();

      if (!isCameraAvailable) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });

      if (mounted) {
        _showCameraErrorDialog();
      }
    }
  }

  // Simplified version that doesn't use missing libraries
  Future<String?> _getBase64FromPath(String path) async {
    try {
      // For web platform
      if (kIsWeb) {
        if (_webImageBytes != null) {
          return base64Encode(_webImageBytes!);
        } else {
          // Try to load from path for web
          final response = await http.get(Uri.parse(path));
          if (response.statusCode == 200) {
            return base64Encode(response.bodyBytes);
          } else {
            throw Exception('Failed to load image from URL');
          }
        }
      }
      // For mobile platforms
      else {
        final file = File(path);
        final bytes = await file.readAsBytes();

        // Simple size check
        if (bytes.length > 700000) {
          // Use our image compression helper
          final Uint8List result = await _compressBytesConsistently(
            bytes,
            quality: 80,
            targetWidth: 800,
          );
          return base64Encode(result);
        }

        return base64Encode(bytes);
      }
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List> _compressImage(Uint8List imageBytes) async {
    try {
      final double imageSizeMB = imageBytes.length / (1024 * 1024);

      // Target size of 0.7MB
      final int targetSizeBytes = 716800; // 0.7MB in bytes

      // If already smaller than 0.7MB, keep original
      if (imageBytes.length <= targetSizeBytes) {
        return imageBytes;
      }

      // Compress to exactly 0.7MB
      final Uint8List compressedImage = await compressImage(
        imageBytes,
        targetWidth: 1200, // Initial width
        quality: 90, // Initial quality
      );

      return compressedImage;
    } catch (e) {
      return imageBytes; // Return original if compression fails
    }
  }

  void _displayAnalysisResults(
      Map<String, dynamic> analysisData, String scanId) {
    try {
      // Track if we've already handled navigation
      bool navigationHandled = false;

      print(
          'Processing analysis data format. Keys: ${analysisData.keys.join(', ')}');

      // NEW FORMAT with ingredient_nutrients breakdown
      if (analysisData.containsKey('ingredient_nutrients') &&
          analysisData['ingredient_nutrients'] is List) {
        print('Found ingredient_nutrients format');
        List<dynamic> ingredientNutrientsList =
            analysisData['ingredient_nutrients'];
        String mealName = analysisData['meal_name'] ?? "Analyzed Meal";

        // Aggregate nutrition totals across all ingredients
        Map<String, double> aggregatedNutrients = {};
        List<Map<String, dynamic>> ingredientsList = [];

        double totalCalories = 0;
        double totalProtein = 0;
        double totalFat = 0;
        double totalCarbs = 0;

        // Process each ingredient with its nutrition data
        for (var ingredient in ingredientNutrientsList) {
          if (ingredient is Map) {
            String name = ingredient['name'] ?? "Unknown Ingredient";
            Map<String, dynamic> nutrients = ingredient['nutrients'] is Map
                ? Map<String, dynamic>.from(ingredient['nutrients'])
                : {};

            // Extract basic macros for this ingredient
            double calories =
                _extractDecimalValue(ingredient['calories']?.toString() ?? "0");
            double protein = 0.0;
            double fat = 0.0;
            double carbs = 0.0;

            // Extract macros from nutrients object
            if (nutrients.containsKey('protein')) {
              protein = nutrients['protein'] is num
                  ? (nutrients['protein'] as num).toDouble()
                  : _extractDecimalValue(
                      nutrients['protein']?.toString() ?? "0");
            }

            if (nutrients.containsKey('fat')) {
              fat = nutrients['fat'] is num
                  ? (nutrients['fat'] as num).toDouble()
                  : _extractDecimalValue(nutrients['fat']?.toString() ?? "0");
            }

            if (nutrients.containsKey('carbs') ||
                nutrients.containsKey('carbohydrates')) {
              carbs = nutrients.containsKey('carbs')
                  ? (nutrients['carbs'] is num
                      ? (nutrients['carbs'] as num).toDouble()
                      : _extractDecimalValue(
                          nutrients['carbs']?.toString() ?? "0"))
                  : (nutrients['carbohydrates'] is num
                      ? (nutrients['carbohydrates'] as num).toDouble()
                      : _extractDecimalValue(
                          nutrients['carbohydrates']?.toString() ?? "0"));
            }

            // Add to totals
            totalCalories += calories;
            totalProtein += protein;
            totalFat += fat;
            totalCarbs += carbs;

            // Create ingredient data
            Map<String, dynamic> ingredientData = {
              'name': name,
              'amount': ingredient['amount']?.toString() ?? "30g",
              'calories': calories.toInt(),
              'protein': protein,
              'fat': fat,
              'carbs': carbs,
            };

            print(
                'Processed ingredient: $name, calories: $calories, protein: $protein, fat: $fat, carbs: $carbs');

            // Process micronutrients (vitamins/minerals/others)
            nutrients.forEach((nutrientName, value) {
              // Convert value to double if it's not already
              double nutrientValue = 0.0;
              if (value is String) {
                nutrientValue = double.tryParse(value) ?? 0.0;
              } else if (value is num) {
                nutrientValue = value.toDouble();
              }

              // Only include nutrients where value is >= 0.4
              if (nutrientValue >= 0.4) {
                // Add to the aggregated total
                aggregatedNutrients[nutrientName] =
                    (aggregatedNutrients[nutrientName] ?? 0.0) + nutrientValue;

                // Store in the terminal output for debugging
                print(
                    'Ingredient: $name, Nutrient: $nutrientName, Value: $nutrientValue');
              }
            });

            ingredientsList.add(ingredientData);
          }
        }

        print(
            'Aggregated totals: calories=$totalCalories, protein=$totalProtein, fat=$totalFat, carbs=$totalCarbs');

        // Extract health score if available
        String healthScore = analysisData['health_score']?.toString() ?? "5/10";

        // Create additionalNutrients map from aggregated nutrients
        Map<String, dynamic> additionalNutrients = {};
        aggregatedNutrients.forEach((key, value) {
          additionalNutrients[key] = value.toString();
        });

        // If top level nutrients exist, add them
        if (analysisData.containsKey('vitamins') &&
            analysisData['vitamins'] is Map) {
          Map<String, dynamic> vitamins =
              Map<String, dynamic>.from(analysisData['vitamins']);
          vitamins.forEach((key, value) {
            String normalizedKey = 'vitamin_${key.toLowerCase()}';
            if (value is num && value >= 0.4) {
              additionalNutrients[normalizedKey] = value.toString();
            }
          });
        }

        if (analysisData.containsKey('minerals') &&
            analysisData['minerals'] is Map) {
          Map<String, dynamic> minerals =
              Map<String, dynamic>.from(analysisData['minerals']);
          minerals.forEach((key, value) {
            if (value is num && value >= 0.4) {
              additionalNutrients[key.toLowerCase()] = value.toString();
            }
          });
        }

        // Save to FoodCardOpen and navigate
        _saveFoodCardData(
          mealName,
          ingredientsList.map((i) => i['name']).join(", "),
          totalCalories.toString(),
          totalProtein.toString(),
          totalFat.toString(),
          totalCarbs.toString(),
          ingredientsList,
          healthScore,
          scanId,
          additionalNutrients,
        );

        navigationHandled = true;
      }
      // ORIGINAL NEW FORMAT with per-ingredient breakdown
      else if (analysisData.containsKey('ingredients') &&
          analysisData['ingredients'] is List) {
        print('Found ingredients format');
        List<dynamic> ingredientsData = analysisData['ingredients'];
        String mealName = analysisData['meal_name'] ?? "Analyzed Meal";

        // Aggregate nutrition totals across all ingredients
        Map<String, double> aggregatedNutrients = {};
        List<Map<String, dynamic>> ingredientsList = [];

        // Use the top-level nutrition values if available
        double totalCalories = analysisData['calories'] is num
            ? (analysisData['calories'] as num).toDouble()
            : _extractDecimalValue(analysisData['calories']?.toString() ?? "0");
        double totalProtein = analysisData['protein'] is num
            ? (analysisData['protein'] as num).toDouble()
            : _extractDecimalValue(analysisData['protein']?.toString() ?? "0");
        double totalFat = analysisData['fat'] is num
            ? (analysisData['fat'] as num).toDouble()
            : _extractDecimalValue(analysisData['fat']?.toString() ?? "0");
        double totalCarbs = analysisData['carbs'] is num
            ? (analysisData['carbs'] as num).toDouble()
            : _extractDecimalValue(analysisData['carbs']?.toString() ?? "0");

        print(
            'Using top-level nutrition: calories=$totalCalories, protein=$totalProtein, fat=$totalFat, carbs=$totalCarbs');

        // If nutrition values are still 0, try to aggregate from ingredients
        if (totalCalories == 0 &&
            totalProtein == 0 &&
            totalFat == 0 &&
            totalCarbs == 0) {
          print('Top-level nutrition is zero, aggregating from ingredients');
          // Process each ingredient with its nutrition data
          for (var ingredient in ingredientsData) {
            if (ingredient is String) {
              // Handle string format (e.g., "Pasta (100g) 200kcal")
              final parts = ingredient.split(' ');
              String name = parts.isNotEmpty ? parts[0] : "Unknown";
              String amount = parts.length > 1
                  ? parts[1].replaceAll('(', '').replaceAll(')', '')
                  : "30g";
              int calories =
                  parts.length > 2 ? _extractNumericValueAsInt(parts[2]) : 0;

              // Add to the total
              totalCalories += calories.toDouble();

              // Create ingredient data with default values
              Map<String, dynamic> ingredientData = {
                'name': name,
                'amount': amount,
                'calories': calories,
                'protein': 0.0, // Default values
                'fat': 0.0,
                'carbs': 0.0
              };

              ingredientsList.add(ingredientData);
            } else if (ingredient is Map) {
              // Process structured ingredient data
              String name = ingredient['name'] ?? "Unknown Ingredient";
              double calories = _extractDecimalValue(
                  ingredient['calories']?.toString() ?? "0");
              double protein = _extractDecimalValue(
                  ingredient['protein']?.toString() ?? "0");
              double fat =
                  _extractDecimalValue(ingredient['fat']?.toString() ?? "0");
              double carbs = _extractDecimalValue(
                  ingredient['carbs']?.toString() ??
                      ingredient['carbohydrates']?.toString() ??
                      "0");

              // Add to totals
              totalCalories += calories;
              totalProtein += protein;
              totalFat += fat;
              totalCarbs += carbs;

              // Create ingredient data
              Map<String, dynamic> ingredientData = {
                'name': name,
                'amount': ingredient['amount']?.toString() ?? "30g",
                'calories': calories.toInt(),
                'protein': protein,
                'fat': fat,
                'carbs': carbs,
              };

              ingredientsList.add(ingredientData);
            }
          }
        } else {
          // Use the ingredients list from the response
          for (var ingredient in ingredientsData) {
            if (ingredient is String) {
              // Handle string format (e.g., "Pasta (100g) 200kcal")
              final parts = ingredient.split(' ');
              String name = parts.isNotEmpty ? parts[0] : "Unknown";
              String amount = parts.length > 1
                  ? parts[1].replaceAll('(', '').replaceAll(')', '')
                  : "30g";
              int calories =
                  parts.length > 2 ? _extractNumericValueAsInt(parts[2]) : 0;

              // Create ingredient data with default values
              Map<String, dynamic> ingredientData = {
                'name': name,
                'amount': amount,
                'calories': calories,
                'protein': 0.0,
                'fat': 0.0,
                'carbs': 0.0
              };

              ingredientsList.add(ingredientData);
            } else if (ingredient is Map) {
              // Process structured ingredient data
              String name = ingredient['name'] ?? "Unknown Ingredient";

              Map<String, dynamic> ingredientData = {
                'name': name,
                'amount': ingredient['amount']?.toString() ?? "30g",
                'calories': _extractDecimalValue(
                        ingredient['calories']?.toString() ?? "0")
                    .toInt(),
                'protein': _extractDecimalValue(
                    ingredient['protein']?.toString() ?? "0"),
                'fat':
                    _extractDecimalValue(ingredient['fat']?.toString() ?? "0"),
                'carbs': _extractDecimalValue(ingredient['carbs']?.toString() ??
                    ingredient['carbohydrates']?.toString() ??
                    "0"),
              };

              ingredientsList.add(ingredientData);
            }
          }
        }

        // Get additional nutrients from all possible sources
        Map<String, dynamic> additionalNutrients =
            _extractAdditionalNutrients(analysisData);

        // Extract health score if available
        String healthScore = analysisData['health_score']?.toString() ?? "5/10";

        // Save to FoodCardOpen and navigate
        _saveFoodCardData(
          mealName,
          ingredientsList.map((i) => i['name']).join(", "),
          totalCalories.toString(),
          totalProtein.toString(),
          totalFat.toString(),
          totalCarbs.toString(),
          ingredientsList,
          healthScore,
          scanId,
          additionalNutrients,
        );

        navigationHandled = true;
      }

      // If we couldn't handle the new format, fall back to the old formats
      if (!navigationHandled) {
        print('Falling back to original format processing');
        // Direct extraction method
        double calories = analysisData['calories'] is num
            ? (analysisData['calories'] as num).toDouble()
            : _extractDecimalValue(analysisData['calories']?.toString() ?? "0");
        double protein = analysisData['protein'] is num
            ? (analysisData['protein'] as num).toDouble()
            : _extractDecimalValue(analysisData['protein']?.toString() ?? "0");
        double fat = analysisData['fat'] is num
            ? (analysisData['fat'] as num).toDouble()
            : _extractDecimalValue(analysisData['fat']?.toString() ?? "0");
        double carbs = analysisData['carbs'] is num
            ? (analysisData['carbs'] as num).toDouble()
            : _extractDecimalValue(analysisData['carbs']?.toString() ?? "0");

        String mealName = analysisData['meal_name'] ?? "Analyzed Meal";
        String healthScore = analysisData['health_score']?.toString() ?? "5/10";

        print(
            'Fallback nutrition: calories=$calories, protein=$protein, fat=$fat, carbs=$carbs');

        // Extract additional nutrients
        Map<String, dynamic> additionalNutrients =
            _extractAdditionalNutrients(analysisData);

        List<Map<String, dynamic>> ingredientsList = [];

        // Try to extract ingredients if available
        if (analysisData.containsKey('ingredients') &&
            analysisData['ingredients'] is List) {
          List<dynamic> ingredients = analysisData['ingredients'];
          for (var ingredient in ingredients) {
            if (ingredient is String) {
              final parts = ingredient.split(' ');
              String name = parts.isNotEmpty ? parts[0] : "Unknown";
              String amount = parts.length > 1
                  ? parts[1].replaceAll('(', '').replaceAll(')', '')
                  : "30g";
              int calories =
                  parts.length > 2 ? _extractNumericValueAsInt(parts[2]) : 0;

              ingredientsList.add({
                'name': name,
                'amount': amount,
                'calories': calories,
                'protein': 0.0,
                'fat': 0.0,
                'carbs': 0.0,
              });
            }
          }
        }

        // If no ingredients were found, create a default one
        if (ingredientsList.isEmpty) {
          ingredientsList.add({
            'name': "Mixed ingredients",
            'amount': "100g",
            'calories': calories.toInt(),
            'protein': protein,
            'fat': fat,
            'carbs': carbs,
          });
        }

        // Save and navigate
        _saveFoodCardData(
          mealName,
          ingredientsList.map((i) => i['name']).join(", "),
          calories.toString(),
          protein.toString(),
          fat.toString(),
          carbs.toString(),
          ingredientsList,
          healthScore,
          scanId,
          additionalNutrients,
        );
      }
    } catch (e) {
      print('Error processing analysis result: $e');
      // Error fallback
      if (mounted && _analysisResult != null) {
        Map<String, dynamic> additionalNutrients =
            _extractAdditionalNutrients(_analysisResult ?? {});

        _saveFoodCardData(
          "Analyzed Meal",
          "Mixed ingredients",
          "250",
          "15",
          "10",
          "30",
          [
            {
              'name': "Unidentified ingredient",
              'amount': "100g",
              'calories': 250,
              'protein': 15.0,
              'fat': 10.0,
              'carbs': 30.0,
            }
          ],
          "5/10",
          scanId,
          additionalNutrients,
        );
      }
    }
  }

  // Helper method to extract numeric value from a string, preserving decimal places
  String _extractNumericValue(String input) {
    // Use a pre-compiled RegExp for performance
    final numericRegex = RegExp(r'(\d+\.?\d*)');
    final match = numericRegex.firstMatch(input);
    if (match != null && match.group(1) != null) {
      return match.group(1)!;
    }
    return "0";
  }

  // Helper method to extract numeric value from a string and convert to int
  int _extractNumericValueAsInt(String input) {
    final numericRegex = RegExp(r'(\d+\.?\d*)');
    final match = numericRegex.firstMatch(input);
    if (match != null && match.group(1) != null) {
      final value = double.tryParse(match.group(1)!) ?? 0.0;
      return value.round();
    }
    return 0;
  }

  // Helper method to extract numeric value with decimal places from a string
  double _extractDecimalValue(String input) {
    final numericRegex = RegExp(r'(\d+\.?\d*)');
    final match = numericRegex.firstMatch(input);
    if (match != null && match.group(1) != null) {
      return double.tryParse(match.group(1)!) ?? 0.0;
    }
    return 0.0;
  }

  // Gets exact raw calorie value as integer
  int _getRawCalorieValue(double calories) {
    // Just convert to integer, no rounding to multiples
    return calories.toInt();
  }

  // Save food card data to SharedPreferences
  Future<void> _saveFoodCardData(
      String foodName,
      String ingredients,
      String calories,
      String protein,
      String fat,
      String carbs,
      List<Map<String, dynamic>> ingredientsList,
      [String healthScore = "5/10",
      String? scanId,
      Map<String, dynamic>? additionalNutrients]) async {
    // Use provided scanId or generate a new one as fallback
    final String finalScanId = scanId ??
        '${foodName.isEmpty ? 'analyzed_meal' : foodName.replaceAll(' ', '_').toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}';

    // Get the current image bytes - optimize this process to avoid multiple compressions
    Uint8List? compressedImage;
    String? base64Image;

    try {
      Uint8List? sourceBytes;

      // Get source bytes only once
      if (_webImageBytes != null) {
        sourceBytes = _webImageBytes;
      } else if (_webImagePath != null && kIsWeb) {
        try {
          sourceBytes = await getWebImageBytes(_webImagePath!);
        } catch (e) {}
      } else if (_imageFile != null && !kIsWeb) {
        try {
          sourceBytes = await _imageFile!.readAsBytes();
        } catch (e) {}
      }

      // Compress image for storage in a single operation
      if (sourceBytes != null) {
        try {
          // Higher compression ratio for storage
          compressedImage = await compressImage(
            sourceBytes,
            quality: 55, // Lower quality to save storage
            targetWidth: 250, // Smaller width for thumbnails
          );

          // Set base64 string for storage
          base64Image = base64Encode(compressedImage);
        } catch (e) {}
      }
    } catch (e) {}

    // Create food card data
    final Map<String, dynamic> foodCard = {
      'name': foodName.isNotEmpty ? foodName : 'Analyzed Meal',
      'calories': calories,
      'protein': protein,
      'fat': fat,
      'carbs': carbs,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'image': base64Image,
      'ingredients': ingredientsList,
      'health_score': healthScore,
      'scan_id': finalScanId, // Store scanId in the food card data
    };

    // Separate try block for storage operations
    try {
      // Load existing food cards
      final prefs = await SharedPreferences.getInstance();
      final List<String> storedCards = prefs.getStringList('food_cards') ?? [];

      // Add new food card as JSON
      storedCards.insert(0, jsonEncode(foodCard));

      // Limit to last 5 cards to prevent excessive storage (reduced from 10)
      if (storedCards.length > 5) {
        storedCards.removeRange(5, storedCards.length);
      }

      // Save updated list
      await prefs.setStringList('food_cards', storedCards);
    } catch (e) {}

    // Prepare display image in parallel with storage operations
    Uint8List? displayImageBytes;
    String? displayImageBase64;

    try {
      Uint8List? sourceBytes;

      // Reuse existing image data
      if (_webImageBytes != null) {
        sourceBytes = _webImageBytes;
      } else if (compressedImage != null) {
        // Use the already compressed image as a fallback
        displayImageBytes = compressedImage;
        displayImageBase64 = base64Image;
        sourceBytes = null; // Skip further processing
      }

      if (sourceBytes != null) {
        // Use moderate compression for display
        displayImageBytes = await compressImage(
          sourceBytes,
          quality: 70, // Better quality for display
          targetWidth: 800, // Reasonable size for display
        );

        displayImageBase64 = base64Encode(displayImageBytes);
      }
    } catch (e) {}

    // After saving, navigate to FoodCardOpen
    if (mounted) {
      try {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FoodCardOpen(
              foodName: foodName,
              healthScore: healthScore,
              calories: calories.toString(),
              protein: protein.toString(),
              fat: fat.toString(),
              carbs: carbs.toString(),
              imageBase64: displayImageBase64 ?? base64Image,
              ingredients: ingredientsList,
              additionalNutrients: additionalNutrients ??
                  _extractAdditionalNutrients(_analysisResult ?? {}),
              scanId: finalScanId, // Pass the scanId to FoodCardOpen
            ),
          ),
        ).then((_) {
          // Set _isAnalyzing to false only after returning from FoodCardOpen
          if (mounted) {
            setState(() {
              _isAnalyzing = false;
            });

            // Clean up large memory objects after navigation
            _webImageBytes = null;
            compressedImage = null;
            displayImageBytes = null;
          }
        });
      } catch (e) {
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  // Test the echo function to verify callable functions work
  Future<void> _testEchoFunction() async {
    // Function logic removed
  }

  // Test the simple image analyzer function
  Future<void> _testSimpleImageAnalyzer() async {
    // Function logic removed
  }

  // Test the per-ingredient nutrient breakdown and aggregation
  void _testIngredientNutrientsAggregation() {
    // Sample data similar to what we'd get from the API
    final sampleData = {
      'ingredients': [
        {
          'name': 'Rigatoni',
          'nutrients': {
            'Vitamin A': 0.5,
            'Iron': 0.7,
            'Calcium': 0.2, // Below threshold, should be excluded
          }
        },
        {
          'name': 'Cream Sauce',
          'nutrients': {
            'Vitamin D': 0.4,
            'Calcium': 1.2,
            'Vitamin A': 0.3, // Below threshold, should be excluded
          }
        }
      ]
    };

    // Process the sample data
    Map<String, double> aggregatedNutrients = {};

    // Loop through ingredients
    for (var ingredient in sampleData['ingredients'] as List) {
      final Map<String, dynamic> nutrients =
          ingredient['nutrients'] as Map<String, dynamic>;

      // Log the ingredient name
      print('Processing test ingredient: ${ingredient['name']}');

      // Process each nutrient in this ingredient
      nutrients.forEach((nutrientName, value) {
        double nutrientValue = 0.0;
        if (value is num) {
          nutrientValue = value.toDouble();
        } else if (value is String) {
          nutrientValue = double.tryParse(value) ?? 0.0;
        }

        // Only include nutrients where value is >= 0.4
        if (nutrientValue >= 0.4) {
          print('  - $nutrientName: $nutrientValue (included)');
          aggregatedNutrients[nutrientName] =
              (aggregatedNutrients[nutrientName] ?? 0.0) + nutrientValue;
        } else {
          print(
              '  - $nutrientName: $nutrientValue (excluded, below threshold)');
        }
      });
    }

    // Display the aggregated totals
    print('\nAggregated nutrient totals:');
    aggregatedNutrients.forEach((key, value) {
      print('$key: $value');
    });

    // Expected output:
    // Vitamin A: 0.5
    // Iron: 0.7
    // Vitamin D: 0.4
    // Calcium: 1.2
  }

  // Test the full nutrition analysis flow with the new API format
  Future<void> _testNewApiFormatParsing() async {
    print('---------- Testing New API Format Parsing ----------');

    // Sample data similar to what we'd get from the API with the new format
    final sampleData = {
      'meal_name': 'Test Fruit Bowl',
      'calories': 150,
      'protein': 2.5,
      'fat': 0.5,
      'carbs': 35.0,
      'health_score': '8/10',
      'ingredient_nutrients': [
        {
          'name': 'Watermelon',
          'amount': '150g',
          'calories': 45,
          'nutrients': {
            'protein': 0.9,
            'fat': 0.2,
            'carbs': 11.5,
            'vitamin_a': 865,
            'vitamin_c': 12.3,
            'potassium': 170
          }
        },
        {
          'name': 'Pineapple',
          'amount': '100g',
          'calories': 50,
          'nutrients': {
            'protein': 0.5,
            'fat': 0.1,
            'carbs': 13.1,
            'vitamin_c': 47.8,
            'manganese': 1.5,
            'fiber': 1.4
          }
        },
        {
          'name': 'Mango',
          'amount': '80g',
          'calories': 55,
          'nutrients': {
            'protein': 0.8,
            'fat': 0.2,
            'carbs': 14.0,
            'vitamin_a': 1260,
            'vitamin_c': 45.7,
            'folate': 43
          }
        }
      ],
      'vitamins': {
        'vitamin_a': 2125,
        'vitamin_c': 105.8,
        'vitamin_e': 0.8,
        'vitamin_k': 3.2
      },
      'minerals': {'potassium': 470, 'manganese': 1.8, 'magnesium': 24},
      'other': {'fiber': 3.8, 'sugar': 28.5}
    };

    // Process the sample data using our parsing function
    _displayAnalysisResults(
        sampleData, 'test_fruit_bowl_${DateTime.now().millisecondsSinceEpoch}');

    print('---------- Test Complete ----------');
  }

  @override
  Widget build(BuildContext context) {
    // Process pending analysis only once
    if (_pendingAnalysis && _mostRecentImage != null) {
      _pendingAnalysis = false;
      // Use Future.microtask to avoid blocking the UI thread
      Future.microtask(() => _analyzeImage(_mostRecentImage));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Background - either selected image or black background
            if (_hasImage)
              _buildBackgroundImage()
            else
              const SizedBox.expand(child: ColoredBox(color: Colors.black)),

            // Top corner frames as a group
            Positioned(
              top: 102, // Distance from gray circle (21+36+45=102)
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 29),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCornerFrame(topLeft: true),
                    _buildCornerFrame(topRight: true),
                  ],
                ),
              ),
            ),

            // Bottom corner frames as a group
            Positioned(
              bottom: 223, // Adjusted for 45px gap (109+69+45=223)
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 29),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCornerFrame(bottomLeft: true),
                    _buildCornerFrame(bottomRight: true),
                  ],
                ),
              ),
            ),

            // Back button with gray circle background
            Positioned(
              top: 21,
              left: 29,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back,
                        color: Colors.black, size: 24),
                  ),
                ),
              ),
            ),

            // Bottom action buttons (Scan Food, Scan Code, Add Photo)
            Positioned(
              bottom: 109,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 29),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Scan Food button
                    _buildActionButton(
                        'Scan Food', 'assets/images/foodscan.png'),

                    // Scan Code button
                    _buildActionButton(
                        'Scan Code', 'assets/images/qrcodescan.png'),

                    // Add Photo button
                    _buildActionButton(
                        'Add Photo', 'assets/images/addphoto.png',
                        leftPadding: 2.0),
                  ],
                ),
              ),
            ),

            // Shutter button area
            Positioned(
              bottom: 15,
              left: 29,
              right: 29,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Flash button
                  Padding(
                    padding: const EdgeInsets.only(right: 40),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Image.asset(
                        'assets/images/flashwhite.png',
                        width: 37,
                        height: 37,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),

                  // Shutter button
                  GestureDetector(
                    onTap: !_isAnalyzing
                        ? _cameraOnly
                        : null, // Disable when analyzing
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5.0),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Empty space to balance the layout
                  const SizedBox(width: 80),
                ],
              ),
            ),

            // Loading indicator while analyzing - moved to last position to cover all UI elements
            if (_isAnalyzing)
              Positioned.fill(
                child: Container(
                  color: Colors.black
                      .withOpacity(0.6), // Changed back to 60% opacity
                  child: AbsorbPointer(
                    // Added AbsorbPointer to block all touches
                    absorbing: true,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: 200,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      "Analyzing meal",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      _loadingDots > 0
                                          ? ".".padRight(_loadingDots, '.')
                                          : "",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _processingSteps[_processingStep],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Optimized action button builder
  Widget _buildActionButton(String buttonName, String imagePath,
      {double leftPadding = 0.0}) {
    return GestureDetector(
      onTap: !_isAnalyzing
          ? () => _setActiveButton(buttonName)
          : null, // Disable when analyzing
      child: Container(
        width: 99,
        height: 69,
        decoration: BoxDecoration(
          color: _activeButton == buttonName
              ? Colors.white
              : Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 8.0, left: leftPadding),
              child: Image.asset(
                imagePath,
                width: 31,
                height: 31,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              buttonName,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Optimized background image builder
  Widget _buildBackgroundImage() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: _getImageProvider(),
          fit: BoxFit.contain,
        ),
        color: Colors.black,
      ),
    );
  }

  // Get image provider based on available sources - optimized to cache and avoid unnecessary rebuilds
  ImageProvider _getImageProvider() {
    // For web or if web path is available
    if (_webImagePath != null) {
      // Use NetworkImage with cacheWidth to improve memory usage
      return NetworkImage(_webImagePath!);
    }
    // For web with bytes
    else if (_webImageBytes != null) {
      // Use MemoryImage for better control
      return MemoryImage(_webImageBytes!);
    }
    // Default placeholder for all other cases
    else {
      // Use AssetImage which is efficiently cached
      return const AssetImage('assets/images/placeholder.png');
    }
  }

  @override
  void dispose() {
    // Cancel timers
    _dotsAnimationTimer?.cancel();

    // Clear large memory objects
    _webImageBytes = null;
    _imageFile = null;
    _analysisResult = null;
    _mostRecentImage = null;

    // Ensure we're not leaking any state
    _isAnalyzing = false;
    _pendingAnalysis = false;

    super.dispose();
  }

  // Helper method to get optimized image bytes for local analysis
  Future<Uint8List> _optimizeImageBytes(Uint8List imageBytes) async {
    if (imageBytes.length < 300 * 1024) {
      // Small enough, no need to optimize
      return imageBytes;
    }

    try {
      // Use our unified image compression function
      return await compressImage(imageBytes, quality: 85, targetWidth: 800);
    } catch (e) {
      return imageBytes;
    }
  }

  // Compress image and convert to base64
  Future<String> _compressAndConvertToBase64(Uint8List imageBytes) async {
    try {
      // Compress the image first
      Uint8List compressedBytes = await compressImage(
        imageBytes,
        quality: 85,
        targetWidth: 1024,
      );

      // Convert to base64
      return base64Encode(compressedBytes);
    } catch (e) {
      return base64Encode(imageBytes); // Fallback to original
    }
  }

  // Helper method for optimizing single image bytes
  Future<Uint8List> _optimizeSingleImage(
    Uint8List bytes, {
    int targetWidth = 800,
    int quality = 85,
  }) async {
    try {
      if (bytes.length < 100 * 1024) return bytes; // Skip small files

      return await compressImage(
        bytes,
        targetWidth: targetWidth,
        quality: quality,
      );
    } catch (e) {
      return bytes;
    }
  }

  // Handle Uint8List compression consistently
  Future<Uint8List> _compressBytesConsistently(
    Uint8List bytes, {
    int quality = 85,
    int targetWidth = 800,
  }) async {
    try {
      return await compressImage(
        bytes,
        quality: quality,
        targetWidth: targetWidth,
      );
    } catch (e) {
      return bytes;
    }
  }

  // Web-specific function to compress images using canvas
  Future<Uint8List> _compressWebImageWithCanvas(
      Uint8List imageData, int maxDimension) async {
    try {
      return await compressImage(imageData, targetWidth: maxDimension);
    } catch (e) {
      return imageData; // Return original if compression fails
    }
  }

  // Helper method to prepare an image for analysis when only file/bytes are available
  void _prepareImageForAnalysis() async {
    // Create an XFile from the available image source
    XFile? fileToAnalyze;

    try {
      if (_imageFile != null) {
        // Mobile platform with File
        fileToAnalyze = XFile(_imageFile!.path);
      } else if (_webImageBytes != null && kIsWeb) {
        // For web, we need to handle this differently
        // Create a data URL and set it as webImagePath
        final base64Image = base64Encode(_webImageBytes!);
        final dataUrl = 'data:image/jpeg;base64,$base64Image';
        fileToAnalyze = XFile(dataUrl);
      } else if (_webImagePath != null) {
        // Web platform with path
        fileToAnalyze = XFile(_webImagePath!);
      }

      if (fileToAnalyze != null) {
        setState(() {
          _isAnalyzing = true;
          _mostRecentImage = fileToAnalyze;
        });
        await _analyzeImage(fileToAnalyze);
      } else {
        _showCustomDialog('Error', 'No image available to analyze');
      }
    } catch (e) {
      _showCustomDialog('Error', 'Error preparing image: ${e.toString()}');
    }
  }

  // Helper method to reduce image size on web platforms
  Future<Uint8List> _reduceImageSizeForWeb(
      Uint8List originalBytes, int targetWidth) async {
    if (!kIsWeb) {
      return originalBytes; // Only for web
    }

    // This function will be implemented by using the html package
    // and is only used on web platforms
    try {
      // Use our unified compressImage function
      return await compressImage(originalBytes, targetWidth: targetWidth);
    } catch (e) {
      return originalBytes;
    }
  }

  // Custom styled dialog to show messages - replaces all SnackBars
  void _showCustomDialog(String title, String message) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.0),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16.0,
                    fontWeight: FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20.0),
                TextButton(
                  child: Text(
                    "OK",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Show any error alerts with proper styling
  void _showErrorAlert(String message) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Analysis Error",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.0),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16.0,
                    fontWeight: FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20.0),
                TextButton(
                  child: Text(
                    "OK",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showUnsupportedPlatformDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Camera Unavailable",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.0),
                Text(
                  "Camera access is not available on this platform. Please use the 'Add Photo' button to select an image from your gallery.",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16.0,
                    fontWeight: FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20.0),
                TextButton(
                  child: Text(
                    "OK",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCameraErrorDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 24.0, horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Camera Error",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.0),
                Text(
                  "There was an error accessing the camera. Please check your camera permissions and try again.",
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16.0,
                    fontWeight: FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20.0),
                TextButton(
                  child: Text(
                    "OK",
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper method to check if we have an image
  bool get _hasImage =>
      _imageFile != null || _webImagePath != null || _webImageBytes != null;

  void _scanFood() {
    // If we have an image, analyze it
    if (_hasImage && !_isAnalyzing && _mostRecentImage != null) {
      _analyzeImage(_mostRecentImage);
    } else if (_hasImage && !_isAnalyzing) {
      // Show dialog to take a new picture instead of using the broken _prepareImageForAnalysis
      _showCustomDialog(
          "Analysis needed", "Please take a new picture to analyze food.");
    }
  }

  void _scanCode() {
    // Placeholder for code scanning functionality
  }

  void _setActiveButton(String buttonName) {
    setState(() {
      _activeButton = buttonName;
    });

    // Perform action based on the selected button
    switch (buttonName) {
      case 'Scan Food':
        _scanFood();
        break;
      case 'Scan Code':
        _scanCode();
        break;
      case 'Add Photo':
        _pickImage();
        break;
    }
  }

  // Format the analysis results for display
  String _formatAnalysisResult(Map<String, dynamic> analysis) {
    // This is no longer used for displaying UI, but we keep it for compatibility
    return "";
  }

  // Helper method to determine unit for a vitamin
  String _getUnitForVitamin(String vitaminName) {
    // Common units for vitamins
    vitaminName = vitaminName.toUpperCase();
    if (vitaminName == 'A') return 'μg'; // Vitamin A - micrograms
    if (vitaminName == 'C') return 'mg'; // Vitamin C - milligrams
    if (vitaminName == 'D') return 'μg'; // Vitamin D - micrograms
    if (vitaminName == 'E') return 'mg'; // Vitamin E - milligrams
    if (vitaminName.startsWith('B'))
      return 'mg'; // B Vitamins - usually milligrams
    if (vitaminName == 'K') return 'μg'; // Vitamin K - micrograms
    return 'mg'; // Default to milligrams
  }

  // Helper method to determine unit for a mineral
  String _getUnitForMineral(String mineralName) {
    // Common units for minerals
    mineralName = mineralName.toLowerCase();
    if (mineralName == 'sodium' ||
        mineralName == 'potassium' ||
        mineralName == 'calcium' ||
        mineralName == 'magnesium') return 'mg';
    if (mineralName == 'iron' ||
        mineralName == 'zinc' ||
        mineralName == 'copper') return 'mg';
    if (mineralName == 'selenium') return 'μg';
    return 'mg'; // Default to milligrams
  }

  // Helper method to determine unit for other nutrients
  String _getUnitForNutrient(String nutrientName) {
    // Common units for other nutrients
    nutrientName = nutrientName.toLowerCase();
    if (nutrientName.contains('fiber') ||
        nutrientName.contains('sugar') ||
        nutrientName.contains('fat')) return 'g';
    if (nutrientName.contains('cholesterol') || nutrientName.contains('sodium'))
      return 'mg';
    if (nutrientName.contains('calorie')) return 'kcal';
    return ''; // Default to no unit if unknown
  }

  // Generate slightly randomized cycle thresholds for a more natural progression
  List<int> _generateCycleThresholds() {
    // Create a new Random instance with caching
    final random = math.Random();

    // Generate thresholds for each step transition
    final thresholds = <int>[];
    int cumulativeThreshold = 0;

    // Use a more efficient calculation approach
    for (int i = 0; i < _processingSteps.length - 1; i++) {
      // Base values with step progression
      int baseValue = (i < 2)
          ? 2
          : (i > 4)
              ? 4
              : 3;

      // Simpler variation calculation
      int variation = random.nextInt(3); // 0, 1, or 2
      int stepThreshold = baseValue + variation;

      // Final step adjustment
      if (i == _processingSteps.length - 2) {
        stepThreshold += 1; // Small boost for final step
      }

      cumulativeThreshold += stepThreshold;
      thresholds.add(cumulativeThreshold);
    }

    return thresholds;
  }

  // Generate step thresholds for processing steps
  List<int> _generateStepThresholds() {
    // Create thresholds for when to change the processing step message
    // These values represent the dot cycles at which to change the step
    return [3, 6, 9, 12, 15, 18, 21, 24];
  }

  // Helper method to extract additional nutrients from the analysis data
  Map<String, dynamic> _extractAdditionalNutrients(
      Map<String, dynamic> analysisData) {
    // Create with initial capacity to avoid resizing
    Map<String, dynamic> nutrients = {};

    // Extract vitamins if available - direct extraction approach
    if (analysisData.containsKey('vitamins') &&
        analysisData['vitamins'] is Map) {
      final Map<String, dynamic> vitamins =
          Map<String, dynamic>.from(analysisData['vitamins'] as Map);
      for (final entry in vitamins.entries) {
        final key = entry.key;
        final value = entry.value;

        // Normalize key format
        String normalizedKey = key.toLowerCase();

        // Quick prefix check for vitamins
        if (normalizedKey.length <= 3 &&
            (normalizedKey == 'a' ||
                normalizedKey == 'c' ||
                normalizedKey == 'd' ||
                normalizedKey == 'e' ||
                normalizedKey == 'k' ||
                normalizedKey.startsWith('b'))) {
          normalizedKey = 'vitamin_$normalizedKey';
        }

        // Simple space replacement
        if (normalizedKey.contains(' ')) {
          normalizedKey = normalizedKey.replaceAll(' ', '_');
        }

        // Convert value to string if it's not already
        String valueStr;
        if (value is num) {
          valueStr = value.toString();
        } else if (value is String) {
          valueStr = value;
        } else if (value is Map && value.containsKey('value')) {
          // Handle structured values (e.g., {"value": 12, "unit": "mg"})
          valueStr = value['value'].toString();
        } else {
          valueStr = value.toString();
        }

        nutrients[normalizedKey] = valueStr;
      }
    }

    // Direct extraction of minerals
    if (analysisData.containsKey('minerals') &&
        analysisData['minerals'] is Map) {
      final Map<String, dynamic> minerals =
          Map<String, dynamic>.from(analysisData['minerals'] as Map);

      for (final entry in minerals.entries) {
        final key = entry.key;
        final value = entry.value;

        // Normalize key format
        String normalizedKey = key.toLowerCase();

        // Simple space replacement
        if (normalizedKey.contains(' ')) {
          normalizedKey = normalizedKey.replaceAll(' ', '_');
        }

        // Convert value to string if it's not already
        String valueStr;
        if (value is num) {
          valueStr = value.toString();
        } else if (value is String) {
          valueStr = value;
        } else if (value is Map && value.containsKey('value')) {
          // Handle structured values
          valueStr = value['value'].toString();
        } else {
          valueStr = value.toString();
        }

        nutrients[normalizedKey] = valueStr;
      }
    }

    // Process ingredient_nutrients if present (new API format)
    if (analysisData.containsKey('ingredient_nutrients') &&
        analysisData['ingredient_nutrients'] is List) {
      Map<String, double> aggregatedValues = {};

      // Loop through each ingredient's nutrients
      for (var ingredient in analysisData['ingredient_nutrients'] as List) {
        if (ingredient is Map &&
            ingredient.containsKey('nutrients') &&
            ingredient['nutrients'] is Map) {
          Map<String, dynamic> ingredientNutrients =
              Map<String, dynamic>.from(ingredient['nutrients'] as Map);

          // Aggregate each nutrient value across all ingredients
          ingredientNutrients.forEach((key, value) {
            double numValue = 0.0;
            if (value is num) {
              numValue = value.toDouble();
            } else if (value is String) {
              numValue = double.tryParse(value) ?? 0.0;
            }

            // Only include nutrients where value is >= 0.4
            if (numValue >= 0.4) {
              String normalizedKey = key.toLowerCase().replaceAll(' ', '_');
              if (key.toLowerCase().startsWith('vitamin') && key.length <= 10) {
                // Normalize vitamin keys (e.g., "vitamin a" -> "vitamin_a")
                List<String> parts = key.split(' ');
                if (parts.length == 2 && parts[1].length == 1) {
                  normalizedKey = 'vitamin_${parts[1].toLowerCase()}';
                }
              }

              // Add to running total
              aggregatedValues[normalizedKey] =
                  (aggregatedValues[normalizedKey] ?? 0.0) + numValue;
            }
          });
        }
      }

      // Convert aggregated values to strings and add to nutrients map
      aggregatedValues.forEach((key, value) {
        nutrients[key] = value.toString();
      });
    }

    // Direct extraction of other nutrients
    if (analysisData.containsKey('other_nutrients') ||
        analysisData.containsKey('other')) {
      final mapKey = analysisData.containsKey('other_nutrients')
          ? 'other_nutrients'
          : 'other';

      if (analysisData[mapKey] is Map) {
        final Map<String, dynamic> otherNutrients =
            Map<String, dynamic>.from(analysisData[mapKey] as Map);

        for (final entry in otherNutrients.entries) {
          final key = entry.key;
          final value = entry.value;

          // Normalize key format
          String normalizedKey = key.toLowerCase();

          // Simple space replacement
          if (normalizedKey.contains(' ')) {
            normalizedKey = normalizedKey.replaceAll(' ', '_');
          }

          // Convert value to string if it's not already
          String valueStr;
          if (value is num) {
            valueStr = value.toString();
          } else if (value is String) {
            valueStr = value;
          } else if (value is Map && value.containsKey('value')) {
            // Handle structured values
            valueStr = value['value'].toString();
          } else {
            valueStr = value.toString();
          }

          nutrients[normalizedKey] = valueStr;
        }
      }
    }

    // Process common root level nutrients in a single pass
    final commonNutrients = [
      'fiber',
      'cholesterol',
      'sodium',
      'sugar',
      'saturated_fat',
      'omega_3',
      'omega_6',
      'potassium',
      'calcium',
      'iron',
      'vitamin_a',
      'vitamin_c',
      'vitamin_d',
      'vitamin_e',
      'vitamin_k',
      'thiamin',
      'riboflavin',
      'niacin',
      'folate',
      'vitamin_b12'
    ];

    for (final nutrient in commonNutrients) {
      if (analysisData.containsKey(nutrient)) {
        final value = analysisData[nutrient];
        if (value is num || value is String) {
          nutrients[nutrient] = value.toString();
        }
      }
    }

    print('Extracted nutrients: ${nutrients.keys.join(', ')}');
    return nutrients;
  }

  // Helper method to build corner frames
  Widget _buildCornerFrame({
    bool topLeft = false,
    bool topRight = false,
    bool bottomLeft = false,
    bool bottomRight = false,
  }) {
    return SizedBox(
      width: 50,
      height: 50,
      child: CustomPaint(
        painter: CornerPainter(
          topLeft: topLeft,
          topRight: topRight,
          bottomLeft: bottomLeft,
          bottomRight: bottomRight,
        ),
      ),
    );
  }
}

// Custom painter for the corner frames
class CornerPainter extends CustomPainter {
  final bool topLeft;
  final bool topRight;
  final bool bottomLeft;
  final bool bottomRight;

  CornerPainter({
    this.topLeft = false,
    this.topRight = false,
    this.bottomLeft = false,
    this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final width = size.width;
    final height = size.height;
    final lineLength = size.width * 0.7;

    if (topLeft) {
      // Top line
      canvas.drawLine(
        Offset(0, 0),
        Offset(lineLength, 0),
        paint,
      );
      // Left line
      canvas.drawLine(
        Offset(0, 0),
        Offset(0, lineLength),
        paint,
      );
    } else if (topRight) {
      // Top line
      canvas.drawLine(
        Offset(width, 0),
        Offset(width - lineLength, 0),
        paint,
      );
      // Right line
      canvas.drawLine(
        Offset(width, 0),
        Offset(width, lineLength),
        paint,
      );
    } else if (bottomLeft) {
      // Bottom line
      canvas.drawLine(
        Offset(0, height),
        Offset(lineLength, height),
        paint,
      );
      // Left line
      canvas.drawLine(
        Offset(0, height),
        Offset(0, height - lineLength),
        paint,
      );
    } else if (bottomRight) {
      // Bottom line
      canvas.drawLine(
        Offset(width, height),
        Offset(width - lineLength, height),
        paint,
      );
      // Right line
      canvas.drawLine(
        Offset(width, height),
        Offset(width, height - lineLength),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CornerPainter oldDelegate) => false;
}
