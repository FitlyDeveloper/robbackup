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
// removed unused http import
// removed unused flutter_image_compress import
// Remove permission_handler temporarily
// import 'package:permission_handler/permission_handler.dart';

// Conditionally import dart:io only on non-web
import 'dart:io' if (dart.library.html) 'package:fitness_app/web_io_stub.dart';

// Import our web handling code
import 'web_impl.dart' if (dart.library.io) 'web_impl_stub.dart';

// Additional imports for mobile platforms
// removed unused web_image_compress_stub import

// Conditionally import the image compress library
// We need to use a different approach to avoid conflicts
import 'image_compress.dart';

// Add import for our secure API service
import '../services/food_analyzer_api.dart';

// Import FoodCardOpen for navigation after analysis
import 'FoodCardOpen.dart';

// Import the codia_page to access NutritionTracker
// import '../Features/codia/codia_page.dart' as main_codia;

// Import Nutrition.dart for persistent scan data storage
import '../Features/codia/Nutrition.dart';

class SnapFood extends StatefulWidget {
  const SnapFood({super.key});

  @override
  State<StatefulWidget> createState() => _SnapFoodState();
}

class _SnapFoodState extends State<SnapFood> {
  // Track the active button
  String _activeButton = 'Scan Food'; // Default active button
  // unused
  // removed unused: _permissionsRequested
  // ignore: unused_field
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
  // unused
  // removed unused: _formattedAnalysisResult
  // ignore: unused_field
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

    // Preload API connection for faster scanning
    _preloadApiConnection();

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

  // removed unused: _requestCameraPermission

  // removed unused: _requestPhotoLibraryPermission
  // ignore: unused_element
  void _requestPhotoLibraryPermission() {}

  // Local analysis fallback removed

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

    // LIGHTNING timer - 30 seconds for 15-second target
    Timer? processingTimer = Timer(Duration(seconds: 30), () {
      if (mounted && _isAnalyzing) {
        setState(() {
          _processingStep = _processingSteps.length - 1;
        });
      }
    });

    try {
      // PARALLEL PROCESSING START - All operations run simultaneously
      final List<Future> parallelTasks = [];

      // Task 1: API warmup (non-blocking)
      parallelTasks.add(FoodAnalyzerApi.warmupApi());

      // Task 2: Read and process image
      final Future<Uint8List> imageProcessingFuture =
          _processImageUltraFast(image);
      parallelTasks.add(imageProcessingFuture);

      // Task 3: Instant UI feedback
      _showInstantFeedback();

      // Wait for image processing to complete (other tasks continue in background)
      final Uint8List finalImage = await imageProcessingFuture;

      print(
          '⚡ Ultra-fast processing: ${(finalImage.length / 1024).toStringAsFixed(1)}KB ready');

      try {
        // LIGHTNING-FAST API call - 15 second target!
        final Map<String, dynamic> response =
            await FoodAnalyzerApi.analyzeFoodImageLightning(finalImage);

        // Cancel the processing timer
        processingTimer?.cancel();
        processingTimer = null;

        // VALIDATE API RESPONSE - Prevent mock data
        if (!_validateApiResponse(response)) {
          throw Exception('Invalid API response - possible mock data detected');
        }

        setState(() {
          _analysisResult = response;
          _formattedAnalysisResult = null;
        });

        // Extract the food name for the scan ID
        String foodName = 'Analyzed Meal';
        if (response.containsKey('meal_name')) {
          foodName = response['meal_name'];
        } else if (response.containsKey('food_name')) {
          foodName = response['food_name'];
        } else if (response.containsKey('name')) {
          foodName = response['name'];
        }

        // Generate a consistent scanId
        String scanId = _generateScanId(foodName);

        // Display the formatted results and navigate with the scanId
        _displayAnalysisResults(_analysisResult!, scanId);
      } catch (e) {
        // Cancel the processing timer
        processingTimer?.cancel();
        processingTimer = null;

        // no terminal spam

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
          } else if (e
              .toString()
              .contains("All API endpoints are unavailable")) {
            errorMessage =
                "Our servers are currently experiencing issues. Please try again in a few minutes or check your internet connection.";
          } else if (e.toString().contains("Analysis failed")) {
            errorMessage =
                "We couldn't analyze your food image. Please try again with a clearer photo showing the food clearly.";
          } else if (e.toString().contains("Invalid response") ||
              e.toString().contains("JSON")) {
            errorMessage =
                "There was an issue processing the analysis results. Please try again.";
          } else if (e.toString().contains("Failed to fetch") ||
              e.toString().contains("Failed to analyze image")) {
            errorMessage =
                "Unable to reach the analysis service. Please try again. Details: ${e.toString()}";
          } else {
            errorMessage =
                "We couldn't analyze your food image. Please try again with a clearer photo or check your internet connection. Details: ${e.toString()}";
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

  // Helper method to generate a consistent scanId - FIXED to match FoodCardOpen format
  String _generateScanId(String foodName) {
    // Normalize the food name - remove special characters, spaces, make lowercase
    final normalizedName = foodName.isEmpty
        ? 'analyzed_meal'
        : foodName
            .toLowerCase()
            .replaceAll(RegExp(r'[^\w\s]+'), '') // Remove special chars
            .replaceAll(RegExp(r'\s+'), '_'); // Replace spaces with underscores

    // CRITICAL FIX: Use the same format as FoodCardOpen.dart to ensure consistency
    // Remove timestamp to make scanId deterministic and matchable
    return 'food_nutrition_$normalizedName';
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
  // removed unused: _takePicture

  // Simplified version that doesn't use missing libraries
  // removed unused: _getBase64FromPath

  // removed unused: _compressImage

  void _displayAnalysisResults(
      Map<String, dynamic> analysisData, String scanId) {
    try {
      // Track if we've already handled navigation
      // navigation handled in push

      // Require the expected format strictly
      if (analysisData.containsKey('meal_name')) {
        String mealName = analysisData['meal_name'];
        List<dynamic> ingredients = analysisData['ingredients'] ?? [];
        if (ingredients.isEmpty) {
          throw Exception('Invalid or empty ingredients in analysis data');
        }

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
        // parsed values used only for validation below
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

        // Process micronutrients from OpenAI response
        Map<String, dynamic> correctedMicronutrients = {};
        allMicronutrients.forEach((key, value) {
          // OpenAI should now provide values in correct units, so use them directly
          correctedMicronutrients[key] = value.toString();
        });
        // no terminal output

        // Save the data
        List<Map<String, dynamic>> ingredientsList = [];

        // Expect ingredients as objects with nutrition data
        if (analysisData['ingredients'] is List) {
          List<dynamic> ingredientsFromAPI = analysisData['ingredients'];

          for (int i = 0; i < ingredientsFromAPI.length; i++) {
            var ingredientData = ingredientsFromAPI[i];

            if (ingredientData is Map<String, dynamic>) {
              // Extract nutrition data directly from the ingredient object
              Map<String, dynamic> processedIngredient = {
                'name':
                    ingredientData['name']?.toString() ?? 'Unknown Ingredient',
                'amount': ingredientData['amount']?.toString() ?? '100g',
                'calories':
                    _extractIngredientValue(ingredientData['calories'], 0),
                'protein': _extractIngredientValueAsDouble(
                    ingredientData['protein'], 0.0),
                'fat':
                    _extractIngredientValueAsDouble(ingredientData['fat'], 0.0),
                'carbs': _extractIngredientValueAsDouble(
                    ingredientData['carbs'], 0.0),
              };

              ingredientsList.add(processedIngredient);
            } else {
              throw Exception('Invalid ingredient data format');
            }
          }
        } else {
          throw Exception('Invalid ingredients format');
        }

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
          correctedMicronutrients, // Pass unit-corrected micronutrients
        );

        // navigation complete
      } else {
        throw Exception('Unexpected analysis format');
      }
    } catch (e) {
      // On any error, show error and return
      if (mounted) {
        _showCustomDialog('Analysis Error',
            'Invalid analysis data received. Please try again.');
        Navigator.of(context).pop();
      }
    }
  }

  // Helper method to extract nutrient values from a map, filtering by threshold
  // removed unused: _extractNutrientValues

  // Validate API response to prevent mock data
  bool _validateApiResponse(Map<String, dynamic> response) {
    // Check if response has required fields
    if (!response.containsKey('meal_name') &&
        !response.containsKey('food_name') &&
        !response.containsKey('name')) {
      debugPrint('❌ API response missing food name');
      return false;
    }

    // Check if calories are reasonable (not 0 or extremely high)
    if (response.containsKey('calories')) {
      int calories = int.tryParse(response['calories'].toString()) ?? 0;
      if (calories == 0 || calories > 5000) {
        debugPrint('❌ API response has suspicious calories: $calories');
        return false;
      }
    }

    // Check if ingredients list exists and is not empty
    if (!response.containsKey('ingredients') ||
        response['ingredients'] == null ||
        (response['ingredients'] is List && response['ingredients'].isEmpty)) {
      debugPrint('❌ API response missing or empty ingredients');
      return false;
    }

    // Check for suspicious default values
    String foodName = response['meal_name']?.toString() ??
        response['food_name']?.toString() ??
        response['name']?.toString() ??
        '';

    if (foodName.toLowerCase().contains('chicken') &&
        !foodName.toLowerCase().contains('dish') &&
        !foodName.toLowerCase().contains('meal')) {
      debugPrint('❌ API response has suspicious generic food name: $foodName');
      return false;
    }

    debugPrint('✅ API response validation passed');
    return true;
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
  // removed unused: _extractNumericValueAsInt

  // Helper method to extract numeric value with decimal places from a string - PRESERVE PRECISION
  // ignore: unused_element
  double _extractDecimalValue(String input) {
    return 0.0;
  }

  // Gets exact raw calorie value as double (not integer) to preserve precision
  // removed unused: _getRawCalorieValue

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
    // STRICT: SnapFood.dart is the ONLY source of scanId generation
    // Generate a unique, consistent scanId for this scan - use same format as existing cards
    final String finalScanId = scanId ??
        'food_nutrition_${foodName.isEmpty ? 'analyzed_meal' : foodName.replaceAll(' ', '_').toLowerCase()}';

    // STRICT: Validate generated scanId
    if (finalScanId.isEmpty) {
      throw StateError('SnapFood: Generated scanId cannot be empty');
    }

    // Use provided micronutrients or empty map
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

    // CRITICAL: Compress image to 100KB to prevent quota exceeded errors
    String? finalBase64Image;
    if (base64Image != null && base64Image.isNotEmpty) {
      print(
          '🔍 SNAPFOOD: Compressing image to 100KB to prevent quota errors...');
      try {
        finalBase64Image = await _compressImageForStorage(base64Image);
        print(
            '🔍 SNAPFOOD: Image compressed from ${(base64Image.length / 1024).toStringAsFixed(1)}KB to ${(finalBase64Image.length / 1024).toStringAsFixed(1)}KB');

        // If still too large, compress more aggressively
        if (finalBase64Image.length > 100 * 1024) {
          print(
              '⚠️ SNAPFOOD: Image still too large, compressing more aggressively...');
          finalBase64Image = await _compressImageForStorage(finalBase64Image);
          print(
              '🔍 SNAPFOOD: Final compression: ${(finalBase64Image.length / 1024).toStringAsFixed(1)}KB');
        }
      } catch (e) {
        print('⚠️ SNAPFOOD: Image compression failed, using original: $e');
        finalBase64Image = base64Image; // Use original if compression fails
      }
    }

    // CRITICAL: Create nutrition data structure for permanent storage
    Map<String, dynamic> nutritionData = {};

    // Add all the micronutrients from the scan results
    if (finalMicronutrients.isNotEmpty) {
      nutritionData.addAll(finalMicronutrients);
      print(
          '💾 SNAPFOOD: Added ${finalMicronutrients.length} micronutrients to food card');
    }

    // Add macronutrients to nutrition data
    nutritionData['protein'] = protein;
    nutritionData['fat'] = fat;
    nutritionData['carbs'] = carbs;
    nutritionData['calories'] = calories;
    nutritionData['food_name'] =
        foodName.isNotEmpty ? foodName : 'Analyzed Meal';
    nutritionData['last_updated'] = DateTime.now().millisecondsSinceEpoch;

    // Create food card data with original image AND nutrition data
    final Map<String, dynamic> foodCard = {
      'name': foodName.isNotEmpty ? foodName : 'Analyzed Meal',
      'calories': calories,
      'protein': protein,
      'fat': fat,
      'carbs': carbs,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      // Store compressed image directly in food card - no size limits
      'image': finalBase64Image ?? '',
      'has_image': (finalBase64Image != null && finalBase64Image.isNotEmpty),
      'ingredients': ingredientsList,
      'health_score': healthScore,
      'scan_id': finalScanId, // Store scanId in the food card data
      // CRITICAL: Store nutrition data directly in the food card
      'nutrition_data': nutritionData,
    };

    // DEBUG: Log what we're about to save
    debugPrint('Saving nutrition data for scanId: $finalScanId');

    // Separate try block for storage operations
    final prefs = await SharedPreferences.getInstance();
    try {
      // Load existing food cards

      // Don't store image separately - it's already in the card data
      // This prevents quota exceeded errors on web
      print('💾 Image stored directly in card data (no separate storage)');
      final List<String> storedCards = prefs.getStringList('food_cards') ?? [];

      // No cleanup needed - images stored in card data

      // Add new food card as JSON (image compressed to 0.4MB)
      final String foodCardJson = jsonEncode(foodCard);

      // Check final card size (allows any size)
      final int cardSizeBytes = foodCardJson.length;
      final double cardSizeMB = cardSizeBytes / (1024 * 1024);

      debugPrint(
          'SNAPFOOD: Final card size: ${cardSizeMB.toStringAsFixed(2)}MB');

      // Add the card (compressed image, but any card size allowed)
      storedCards.insert(0, foodCardJson);

      // Save updated list - no quota management, allow all sizes
      await prefs.setStringList('food_cards', storedCards);
      debugPrint('SNAPFOOD: Successfully saved ${storedCards.length} cards');

      // VERIFY THE SAVE WORKED
      final List<String>? verifyCards = prefs.getStringList('food_cards');
      if (verifyCards != null && verifyCards.length == storedCards.length) {
        debugPrint('SNAPFOOD: Save verified successfully');
      } else {
        debugPrint('SNAPFOOD: Save verification failed');

        // CRITICAL: Save nutrition data separately if food card save failed
        try {
          // Save nutrition data to individual key as backup
          String nutritionKey = 'nutrition_backup_$finalScanId';
          await prefs.setString(nutritionKey, jsonEncode(nutritionData));
          debugPrint('SNAPFOOD: Saved nutrition data backup');
        } catch (e) {
          debugPrint('SNAPFOOD: Failed to save nutrition backup');
        }
      }

      // Invalidate nutrition cache since new food data was added
      // main_codia.NutritionTracker.invalidateCacheStatic();
    } catch (e) {
      debugPrint('SNAPFOOD: Failed to save food card');
      // Try to save without image if storage fails
      try {
        final Map<String, dynamic> foodCardWithoutImage =
            Map<String, dynamic>.from(foodCard);
        foodCardWithoutImage['image'] = '';
        foodCardWithoutImage['has_image'] = false;

        final String foodCardJson = jsonEncode(foodCardWithoutImage);
        final List<String> storedCards =
            prefs.getStringList('food_cards') ?? [];
        storedCards.insert(0, foodCardJson);
        await prefs.setStringList('food_cards', storedCards);
        debugPrint('SNAPFOOD: Saved card without image as fallback');
      } catch (e2) {
        debugPrint('SNAPFOOD: Failed to save even without image');
      }
    }

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

    // Don't store display image separately - it's already in the card data

    // SAVE SCAN DATA TO NUTRITION MANAGER PERMANENTLY
    if (finalMicronutrients.isNotEmpty) {
      await _saveScanDataToNutritionManager(finalScanId, finalMicronutrients);
    }

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
  // removed unused: _testEchoFunction

  // Test the simple image analyzer function
  // removed unused: _testSimpleImageAnalyzer

  @override
  Widget build(BuildContext context) {
    // Process pending analysis only once
    if (_pendingAnalysis) {
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
  // removed unused: _optimizeImageBytes

  // Compress image and convert to base64
  // removed unused: _compressAndConvertToBase64

  // Helper method for optimizing single image bytes
  // removed unused: _optimizeSingleImage

  // Handle Uint8List compression consistently
  // removed unused: _compressBytesConsistently

  // Web-specific function to compress images using canvas
  // removed unused: _compressWebImageWithCanvas

  // Helper method to prepare an image for analysis when only file/bytes are available
  // removed unused: _prepareImageForAnalysis

  // Helper method to reduce image size on web platforms
  // removed unused: _reduceImageSizeForWeb

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
  // removed unused: _showErrorAlert

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

  // removed unused: _showCameraErrorDialog
  // ignore: unused_element
  void _showCameraErrorDialog() {}

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
  // removed unused: _formatAnalysisResult

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
  // removed unused: _extractNutrientsFromIngredients

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

  // Preload API connection to reduce cold start times
  void _preloadApiConnection() {
    // Start API warmup in background (non-blocking)
    FoodAnalyzerApi.preloadConnection().then((_) {
      print('🚀 API connection preloaded for faster scanning');
    }).catchError((e) {
      print('⚠️ API preload failed (non-critical): $e');
    });
  }

  // Ultra-fast parallel image processing
  Future<Uint8List> _processImageUltraFast(XFile image) async {
    final Completer<Uint8List> completer = Completer<Uint8List>();

    // Start image reading immediately
    final Future<Uint8List> readFuture = kIsWeb
        ? (_webImageBytes != null
            ? Future.value(_webImageBytes!)
            : image.readAsBytes())
        : image.readAsBytes();

    readFuture.then((imageBytes) async {
      if (imageBytes.isEmpty) {
        completer.completeError('Could not read image data');
        return;
      }

      print('⚡ Image read: ${(imageBytes.length / 1024).toStringAsFixed(1)}KB');

      // No minimum size requirements - allow all image sizes

      // Ultra-aggressive compression for maximum speed
      Uint8List finalImage = imageBytes;
      if (imageBytes.length > 1024 * 1024) {
        // 1MB threshold for ultra-fast mode
        finalImage = await _ultraFastCompression(imageBytes);
        print(
            '⚡ Ultra-compressed: ${(finalImage.length / 1024).toStringAsFixed(1)}KB');
      }

      completer.complete(finalImage);
    }).catchError((e) {
      completer.completeError(e);
    });

    return completer.future;
  }

  // ULTRA-FAST compression - SPEED PRIORITY
  Future<Uint8List> _ultraFastCompression(Uint8List imageBytes) async {
    try {
      // ULTRA-FAST TARGET: 250KB for maximum speed
      const int lightningTarget = 250 * 1024;

      if (imageBytes.length <= lightningTarget) {
        return imageBytes;
      }

      print(
          '⚡⚡ ULTRA-FAST compression: ${(imageBytes.length / 1024).toStringAsFixed(1)}KB → 250KB target');

      // SPEED-OPTIMIZED settings
      Uint8List compressed = await compressImage(
        imageBytes,
        quality: 70, // Good balance
        targetWidth: 800, // Larger for better recognition but faster processing
      );

      print(
          '⚡⚡ LIGHTNING result: ${(compressed.length / 1024).toStringAsFixed(1)}KB');
      return compressed;
    } catch (e) {
      print('⚠️ Lightning compression failed: $e');
      return imageBytes;
    }
  }

  // Show instant UI feedback
  void _showInstantFeedback() {
    // Immediate progress update
    Future.microtask(() {
      if (mounted) {
        setState(() {
          _processingStep = 1;
        });
      }
    });

    // Rapid progress animation
    Timer(Duration(milliseconds: 200), () {
      if (mounted && _isAnalyzing) {
        setState(() {
          _processingStep = 2;
        });
      }
    });
  }

  // Helper method to extract ingredient calorie value
  int _extractIngredientValue(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;

    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed.round();
    }

    return defaultValue;
  }

  // Helper method to extract ingredient nutrition value as double
  double _extractIngredientValueAsDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;

    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }

    return defaultValue;
  }

  // PERMANENT SCAN DATA STORAGE - Save scan data to NutritionDataManager
  Future<void> _saveScanDataToNutritionManager(
      String scanId, Map<String, dynamic> micronutrients) async {
    try {
      // silent

      // Initialize the NutritionDataManager if not already done
      await NutritionDataManager.initialize();

      // Convert micronutrients to the expected format for NutritionDataManager
      Map<String, NutrientInfo> vitamins = {};
      Map<String, NutrientInfo> minerals = {};
      Map<String, NutrientInfo> other = {};

      // Categorize the micronutrients into vitamins, minerals, and other
      micronutrients.forEach((key, value) {
        double numValue = 0.0;
        if (value is double) {
          numValue = value;
        } else if (value is int) {
          numValue = value.toDouble();
        } else if (value is String) {
          numValue = double.tryParse(value) ?? 0.0;
        }

        // Skip zero values
        if (numValue <= 0) return;

        String normalizedKey = key.toLowerCase();

        // Categorize nutrients
        if (_isVitamin(normalizedKey)) {
          vitamins[key] = NutrientInfo(
            name: key,
            value: '$numValue ${_getUnitForVitamin(key)}',
            percent: '${(numValue * 100 / 100).toStringAsFixed(0)}%',
            progress: (numValue / 100).clamp(0.0, 1.0),
            progressColor: Colors.orange,
          );
        } else if (_isMineral(normalizedKey)) {
          minerals[key] = NutrientInfo(
            name: key,
            value: '$numValue ${_getUnitForMineral(key)}',
            percent: '${(numValue * 100 / 100).toStringAsFixed(0)}%',
            progress: (numValue / 100).clamp(0.0, 1.0),
            progressColor: Colors.blue,
          );
        } else {
          other[key] = NutrientInfo(
            name: key,
            value: '$numValue ${_getUnitForNutrient(key)}',
            percent: '${(numValue * 100 / 100).toStringAsFixed(0)}%',
            progress: (numValue / 100).clamp(0.0, 1.0),
            progressColor: Colors.green,
          );
        }
      });

      // Store the data permanently (silent)

      await NutritionDataManager.storeNutritionData(
          scanId, vitamins, minerals, other);

      // silent
    } catch (e) {
      // silent
    }
  }

  // Helper method to check if a nutrient is a vitamin
  bool _isVitamin(String nutrientName) {
    String name = nutrientName.toLowerCase();
    return name.contains('vitamin') ||
        name == 'a' ||
        name == 'c' ||
        name == 'd' ||
        name == 'e' ||
        name == 'k' ||
        name.startsWith('b') ||
        name == 'thiamine' ||
        name == 'riboflavin' ||
        name == 'niacin' ||
        name == 'folate' ||
        name == 'biotin';
  }

  // Helper method to check if a nutrient is a mineral
  bool _isMineral(String nutrientName) {
    String name = nutrientName.toLowerCase();
    return name == 'calcium' ||
        name == 'iron' ||
        name == 'magnesium' ||
        name == 'phosphorus' ||
        name == 'potassium' ||
        name == 'sodium' ||
        name == 'zinc' ||
        name == 'copper' ||
        name == 'manganese' ||
        name == 'selenium' ||
        name == 'chromium' ||
        name == 'iodine';
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

// Image compression helper function - PROPER COMPRESSION
Future<String> _compressImageForStorage(String base64Image) async {
  try {
    // Decode base64 to bytes
    final Uint8List imageBytes = base64Decode(base64Image);

    // Target size: 100KB to prevent quota exceeded errors
    final int targetSize = 100 * 1024; // 100KB target

    if (imageBytes.length <= targetSize) {
      return base64Image; // Already small enough
    }

    // PROPER COMPRESSION: Use quality-based compression instead of truncation
    // Use proper image compression with quality reduction
    Uint8List compressedBytes = await compressImage(
      imageBytes,
      quality: 60, // Reduce quality to 60%
      targetWidth: 800, // Reduce width to 800px
    );

    // If still too large, compress more aggressively
    if (compressedBytes.length > targetSize) {
      compressedBytes = await compressImage(
        compressedBytes,
        quality: 40, // Reduce quality to 40%
        targetWidth: 600, // Reduce width to 600px
      );
    }

    final String compressedBase64 = base64Encode(compressedBytes);
    return compressedBase64;
  } catch (e) {
    debugPrint('SNAPFOOD: Image compression failed');
    return base64Image; // Return original if compression fails
  }
}

// Storage cleanup helper function
Future<void> _cleanupOldImageKeys(SharedPreferences prefs) async {
  try {
    // Get all keys and find old image keys
    final Set<String> allKeys = prefs.getKeys();
    final List<String> imageKeys = allKeys
        .where((key) =>
            key.startsWith('food_card_image_') ||
            key.startsWith('flutter.food_card_image_'))
        .toList();

    // Keep only the 3 most recent image keys to prevent quota issues
    if (imageKeys.length > 3) {
      // Sort by timestamp if available, otherwise just take the first 5
      imageKeys.sort((a, b) => b.compareTo(a)); // Simple reverse sort
      final List<String> keysToRemove = imageKeys.skip(3).toList();

      for (String key in keysToRemove) {
        try {
          await prefs.remove(key);
        } catch (e) {
          debugPrint('Failed to clean up image key');
        }
      }
    }
  } catch (e) {
    debugPrint('Storage cleanup failed');
  }
}
