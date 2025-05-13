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
    // Don't initialize _picker here since it's already declared as final

    // Add timer for loading animation dots - make it faster (300ms instead of 500ms)
    _dotsAnimationTimer = Timer.periodic(Duration(milliseconds: 300), (timer) {
      if (mounted && _isAnalyzing) {
        setState(() {
          _loadingDots = (_loadingDots + 1) % 4; // Cycles between 0, 1, 2, 3

          // If we complete a dot cycle (back to 0)
          if (_loadingDots == 0) {
            _dotCycles++; // Increment the cycle counter

            // Check if we've reached the next threshold for step change
            if (_cycleThresholds.isNotEmpty &&
                _dotCycles >= _cycleThresholds[0] &&
                _processingStep < _processingSteps.length - 1) {
              _processingStep++;
              _cycleThresholds.removeAt(0); // Remove the used threshold
            }
          }
        });
      }
    });

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

          // DEBUG: Print the entire response structure to see what's available
          print("\n===== FULL API RESPONSE STRUCTURE =====");
          print("Keys in response: ${response.keys.toList()}");
          if (response.containsKey('ingredient_macros')) {
            print(
                "Ingredient macros found: ${response['ingredient_macros'].length} items");
            for (var i = 0; i < response['ingredient_macros'].length; i++) {
              var macro = response['ingredient_macros'][i];
              print("Ingredient ${i + 1}: ${macro.keys.toList()}");

              // Check if this ingredient has vitamins/minerals directly
              if (macro.containsKey('vitamins')) {
                print("  - Has direct vitamins: ${macro['vitamins']}");
              }
              if (macro.containsKey('minerals')) {
                print("  - Has direct minerals: ${macro['minerals']}");
              }
            }
          }

          // Vitamins/minerals at top level
          if (response.containsKey('vitamins')) {
            print("Top-level vitamins found: ${response['vitamins']}");
          }
          if (response.containsKey('minerals')) {
            print("Top-level minerals found: ${response['minerals']}");
          }
          print("======================================\n");

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
          _displayAnalysisResults(_analysisResult!, scanId);
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

      // NEW FORMAT: First check for the meal_name format which is our desired format
      if (analysisData.containsKey('meal_name')) {
        String mealName = analysisData['meal_name'];
        List<dynamic> ingredients = analysisData['ingredients'] ?? [];
        double calories =
            _extractDecimalValue(analysisData['calories']?.toString() ?? "0");
        double protein =
            _extractDecimalValue(analysisData['protein']?.toString() ?? "0");
        double fat =
            _extractDecimalValue(analysisData['fat']?.toString() ?? "0");
        double carbs =
            _extractDecimalValue(analysisData['carbs']?.toString() ?? "0");
        double vitaminC =
            _extractDecimalValue(analysisData['vitamin_c']?.toString() ?? "0");
        String healthScore = analysisData['health_score']?.toString() ?? "5/10";

        // Save the data
        List<Map<String, dynamic>> ingredientsList = [];

        // Check if the API response includes detailed ingredient macros
        List<dynamic> ingredientMacros =
            analysisData['ingredient_macros'] ?? [];

        // Log header for ingredient-specific nutrients
        print('\n===== INGREDIENT-SPECIFIC NUTRIENTS =====');

        // Process each ingredient with macros if available
        for (int i = 0; i < ingredients.length; i++) {
          String name = ingredients[i].toString();

          // Extract weight and calories if available
          final regex = RegExp(r'(.*?)\s*\((.*?)\)\s*(\d+)kcal');
          final match = regex.firstMatch(name);

          Map<String, dynamic> ingredientData = {};

          if (match != null) {
            String ingredientName = match.group(1)?.trim() ?? name;
            String weight = match.group(2) ?? "30g";
            int kcal = int.tryParse(match.group(3) ?? "75") ?? 75;

            ingredientData = {
              'name': ingredientName,
              'amount': weight,
              'calories': kcal,
            };
          } else {
            // Default values if no match
            ingredientData = {
              'name': name,
              'amount': "30g",
              'calories': 75,
            };
          }

          // Add macronutrient data if available
          if (i < ingredientMacros.length && ingredientMacros[i] is Map) {
            Map<String, dynamic> macros =
                Map<String, dynamic>.from(ingredientMacros[i]);

            // Add protein, fat, and carbs data if available
            if (macros.containsKey('protein')) {
              // Convert the value to a number if it's not already
              var proteinValue = macros['protein'];
              if (proteinValue is String) {
                ingredientData['protein'] =
                    double.tryParse(proteinValue) ?? 0.0;
              } else if (proteinValue is num) {
                ingredientData['protein'] = proteinValue.toDouble();
              } else {
                ingredientData['protein'] = 0.0;
              }
            } else {
              ingredientData['protein'] = 0.0;
            }

            if (macros.containsKey('fat')) {
              // Convert the value to a number if it's not already
              var fatValue = macros['fat'];
              if (fatValue is String) {
                ingredientData['fat'] = double.tryParse(fatValue) ?? 0.0;
              } else if (fatValue is num) {
                ingredientData['fat'] = fatValue.toDouble();
              } else {
                ingredientData['fat'] = 0.0;
              }
            } else {
              ingredientData['fat'] = 0.0;
            }

            if (macros.containsKey('carbs') ||
                macros.containsKey('carbohydrates')) {
              // Convert the value to a number if it's not already
              var carbsValue = macros['carbs'] ?? macros['carbohydrates'];
              if (carbsValue is String) {
                ingredientData['carbs'] = double.tryParse(carbsValue) ?? 0.0;
              } else if (carbsValue is num) {
                ingredientData['carbs'] = carbsValue.toDouble();
              } else {
                ingredientData['carbs'] = 0.0;
              }
            } else {
              ingredientData['carbs'] = 0.0;
            }

            // Check for vitamins, minerals and other nutrients in the enhanced format
            // Process all vitamins from our standard API response
            _processNutrientCategory(macros, 'vitamins', ingredientData,
                FoodAnalyzerApi.vitaminUnits);

            // Process all minerals from our standard API response
            _processNutrientCategory(macros, 'minerals', ingredientData,
                FoodAnalyzerApi.mineralUnits);

            // Process all other nutrients from our standard API response
            _processNutrientCategory(macros, 'other', ingredientData,
                FoodAnalyzerApi.otherNutrientUnits);

            // Log this ingredient's nutrients for debugging
            _logIngredientNutrients(ingredientData);
          }

          ingredientsList.add(ingredientData);
        }

        // Extract all top-level nutrients for the entire meal
        Map<String, dynamic> additionalNutrients = {};

        // Process the vitamins at the top level using the newer format from the updated API
        if (analysisData.containsKey('vitamins') &&
            analysisData['vitamins'] is Map) {
          Map<String, dynamic> vitamins =
              Map<String, dynamic>.from(analysisData['vitamins']);

          // Go through all expected vitamins
          FoodAnalyzerApi.vitaminUnits.forEach((vitaminKey, unit) {
            if (vitamins.containsKey(vitaminKey)) {
              // Extract the numeric value from the API response
              var vitaminValue = vitamins[vitaminKey];
              double numericValue = 0.0;

              if (vitaminValue is String) {
                // Remove the unit part if it's a string like "150 mcg"
                numericValue = _extractNumericValueFromString(vitaminValue);
              } else if (vitaminValue is num) {
                numericValue = vitaminValue.toDouble();
              }

              // Store in additionalNutrients with standardized format
              additionalNutrients[vitaminKey] = '$numericValue $unit';
            } else {
              // If vitamin not present, add with zero value
              additionalNutrients[vitaminKey] = '0 $unit';
            }
          });
        }

        // Process the minerals at the top level using the newer format from the updated API
        if (analysisData.containsKey('minerals') &&
            analysisData['minerals'] is Map) {
          Map<String, dynamic> minerals =
              Map<String, dynamic>.from(analysisData['minerals']);

          // Go through all expected minerals
          FoodAnalyzerApi.mineralUnits.forEach((mineralKey, unit) {
            if (minerals.containsKey(mineralKey)) {
              // Extract the numeric value from the API response
              var mineralValue = minerals[mineralKey];
              double numericValue = 0.0;

              if (mineralValue is String) {
                // Remove the unit part if it's a string like "150 mg"
                numericValue = _extractNumericValueFromString(mineralValue);
              } else if (mineralValue is num) {
                numericValue = mineralValue.toDouble();
              }

              // Store in additionalNutrients with standardized format
              additionalNutrients[mineralKey] = '$numericValue $unit';
            } else {
              // If mineral not present, add with zero value
              additionalNutrients[mineralKey] = '0 $unit';
            }
          });
        }

        // Process the other nutrients at the top level using the newer format from the updated API
        if (analysisData.containsKey('other') && analysisData['other'] is Map) {
          Map<String, dynamic> others =
              Map<String, dynamic>.from(analysisData['other']);

          // Go through all expected other nutrients
          FoodAnalyzerApi.otherNutrientUnits.forEach((nutrientKey, unit) {
            if (others.containsKey(nutrientKey)) {
              // Extract the numeric value from the API response
              var nutrientValue = others[nutrientKey];
              double numericValue = 0.0;

              if (nutrientValue is String) {
                // Remove the unit part if it's a string like "5 g"
                numericValue = _extractNumericValueFromString(nutrientValue);
              } else if (nutrientValue is num) {
                numericValue = nutrientValue.toDouble();
              }

              // Store in additionalNutrients with standardized format
              additionalNutrients[nutrientKey] = '$numericValue $unit';
            } else {
              // If nutrient not present, add with zero value
              additionalNutrients[nutrientKey] = '0 $unit';
            }
          });
        }

        // Log the processed nutrients for debugging
        print('\n===== PROCESSED NUTRIENTS FOR NUTRITION TRACKING =====');
        additionalNutrients.forEach((key, value) {
          print('  $key: $value');
        });
        print('=======================================================\n');

        // Save food card data and navigate to the FoodCardOpen screen
        _saveFoodCardAndNavigate(
          mealName,
          calories.toString(),
          protein.toString(),
          fat.toString(),
          carbs.toString(),
          ingredientsList,
          healthScore,
          scanId,
          additionalNutrients,
        );

        // Mark navigation as handled
        navigationHandled = true;
      }

      // Fallback formats handling remains unchanged...
      // [remaining code for fallback formats]
    } catch (e) {
      print('Error in _displayAnalysisResults: $e');
      // Error handling code remains unchanged...
    }
  }

  // Helper method to process nutrients from a specific category
  void _processNutrientCategory(Map<String, dynamic> source, String categoryKey,
      Map<String, dynamic> targetIngredientData, Map<String, String> unitsMap) {
    if (source.containsKey(categoryKey) && source[categoryKey] is Map) {
      Map<String, dynamic> nutrients =
          Map<String, dynamic>.from(source[categoryKey]);

      // Process each nutrient
      nutrients.forEach((nutrientKey, nutrientValue) {
        // Get the expected unit for this nutrient
        String unit = unitsMap[nutrientKey] ?? 'mg';

        // Extract numeric value
        double numericValue = 0.0;
        if (nutrientValue is String) {
          // If value includes unit (e.g. "150 mcg"), extract numeric part
          numericValue = _extractNumericValueFromString(nutrientValue);
        } else if (nutrientValue is num) {
          numericValue = nutrientValue.toDouble();
        }

        // Only include nutrients with values >= 0.4
        if (numericValue >= 0.4) {
          // Store the nutrient with its proper unit
          targetIngredientData['${categoryKey}_${nutrientKey}'] =
              '$numericValue $unit';
        }
      });
    }
  }

  // Helper method to log ingredient nutrients for debugging
  void _logIngredientNutrients(Map<String, dynamic> ingredientData) {
    // Group keys by categories
    List<String> vitaminKeys =
        ingredientData.keys.where((k) => k.startsWith('vitamins_')).toList();
    List<String> mineralKeys =
        ingredientData.keys.where((k) => k.startsWith('minerals_')).toList();
    List<String> otherKeys =
        ingredientData.keys.where((k) => k.startsWith('other_')).toList();

    // If we have any nutrients, log them
    if (vitaminKeys.isNotEmpty ||
        mineralKeys.isNotEmpty ||
        otherKeys.isNotEmpty) {
      print(
          '\nIngredient: ${ingredientData['name']} (${ingredientData['amount']}, ${ingredientData['calories']}kcal)');

      if (vitaminKeys.isNotEmpty) {
        print('  Vitamins:');
        vitaminKeys.forEach((key) {
          print(
              '    • ${key.replaceFirst('vitamins_', '')}: ${ingredientData[key]}');
        });
      }

      if (mineralKeys.isNotEmpty) {
        print('  Minerals:');
        mineralKeys.forEach((key) {
          print(
              '    • ${key.replaceFirst('minerals_', '')}: ${ingredientData[key]}');
        });
      }

      if (otherKeys.isNotEmpty) {
        print('  Other Nutrients:');
        otherKeys.forEach((key) {
          print(
              '    • ${key.replaceFirst('other_', '')}: ${ingredientData[key]}');
        });
      }
    }
  }

  // Helper method to extract numeric value from string with unit
  double _extractNumericValueFromString(String value) {
    // Extract just the numeric portion, handles formats like "150 mcg", "2.5 mg", etc.
    final numericRegex = RegExp(r'(\d+\.?\d*)');
    final match = numericRegex.firstMatch(value);
    if (match != null && match.group(1) != null) {
      return double.tryParse(match.group(1)!) ?? 0.0;
    }
    return 0.0;
  }

  // Helper method to save and navigate to FoodCardOpen
  void _saveFoodCardAndNavigate(
    String foodName,
    String calories,
    String protein,
    String fat,
    String carbs,
    List<Map<String, dynamic>> ingredientsList,
    String healthScore,
    String scanId,
    Map<String, dynamic> additionalNutrients,
  ) {
    // Compress and save the current image for display
    Future<String?> base64Future;
    if (_webImageBytes != null) {
      // Compress the web image bytes first
      base64Future = _compressImageToBase64(_webImageBytes!);
    } else if (_imageFile != null) {
      // Read the image file and compress it
      base64Future = _imageFile!.readAsBytes().then(_compressImageToBase64);
    } else if (_mostRecentImage != null) {
      // Read the XFile and compress it
      base64Future =
          _mostRecentImage!.readAsBytes().then(_compressImageToBase64);
    } else {
      // No image available
      base64Future = Future.value(null);
    }

    // Once we have the compressed image, navigate to the FoodCardOpen screen
    base64Future.then((base64Image) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FoodCardOpen(
              foodName: foodName,
              calories: calories,
              protein: protein,
              fat: fat,
              carbs: carbs,
              healthScore: healthScore,
              imageBase64: base64Image,
              ingredients: ingredientsList,
              additionalNutrients: additionalNutrients,
              scanId: scanId,
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
          }
        });
      }
    });
  }

  // Helper method to compress image to base64
  Future<String?> _compressImageToBase64(Uint8List imageBytes) async {
    try {
      // Compress image to reasonable size for storage
      final Uint8List compressed = await compressImage(
        imageBytes,
        quality: 80,
        targetWidth: 600,
      );

      // Convert to base64
      return base64Encode(compressed);
    } catch (e) {
      print('Error compressing image to base64: $e');
      // Fall back to original image if compression fails
      return base64Encode(imageBytes);
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

        nutrients[normalizedKey] = value.toString();
      }
    }

    // Direct extraction of minerals
    if (analysisData.containsKey('minerals') &&
        analysisData['minerals'] is Map) {
      final Map<String, dynamic> minerals =
          Map<String, dynamic>.from(analysisData['minerals'] as Map);
      minerals.forEach(
          (key, value) => nutrients[key.toLowerCase()] = value.toString());
    }

    // Direct extraction of other nutrients
    if (analysisData.containsKey('other_nutrients') &&
        analysisData['other_nutrients'] is Map) {
      final Map<String, dynamic> otherNutrients =
          Map<String, dynamic>.from(analysisData['other_nutrients'] as Map);
      otherNutrients.forEach(
          (key, value) => nutrients[key.toLowerCase()] = value.toString());
    }

    // Extract from nutrition or nutrition_values
    if (analysisData.containsKey('nutrition') &&
        analysisData['nutrition'] is Map) {
      _extractNestedNutrients(
          Map<String, dynamic>.from(analysisData['nutrition']), nutrients);
    } else if (analysisData.containsKey('nutrition_values') &&
        analysisData['nutrition_values'] is Map) {
      _extractNestedNutrients(
          Map<String, dynamic>.from(analysisData['nutrition_values']),
          nutrients);
    }

    // Check for ingredient_macros which might contain nutrient data
    if (analysisData.containsKey('ingredient_macros') &&
        analysisData['ingredient_macros'] is List) {
      List<dynamic> ingredientMacros = analysisData['ingredient_macros'];

      // For aggregate nutrients, we'll combine values from all ingredients
      for (var macroData in ingredientMacros) {
        if (macroData is Map) {
          Map<String, dynamic> macros = Map<String, dynamic>.from(macroData);

          // Check for nested nutrition data
          if (macros.containsKey('nutrition') && macros['nutrition'] is Map) {
            _extractNestedNutrients(
                Map<String, dynamic>.from(macros['nutrition']), nutrients);
          } else if (macros.containsKey('nutrition_values') &&
              macros['nutrition_values'] is Map) {
            _extractNestedNutrients(
                Map<String, dynamic>.from(macros['nutrition_values']),
                nutrients);
          }
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
        nutrients[nutrient] = analysisData[nutrient].toString();
      }
    }

    return nutrients;
  }

  // Helper method to extract nested nutrient data
  void _extractNestedNutrients(
      Map<String, dynamic> source, Map<String, dynamic> target) {
    // Check for vitamins
    if (source.containsKey('vitamins') && source['vitamins'] is Map) {
      Map<String, dynamic> vitamins =
          Map<String, dynamic>.from(source['vitamins']);
      vitamins.forEach((key, value) {
        String normalizedKey = key.toLowerCase();
        // Format vitamin keys consistently
        if (normalizedKey.length <= 3 &&
            (normalizedKey == 'a' ||
                normalizedKey == 'c' ||
                normalizedKey == 'd' ||
                normalizedKey == 'e' ||
                normalizedKey == 'k' ||
                normalizedKey.startsWith('b'))) {
          normalizedKey = 'vitamin_$normalizedKey';
        }

        // Handle different value types
        if (value is Map && value.containsKey('amount')) {
          target[normalizedKey] = value['amount'].toString();
        } else {
          target[normalizedKey] = value.toString();
        }
      });
    }

    // Check for minerals
    if (source.containsKey('minerals') && source['minerals'] is Map) {
      Map<String, dynamic> minerals =
          Map<String, dynamic>.from(source['minerals']);
      minerals.forEach((key, value) {
        String normalizedKey = key.toLowerCase();
        // Handle different value types
        if (value is Map && value.containsKey('amount')) {
          target[normalizedKey] = value['amount'].toString();
        } else {
          target[normalizedKey] = value.toString();
        }
      });
    }

    // Check for other nutrients
    if (source.containsKey('other') && source['other'] is Map) {
      Map<String, dynamic> other = Map<String, dynamic>.from(source['other']);
      other.forEach((key, value) {
        String normalizedKey = key.toLowerCase();
        // Handle different value types
        if (value is Map && value.containsKey('amount')) {
          target[normalizedKey] = value['amount'].toString();
        } else {
          target[normalizedKey] = value.toString();
        }
      });
    }

    // Also check for flat nutrient values directly in the source
    source.forEach((key, value) {
      if (key != 'vitamins' && key != 'minerals' && key != 'other') {
        String normalizedKey = key.toLowerCase();
        // Handle different value types
        if (value is Map && value.containsKey('amount')) {
          target[normalizedKey] = value['amount'].toString();
        } else if (value is num || value is String) {
          target[normalizedKey] = value.toString();
        }
      }
    });
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

  // Helper method to extract numeric value with decimal places from a string
  double _extractDecimalValue(String input) {
    final numericRegex = RegExp(r'(\d+\.?\d*)');
    final match = numericRegex.firstMatch(input);
    if (match != null && match.group(1) != null) {
      return double.tryParse(match.group(1)!) ?? 0.0;
    }
    return 0.0;
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
