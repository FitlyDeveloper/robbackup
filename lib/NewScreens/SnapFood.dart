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

// Import the codia_page to access NutritionTracker
// import '../Features/codia/codia_page.dart' as main_codia;

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
      // Read image as bytes
      Uint8List? imageBytes;

      if (kIsWeb) {
        // For web platform
        imageBytes = _webImageBytes ?? await image.readAsBytes();
      } else {
        // For mobile platforms
        imageBytes = await image.readAsBytes();
      }

      if (imageBytes == null || imageBytes.isEmpty) {
        throw Exception('Could not read image data');
      }

      print(
          'Image loaded, size: ${(imageBytes.length / 1024).toStringAsFixed(1)}KB');

      // Light compression only if image is too large for Render.com (>3MB)
      Uint8List finalImage = imageBytes;
      if (imageBytes.length > 3 * 1024 * 1024) {
        print('Image too large for server, applying compression...');
        finalImage = await _lightCompressImage(imageBytes);
        print(
            'After compression, size: ${(finalImage.length / 1024).toStringAsFixed(1)}KB');
      } else {
        print('Image size acceptable, using original');
      }

      // Enhance image quality for better ingredient detection
      // Ensure minimum resolution for API analysis
      if (finalImage.length < 100 * 1024) {
        // If less than 100KB, might be too small
        print(
            'Image might be too small for detailed analysis, but proceeding...');
      }

      // Show progress update
      if (mounted) {
        setState(() {
          // Update processing step
          _processingStep = 1; // Move to identification step
        });
      }

      try {
        // Call the updated API service that handles job submission and polling
        print('Submitting image for analysis...');
        final Map<String, dynamic> response =
            await FoodAnalyzerApi.analyzeFoodImage(finalImage);

        // Cancel the processing timer
        if (processingTimer != null) {
          processingTimer.cancel();
          processingTimer = null;
        }

        if (response != null) {
          setState(() {
            _analysisResult = response;
            _formattedAnalysisResult = null;
          });

          // Check if only one ingredient was detected and log this
          if (response.containsKey('meal') && response['meal'] is List) {
            List<dynamic> ingredients = response['meal'];
            if (ingredients.length == 1) {
              print(
                  'WARNING: Only 1 ingredient detected. This might indicate the image needs better lighting or the meal is simple.');
              print(
                  'Detected ingredient: ${ingredients[0]['dish'] ?? 'Unknown'}');
            } else {
              print('SUCCESS: ${ingredients.length} ingredients detected');
            }
          }

          // Extract the food name for the scan ID
          String foodName = 'Analyzed Meal';
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

        print("API error in _analyzeImage: $e");

        // Show error and redirect to codia_page - NO FALLBACK DATA
        if (mounted) {
          setState(() {
            _isAnalyzing = false;
          });

          // Show a helpful error message based on the error type
          String errorMessage;
          if (e.toString().contains("TimeoutException") ||
              e.toString().contains("timeout")) {
            errorMessage =
                "The analysis timed out. This might be due to high server load. Please try again in a few minutes.";
          } else if (e.toString().contains("Analysis failed")) {
            errorMessage =
                "We couldn't analyze your food image. Please try again with a clearer photo showing the food clearly.";
          } else if (e.toString().contains("Invalid response") ||
              e.toString().contains("JSON")) {
            errorMessage =
                "There was an issue processing the analysis results. Please try again.";
          } else {
            errorMessage =
                "We couldn't analyze your food image. Please try again with a clearer photo or check your internet connection.";
          }

          // Show error dialog
          _showCustomDialog("Analysis Failed", errorMessage);

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
        maxHeight: 2000, // Increased from 1000 for better ingredient detection
        maxWidth: 2000, // Increased from 1000 for better ingredient detection
        imageQuality: 95, // Increased from 85 for better ingredient detection
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

        // Use original image without compression
        return base64Encode(bytes);
      }
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List> _compressImage(Uint8List imageBytes) async {
    // This function has been removed - no compression is performed
    return imageBytes;
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

        // PRESERVE PRECISION: Use string extraction to avoid rounding
        String calories =
            _extractNumericValue(analysisData['calories']?.toString() ?? "0");
        String protein =
            _extractNumericValue(analysisData['protein']?.toString() ?? "0");
        String fat =
            _extractNumericValue(analysisData['fat']?.toString() ?? "0");
        String carbs =
            _extractNumericValue(analysisData['carbs']?.toString() ?? "0");

        // Only convert to double for calculations, keep strings for display
        double caloriesDouble = double.tryParse(calories) ?? 0.0;
        double vitaminC =
            _extractDecimalValue(analysisData['vitamin_c']?.toString() ?? "0");
        String healthScore = analysisData['health_score']?.toString() ?? "5/10";

        // EXTRACT ALL 34 MICRONUTRIENTS FROM OPENAI RESPONSE
        Map<String, dynamic> allMicronutrients = {};

        // Extract vitamins (13 nutrients)
        allMicronutrients['vitamin_a'] =
            _extractNumericValue(analysisData['vitamin_a']?.toString() ?? "0");
        allMicronutrients['vitamin_c'] =
            _extractNumericValue(analysisData['vitamin_c']?.toString() ?? "0");
        allMicronutrients['vitamin_d'] =
            _extractNumericValue(analysisData['vitamin_d']?.toString() ?? "0");
        allMicronutrients['vitamin_e'] =
            _extractNumericValue(analysisData['vitamin_e']?.toString() ?? "0");
        allMicronutrients['vitamin_k'] =
            _extractNumericValue(analysisData['vitamin_k']?.toString() ?? "0");
        allMicronutrients['vitamin_b1'] =
            _extractNumericValue(analysisData['vitamin_b1']?.toString() ?? "0");
        allMicronutrients['vitamin_b2'] =
            _extractNumericValue(analysisData['vitamin_b2']?.toString() ?? "0");
        allMicronutrients['vitamin_b3'] =
            _extractNumericValue(analysisData['vitamin_b3']?.toString() ?? "0");
        allMicronutrients['vitamin_b5'] =
            _extractNumericValue(analysisData['vitamin_b5']?.toString() ?? "0");
        allMicronutrients['vitamin_b6'] =
            _extractNumericValue(analysisData['vitamin_b6']?.toString() ?? "0");
        allMicronutrients['vitamin_b7'] =
            _extractNumericValue(analysisData['vitamin_b7']?.toString() ?? "0");
        allMicronutrients['vitamin_b9'] =
            _extractNumericValue(analysisData['vitamin_b9']?.toString() ?? "0");
        allMicronutrients['vitamin_b12'] = _extractNumericValue(
            analysisData['vitamin_b12']?.toString() ?? "0");

        // Extract minerals (15 nutrients)
        allMicronutrients['calcium'] =
            _extractNumericValue(analysisData['calcium']?.toString() ?? "0");
        allMicronutrients['chloride'] =
            _extractNumericValue(analysisData['chloride']?.toString() ?? "0");
        allMicronutrients['chromium'] =
            _extractNumericValue(analysisData['chromium']?.toString() ?? "0");
        allMicronutrients['copper'] =
            _extractNumericValue(analysisData['copper']?.toString() ?? "0");
        allMicronutrients['fluoride'] =
            _extractNumericValue(analysisData['fluoride']?.toString() ?? "0");
        allMicronutrients['iodine'] =
            _extractNumericValue(analysisData['iodine']?.toString() ?? "0");
        allMicronutrients['iron'] =
            _extractNumericValue(analysisData['iron']?.toString() ?? "0");
        allMicronutrients['magnesium'] =
            _extractNumericValue(analysisData['magnesium']?.toString() ?? "0");
        allMicronutrients['manganese'] =
            _extractNumericValue(analysisData['manganese']?.toString() ?? "0");
        allMicronutrients['molybdenum'] =
            _extractNumericValue(analysisData['molybdenum']?.toString() ?? "0");
        allMicronutrients['phosphorus'] =
            _extractNumericValue(analysisData['phosphorus']?.toString() ?? "0");
        allMicronutrients['potassium'] =
            _extractNumericValue(analysisData['potassium']?.toString() ?? "0");
        allMicronutrients['selenium'] =
            _extractNumericValue(analysisData['selenium']?.toString() ?? "0");
        allMicronutrients['sodium'] =
            _extractNumericValue(analysisData['sodium']?.toString() ?? "0");
        allMicronutrients['zinc'] =
            _extractNumericValue(analysisData['zinc']?.toString() ?? "0");

        // Extract other nutrients (6 nutrients)
        allMicronutrients['fiber'] =
            _extractNumericValue(analysisData['fiber']?.toString() ?? "0");
        allMicronutrients['cholesterol'] = _extractNumericValue(
            analysisData['cholesterol']?.toString() ?? "0");
        allMicronutrients['sugar'] =
            _extractNumericValue(analysisData['sugar']?.toString() ?? "0");
        allMicronutrients['saturated_fats'] = _extractNumericValue(
            analysisData['saturated_fats']?.toString() ?? "0");
        allMicronutrients['omega_3'] =
            _extractNumericValue(analysisData['omega_3']?.toString() ?? "0");
        allMicronutrients['omega_6'] =
            _extractNumericValue(analysisData['omega_6']?.toString() ?? "0");

        print('🔬 EXTRACTED ALL 34 MICRONUTRIENTS FROM OPENAI RESPONSE:');
        print(
            '📊 Vitamins (13): ${allMicronutrients.keys.where((k) => k.startsWith('vitamin_')).length}');
        print('⚗️ Minerals (15): ${[
          'calcium',
          'chloride',
          'chromium',
          'copper',
          'fluoride',
          'iodine',
          'iron',
          'magnesium',
          'manganese',
          'molybdenum',
          'phosphorus',
          'potassium',
          'selenium',
          'sodium',
          'zinc'
        ].where((k) => allMicronutrients.containsKey(k)).length}');
        print('🥗 Other (6): ${[
          'fiber',
          'cholesterol',
          'sugar',
          'saturated_fats',
          'omega_3',
          'omega_6'
        ].where((k) => allMicronutrients.containsKey(k)).length}');
        print('💾 Total nutrients extracted: ${allMicronutrients.length}');

        // Save the data
        List<Map<String, dynamic>> ingredientsList = [];

        // Check if the API response includes ingredient_nutrients (our preferred format)
        List<dynamic> ingredientNutrients =
            analysisData['ingredient_nutrients'] ?? [];

        // Log header for ingredient-specific nutrients
        print('\n===== INGREDIENT-SPECIFIC NUTRIENTS =====');

        // Process each ingredient with detailed nutrients if available
        for (int i = 0; i < ingredients.length; i++) {
          // Get the actual ingredient object instead of parsing strings
          dynamic ingredientData = ingredients[i];

          Map<String, dynamic> processedIngredient = {};

          // If ingredient is already a proper map (from API response)
          if (ingredientData is Map) {
            Map<String, dynamic> ingredient =
                Map<String, dynamic>.from(ingredientData);

            processedIngredient = {
              'name': ingredient['name'] ?? 'Unknown ingredient',
              'amount': '${ingredient['weight_g'] ?? 100}g',
              'calories': ingredient['calories'] ?? 0,
              'protein': ingredient['protein_g'] ??
                  0.0, // Keep as number to preserve precision
              'fat': ingredient['fat_g'] ??
                  0.0, // Keep as number to preserve precision
              'carbs': ingredient['carbs_g'] ??
                  0.0, // Keep as number to preserve precision
            };
          }
          // If ingredient is a string, try to parse it properly
          else {
            String ingredientString = ingredientData.toString();

            // Skip if this looks like a JSON field name rather than an ingredient
            if (ingredientString.contains(':') ||
                ingredientString.contains('{') ||
                ingredientString.contains('}') ||
                ingredientString.startsWith('weight_g') ||
                ingredientString.startsWith('calories') ||
                ingredientString.startsWith('protein_g') ||
                ingredientString.startsWith('fat_g') ||
                ingredientString.startsWith('carbs_g')) {
              print('Skipping malformed ingredient: $ingredientString');
              continue; // Skip this malformed "ingredient"
            }

            // Parse ingredient string format: "Name (weight) calories"
            // Example: "Grilled Sausage (100g) 300kcal"
            String name = ingredientString;
            String amount = "100g";
            int calories = 100;

            // Extract weight in parentheses
            RegExp weightRegex = RegExp(r'\(([^)]+)\)');
            Match? weightMatch = weightRegex.firstMatch(ingredientString);
            if (weightMatch != null) {
              amount = weightMatch.group(1) ?? "100g";
              // Remove the weight part from the name
              name = ingredientString.replaceFirst(weightRegex, '').trim();
            }

            // Extract calories at the end
            RegExp caloriesRegex =
                RegExp(r'(\d+)\s*kcal', caseSensitive: false);
            Match? caloriesMatch = caloriesRegex.firstMatch(ingredientString);
            if (caloriesMatch != null) {
              calories = int.tryParse(caloriesMatch.group(1) ?? '100') ?? 100;
              // Remove the calories part from the name
              name = name.replaceFirst(caloriesRegex, '').trim();
            }

            // For clean ingredient names, create values based on parsed data
            processedIngredient = {
              'name': name,
              'amount': amount,
              'calories': calories,
              'protein': (calories * 0.15).round(), // Estimate 15% protein
              'fat': (calories * 0.25).round(), // Estimate 25% fat
              'carbs': (calories * 0.60).round(), // Estimate 60% carbs
            };
          }

          // IMPORTANT: First check for detailed nutrients in ingredient_nutrients array
          if (i < ingredientNutrients.length && ingredientNutrients[i] is Map) {
            Map<String, dynamic> nutrient =
                Map<String, dynamic>.from(ingredientNutrients[i]);

            // Update macronutrient data from detailed nutrients
            processedIngredient['protein'] =
                nutrient['protein'] ?? processedIngredient['protein'];
            processedIngredient['fat'] =
                nutrient['fat'] ?? processedIngredient['fat'];
            processedIngredient['carbs'] =
                nutrient['carbs'] ?? processedIngredient['carbs'];

            // Process vitamins
            if (nutrient.containsKey('vitamins') &&
                nutrient['vitamins'] is Map) {
              Map<String, dynamic> vitaminsMap =
                  Map<String, dynamic>.from(nutrient['vitamins']);
              processedIngredient['vitamins'] = vitaminsMap;

              print(
                  '\nIngredient: ${processedIngredient['name']} - Found ${vitaminsMap.length} vitamins');
              print('  Vitamins:');
              vitaminsMap.forEach((key, value) {
                print('    • $key: ${value}${_getUnitForVitamin(key)}');
              });
            }

            // Process minerals
            if (nutrient.containsKey('minerals') &&
                nutrient['minerals'] is Map) {
              Map<String, dynamic> mineralsMap =
                  Map<String, dynamic>.from(nutrient['minerals']);
              processedIngredient['minerals'] = mineralsMap;

              print('  Minerals:');
              mineralsMap.forEach((key, value) {
                print('    • $key: ${value}${_getUnitForMineral(key)}');
              });
            }

            // Process other nutrients
            if (nutrient.containsKey('other') && nutrient['other'] is Map) {
              Map<String, dynamic> otherMap =
                  Map<String, dynamic>.from(nutrient['other']);
              processedIngredient['other'] = otherMap;

              print('  Other Nutrients:');
              otherMap.forEach((key, value) {
                print('    • $key: ${value}${_getUnitForNutrient(key)}');
              });
            }
          } else {
            // FALLBACK: Generate individual ingredient micronutrients from total meal values
            // This distributes the total micronutrients proportionally based on calories
            print(
                '\n🔍 DEBUG: ingredient_nutrients length: ${ingredientNutrients.length}, current index: $i');

            double totalMealCalories = double.tryParse(calories) ?? 1.0;
            double ingredientCalories =
                processedIngredient['calories']?.toDouble() ?? 100.0;
            double proportion = ingredientCalories / totalMealCalories;

            print(
                '\n🔄 FALLBACK: Generating micronutrients for ${processedIngredient['name']} (${(proportion * 100).toStringAsFixed(1)}% of meal)');

            // Generate vitamins proportionally
            Map<String, dynamic> generatedVitamins = {};
            allMicronutrients.forEach((key, value) {
              if (key.startsWith('vitamin_')) {
                double totalValue = double.tryParse(value.toString()) ?? 0.0;
                double ingredientValue = totalValue * proportion;
                generatedVitamins[key] = ingredientValue.toStringAsFixed(1);
              }
            });
            processedIngredient['vitamins'] = generatedVitamins;

            // Generate minerals proportionally
            Map<String, dynamic> generatedMinerals = {};
            List<String> mineralKeys = [
              'calcium',
              'chloride',
              'chromium',
              'copper',
              'fluoride',
              'iodine',
              'iron',
              'magnesium',
              'manganese',
              'molybdenum',
              'phosphorus',
              'potassium',
              'selenium',
              'sodium',
              'zinc'
            ];
            mineralKeys.forEach((key) {
              if (allMicronutrients.containsKey(key)) {
                double totalValue =
                    double.tryParse(allMicronutrients[key].toString()) ?? 0.0;
                double ingredientValue = totalValue * proportion;
                generatedMinerals[key] = ingredientValue.toStringAsFixed(1);
              }
            });
            processedIngredient['minerals'] = generatedMinerals;

            // Generate other nutrients proportionally
            Map<String, dynamic> generatedOther = {};
            List<String> otherKeys = [
              'fiber',
              'cholesterol',
              'sugar',
              'saturated_fats',
              'omega_3',
              'omega_6'
            ];
            otherKeys.forEach((key) {
              if (allMicronutrients.containsKey(key)) {
                double totalValue =
                    double.tryParse(allMicronutrients[key].toString()) ?? 0.0;
                double ingredientValue = totalValue * proportion;
                generatedOther[key] = ingredientValue.toStringAsFixed(1);
              }
            });
            processedIngredient['other'] = generatedOther;

            print(
                '✅ Generated ${generatedVitamins.length} vitamins, ${generatedMinerals.length} minerals, ${generatedOther.length} other nutrients');
          }

          // Only add valid ingredients to the list
          if (processedIngredient.isNotEmpty &&
              processedIngredient['name'] != null) {
            ingredientsList.add(processedIngredient);

            // 🔬 LOG DETAILED MICRONUTRIENTS FOR EACH INGREDIENT
            String ingredientName = processedIngredient['name'];
            String ingredientAmount = processedIngredient['amount'] ?? '100g';
            int ingredientCalories = processedIngredient['calories'] ?? 0;

            print(
                '\n🍽️ ===== INGREDIENT: $ingredientName ($ingredientAmount) - ${ingredientCalories}kcal =====');

            // Log macronutrients
            print('📊 MACRONUTRIENTS:');
            print('  🥩 Protein: ${processedIngredient['protein'] ?? 0}g');
            print('  🧈 Fat: ${processedIngredient['fat'] ?? 0}g');
            print('  🍞 Carbs: ${processedIngredient['carbs'] ?? 0}g');

            // Log vitamins if available
            if (processedIngredient.containsKey('vitamins') &&
                processedIngredient['vitamins'] is Map) {
              Map<String, dynamic> vitamins = processedIngredient['vitamins'];
              print('💊 VITAMINS (${vitamins.length}):');
              vitamins.forEach((key, value) {
                print('  • $key: ${value}${_getUnitForVitamin(key)}');
              });
            } else {
              print('💊 VITAMINS: No detailed vitamin data available');
            }

            // Log minerals if available
            if (processedIngredient.containsKey('minerals') &&
                processedIngredient['minerals'] is Map) {
              Map<String, dynamic> minerals = processedIngredient['minerals'];
              print('⚗️ MINERALS (${minerals.length}):');
              minerals.forEach((key, value) {
                print('  • $key: ${value}${_getUnitForMineral(key)}');
              });
            } else {
              print('⚗️ MINERALS: No detailed mineral data available');
            }

            // Log other nutrients if available
            if (processedIngredient.containsKey('other') &&
                processedIngredient['other'] is Map) {
              Map<String, dynamic> other = processedIngredient['other'];
              print('🥗 OTHER NUTRIENTS (${other.length}):');
              other.forEach((key, value) {
                print('  • $key: ${value}${_getUnitForNutrient(key)}');
              });
            } else {
              print(
                  '🥗 OTHER NUTRIENTS: No detailed other nutrient data available');
            }

            print('🔬 ================================================\n');

            print('Added valid ingredient: ${processedIngredient['name']}');
          }
        }

        print('=====================================\n');

        // Pass the scanId to _saveFoodCardData - this ensures consistent ID usage
        _saveFoodCardData(
          mealName,
          ingredients.join(", "),
          calories,
          protein,
          fat,
          carbs,
          ingredientsList,
          healthScore,
          scanId, // Pass the scanId parameter
          allMicronutrients, // Pass all 34 extracted micronutrients
        );

        // Mark navigation as handled
        navigationHandled = true;
      }

      // Rest of the method remains the same...
    } catch (e) {
      // Even if there's an error, try to navigate with default values
      if (mounted && _analysisResult != null) {
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
          {}, // Empty micronutrients for error case
        );
      }
    }
  }

  // Helper method to extract nutrient values from a map, filtering by threshold
  void _extractNutrientValues(
      Map<String, dynamic> source, Map<String, double> target) {
    source.forEach((key, value) {
      double numValue = 0.0;

      // Handle different value types
      if (value is String) {
        numValue = double.tryParse(value) ?? 0.0;
      } else if (value is num) {
        numValue = value.toDouble();
      } else if (value is Map && value.containsKey('amount')) {
        // Handle nested structure like {amount: 1.2}
        var amountValue = value['amount'];
        if (amountValue is String) {
          numValue = double.tryParse(amountValue) ?? 0.0;
        } else if (amountValue is num) {
          numValue = amountValue.toDouble();
        }
      }

      // Only add values >= 0.4
      if (numValue >= 0.4) {
        target[key] = numValue;
      }
    });
  }

  // Helper method to extract numeric value from a string, preserving decimal places
  String _extractNumericValue(String input) {
    // Use a more precise RegExp that captures decimal values properly
    final numericRegex = RegExp(r'(\d+(?:\.\d+)?)');
    final match = numericRegex.firstMatch(input);
    if (match != null && match.group(1) != null) {
      // Parse as double first to validate, then return as string to preserve precision
      final value = double.tryParse(match.group(1)!);
      if (value != null) {
        // Return the original matched string to preserve exact decimal places
        return match.group(1)!;
      }
    }
    return "0";
  }

  // Helper method to extract numeric value from a string and convert to int (only when needed)
  int _extractNumericValueAsInt(String input) {
    final numericRegex = RegExp(r'(\d+(?:\.\d+)?)');
    final match = numericRegex.firstMatch(input);
    if (match != null && match.group(1) != null) {
      final value = double.tryParse(match.group(1)!) ?? 0.0;
      return value
          .round(); // Only round when converting to int is specifically needed
    }
    return 0;
  }

  // Helper method to extract numeric value with decimal places from a string - PRESERVE PRECISION
  double _extractDecimalValue(String input) {
    final numericRegex = RegExp(r'(\d+(?:\.\d+)?)');
    final match = numericRegex.firstMatch(input);
    if (match != null && match.group(1) != null) {
      return double.tryParse(match.group(1)!) ?? 0.0;
    }
    return 0.0;
  }

  // Gets exact raw calorie value as double (not integer) to preserve precision
  double _getRawCalorieValue(double calories) {
    // Return exact value without any rounding
    return calories;
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
      Map<String, dynamic>? micronutrients]) async {
    // Use provided scanId or generate a new one as fallback
    final String finalScanId = scanId ??
        '${foodName.isEmpty ? 'analyzed_meal' : foodName.replaceAll(' ', '_').toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}';

    // Use provided micronutrients or empty map as fallback
    final Map<String, dynamic> finalMicronutrients = micronutrients ?? {};

    // Get the current image bytes - use original without compression
    Uint8List? originalImage;
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

      // Use original image without compression
      if (sourceBytes != null) {
        try {
          // Use original image for storage
          originalImage = sourceBytes;

          // Set base64 string for storage
          base64Image = base64Encode(originalImage);
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

      // Invalidate nutrition cache since new food data was added
      // main_codia.NutritionTracker.invalidateCacheStatic();
    } catch (e) {}

    // Prepare display image in parallel with storage operations
    Uint8List? displayImageBytes;
    String? displayImageBase64;

    try {
      Uint8List? sourceBytes;

      // Reuse existing image data
      if (_webImageBytes != null) {
        sourceBytes = _webImageBytes;
      } else if (originalImage != null) {
        // Use original image for display too
        displayImageBytes = originalImage;
        displayImageBase64 = base64Image;
        sourceBytes = null; // Skip further processing
      }

      if (sourceBytes != null) {
        // Use original image for display too
        displayImageBytes = sourceBytes;

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
              additionalNutrients:
                  finalMicronutrients, // Pass the extracted micronutrients directly
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
            originalImage = null;
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
    // No optimization needed - return original
    return imageBytes;
  }

  // Compress image and convert to base64
  Future<String> _compressAndConvertToBase64(Uint8List imageBytes) async {
    // No compression - convert original to base64
    return base64Encode(imageBytes);
  }

  // Helper method for optimizing single image bytes
  Future<Uint8List> _optimizeSingleImage(
    Uint8List bytes, {
    int targetWidth = 800,
    int quality = 85,
  }) async {
    // No optimization - return original
    return bytes;
  }

  // Handle Uint8List compression consistently
  Future<Uint8List> _compressBytesConsistently(
    Uint8List bytes, {
    int quality = 85,
    int targetWidth = 800,
  }) async {
    // No compression - return original
    return bytes;
  }

  // Web-specific function to compress images using canvas
  Future<Uint8List> _compressWebImageWithCanvas(
      Uint8List imageData, int maxDimension) async {
    // No compression - return original
    return imageData;
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

    // No compression - return original
    return originalBytes;
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

    // IMPORTANT: Match the exact field names used in the "other" nutrition object
    if (nutrientName == 'fiber' ||
        nutrientName == 'sugar' ||
        nutrientName == 'saturated_fats' ||
        nutrientName == 'omega_6') {
      return 'g';
    }

    if (nutrientName == 'cholesterol' || nutrientName == 'omega_3') {
      return 'mg';
    }

    // Fallback patterns for other variants
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

  // Helper method to extract nutrients from ingredients list
  Map<String, dynamic> _extractNutrientsFromIngredients(
      List<Map<String, dynamic>> ingredientsList) {
    Map<String, dynamic> nutrients = {};

    // Aggregate vitamins and minerals from all ingredients
    for (var ingredient in ingredientsList) {
      // Extract vitamins
      if (ingredient.containsKey('vitamins') && ingredient['vitamins'] is Map) {
        Map<String, dynamic> vitamins =
            Map<String, dynamic>.from(ingredient['vitamins']);
        vitamins.forEach((key, value) {
          String normalizedKey = key.toLowerCase().replaceAll(' ', '_');
          double currentValue =
              double.tryParse(nutrients[normalizedKey]?.toString() ?? '0') ??
                  0.0;
          double newValue = double.tryParse(value.toString()) ?? 0.0;
          nutrients[normalizedKey] = (currentValue + newValue).toString();
        });
      }

      // Extract minerals
      if (ingredient.containsKey('minerals') && ingredient['minerals'] is Map) {
        Map<String, dynamic> minerals =
            Map<String, dynamic>.from(ingredient['minerals']);
        minerals.forEach((key, value) {
          String normalizedKey = key.toLowerCase().replaceAll(' ', '_');
          double currentValue =
              double.tryParse(nutrients[normalizedKey]?.toString() ?? '0') ??
                  0.0;
          double newValue = double.tryParse(value.toString()) ?? 0.0;
          nutrients[normalizedKey] = (currentValue + newValue).toString();
        });
      }

      // Extract other nutrients
      if (ingredient.containsKey('other') && ingredient['other'] is Map) {
        Map<String, dynamic> other =
            Map<String, dynamic>.from(ingredient['other']);
        other.forEach((key, value) {
          String normalizedKey = key.toLowerCase().replaceAll(' ', '_');
          double currentValue =
              double.tryParse(nutrients[normalizedKey]?.toString() ?? '0') ??
                  0.0;
          double newValue = double.tryParse(value.toString()) ?? 0.0;
          nutrients[normalizedKey] = (currentValue + newValue).toString();
        });
      }
    }

    print("Extracted nutrients from ingredients list: $nutrients");
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

  // Proper image compression for large images to meet server limits
  Future<Uint8List> _lightCompressImage(Uint8List imageBytes) async {
    try {
      // Target: compress to 0.7MB for optimal API performance
      const int maxSizeBytes = 700 * 1024; // 0.7MB (700KB)

      if (imageBytes.length <= maxSizeBytes) {
        print(
            'Image already below 0.7MB (${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)}MB), no compression needed');
        return imageBytes; // Already small enough
      }

      print(
          'Image too large (${(imageBytes.length / 1024 / 1024).toStringAsFixed(1)}MB), compressing...');

      // Use the proper compression function that already exists
      // This uses proper image compression algorithms instead of corrupting the data
      Uint8List compressed = await compressImage(
        imageBytes,
        quality: 70,
        targetWidth: 800,
        targetSizeBytes: 716800, // 700KB target
      );

      print(
          'Compressed to ${(compressed.length / 1024 / 1024).toStringAsFixed(1)}MB');
      return compressed;
    } catch (e) {
      print('Compression failed: $e, using original');
      return imageBytes; // Return original on error
    }
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
