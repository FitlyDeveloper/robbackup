import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart';
import '../Features/codia/codia_page.dart';
import '../Features/codia/Nutrition.dart' as nutrition_page;
import 'dart:math';
import 'dart:ui';
import 'dart:async';
import 'package:fitness_app/NewScreens/food_helper_methods.dart';
import 'package:provider/provider.dart';
import 'dialog_helper.dart';

// Custom scroll physics optimized for mouse wheel
class SlowScrollPhysics extends ScrollPhysics {
  const SlowScrollPhysics({ScrollPhysics? parent}) : super(parent: parent);

  @override
  SlowScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SlowScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return offset * 0.4; // Slow down by 60%
  }
}

class FoodCardOpen extends StatefulWidget {
  final String? foodName;
  final String? healthScore;
  final String? calories;
  final String? protein;
  final String? fat;
  final String? carbs;
  final String? imageBase64;
  final List<Map<String, dynamic>>? ingredients;
  final Map<String, dynamic>? additionalNutrients;
  final String? scanId; // Add scan ID parameter

  const FoodCardOpen({
    super.key,
    this.foodName,
    this.healthScore,
    this.calories,
    this.protein,
    this.fat,
    this.carbs,
    this.imageBase64,
    this.ingredients,
    this.additionalNutrients,
    this.scanId, // Include scan ID in constructor
  });

  @override
  State<FoodCardOpen> createState() => _FoodCardOpenState();
}

class _FoodCardOpenState extends State<FoodCardOpen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _isLiked = false;
  bool _isBookmarked = false; // Track bookmark state
  bool _isEditMode = false; // Track if we're in edit mode for teal outlines
  int _counter = 1; // Counter for +/- buttons
  String _privacyStatus =
      'Private'; // Default privacy status changed to Private
  bool _hasUnsavedChanges = false; // Track whether user has made changes
  // Original values to compare for changes
  String _originalFoodName = '';
  String _originalHealthScore = '';
  String _originalCalories = '';
  String _originalProtein = '';
  String _originalFat = '';
  String _originalCarbs = '';
  int _originalCounter = 1;

  // Keep a backup of original ingredients for restoring if changes are discarded
  List<Map<String, dynamic>> _originalIngredients = [];

  late AnimationController _bookmarkController;
  late Animation<double> _bookmarkScaleAnimation;
  late AnimationController _likeController;
  late Animation<double> _likeScaleAnimation;
  // Initialize with default values to prevent late initialization errors
  String _foodName = 'Delicious Meal';
  String _healthScore = '8/10';
  double _healthScoreValue = 0.8;
  String _calories = '0';
  String _protein = '0';
  String _fat = '0';
  String _carbs = '0';
  Uint8List? _imageBytes; // Store decoded image bytes
  String?
      _storedImageBase64; // For storing retrieved image from SharedPreferences
  List<Map<String, dynamic>> _ingredients = []; // Store ingredients list
  Map<String, bool> _isIngredientFlipped = {};
  Set<String> _flippedCards = {}; // Track flipped cards
  Map<String, AnimationController> _flipAnimationControllers = {};
  Map<String, Animation<double>> _flipAnimations = {};

  @override
  void initState() {
    super.initState();
    print('FoodCardOpen initState called');

    // Initialize with no unsaved changes
    _hasUnsavedChanges = false;

    // Initialize animation controllers
    _initAnimationControllers();

    // Set initial values from parameters if available - but don't set _originalXXX yet
    if (widget.foodName != null && widget.foodName!.isNotEmpty) {
      _foodName = widget.foodName!;
      // We'll set _originalFoodName later after all data is loaded
    }

    if (widget.healthScore != null && widget.healthScore!.isNotEmpty) {
      _healthScore = widget.healthScore!;
      _healthScoreValue = _extractHealthScoreValue(_healthScore);
      // We'll set _originalHealthScore later
    }

    if (widget.calories != null && widget.calories!.isNotEmpty) {
      _calories = _formatDecimalValue(widget.calories!);
      // We'll set _originalCalories later
    }

    if (widget.protein != null && widget.protein!.isNotEmpty) {
      _protein = widget.protein!;
      // We'll set _originalProtein later
    }

    if (widget.fat != null && widget.fat!.isNotEmpty) {
      _fat = widget.fat!;
      // We'll set _originalFat later
    }

    if (widget.carbs != null && widget.carbs!.isNotEmpty) {
      _carbs = widget.carbs!;
      // We'll set _originalCarbs later
    }

    _counter = 1; // Always start at 1
    // We'll set _originalCounter later

    // Process image if available
    _processImage();

    // Load saved data from SharedPreferences
    _loadSavedData().then((_) {
      // Initialize food data if needed
      if (_ingredients.isEmpty) {
        _initFoodData();
      }

      // Create backup of original ingredients for potential restore on discard
      _backupOriginalIngredients();

      // Calculate total nutrition after everything is loaded
      if (mounted) {
        _calculateTotalNutrition();

        // Important: Now set the original values to match current values
        // This will ensure _checkForUnsavedChanges() returns false initially
        _resetUnsavedChangesState();
      }
    });
  }

  // Create a deep copy of ingredients to restore if changes are discarded
  void _backupOriginalIngredients() {
    _originalIngredients = [];
    for (var ingredient in _ingredients) {
      _originalIngredients.add(Map<String, dynamic>.from(ingredient));
    }
    print('Backed up ${_originalIngredients.length} original ingredients');
  }

  // Restore original ingredients when discarding changes
  void _restoreOriginalIngredients() {
    _ingredients = [];
    for (var ingredient in _originalIngredients) {
      _ingredients.add(Map<String, dynamic>.from(ingredient));
    }
    print('Restored ${_ingredients.length} original ingredients');
  }

  // Debug method to print ingredient details
  void _debugPrintIngredients(String source) {
    print('\n========== INGREDIENTS DEBUG ($source) ==========');
    print('Food: $_foodName');
    print('Ingredient count: ${_ingredients.length}');

    for (int i = 0; i < _ingredients.length; i++) {
      var ingredient = _ingredients[i];
      String name = ingredient['name'] ?? 'NO NAME';
      String amount = ingredient['amount'] ?? 'NO AMOUNT';
      var calories = ingredient['calories'] ?? 'NO CALORIES';
      var protein = ingredient['protein'] ?? '0';
      var fat = ingredient['fat'] ?? '0';
      var carbs = ingredient['carbs'] ?? '0';

      print(
          '[$i] $name - $amount - $calories kcal (${calories.runtimeType}) - ' +
              'P: $protein, F: $fat, C: $carbs');
    }

    print('===========================================\n');
  }

  void _initAnimationControllers() {
    // Bookmark animations
    _bookmarkController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );

    _bookmarkScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(
      CurvedAnimation(
        parent: _bookmarkController,
        curve: Curves.easeOutBack,
      ),
    );

    // Like animations
    _likeController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );

    _likeScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(
      CurvedAnimation(
        parent: _likeController,
        curve: Curves.easeOutBack,
      ),
    );
  }

  void _initFoodData() {
    print(
        'Initializing food data. Current name: $_foodName, ingredients count: ${_ingredients.length}');

    // Skip all initialization if we already have ingredients loaded from SharedPreferences
    if (_ingredients.isNotEmpty) {
      print(
          'Ingredients already loaded from SharedPreferences, skipping initialization');
      return;
    }

    // Initialize ingredients list with 17-character limit enforcement
    if (widget.ingredients != null && widget.ingredients!.isNotEmpty) {
      _ingredients = [];

      // Process each ingredient and split if necessary
      for (var ingredient in widget.ingredients!) {
        // Ensure ingredient is a Map<String, dynamic>
        if (ingredient is! Map<String, dynamic>) {
          print('Skipping invalid ingredient: $ingredient (not a Map)');
          continue;
        }

        // Extract ingredient data with proper fallbacks
        String name = ingredient['name'] ?? '';
        String amount =
            ingredient['amount'] ?? '1 serving'; // Ensure we keep the amount

        // Enforce 16-character limit for amount
        if (amount.length > 16) {
          amount = amount.substring(0, 13) + "...";
        }

        // Handle different types of calories values properly
        dynamic calories = ingredient['calories'] ?? 0;
        // If calories is a string, try to parse it to a number
        if (calories is String) {
          try {
            calories = double.tryParse(calories) ?? 0;
          } catch (e) {
            calories = 0;
          }
        }

        // Get macronutrient values with proper handling
        double protein = 0.0;
        double fat = 0.0;
        double carbs = 0.0;

        // Process protein value
        if (ingredient.containsKey('protein')) {
          var proteinValue = ingredient['protein'];
          if (proteinValue is String) {
            protein = double.tryParse(proteinValue) ?? 0.0;
          } else if (proteinValue is num) {
            protein = proteinValue.toDouble();
          }
        }

        // Process fat value
        if (ingredient.containsKey('fat')) {
          var fatValue = ingredient['fat'];
          if (fatValue is String) {
            fat = double.tryParse(fatValue) ?? 0.0;
          } else if (fatValue is num) {
            fat = fatValue.toDouble();
          }
        }

        // Process carbs value
        if (ingredient.containsKey('carbs')) {
          var carbsValue = ingredient['carbs'];
          if (carbsValue is String) {
            carbs = double.tryParse(carbsValue) ?? 0.0;
          } else if (carbsValue is num) {
            carbs = carbsValue.toDouble();
          }
        }

        // Skip ingredients containing "with"
        if (name.toLowerCase().contains(' with ')) {
          // Split at "with" instead of skipping
          List<String> parts = name.split(' with ');
          if (parts.length >= 2) {
            // Add first part with original amount and calories
            if (parts[0].isNotEmpty && parts[0].length <= 16) {
              _ingredients.add({
                'name': parts[0].trim(),
                'amount': amount, // Keep original amount
                'calories': calories, // Keep original calories
                'protein': protein,
                'fat': fat,
                'carbs': carbs
              });
            } else if (parts[0].isNotEmpty) {
              // First part exceeds 16 characters, truncate with ellipsis
              _ingredients.add({
                'name': parts[0].trim().substring(0, 13) + "...",
                'amount': amount,
                'calories': calories,
                'protein': protein,
                'fat': fat,
                'carbs': carbs
              });
            }

            // Add second part
            if (parts[1].isNotEmpty && parts[1].length <= 16) {
              _ingredients.add({
                'name': parts[1].trim(),
                'amount': amount, // Keep original amount
                'calories':
                    calories / 2, // Split calories between two ingredients
                'protein': protein / 2,
                'fat': fat / 2,
                'carbs': carbs / 2
              });
            } else if (parts[1].isNotEmpty) {
              // Second part exceeds 16 characters, truncate with ellipsis
              _ingredients.add({
                'name': parts[1].trim().substring(0, 13) + "...",
                'amount': amount,
                'calories': calories / 2,
                'protein': protein / 2,
                'fat': fat / 2,
                'carbs': carbs / 2
              });
            }
          }
          continue; // Skip the rest of the loop
        }

        // Check if name exceeds 16 characters
        if (name.length > 16) {
          // Split the name by spaces
          List<String> words = name.split(' ');
          String currentSegment = '';

          for (var word in words) {
            // If adding this word would exceed limit, create a new ingredient with current segment
            if (currentSegment.isNotEmpty &&
                (currentSegment.length + word.length + 1) > 16) {
              _ingredients.add({
                'name': currentSegment.trim(),
                'amount': amount, // Keep original amount
                'calories': calories, // Keep original calories
                'protein': protein,
                'fat': fat,
                'carbs': carbs
              });
              currentSegment = word;
            } else {
              // Add word to current segment
              if (currentSegment.isEmpty) {
                currentSegment = word;
              } else {
                currentSegment += ' $word';
              }
            }
          }

          // Add remaining segment as an ingredient
          if (currentSegment.isNotEmpty) {
            if (currentSegment.length <= 16) {
              _ingredients.add({
                'name': currentSegment.trim(),
                'amount': amount, // Keep original amount
                'calories': calories, // Keep original calories
                'protein': protein,
                'fat': fat,
                'carbs': carbs
              });
            } else {
              // Truncate with ellipsis if still too long
              _ingredients.add({
                'name': currentSegment.trim().substring(0, 13) + "...",
                'amount': amount,
                'calories': calories,
                'protein': protein,
                'fat': fat,
                'carbs': carbs
              });
            }
          }
        } else {
          // Name is within limit, add as is with original values
          _ingredients.add({
            'name': name,
            'amount': amount,
            'calories': calories,
            'protein': protein,
            'fat': fat,
            'carbs': carbs
          });
        }
      }

      // Sort ingredients by calories (highest to lowest)
      _ingredients.sort((a, b) {
        final caloriesA = a.containsKey('calories')
            ? double.tryParse(a['calories'].toString()) ?? 0
            : 0;
        final caloriesB = b.containsKey('calories')
            ? double.tryParse(b['calories'].toString()) ?? 0
            : 0;
        return caloriesB.compareTo(caloriesA);
      });

      // Debug print the processed ingredients
      _debugPrintIngredients('After processing widget ingredients');

      // We've processed widget.ingredients - immediately save them to SharedPreferences
      // to make sure they persist across screens
      _saveData();
    }

    print(
        'Initialized food data: name=$_foodName, calories=$_calories, protein=$_protein, fat=$_fat, carbs=$_carbs, healthScore=$_healthScore');
  }

  void _processImage() {
    // Try to use image from parameters first
    if (widget.imageBase64 != null && widget.imageBase64!.isNotEmpty) {
      try {
        // Store the original image base64 to avoid any quality loss
        _storedImageBase64 = widget.imageBase64;

        // Decode base64 string to bytes
        _imageBytes = base64Decode(widget.imageBase64!);
        print(
            'Loaded image from passed parameter, size: ${_imageBytes!.length} bytes');

        // Call optimize method
        _optimizeImage();
      } catch (e) {
        print('Error decoding image from parameter: $e');
      }
    }
  }

  // Add this method to reset the unsaved changes state after loading
  void _resetUnsavedChangesState() {
    // Update all original values to match current values
    _originalFoodName = _foodName;
    _originalHealthScore = _healthScore;
    _originalCalories = _calories;
    _originalProtein = _protein;
    _originalFat = _fat;
    _originalCarbs = _carbs;
    _originalCounter = _counter;

    // Create a fresh backup of ingredients
    _backupOriginalIngredients();

    // Reset the unsaved changes flag
    _hasUnsavedChanges = false;

    print('Reset unsaved changes state - screen is now in clean state');
  }

  // At the end of _loadSavedData method, add call to reset unsaved changes state
  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final foodId = _foodName.replaceAll(' ', '_').toLowerCase();

      print('Attempting to load saved data for foodId: $foodId');

      // Load ingredients array
      final ingredientsJson = prefs.getString('food_ingredients_$foodId');
      print('Loaded ingredients JSON: $ingredientsJson');

      if (ingredientsJson != null) {
        try {
          final List<dynamic> decoded = jsonDecode(ingredientsJson);
          _ingredients = [];

          // Process each item in the decoded list
          for (var item in decoded) {
            // Handle both object and string formats
            if (item is Map) {
              // Make sure all required fields exist
              if (!item.containsKey('name') ||
                  !item.containsKey('amount') ||
                  !item.containsKey('calories')) {
                // Add missing fields with defaults
                item['name'] = item['name'] ?? 'Ingredient';
                item['amount'] = item['amount'] ?? '1 serving';
                item['calories'] = item['calories'] ?? 0;
              }

              // Ensure macronutrient values are properly converted to doubles
              double protein = 0.0;
              double fat = 0.0;
              double carbs = 0.0;

              // Process protein value
              if (item.containsKey('protein')) {
                var proteinValue = item['protein'];
                if (proteinValue is String) {
                  protein = double.tryParse(proteinValue) ?? 0.0;
                } else if (proteinValue is num) {
                  protein = proteinValue.toDouble();
                }
              }

              // Process fat value
              if (item.containsKey('fat')) {
                var fatValue = item['fat'];
                if (fatValue is String) {
                  fat = double.tryParse(fatValue) ?? 0.0;
                } else if (fatValue is num) {
                  fat = fatValue.toDouble();
                }
              }

              // Process carbs value
              if (item.containsKey('carbs')) {
                var carbsValue = item['carbs'];
                if (carbsValue is String) {
                  carbs = double.tryParse(carbsValue) ?? 0.0;
                } else if (carbsValue is num) {
                  carbs = carbsValue.toDouble();
                }
              }

              // Also include macro values with fallbacks
              Map<String, dynamic> validIngredient = {
                'name': item['name'] ?? 'Ingredient',
                'amount': item['amount'] ?? '1 serving',
                'calories': item['calories'] ?? 0,
                'protein': protein,
                'fat': fat,
                'carbs': carbs,
              };

              _ingredients.add(validIngredient);
            } else if (item is String) {
              // Handle old format - string-only ingredients
              // Create default ingredient object
              Map<String, dynamic> validIngredient = {
                'name': item,
                'amount': '1 serving',
                'calories': 100,
                'protein': 5.0,
                'fat': 2.0,
                'carbs': 15.0,
              };
              _ingredients.add(validIngredient);
            }
          }
          print(
              'Loaded and validated ${_ingredients.length} ingredients from SharedPreferences');
        } catch (e) {
          print('Error parsing saved ingredients: $e');
          _ingredients = []; // Reset to empty on error
        }
      }

      setState(() {
        // Load interaction data only (likes, bookmarks, counter)
        _isLiked = prefs.getBool('food_liked_$foodId') ?? false;
        _isBookmarked = prefs.getBool('food_bookmarked_$foodId') ?? false;
        _counter = prefs.getInt('food_counter_$foodId') ?? 1;
        // Load privacy status for this food item
        _privacyStatus = prefs.getString('food_privacy_$foodId') ?? 'Private';

        // Only load nutrition values if they weren't passed as parameters
        if (widget.calories == null || widget.calories!.isEmpty) {
          _calories = _formatDecimalValue(
              prefs.getString('food_calories_$foodId') ?? _calories);
        }

        if (widget.protein == null || widget.protein!.isEmpty) {
          _protein = prefs.getString('food_protein_$foodId') ?? _protein;
        }

        if (widget.fat == null || widget.fat!.isEmpty) {
          _fat = prefs.getString('food_fat_$foodId') ?? _fat;
        }

        if (widget.carbs == null || widget.carbs!.isEmpty) {
          _carbs = prefs.getString('food_carbs_$foodId') ?? _carbs;
        }

        if (widget.healthScore == null || widget.healthScore!.isEmpty) {
          _healthScore =
              prefs.getString('food_health_score_$foodId') ?? _healthScore;
          // Update health score value when loaded
          _healthScoreValue = _extractHealthScoreValue(_healthScore);
        }

        // Load image from SharedPreferences if not already loaded from parameter
        if (_imageBytes == null) {
          _storedImageBase64 = prefs.getString('food_image_$foodId');
          if (_storedImageBase64 != null && _storedImageBase64!.isNotEmpty) {
            print(
                'Loading image from SharedPreferences: ${_storedImageBase64!.length} characters');
            try {
              _imageBytes = base64Decode(_storedImageBase64!);
              print(
                  'Loaded image from SharedPreferences, size: ${_imageBytes!.length} bytes');

              // Call optimize method
              _optimizeImage();
            } catch (e) {
              print('Error decoding stored image: $e');
            }
          }
        }
      });

      // After loading - check what we have
      _debugPrintIngredients('After load');

      print(
          'Loaded interaction data for $foodId: liked=$_isLiked, bookmarked=$_isBookmarked, counter=$_counter');
      print(
          'Using nutrition data: calories=$_calories, protein=$_protein, fat=$_fat, carbs=$_carbs, healthScore=$_healthScore');
      if (_ingredients.isNotEmpty) {
        print('Loaded ${_ingredients.length} ingredients');

        // Calculate total nutrition from all ingredients after loading
        _calculateTotalNutrition();
        print('Calculated total nutrition values from loaded ingredients');
      }

      // Important: Reset unsaved changes state after everything is loaded
      _resetUnsavedChangesState();
    } catch (e) {
      print('Error loading saved food data: $e');
    }
  }

  // Save all data to SharedPreferences
  Future<void> _saveData() async {
    // Debug output before saving
    _debugPrintIngredients('Before save');

    try {
      print('Saving all data to SharedPreferences...');
      final prefs = await SharedPreferences.getInstance();
      final String foodId = _foodName.replaceAll(' ', '_').toLowerCase();

      // First, recalculate nutrition totals to ensure they're up to date
      // This ensures ingredients and nutrition values are always in sync
      _calculateTotalNutrition();

      // Store ingredients list
      if (_ingredients.isNotEmpty) {
        print('Saving ${_ingredients.length} ingredients');
        // Validate that _ingredients contains valid Map objects before saving
        List<Map<String, dynamic>> validIngredients = [];
        for (var ingredient in _ingredients) {
          if (ingredient is Map<String, dynamic>) {
            // Create a map with all required data to ensure format consistency
            Map<String, dynamic> validIngredient = {
              'name': ingredient['name'] ?? 'Ingredient',
              'amount': ingredient['amount'] ?? '1 serving',
              'calories': ingredient['calories'] ?? 0,
              // Include macros with proper type conversion
              'protein': _convertToDouble(ingredient['protein']),
              'fat': _convertToDouble(ingredient['fat']),
              'carbs': _convertToDouble(ingredient['carbs']),
            };
            // Copy any micronutrient data that might exist
            if (ingredient.containsKey('vitamins') &&
                ingredient['vitamins'] is Map) {
              validIngredient['vitamins'] =
                  Map<String, dynamic>.from(ingredient['vitamins']);
            }
            if (ingredient.containsKey('minerals') &&
                ingredient['minerals'] is Map) {
              validIngredient['minerals'] =
                  Map<String, dynamic>.from(ingredient['minerals']);
            }
            if (ingredient.containsKey('other') && ingredient['other'] is Map) {
              validIngredient['other'] =
                  Map<String, dynamic>.from(ingredient['other']);
            }
            validIngredients.add(validIngredient);
          }
        }

        final ingredientsJson = jsonEncode(validIngredients);
        await prefs.setString('food_ingredients_$foodId', ingredientsJson);
        print('Successfully saved ingredients to SharedPreferences');

        // IMPORTANT: Also update the ingredients in the food_cards list
        // This ensures that when returning to FoodCardOpen, we have correct ingredients
        final List<String>? storedCards = prefs.getStringList('food_cards');
        if (storedCards != null && storedCards.isNotEmpty) {
          List<String> updatedCards = [];
          bool foundCard = false;

          // Find the correct card and update it
          for (String cardJson in storedCards) {
            try {
              Map<String, dynamic> cardData = jsonDecode(cardJson);
              String cardName = cardData['name'] ?? '';

              // If this is our card, update the ingredients
              if (cardName.toLowerCase() == _foodName.toLowerCase()) {
                foundCard = true;

                // Update with our valid ingredients
                cardData['ingredients'] = validIngredients;

                // Also save the counter value in the food card data
                // This will be used by codia_page.dart to multiply the nutrition values
                cardData['counter'] = _counter;

                // Update the total nutrition values for the meal card - base values (not multiplied)
                // These values come directly from _calculateTotalNutrition
                cardData['calories'] = _calories.toString();
                cardData['protein'] = _protein.toString();
                cardData['fat'] = _fat.toString();
                cardData['carbs'] = _carbs.toString();
                cardData['health_score'] = _healthScore;

                // Also create ingredient lookup maps for future use
                Map<String, dynamic> ingredientAmounts = {};
                Map<String, dynamic> ingredientCalories = {};
                Map<String, dynamic> ingredientProteins = {};
                Map<String, dynamic> ingredientFats = {};
                Map<String, dynamic> ingredientCarbs = {};

                for (var ingredient in validIngredients) {
                  String name = ingredient['name'];
                  ingredientAmounts[name] = ingredient['amount'];
                  ingredientCalories[name] = ingredient['calories'];
                  ingredientProteins[name] = ingredient['protein'];
                  ingredientFats[name] = ingredient['fat'];
                  ingredientCarbs[name] = ingredient['carbs'];
                }

                cardData['ingredient_amounts'] = ingredientAmounts;
                cardData['ingredient_calories'] = ingredientCalories;
                cardData['ingredient_proteins'] = ingredientProteins;
                cardData['ingredient_fats'] = ingredientFats;
                cardData['ingredient_carbs'] = ingredientCarbs;

                // Save any top-level micronutrient data if available
                if (widget.additionalNutrients != null &&
                    widget.additionalNutrients!.isNotEmpty) {
                  // Check for vitamins and minerals - preserve them
                  if (widget.additionalNutrients!.containsKey('vitamins')) {
                    cardData['vitamins'] =
                        widget.additionalNutrients!['vitamins'];
                  }
                  if (widget.additionalNutrients!.containsKey('minerals')) {
                    cardData['minerals'] =
                        widget.additionalNutrients!['minerals'];
                  }
                  if (widget.additionalNutrients!
                      .containsKey('other_nutrients')) {
                    cardData['other_nutrients'] =
                        widget.additionalNutrients!['other_nutrients'];
                  }
                }

                // Update with our high quality image - preserve original quality
                if (_storedImageBase64 != null &&
                    _storedImageBase64!.isNotEmpty) {
                  cardData['image'] = _storedImageBase64;
                  print(
                      'Using high-quality stored image data for food_cards: ${_storedImageBase64!.length} characters');
                }

                // Add the updated card to our list
                updatedCards.add(jsonEncode(cardData));
              } else {
                // Not our card, keep it as is
                updatedCards.add(cardJson);
              }
            } catch (e) {
              print('Error updating food card ingredient data: $e');
              // If there was an error, keep the original card
              updatedCards.add(cardJson);
            }
          }

          // Save the updated cards list back to SharedPreferences
          if (foundCard) {
            await prefs.setStringList('food_cards', updatedCards);
            print('Updated ingredients in food_cards list for: $_foodName');
            print(
                'Updated total nutrition values in food_cards list: calories=$_calories, protein=$_protein, fat=$_fat, carbs=$_carbs');
          } else {
            // If the card wasn't found in food_cards, we might need to add it
            print('Card not found in food_cards list, creating new card');

            // Create a new card with current data
            Map<String, dynamic> newCard = {
              'name': _foodName,
              'calories': _calories.toString(),
              'protein': _protein.toString(),
              'fat': _fat.toString(),
              'carbs': _carbs.toString(),
              'health_score': _healthScore,
              'ingredients': validIngredients,
              'counter': _counter, // Add counter to food card
              'time': DateTime.now().millisecondsSinceEpoch.toString(),
            };

            // Add image if available
            if (_storedImageBase64 != null && _storedImageBase64!.isNotEmpty) {
              newCard['image'] = _storedImageBase64;
            }

            // Create ingredient lookup maps
            Map<String, dynamic> ingredientAmounts = {};
            Map<String, dynamic> ingredientCalories = {};
            Map<String, dynamic> ingredientProteins = {};
            Map<String, dynamic> ingredientFats = {};
            Map<String, dynamic> ingredientCarbs = {};

            for (var ingredient in validIngredients) {
              String name = ingredient['name'];
              ingredientAmounts[name] = ingredient['amount'];
              ingredientCalories[name] = ingredient['calories'];
              ingredientProteins[name] = ingredient['protein'];
              ingredientFats[name] = ingredient['fat'];
              ingredientCarbs[name] = ingredient['carbs'];
            }

            newCard['ingredient_amounts'] = ingredientAmounts;
            newCard['ingredient_calories'] = ingredientCalories;
            newCard['ingredient_proteins'] = ingredientProteins;
            newCard['ingredient_fats'] = ingredientFats;
            newCard['ingredient_carbs'] = ingredientCarbs;

            // Add the new card to stored cards
            updatedCards.add(jsonEncode(newCard));
            await prefs.setStringList('food_cards', updatedCards);
            print('Added new card to food_cards list for: $_foodName');
          }
        } else {
          // No stored cards yet, create a new list with just this card
          print('No existing food_cards list, creating new one');

          // Create a new card with current data
          Map<String, dynamic> newCard = {
            'name': _foodName,
            'calories': _calories.toString(),
            'protein': _protein.toString(),
            'fat': _fat.toString(),
            'carbs': _carbs.toString(),
            'health_score': _healthScore,
            'ingredients': validIngredients,
            'counter': _counter, // Add counter to food card
            'time': DateTime.now().millisecondsSinceEpoch.toString(),
          };

          // Add image if available
          if (_storedImageBase64 != null && _storedImageBase64!.isNotEmpty) {
            newCard['image'] = _storedImageBase64;
          }

          // Create ingredient lookup maps
          Map<String, dynamic> ingredientAmounts = {};
          Map<String, dynamic> ingredientCalories = {};
          Map<String, dynamic> ingredientProteins = {};
          Map<String, dynamic> ingredientFats = {};
          Map<String, dynamic> ingredientCarbs = {};

          for (var ingredient in validIngredients) {
            String name = ingredient['name'];
            ingredientAmounts[name] = ingredient['amount'];
            ingredientCalories[name] = ingredient['calories'];
            ingredientProteins[name] = ingredient['protein'];
            ingredientFats[name] = ingredient['fat'];
            ingredientCarbs[name] = ingredient['carbs'];
          }

          newCard['ingredient_amounts'] = ingredientAmounts;
          newCard['ingredient_calories'] = ingredientCalories;
          newCard['ingredient_proteins'] = ingredientProteins;
          newCard['ingredient_fats'] = ingredientFats;
          newCard['ingredient_carbs'] = ingredientCarbs;

          // Create a new list with just this card
          await prefs.setStringList('food_cards', [jsonEncode(newCard)]);
          print('Created new food_cards list with card for: $_foodName');
        }
      }

      await prefs.setBool('food_liked_$foodId', _isLiked);
      await prefs.setBool('food_bookmarked_$foodId', _isBookmarked);
      await prefs.setInt('food_counter_$foodId', _counter);
      await prefs.setString(
          'food_privacy_$foodId', _privacyStatus); // Save the privacy setting

      // Save all nutrition values
      await prefs.setString('food_calories_$foodId', _calories);
      await prefs.setString('food_protein_$foodId', _protein);
      await prefs.setString('food_fat_$foodId', _fat);
      await prefs.setString('food_carbs_$foodId', _carbs);
      await prefs.setString('food_health_score_$foodId', _healthScore);

      // Save image if available - ensure high quality
      if (_imageBytes != null || _storedImageBase64 != null) {
        // Prefer to use the stored base64 string directly if available
        // This prevents re-encoding which can reduce quality
        String imageData;
        if (_storedImageBase64 != null && _storedImageBase64!.isNotEmpty) {
          imageData = _storedImageBase64!;
          print(
              'Using original stored image data: ${imageData.length} characters');
        } else {
          // Only re-encode if we must
          imageData = base64Encode(_imageBytes!);
          print('Re-encoded image data: ${imageData.length} characters');
        }

        // Store the image
        await prefs.setString('food_image_$foodId', imageData);

        // Also update the image in the food_cards list to ensure high quality there too
        final List<String>? storedCards = prefs.getStringList('food_cards');
        if (storedCards != null && storedCards.isNotEmpty) {
          List<String> updatedCards = [];
          bool foundCard = false;

          // Find the correct card and update its image
          for (String cardJson in storedCards) {
            try {
              Map<String, dynamic> cardData = jsonDecode(cardJson);
              String cardName = cardData['name'] ?? '';

              // If this is our card, update the image
              if (cardName.toLowerCase() == _foodName.toLowerCase()) {
                foundCard = true;

                // Update with our high quality image
                cardData['image'] = imageData;

                // Add the updated card to our list
                updatedCards.add(jsonEncode(cardData));
              } else {
                // Not our card, keep it as is
                updatedCards.add(cardJson);
              }
            } catch (e) {
              print('Error updating food card image data: $e');
              // If there was an error, keep the original card
              updatedCards.add(cardJson);
            }
          }

          // Save the updated cards list back to SharedPreferences
          if (foundCard) {
            await prefs.setStringList('food_cards', updatedCards);
            print(
                'Updated high-quality image in food_cards list for: $_foodName');
          }
        }
      }

      print(
          'Saved data for $foodId: liked=$_isLiked, bookmarked=$_isBookmarked, counter=$_counter, calories=$_calories, protein=$_protein, fat=$_fat, carbs=$_carbs, healthScore=$_healthScore, ingredients=${_ingredients.length}');
    } catch (e) {
      print('Error saving food data: $e');
    }
  }

  // Helper method to convert various types to double
  double _convertToDouble(dynamic value) {
    if (value == null) return 0.0;

    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  @override
  void dispose() {
    // We're not automatically saving data when leaving the screen
    // This prevents unwanted changes from being saved when discarding

    _bookmarkController.dispose();
    _likeController.dispose();

    // Dispose of all flip animation controllers
    for (var controller in _flipAnimationControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  // Check if there are unsaved changes
  bool _checkForUnsavedChanges() {
    print('\nChecking for unsaved changes:');

    // Check if _hasUnsavedChanges flag is set
    if (_hasUnsavedChanges) {
      print('_hasUnsavedChanges flag is set to true');
      return true;
    }

    // Compare current values with original values
    if (_foodName != _originalFoodName) {
      print('Food name changed: $_foodName != $_originalFoodName');
      return true;
    }

    if (_healthScore != _originalHealthScore) {
      print('Health score changed: $_healthScore != $_originalHealthScore');
      return true;
    }

    // For numeric values, normalize to handle format differences
    String normalizeNumber(String val) {
      try {
        // Convert to double and back to string to normalize format
        return double.parse(val.replaceAll(',', '.')).toString();
      } catch (e) {
        return val;
      }
    }

    if (normalizeNumber(_calories) != normalizeNumber(_originalCalories)) {
      print('Calories changed: $_calories != $_originalCalories');
      return true;
    }

    if (normalizeNumber(_protein) != normalizeNumber(_originalProtein)) {
      print('Protein changed: $_protein != $_originalProtein');
      return true;
    }

    if (normalizeNumber(_fat) != normalizeNumber(_originalFat)) {
      print('Fat changed: $_fat != $_originalFat');
      return true;
    }

    if (normalizeNumber(_carbs) != normalizeNumber(_originalCarbs)) {
      print('Carbs changed: $_carbs != $_originalCarbs');
      return true;
    }

    if (_counter != _originalCounter) {
      print('Counter changed: $_counter != $_originalCounter');
      return true;
    }

    // If ingredients list length is different, consider it a change
    if (_ingredients.length != _originalIngredients.length) {
      print(
          'Different number of ingredients: ${_ingredients.length} vs ${_originalIngredients.length}');
      return true;
    }

    // Compare each ingredient carefully
    for (int i = 0; i < _ingredients.length; i++) {
      var current = _ingredients[i];
      var original = _originalIngredients[i];

      // Normalize and compare essential fields
      String currentName = current['name']?.toString() ?? '';
      String originalName = original['name']?.toString() ?? '';

      String currentAmount = current['amount']?.toString() ?? '';
      String originalAmount = original['amount']?.toString() ?? '';

      // Normalize calories for comparison
      String currentCalories =
          normalizeNumber(current['calories']?.toString() ?? '0');
      String originalCalories =
          normalizeNumber(original['calories']?.toString() ?? '0');

      if (currentName != originalName) {
        print('Ingredient $i name changed: $currentName != $originalName');
        return true;
      }

      if (currentAmount != originalAmount) {
        print(
            'Ingredient $i amount changed: $currentAmount != $originalAmount');
        return true;
      }

      if (currentCalories != originalCalories) {
        print(
            'Ingredient $i calories changed: $currentCalories != $originalCalories');
        return true;
      }
    }

    print('No changes detected');
    return false;
  }

  // Show confirmation dialog for unsaved changes
  Future<bool> _showUnsavedChangesDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withOpacity(0.5),
          builder: (BuildContext context) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              backgroundColor: Colors.white,
              insetPadding: EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                width: 326,
                height: 182,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Title
                      Text(
                        "Discard Changes?",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'SF Pro Display',
                        ),
                      ),
                      SizedBox(height: 20),

                      // Discard button
                      Container(
                        width: 267,
                        height: 40,
                        margin: EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Centered text
                            Text(
                              "Discard",
                              style: TextStyle(
                                color: Color(0xFFE97372),
                                fontSize: 16,
                                fontFamily: 'SF Pro Display',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            // Icon positioned to the left with exact spacing
                            Positioned(
                              left: 70,
                              child: Image.asset(
                                'assets/images/trashcan.png',
                                width: 20,
                                height: 20,
                                color: Color(0xFFE97372),
                              ),
                            ),
                            // Full-width button for tap area
                            Positioned.fill(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    Navigator.of(context)
                                        .pop(true); // Discard changes
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Cancel button
                      Container(
                        width: 267,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              offset: Offset(0, 2),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Centered text
                            Text(
                              "Cancel",
                              style: TextStyle(
                                fontSize: 16,
                                fontFamily: 'SF Pro Display',
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            // Icon positioned to the left with exact spacing
                            Positioned(
                              left: 70,
                              child: Image.asset(
                                'assets/images/closeicon.png',
                                width: 18,
                                height: 18,
                              ),
                            ),
                            // Full-width button for tap area
                            Positioned.fill(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    Navigator.of(context).pop(
                                        false); // Cancel and return to editing
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ) ??
        false;
  }

  // Handle back button press
  void _handleBack() async {
    // Check if there are unsaved changes
    if (_checkForUnsavedChanges()) {
      // Show confirmation dialog
      bool shouldDiscard = await _showUnsavedChangesDialog();

      if (shouldDiscard) {
        // User clicked "Discard" - RESET ALL VALUES to original state
        // This ensures any temporary changes are completely undone
        if (mounted) {
          setState(() {
            // Reset all values to their original values
            _foodName = _originalFoodName;
            _healthScore = _originalHealthScore;
            _healthScoreValue = _extractHealthScoreValue(_originalHealthScore);
            _calories = _originalCalories;
            _protein = _originalProtein;
            _fat = _originalFat;
            _carbs = _originalCarbs;
            _counter = _originalCounter;
            _hasUnsavedChanges = false;

            // Restore original ingredients directly from our backup
            _restoreOriginalIngredients();

            // Always navigate to CodiaPage instead of using pop()
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => CodiaPage()),
            );
          });
        }
      }
      // If shouldDiscard is false, user clicked "Cancel", stay on FoodCardOpen
      // No action needed here - the dialog is dismissed and user stays on current screen
    } else {
      // No unsaved changes, navigate to CodiaPage
      if (mounted) {
        // Always navigate to CodiaPage instead of using pop()
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => CodiaPage()),
        );
      }
    }
  }

  // Method to increment counter with maximum limit
  void _incrementCounter() {
    setState(() {
      if (_counter < 10) {
        _counter++;
        _markAsUnsaved(); // Mark as having unsaved changes

        // Recalculate nutrition values based on the updated counter
        _calculateTotalNutrition();
      }
    });
  }

  // Method to decrement counter with minimum limit
  void _decrementCounter() {
    setState(() {
      if (_counter > 1) {
        _counter--;
        _markAsUnsaved(); // Mark as having unsaved changes

        // Recalculate nutrition values based on the updated counter
        _calculateTotalNutrition();
      }
    });
  }

  // Method to toggle bookmark state with animation
  void _toggleBookmark() {
    setState(() {
      _isBookmarked = !_isBookmarked;
      _bookmarkController.reset();
      _bookmarkController.forward();
      _markAsUnsaved(); // Mark as having unsaved changes
      // Don't save immediately, only mark as unsaved
    });
  }

  // Method to toggle like state with animation
  void _toggleLike() {
    setState(() {
      _isLiked = !_isLiked;
      _likeController.reset();
      _likeController.forward();
      _markAsUnsaved(); // Mark as having unsaved changes
      // Don't save immediately, only mark as unsaved
    });
  }

  // Method to show privacy options in a bottom sheet
  void _showPrivacyOptions() {
    // Use the current privacy status instead of defaulting to Public
    String _selectedPrivacy = _privacyStatus;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withOpacity(0.5),
      isScrollControlled: true, // Allow more height for additional options
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          width: MediaQuery.of(context).size.width, // Use full width
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Show Private option first to make it most prominent
              _buildPrivacyOption(
                  'Private', 'assets/images/Lock.png', _selectedPrivacy,
                  (value) {
                // Update both the modal state and the parent state
                setModalState(() => _selectedPrivacy = value);
                setState(() {
                  _privacyStatus = value;
                  _markAsUnsaved(); // Mark as having unsaved changes instead of saving
                });
                Navigator.pop(context);
              }),
              _buildPrivacyOption('Friends Only',
                  'assets/images/socialicon.png', _selectedPrivacy, (value) {
                // Update both the modal state and the parent state
                setModalState(() => _selectedPrivacy = value);
                setState(() {
                  _privacyStatus = value;
                  _markAsUnsaved(); // Mark as having unsaved changes instead of saving
                });
                Navigator.pop(context);
              }),
              _buildPrivacyOption(
                  'Public', 'assets/images/globe.png', _selectedPrivacy,
                  (value) {
                // Update both the modal state and the parent state
                setModalState(() => _selectedPrivacy = value);
                setState(() {
                  _privacyStatus = value;
                  _markAsUnsaved(); // Mark as having unsaved changes instead of saving
                });
                Navigator.pop(context);
              }),
              // Add Delete option with trashcan icon
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  // Show confirmation dialog for delete
                  showDialog(
                    context: context,
                    barrierColor:
                        Colors.black.withOpacity(0.5), // Add dark overlay
                    builder: (BuildContext context) {
                      return Dialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                        backgroundColor: Colors.white,
                        insetPadding: EdgeInsets.symmetric(horizontal: 32),
                        child: Container(
                          width: 326,
                          height: 182,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Title
                                Text(
                                  "Delete Meal?",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                SizedBox(height: 20),

                                // Delete button
                                Container(
                                  width: 267,
                                  height: 40,
                                  margin: EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        offset: Offset(0, 2),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Centered text
                                      Text(
                                        "Delete",
                                        style: TextStyle(
                                          color: Color(0xFFE97372),
                                          fontSize: 16,
                                          fontFamily: 'SF Pro Display',
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      // Icon positioned to the left with exact spacing
                                      Positioned(
                                        left:
                                            70, // Position for 28px from text (calculated based on button width)
                                        child: Image.asset(
                                          'assets/images/trashcan.png',
                                          width: 20,
                                          height: 20,
                                          color: Color(0xFFE97372),
                                        ),
                                      ),
                                      // Full-width button for tap area
                                      Positioned.fill(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            onTap: () {
                                              // Use the dedicated delete method
                                              _deleteMeal();
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Cancel button
                                Container(
                                  width: 267,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        offset: Offset(0, 2),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Centered text
                                      Text(
                                        "Cancel",
                                        style: TextStyle(
                                          color: Colors.black54,
                                          fontSize: 16,
                                          fontFamily: 'SF Pro Display',
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      // Icon positioned to match the delete icon's position
                                      Positioned(
                                        left:
                                            70, // Same position as delete icon
                                        child: Image.asset(
                                          'assets/images/closeicon.png',
                                          width: 18, // 10% smaller than 20
                                          height: 18, // 10% smaller than 20
                                          color: Colors.black54,
                                        ),
                                      ),
                                      // Full-width button for tap area
                                      Positioned.fill(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            onTap: () =>
                                                Navigator.of(context).pop(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/trashcan.png',
                            width: 20,
                            height: 20,
                            color: Color(0xFFE97372),
                          ),
                          SizedBox(width: 12),
                          Text(
                            "Delete",
                            style: TextStyle(
                              color: Color(0xFFE97372),
                              fontSize: 16,
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper widget to build privacy option rows
  Widget _buildPrivacyOption(String title, String iconPath,
      String selectedPrivacy, Function(String) onSelect) {
    bool isSelected = selectedPrivacy == title;
    return InkWell(
      onTap: () => onSelect(title),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Image.asset(
                  iconPath,
                  width: 20,
                  height: 20,
                  color: isSelected ? Colors.black : Colors.grey,
                ),
                SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.grey,
                    fontSize: 16,
                    fontFamily: 'SF Pro Display',
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
            if (isSelected) Icon(Icons.check, color: Colors.black),
          ],
        ),
      ),
    );
  }

  // Helper method to extract numeric value from health score
  double _extractHealthScoreValue(String score) {
    final match = RegExp(r'(\d+)\/10').firstMatch(score);
    if (match != null && match.group(1) != null) {
      return double.parse(match.group(1)!) / 10;
    }
    return 0.8; // Default to 8/10 if parsing fails
  }

  // Helper method to format decimal values for consistent display
  String _formatDecimalValue(String input) {
    try {
      // Try to extract number with possible decimal point
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(input);
      if (match != null && match.group(1) != null) {
        // Use original value with decimal places
        double value = double.tryParse(match.group(1)!) ?? 0.0;

        // Keep full precision for all calorie values
        return value.toString();
      }
    } catch (e) {
      print('Error formatting decimal value: $e');
    }
    return input; // Return original if parsing fails
  }

  // Helper method to optimize image quality
  void _optimizeImage() {
    if (_imageBytes != null) {
      try {
        print('Optimizing image quality for display...');
        // Create an optimized image storage if needed
        if (_storedImageBase64 == null || _storedImageBase64!.isEmpty) {
          _storedImageBase64 = base64Encode(_imageBytes!);
          print(
              'Created high-quality image storage: ${_storedImageBase64!.length} characters');
        }
      } catch (e) {
        print('Error optimizing image: $e');
      }
    }
  }

  // Helper method to format ingredient calories for display
  String _formatIngredientCalories(dynamic calories) {
    if (calories == null) return "0 kcal";

    // If it's already a string, ensure it has "kcal" suffix
    if (calories is String) {
      // Try to parse the string to a number to remove decimal points
      try {
        double calValue = double.parse(calories.replaceAll("kcal", "").trim());
        // Round to a whole number
        int roundedCal = calValue.round();
        return "$roundedCal kcal";
      } catch (e) {
        // If parsing fails, just ensure it has kcal suffix
        return calories.contains("kcal") ? calories : "$calories kcal";
      }
    }

    // If it's a number, convert to whole number string with "kcal" suffix
    if (calories is num) {
      return "${calories.round()} kcal";
    }

    // Fallback for any other type
    return "$calories kcal";
  }

  // Helper function to estimate calories based on food name and serving size
  double _estimateCaloriesForFood(String foodName, String servingSize) {
    double baseCalories = 100.0; // Default base calories
    double servingSizeMultiplier = 1.0;

    // Adjust for serving size if numerical values are present
    RegExp numericRegex = RegExp(r'(\d+(?:\.\d+)?)');
    var numericMatches = numericRegex.allMatches(servingSize);

    if (numericMatches.isNotEmpty) {
      try {
        double? sizeValue =
            double.tryParse(numericMatches.first.group(0) ?? '1');
        if (sizeValue != null) {
          // Adjust serving size multiplier based on common units
          if (servingSize.contains('cup') || servingSize.contains('cups')) {
            servingSizeMultiplier =
                sizeValue * 2.0; // 1 cup is about 200 calories for many foods
          } else if (servingSize.contains('tbsp') ||
              servingSize.contains('tablespoon')) {
            servingSizeMultiplier =
                sizeValue * 0.3; // 1 tbsp is about 30 calories
          } else if (servingSize.contains('tsp') ||
              servingSize.contains('teaspoon')) {
            servingSizeMultiplier =
                sizeValue * 0.1; // 1 tsp is about 10 calories
          } else if (servingSize.contains('oz') ||
              servingSize.contains('ounce')) {
            servingSizeMultiplier =
                sizeValue * 0.7; // 1 oz is about 70 calories
          } else if (servingSize.contains('g') ||
              servingSize.contains('gram')) {
            servingSizeMultiplier =
                sizeValue * 0.01; // 1g is about 1 calorie for many foods
          } else {
            // General multiplier for other units
            servingSizeMultiplier = sizeValue;
          }
        }
      } catch (e) {
        // If parsing fails, keep the default multiplier
        print('Could not parse serving size: $servingSize');
      }
    }

    // Adjust base calories based on food type
    String lowercaseName = foodName.toLowerCase();

    // High-calorie foods
    if (lowercaseName.contains('cake') ||
        lowercaseName.contains('pizza') ||
        lowercaseName.contains('burger') ||
        lowercaseName.contains('fries') ||
        lowercaseName.contains('chocolate') ||
        lowercaseName.contains('ice cream')) {
      baseCalories = 300.0;
    }
    // Medium-calorie foods
    else if (lowercaseName.contains('meat') ||
        lowercaseName.contains('chicken') ||
        lowercaseName.contains('fish') ||
        lowercaseName.contains('pasta') ||
        lowercaseName.contains('rice') ||
        lowercaseName.contains('bread')) {
      baseCalories = 200.0;
    }
    // Low-calorie foods
    else if (lowercaseName.contains('vegetable') ||
        lowercaseName.contains('fruit') ||
        lowercaseName.contains('salad') ||
        lowercaseName.contains('soup')) {
      baseCalories = 80.0;
    }

    return baseCalories * servingSizeMultiplier;
  }

  // Add the food analyzer service directly to FoodCardOpen to handle text analysis for ingredients
  Future<Map<String, dynamic>> _analyzeIngredientWithAPI(
      String foodName, String servingSize,
      [BuildContext? dialogContext]) async {
    try {
      // Format the prompt for DeepSeek AI with improved validation instructions
      // For single ingredients (Add Ingredient feature), use a simpler prompt focused on accurate nutrition
      final messages = [
        {
          'role': 'system',
          'content':
              'You are a nutrition expert analyzing food items. You must check TWO things:\n\n1. FIRST check if the input is a valid food name. If it contains nonsensical strings (like "hwheqhgye21" or "xyz123"), random characters, or is clearly not a food, respond with ONLY: {"invalid_food": true}.\n\n2. SECOND check if the serving size is valid and makes sense for the food. If the serving size is unclear, implausible, or nonsensical (like "xyz amount" or unspecified units), also respond with ONLY: {"invalid_food": true}.\n\nOtherwise, for valid foods with clear serving sizes, return ONLY RAW JSON with nutritional values that are accurate for the food type. Calculate values based on typical nutritional composition - DO NOT inflate protein content. For example, donuts should have LOW protein (3-7g), not high protein. CALORIES MUST BE PRECISE NUMBERS - not rounded to multiples of 10 or 50. For example, if a food has 283 calories, return 283 (not 280 or 300). Use accurate macronutrient distribution based on food type (e.g. more carbs for sweets, more protein for meat).'
        },
        {
          'role': 'user',
          'content':
              'Calculate accurate nutritional values for $foodName, serving size: $servingSize. Return only the JSON with calories, protein, fat, and carbs. If either the food name or serving size is invalid/unclear, return {"invalid_food": true}.'
        }
      ];

      print(
          'FOOD ANALYZER: Creating direct DeepSeek API request for "$foodName" ($servingSize)');

      // Use Render.com API endpoint instead of direct DeepSeek API
      // Instead of using hardcoded API key, we'll use the Render.com API which has the API key
      const String apiEndpoint =
          'https://deepseek-uhrc.onrender.com/api/analyze-food';

      // Store a local copy of the context to handle potential errors safely
      final BuildContext? localDialogContext = dialogContext;
      final BuildContext localContext = context;

      // Call API endpoint that proxies to DeepSeek
      final response = await http
          .post(
            Uri.parse(apiEndpoint),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'messages': messages,
              'food_name': foodName,
              'serving_size': servingSize,
              'operation_type': 'NUTRITION_CALCULATION'
            }),
          )
          .timeout(const Duration(minutes: 1))
          .catchError((error) {
        print('FOOD ANALYZER: Request error caught in catchError: $error');

        // Safely dismiss any loading dialog
        if (localDialogContext != null) {
          _safelyDismissDialog(localDialogContext, true);
        }

        // Return a proper http.Response object instead of a Map
        return http.Response('{"error": true}', 500);
      });

      print(
          'FOOD ANALYZER: Received DeepSeek API response with status: ${response.statusCode}');

      // Dismiss any loading dialog that might be showing (immediately after getting the response)
      if (dialogContext != null) {
        _safelyDismissDialog(dialogContext, true);
      }

      if (response.statusCode != 200) {
        throw Exception('API error: ${response.statusCode}, ${response.body}');
      }

      // Parse the response
      final Map<String, dynamic> responseData = jsonDecode(response.body);
      print(
          'FOOD ANALYZER: API response: ${responseData.toString().substring(0, min(200, responseData.toString().length))}...');

      // Check if the response contains an error
      if (responseData.containsKey('error') && responseData['error'] == true) {
        throw Exception(
            'API error: ${responseData['message'] ?? 'Unknown error'}');
      }

      // Extract the content from the response
      Map<String, dynamic> nutrition = {};

      if (responseData.containsKey('data')) {
        nutrition = responseData['data'] is Map
            ? Map<String, dynamic>.from(responseData['data'])
            : {};
      } else if (responseData.containsKey('nutrition')) {
        nutrition = responseData['nutrition'] is Map
            ? Map<String, dynamic>.from(responseData['nutrition'])
            : {};
      } else {
        // Try to find nutrition data in the response
        nutrition = responseData;
      }

      // Check if the model identified this as an invalid food or serving size
      if (nutrition.containsKey('invalid_food') &&
          nutrition['invalid_food'] == true) {
        print(
            'FOOD ANALYZER: Invalid food name or serving size detected: $foodName ($servingSize)');
        return {'invalid_food': true};
      }

      return {
        'calories':
            _extractNumericValue(nutrition, ['calories', 'kcal', 'energy']),
        'protein': _extractNumericValue(nutrition, ['protein', 'proteins']),
        'carbs': _extractNumericValue(nutrition, ['carbs', 'carbohydrates']),
        'fat': _extractNumericValue(nutrition, ['fat', 'fats', 'total_fat']),
      };
    } catch (e) {
      print('FOOD ANALYZER error with DeepSeek: $e');

      // Since DeepSeek API call failed, fall back to the render.com API
      try {
        print('Falling back to render.com API for nutrition data');

        // Format the query for the text-based analysis
        final query =
            "Calculate nutrition for $foodName, serving size: $servingSize";

        print(
            'FOOD ANALYZER FALLBACK: Creating text analysis request for "$query"');

        // Use the render.com API endpoint as a fallback
        final String baseUrl = 'https://snap-food.onrender.com';
        final String analyzeEndpoint = '/api/analyze-food';

        final Map<String, dynamic> requestBody = {
          'text_query': query,
          'type': 'nutrition'
        };

        final response = await http
            .post(
              Uri.parse('$baseUrl$analyzeEndpoint'),
              headers: {
                'Content-Type': 'application/json',
              },
              body: jsonEncode(requestBody),
            )
            .timeout(
                const Duration(minutes: 1)); // Increased timeout to 1 minute

        print(
            'FOOD ANALYZER FALLBACK: Received response status: ${response.statusCode}');

        // Dismiss any loading dialog that might be showing (immediately after getting the response)
        if (dialogContext != null) {
          _safelyDismissDialog(dialogContext, true);
        }

        if (response.statusCode != 200) {
          throw Exception('Fallback API error: ${response.statusCode}');
        }

        final Map<String, dynamic> responseData = jsonDecode(response.body);

        if (responseData['success'] != true) {
          throw Exception('Fallback API error: ${responseData['error']}');
        }

        final data = responseData['data'];
        Map<String, dynamic> nutrition = {};

        if (data is Map) {
          if (data.containsKey('nutrition')) {
            nutrition = data['nutrition'] is Map
                ? Map<String, dynamic>.from(data['nutrition'])
                : {};
          } else if (data.containsKey('nutrients')) {
            nutrition = data['nutrients'] is Map
                ? Map<String, dynamic>.from(data['nutrients'])
                : {};
          } else {
            nutrition = Map<String, dynamic>.from(data);
          }
        }

        print(
            'FOOD ANALYZER FALLBACK: Using render.com API nutrition data: $nutrition');

        return {
          'calories':
              _extractNumericValue(nutrition, ['calories', 'kcal', 'energy']),
          'protein': _extractNumericValue(nutrition, ['protein', 'proteins']),
          'carbs': _extractNumericValue(nutrition, ['carbs', 'carbohydrates']),
          'fat': _extractNumericValue(nutrition, ['fat', 'fats', 'total_fat']),
        };
      } catch (fallbackError) {
        // Handle both API failures
        print('FOOD ANALYZER FALLBACK also failed: $fallbackError');

        // Last resort - estimate based on food type
        print('Falling back to estimated nutrition values');
        double estimatedCalories =
            _estimateCaloriesForFood(foodName, servingSize);

        // Estimate macros based on food type
        double protein = 0.0, fat = 0.0, carbs = 0.0;
        String lowercaseName = foodName.toLowerCase();

        // Sweet/dessert foods
        if (lowercaseName.contains('cake') ||
            lowercaseName.contains('cookie') ||
            lowercaseName.contains('sweet') ||
            lowercaseName.contains('dessert') ||
            lowercaseName.contains('donut')) {
          // Low protein, high carbs, moderate fat
          protein = estimatedCalories * 0.05 / 4; // 5% protein
          fat = estimatedCalories * 0.3 / 9; // 30% fat
          carbs = estimatedCalories * 0.65 / 4; // 65% carbs
        }
        // Meat-based foods
        else if (lowercaseName.contains('chicken') ||
            lowercaseName.contains('beef') ||
            lowercaseName.contains('fish') ||
            lowercaseName.contains('meat')) {
          // High protein, moderate fat, low carbs
          protein = estimatedCalories * 0.4 / 4; // 40% protein
          fat = estimatedCalories * 0.4 / 9; // 40% fat
          carbs = estimatedCalories * 0.2 / 4; // 20% carbs
        }
        // Balanced meals
        else {
          // Moderate protein, moderate fat, moderate carbs
          protein = estimatedCalories * 0.25 / 4; // 25% protein
          fat = estimatedCalories * 0.3 / 9; // 30% fat
          carbs = estimatedCalories * 0.45 / 4; // 45% carbs
        }

        return {
          'calories': estimatedCalories,
          'protein': protein,
          'carbs': carbs,
          'fat': fat,
        };
      }
    }
  }

  // Helper method to extract numeric values from different possible field names
  double _extractNumericValue(
      Map<String, dynamic> data, List<String> possibleKeys) {
    for (var key in possibleKeys) {
      if (data.containsKey(key)) {
        var value = data[key];
        if (value is num) {
          return value.toDouble();
        } else if (value is String) {
          // Try to extract numeric portion from strings like "150 kcal"
          final numericMatch = RegExp(r'(\d+\.?\d*)').firstMatch(value);
          if (numericMatch != null) {
            return double.tryParse(numericMatch.group(1) ?? '0') ?? 0.0;
          }
        } else if (value is Map && value.containsKey('amount')) {
          var amount = value['amount'];
          if (amount is num) return amount.toDouble();
          if (amount is String) return double.tryParse(amount) ?? 0.0;
        }
      }
    }
    return 0.0;
  }

  // Calculate nutrition using the Render.com DeepSeek service - improved version similar to _fixFoodWithAI
  Future<Map<String, dynamic>> _calculateNutritionWithAI(
      String foodName, String servingSize) async {
    // Store a local copy of the context to avoid BuildContext issues
    BuildContext? localContext = context;
    BuildContext? dialogContext;
    bool isDialogShowing = false;

    try {
      // Updated to include micronutrient extraction for Nutrition.dart integration
      print('STARTING NUTRITION CALCULATION for: $foodName ($servingSize)');

      // Show loading dialog if context is still valid
      if (mounted && localContext != null) {
        isDialogShowing = true;
        try {
          // Show loading indicator with an improved UI
          showDialog(
            context: localContext,
            barrierColor: Colors.black.withOpacity(0.3),
            barrierDismissible: false,
            builder: (BuildContext ctx) {
              dialogContext = ctx;
              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 0,
                backgroundColor: Colors.white,
                child: Container(
                  width: 270,
                  height: 136,
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 3,
                        ),
                      ),
                      SizedBox(height: 24),
                      Text(
                        "Calculating...",
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        } catch (dialogError) {
          print('Error showing dialog: $dialogError');
          // Continue without dialog
          isDialogShowing = false;
          dialogContext = null;
        }
      }

      // Create the request data similar to _fixFoodWithAI method
      final requestData = {
        'food_name': foodName,
        'serving_size': servingSize,
        'operation_type': 'NUTRITION_CALCULATION',
        'include_micronutrients': true // Request micronutrient data as well
      };

      print(
          'NUTRITION CALCULATOR: Creating request to Render.com DeepSeek service');
      print('NUTRITION CALCULATOR: Request data: ${jsonEncode(requestData)}');

      // Use the same endpoint as Fix with AI
      final response = await http
          .post(
        Uri.parse('https://deepseek-uhrc.onrender.com/api/nutrition'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestData),
      )
          .timeout(const Duration(minutes: 1), onTimeout: () {
        print('FOOD FIXER: Request timed out');
        // Safely show error dialog on timeout without navigating away
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _safelyDismissDialog(dialogContext, isDialogShowing);
            showDialog(
              context: localContext,
              barrierDismissible: false,
              barrierColor: Colors.black.withOpacity(0.75),
              builder: (BuildContext context) {
                return Dialog(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                  child: Container(
                    width: 311,
                    padding: EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Service Unavailable',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'The food modification service is currently unavailable. Please try again later.',
                          style: TextStyle(
                            fontSize: 17,
                            fontFamily: 'SF Pro Display',
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 32),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            child: Text(
                              'OK',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                                color: Colors.red.shade400,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }
        });

        // Show error dialog and return error result
        if (mounted) {
          _showStandardDialog(
            title: "Service Timeout",
            message:
                "The food modification service timed out. Please try again later.",
            positiveButtonText: "OK",
          );
        }

        // Return error result
        return http.Response(
          jsonEncode({
            'error': true,
            'message':
                'The food modification service timed out. Please try again later.'
          }),
          408,
          headers: {'content-type': 'application/json'},
        );
      });

      print(
          'NUTRITION CALCULATOR: Received Render.com service response with status: ${response.statusCode}');

      // Safely dismiss the loading dialog if it's showing
      _safelyDismissDialog(dialogContext, isDialogShowing);

      if (response.statusCode != 200) {
        throw Exception(
            'Service error: ${response.statusCode}, ${response.body}');
      }

      // Parse the response
      final Map<String, dynamic> responseData = jsonDecode(response.body);
      print('NUTRITION CALCULATOR: Response data: $responseData');

      // Check for success and data
      if (responseData.containsKey('success') &&
          responseData['success'] == true) {
        // Extract nutrition data
        Map<String, dynamic> nutritionData = {};

        if (responseData.containsKey('data')) {
          nutritionData = responseData['data'];
        } else {
          nutritionData = responseData;
        }

        // If nutritionData contains a 'nutrition' key, extract from it
        if (nutritionData.containsKey('nutrition') &&
            nutritionData['nutrition'] is Map) {
          nutritionData = Map<String, dynamic>.from(nutritionData['nutrition']);
        }
        // If nutritionData contains a 'nutrition_values' key, extract from it
        if (nutritionData.containsKey('nutrition_values') &&
            nutritionData['nutrition_values'] is Map) {
          nutritionData =
              Map<String, dynamic>.from(nutritionData['nutrition_values']);
        }

        print('NUTRITION CALCULATOR: Parsed nutrition data: $nutritionData');

        // Check if the model identified this as an invalid food or serving size
        if (nutritionData.containsKey('invalid_food') &&
            nutritionData['invalid_food'] == true) {
          print(
              'NUTRITION CALCULATOR: Invalid food name or serving size detected: $foodName ($servingSize)');

          // Show the invalid ingredient dialog
          if (mounted) {
            _showStandardDialog(
              title: "Invalid Food Item",
              message:
                  "Sorry, the food name or serving size you entered is not recognized. Please try a more specific name or common serving size.",
              positiveButtonText: "OK",
            );
          }

          return {'invalid_food': true};
        }

        // Extract micronutrients from the response
        // Start with an empty result with basic macros
        Map<String, dynamic> result = {
          'calories': _extractNumericValue(
              nutritionData, ['calories', 'kcal', 'energy']),
          'protein':
              _extractNumericValue(nutritionData, ['protein', 'proteins']),
          'carbs':
              _extractNumericValue(nutritionData, ['carbs', 'carbohydrates']),
          'fat':
              _extractNumericValue(nutritionData, ['fat', 'fats', 'total_fat']),
        };

        // Add vitamins
        _extractVitaminsFromData(nutritionData, result);

        // Add minerals
        _extractMineralsFromData(nutritionData, result);

        // Add other nutrients
        _extractOtherNutrientsFromData(nutritionData, result);

        print('COMPLETED nutrition calculation: $result');
        return result;
      } else {
        // Handle error in response
        print(
            'NUTRITION CALCULATOR: Error in response: ${responseData['error'] ?? "Unknown error"}');
        throw Exception(
            'Service error: ${responseData['error'] ?? "Unknown error"}');
      }
    } catch (e) {
      print('CRITICAL ERROR calculating nutrition: $e');

      // Safely dismiss the loading dialog if it's showing
      _safelyDismissDialog(dialogContext, isDialogShowing);

      // Show a properly styled error dialog to the user
      if (mounted) {
        _showStandardDialog(
          title: "Calculation Error",
          message:
              "We couldn't calculate the nutrition for this ingredient. Using estimated values instead.",
          positiveButtonText: "OK",
        );
      }

      // Use fallback estimation for nutrition values
      double estimatedCalories =
          _estimateCaloriesForFood(foodName, servingSize);

      // Estimate macros based on food type
      double estimatedProtein = 0.0;
      double estimatedFat = 0.0;
      double estimatedCarbs = 0.0;

      // Simple rules for macro distribution based on food types
      if (foodName.toLowerCase().contains('meat') ||
          foodName.toLowerCase().contains('chicken') ||
          foodName.toLowerCase().contains('fish')) {
        // High protein foods
        estimatedProtein =
            estimatedCalories * 0.4 / 4; // 40% of calories from protein
        estimatedFat = estimatedCalories * 0.4 / 9; // 40% of calories from fat
        estimatedCarbs =
            estimatedCalories * 0.2 / 4; // 20% of calories from carbs
      } else if (foodName.toLowerCase().contains('salad') ||
          foodName.toLowerCase().contains('vegetable')) {
        // Vegetable-based foods
        estimatedProtein = estimatedCalories * 0.15 / 4; // 15% protein
        estimatedFat = estimatedCalories * 0.25 / 9; // 25% fat
        estimatedCarbs = estimatedCalories * 0.6 / 4; // 60% carbs
      } else if (foodName.toLowerCase().contains('dessert') ||
          foodName.toLowerCase().contains('cake') ||
          foodName.toLowerCase().contains('sweet') ||
          foodName.toLowerCase().contains('cookie')) {
        // Desserts and sweets
        estimatedProtein = estimatedCalories * 0.05 / 4; // 5% protein
        estimatedFat = estimatedCalories * 0.3 / 9; // 30% fat
        estimatedCarbs = estimatedCalories * 0.65 / 4; // 65% carbs
      } else {
        // Default balanced distribution
        estimatedProtein = estimatedCalories * 0.2 / 4; // 20% protein
        estimatedFat = estimatedCalories * 0.3 / 9; // 30% fat
        estimatedCarbs = estimatedCalories * 0.5 / 4; // 50% carbs
      }

      // Round to one decimal place
      final result = {
        'calories': double.parse(estimatedCalories.toStringAsFixed(1)),
        'protein': double.parse(estimatedProtein.toStringAsFixed(1)),
        'carbs': double.parse(estimatedCarbs.toStringAsFixed(1)),
        'fat': double.parse(estimatedFat.toStringAsFixed(1)),
      };

      print('Using estimated nutrition values: $result');
      return result;
    }
  }

  // Helper function to extract vitamins from nutrition data
  void _extractVitaminsFromData(
      Map<String, dynamic> nutritionData, Map<String, dynamic> result) {
    // Define mapping of possible API keys to vitamin names
    final vitaminMappings = {
      'vitamin_a': 'vitamin_a',
      'vitamin_c': 'vitamin_c',
      'vitamin_d': 'vitamin_d',
      'vitamin_e': 'vitamin_e',
      'vitamin_k': 'vitamin_k',
      'vitamin_b1': 'vitamin_b1',
      'thiamin': 'vitamin_b1',
      'vitamin_b2': 'vitamin_b2',
      'riboflavin': 'vitamin_b2',
      'vitamin_b3': 'vitamin_b3',
      'niacin': 'vitamin_b3',
      'vitamin_b5': 'vitamin_b5',
      'pantothenic_acid': 'vitamin_b5',
      'vitamin_b6': 'vitamin_b6',
      'pyridoxine': 'vitamin_b6',
      'vitamin_b7': 'vitamin_b7',
      'biotin': 'vitamin_b7',
      'vitamin_b9': 'vitamin_b9',
      'folate': 'vitamin_b9',
      'folic_acid': 'vitamin_b9',
      'vitamin_b12': 'vitamin_b12',
      'cobalamin': 'vitamin_b12',
    };

    // Loop through nutrition data keys and extract vitamins
    nutritionData.forEach((key, value) {
      // Convert key to lowercase for case-insensitive matching
      String keyLower = key.toLowerCase();

      // Check if this key corresponds to a vitamin
      for (var entry in vitaminMappings.entries) {
        if (keyLower.contains(entry.key)) {
          // Found a match - extract the value
          double amount = 0.0;
          if (value is num) {
            amount = value.toDouble();
          } else if (value is String) {
            try {
              amount =
                  double.tryParse(value.replaceAll(RegExp(r'[^\d\.]'), '')) ??
                      0.0;
            } catch (e) {
              print('Error parsing vitamin value: $e');
            }
          }

          // Only add non-zero values
          if (amount > 0) {
            result[entry.value] = amount;
            print('Extracted ${entry.value}: $amount');
          }
          break;
        }
      }
    });
  }

  // Helper function to extract minerals from nutrition data
  void _extractMineralsFromData(
      Map<String, dynamic> nutritionData, Map<String, dynamic> result) {
    // Define mapping of possible API keys to mineral names
    final mineralMappings = {
      'calcium': 'calcium',
      'iron': 'iron',
      'magnesium': 'magnesium',
      'phosphorus': 'phosphorus',
      'potassium': 'potassium',
      'sodium': 'sodium',
      'zinc': 'zinc',
      'copper': 'copper',
      'manganese': 'manganese',
      'selenium': 'selenium',
      'chloride': 'chloride',
      'chromium': 'chromium',
      'iodine': 'iodine',
      'molybdenum': 'molybdenum',
      'fluoride': 'fluoride',
    };

    // Loop through nutrition data keys and extract minerals
    nutritionData.forEach((key, value) {
      // Convert key to lowercase for case-insensitive matching
      String keyLower = key.toLowerCase();

      // Check if this key corresponds to a mineral
      for (var entry in mineralMappings.entries) {
        if (keyLower.contains(entry.key)) {
          // Found a match - extract the value
          double amount = 0.0;
          if (value is num) {
            amount = value.toDouble();
          } else if (value is String) {
            try {
              amount =
                  double.tryParse(value.replaceAll(RegExp(r'[^\d\.]'), '')) ??
                      0.0;
            } catch (e) {
              print('Error parsing mineral value: $e');
            }
          }

          // Only add non-zero values
          if (amount > 0) {
            result[entry.value] = amount;
            print('Extracted ${entry.value}: $amount');
          }
          break;
        }
      }
    });
  }

  // Helper function to extract other nutrients from nutrition data
  void _extractOtherNutrientsFromData(
      Map<String, dynamic> nutritionData, Map<String, dynamic> result) {
    // Define mapping of possible API keys to other nutrient names
    final otherNutrientMappings = {
      'fiber': 'fiber',
      'dietary_fiber': 'fiber',
      'fibre': 'fiber',
      'cholesterol': 'cholesterol',
      'sugar': 'sugar',
      'sugars': 'sugar',
      'total_sugar': 'sugar',
      'saturated_fat': 'saturated_fat',
      'saturated_fats': 'saturated_fat',
      'sat_fat': 'saturated_fat',
      'omega_3': 'omega_3',
      'omega3': 'omega_3',
      'omega_6': 'omega_6',
      'omega6': 'omega_6',
    };

    // Loop through nutrition data keys and extract other nutrients
    nutritionData.forEach((key, value) {
      // Convert key to lowercase for case-insensitive matching
      String keyLower = key.toLowerCase();

      // Check if this key corresponds to another nutrient
      for (var entry in otherNutrientMappings.entries) {
        if (keyLower.contains(entry.key)) {
          // Found a match - extract the value
          double amount = 0.0;
          if (value is num) {
            amount = value.toDouble();
          } else if (value is String) {
            try {
              amount =
                  double.tryParse(value.replaceAll(RegExp(r'[^\d\.]'), '')) ??
                      0.0;
            } catch (e) {
              print('Error parsing nutrient value: $e');
            }
          }

          // Only add non-zero values
          if (amount > 0) {
            result[entry.value] = amount;
            print('Extracted ${entry.value}: $amount');
          }
          break;
        }
      }
    });
  }

  // Helper method to safely dismiss dialog without context errors
  void _safelyDismissDialog(BuildContext? dialogContext, bool isDialogShowing) {
    // First approach: Try using the specific dialog context if available
    if (isDialogShowing && dialogContext != null) {
      try {
        if (Navigator.canPop(dialogContext)) {
          Navigator.of(dialogContext).pop();
          print('Dialog dismissed using dialog context');
          return;
        }
      } catch (e) {
        print('Error dismissing dialog with dialog context: $e');
      }
    }

    // Second approach: Try using the global context as fallback
    if (mounted && context != null) {
      try {
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
          print('Dialog dismissed using global context');
          return;
        }
      } catch (e) {
        print('Error dismissing dialog with global context: $e');
      }
    }

    print('Could not dismiss dialog - no valid context found');
  }

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).viewPadding.top;

    return Scaffold(
      backgroundColor: Color(0xFFDADADA),
      // Use a stack for better layout control
      body: WillPopScope(
        onWillPop: () async {
          // Use the same _handleBack logic for system back button
          _handleBack();
          // Return false to prevent default pop behavior
          return false;
        },
        child: Stack(
          children: [
            // Scrollable content with extra slow physics for mouse wheel
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                },
              ),
              child: SingleChildScrollView(
                physics: SlowScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Gray image header with back button on it
                    Container(
                      height: MediaQuery.of(context).size.width,
                      color: Color(0xFFDADADA),
                      child: Stack(
                        children: [
                          // Meal image - show user image or fallback
                          _imageBytes != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.zero,
                                  child: Image.memory(
                                    _imageBytes!,
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.center,
                                    filterQuality: FilterQuality.high,
                                    cacheWidth: MediaQuery.of(context)
                                            .size
                                            .width
                                            .toInt() *
                                        2, // 2x display size for quality
                                    isAntiAlias: true,
                                  ),
                                )
                              : Center(
                                  child: Image.asset(
                                    'assets/images/meal1.png',
                                    width: 48,
                                    height: 48,
                                  ),
                                ),
                          // Back button inside the scrollable area
                          Positioned(
                            top: statusBarHeight + 16,
                            left: 16,
                            child: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.7),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(Icons.arrow_back,
                                      color: Colors.black, size: 24),
                                  onPressed: _handleBack,
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(),
                                ),
                              ),
                            ),
                          ),
                          // Share and more buttons
                          Positioned(
                            top: statusBarHeight + 16,
                            right: 16,
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.7),
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: Image.asset(
                                        'assets/images/share.png',
                                        width:
                                            21.6, // 10% smaller (24 * 0.9 = 21.6)
                                        height: 21.6, // 10% smaller
                                        color: Colors.black,
                                      ),
                                      onPressed: () {},
                                      padding: EdgeInsets.zero,
                                      constraints: BoxConstraints(),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8), // Add spacing between icons
                                Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.7),
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: Image.asset(
                                        'assets/images/more2.png',
                                        width:
                                            21.6, // 10% smaller (24 * 0.9 = 21.6)
                                        height: 21.6, // 10% smaller
                                        color: Colors.black,
                                      ),
                                      onPressed: _showPrivacyOptions,
                                      padding: EdgeInsets.zero,
                                      constraints: BoxConstraints(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // White rounded container with gradient
                    Transform.translate(
                      offset: Offset(0, -40), // Move up to create overlap
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(40),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0, 0.4, 1],
                            colors: [
                              Color(0xFFFFFFFF),
                              Color(0xFFFFFFFF),
                              Color(0xFFEBEBEB),
                            ],
                          ),
                        ),
                        child: Column(
                          children: [
                            // Add 20px gap at top of white container
                            SizedBox(height: 20),

                            // Time and interaction buttons
                            Padding(
                              padding: const EdgeInsets.fromLTRB(29, 0, 29, 0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Left side: Bookmark and time
                                  Row(
                                    children: [
                                      // Bookmark button with enhanced animation
                                      GestureDetector(
                                        onTap: _toggleBookmark,
                                        child: AnimatedBuilder(
                                          animation: _bookmarkController,
                                          builder: (context, child) {
                                            return Transform.scale(
                                              scale:
                                                  _bookmarkScaleAnimation.value,
                                              child: Image.asset(
                                                _isBookmarked
                                                    ? 'assets/images/bookmarkfilled.png'
                                                    : 'assets/images/bookmark.png',
                                                width: 24,
                                                height: 24,
                                                color: _isBookmarked
                                                    ? Color(0xFFFFC300)
                                                    : Colors.black,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      SizedBox(width: 16),
                                      // Time
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Color(0xFFF2F2F2),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '12:07',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),

                                  // Right side: Counter with minus and plus buttons
                                  Row(
                                    children: [
                                      // Minus button
                                      GestureDetector(
                                        onTap: _decrementCounter,
                                        child: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white,
                                          ),
                                          child: Center(
                                            child: Image.asset(
                                              'assets/images/minus.png',
                                              width: 24,
                                              height: 24,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // Counter with smaller width
                                      Container(
                                        width:
                                            24, // Reduced from 40 to bring icons closer
                                        child: Center(
                                          child: Text(
                                            '$_counter',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // Plus button
                                      GestureDetector(
                                        onTap: _incrementCounter,
                                        child: Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white,
                                          ),
                                          child: Center(
                                            child: Image.asset(
                                              'assets/images/plus.png',
                                              width: 24,
                                              height: 24,
                                              color: Colors.black,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Title and description with adjusted padding
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title and subtitle area with 14px top spacing
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 29, right: 29, top: 14, bottom: 0),
                                  child: Container(
                                    width: double.infinity,
                                    // Remove fixed height and use dynamic sizing
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _foodName,
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                          // Allow wrapping to multiple lines
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Rusty Pelican is so good',
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Add 20px gap between subtitle and divider
                                SizedBox(height: 20),

                                // Only show social interaction area if not Private
                                if (_privacyStatus != 'Private') ...[
                                  // Divider with correct color and margins
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 29),
                                    child: Container(
                                      height: 0.5,
                                      color: Color(0xFFBDBDBD),
                                    ),
                                  ),

                                  // Social sharing buttons
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 48, vertical: 16),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Like button area (left section)
                                        Row(
                                          children: [
                                            GestureDetector(
                                              onTap: _toggleLike,
                                              child: AnimatedBuilder(
                                                animation: _likeController,
                                                builder: (context, child) {
                                                  return Transform.scale(
                                                    scale: _likeScaleAnimation
                                                        .value,
                                                    child: Image.asset(
                                                      _isLiked
                                                          ? 'assets/images/likefilled.png'
                                                          : 'assets/images/like.png',
                                                      width: 24,
                                                      height: 24,
                                                      color: Colors.black,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              '2',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),

                                        // Comment button (center section)
                                        Row(
                                          children: [
                                            Image.asset(
                                              'assets/images/comment.png',
                                              width: 24,
                                              height: 24,
                                              color: Colors.black,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              '2',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),

                                        // Share button (right section)
                                        Image.asset(
                                          'assets/images/share.png',
                                          width: 24,
                                          height: 24,
                                          color: Colors.black,
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Divider with correct color and margins
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 29),
                                    child: Container(
                                      height: 0.5,
                                      color: Color(0xFFBDBDBD),
                                    ),
                                  ),

                                  // Add space after social interaction area
                                  SizedBox(height: 20),
                                ],
                              ],
                            ),

                            // Rest of the content
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Calories and macros card
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 29),
                                  child: Container(
                                    padding: EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      // Remove border on this card even in edit mode
                                      border: null,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 10,
                                          offset: Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Calories circle
                                        Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // Circle image instead of custom painted progress
                                            Transform.translate(
                                              offset: Offset(0, -3.9),
                                              child: ColorFiltered(
                                                colorFilter: ColorFilter.mode(
                                                  Colors.black,
                                                  BlendMode.srcIn,
                                                ),
                                                child: Image.asset(
                                                  'assets/images/circle.png',
                                                  width: 130,
                                                  height: 130,
                                                  fit: BoxFit.contain,
                                                ),
                                              ),
                                            ),
                                            // Calories text
                                            Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  _calories,
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.black,
                                                    decoration:
                                                        TextDecoration.none,
                                                  ),
                                                ),
                                                Text(
                                                  'Calories',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.normal,
                                                    color: Colors.black,
                                                    decoration:
                                                        TextDecoration.none,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 5),

                                        // Macros
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceAround,
                                          children: [
                                            _buildMacro(
                                                'Protein',
                                                '${_protein}g',
                                                Color(0xFFD7C1FF)),
                                            _buildMacro('Fat', '${_fat}g',
                                                Color(0xFFFFD8B1)),
                                            _buildMacro('Carbs', '${_carbs}g',
                                                Color(0xFFB1EFD8)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Gap between calorie box and health score - changed to 15px
                                SizedBox(height: 15),

                                // Health Score
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 29),
                                  child: _buildHealthScore(),
                                ),

                                // Gap between health score and ingredients label - set to 20px
                                SizedBox(height: 20),

                                // Ingredients
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 29),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Ingredients',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      // Gap between Ingredients label and boxes - set to 20px
                                      SizedBox(height: 20),
                                      // Display ingredient grid
                                      _buildIngredientGrid(),
                                    ],
                                  ),
                                ),

                                // Set exact 20px spacing between Ingredients section and More label
                                SizedBox(height: 20),

                                // More options
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 29),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'More',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      // Set exact 20px spacing between More label and buttons
                                      SizedBox(height: 20),
                                      _buildMoreOption('In-Depth Nutrition',
                                          'nutrition.png'),
                                      _buildMoreOption(
                                          'Fix Manually', 'pencilicon.png'),
                                      _buildMoreOption(
                                          'Fix with AI', 'bulb.png'),
                                      _buildMoreOption('Publish', 'globe.png'),
                                    ],
                                  ),
                                ),

                                // Extra space at the bottom to account for the Save button
                                SizedBox(height: 120),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // White box at bottom - EXACTLY as in signin.dart
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.of(context).size.height * 0.148887,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),

            // Save button - EXACTLY as in signin.dart
            Positioned(
              left: 24,
              right: 24,
              bottom: MediaQuery.of(context).size.height * 0.06,
              child: Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.0689,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: TextButton(
                  onPressed: () {
                    // Exit edit mode if active
                    if (_isEditMode) {
                      setState(() {
                        _isEditMode = false;
                      });
                    }
                    // Save data and navigate to CodiaPage
                    _saveData().then((_) {
                      setState(() {
                        _hasUnsavedChanges =
                            false; // Clear unsaved changes flag

                        // Update original values to match current values
                        // so subsequent changes are tracked properly
                        _originalFoodName = _foodName;
                        _originalHealthScore = _healthScore;
                        _originalCalories = _calories;
                        _originalProtein = _protein;
                        _originalFat = _fat;
                        _originalCarbs = _carbs;
                        _originalCounter = _counter;
                      });
                      // Always navigate to CodiaPage instead of popping
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => CodiaPage()),
                      );
                    });
                  },
                  style: ButtonStyle(
                    overlayColor: MaterialStateProperty.all(Colors.transparent),
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      fontFamily: '.SF Pro Display',
                      color: Colors.white,
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

  Widget _buildMacro(String name, String amount, Color color) {
    return Column(
      children: [
        Text(name, style: TextStyle(fontSize: 12)),
        SizedBox(height: 4),
        Container(
          width: 80,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            widthFactor: 1.0, // Changed from 0.5 to 1.0 to fill entirely
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(amount,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // Helper method to format macronutrient values
  String _formatMacroValue(dynamic value) {
    if (value == null) return "0g";

    double numValue = 0.0;

    if (value is String) {
      numValue = double.tryParse(value.replaceAll("g", "").trim()) ?? 0.0;
    } else if (value is num) {
      numValue = value.toDouble();
    }

    // Custom rounding logic: X.0-0.4 = X, X.5-0.9 = X+1
    int roundedValue;
    double fractionalPart = numValue - numValue.floor();

    if (fractionalPart < 0.5) {
      // Round down for 0.0-0.4
      roundedValue = numValue.floor();
    } else {
      // Round up for 0.5-0.9
      roundedValue = numValue.floor() + 1;
    }

    return "${roundedValue}g";
  }

  // Build a flippable ingredient card
  Widget _buildIngredient(String name, String amount, String calories,
      {String protein = "0", String fat = "0", String carbs = "0"}) {
    final boxWidth = (MediaQuery.of(context).size.width - 78) / 2;

    // Format name and amount to fit in one line with max 16 chars
    String displayName = name;
    if (displayName.length > 16) {
      displayName = displayName.substring(0, 13) + "...";
    }

    String displayAmount = amount;
    if (displayAmount.length > 16) {
      displayAmount = displayAmount.substring(0, 13) + "...";
    }

    // Also format calories to ensure it fits on one line
    String displayCalories = calories;
    if (displayCalories.length > 16) {
      displayCalories = displayCalories.substring(0, 13) + "...";
    }

    // Check if it's an "Add" card - don't make these flippable
    if (name == "Add") {
      return GestureDetector(
        // Only enable the "Add" button when not in edit mode
        onTap: _isEditMode
            ? null
            : () {
                // Show the add ingredient dialog
                print("Add ingredient tapped");
                // Add your implementation here
                _showAddIngredientDialog();
              },
        child: Opacity(
          // Lower opacity in edit mode to indicate it's disabled
          opacity: _isEditMode ? 0.5 : 1.0,
          child: Container(
            width: boxWidth,
            height: 110,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              // No border for Add box, regardless of edit mode
              border: null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        SizedBox(height: 10),
                        Text(
                          amount,
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: 'SF Pro Display',
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        SizedBox(height: 10),
                        Text(
                          calories,
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: 'SF Pro Display',
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                // Add icon overlay
                Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: Image.asset(
                    'assets/images/add.png',
                    width: 29.0,
                    height: 29.0,
                    color:
                        Colors.black, // Always black, regardless of edit mode
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // For regular ingredient cards, create a flippable card
    // Use a unique key based on ingredient name and amount to track flip state
    final cardKey = "$name-$amount";

    // Initialize flip state for this card if it doesn't exist
    if (!_isIngredientFlipped.containsKey(cardKey)) {
      _isIngredientFlipped[cardKey] = false;
    }

    // Create controller for this specific card if it doesn't exist
    if (!_flipAnimationControllers.containsKey(cardKey)) {
      _flipAnimationControllers[cardKey] = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 400), // Slightly faster duration
      );

      _flipAnimations[cardKey] = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _flipAnimationControllers[cardKey]!,
          curve: Curves.easeInOut, // Gentler animation curve
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        // If in edit mode, show edit popup instead of flipping
        if (_isEditMode) {
          _showIngredientEditOptions(
              name, amount, calories, protein, fat, carbs);
        } else {
          setState(() {
            // Toggle flip state for this specific card
            _isIngredientFlipped[cardKey] =
                !(_isIngredientFlipped[cardKey] ?? false);

            // Run the animation
            if (_isIngredientFlipped[cardKey]!) {
              _flipAnimationControllers[cardKey]!.forward();
            } else {
              _flipAnimationControllers[cardKey]!.reverse();
            }
          });
        }
      },
      child: AnimatedBuilder(
        animation: _flipAnimationControllers[cardKey]!,
        builder: (context, child) {
          final value = _flipAnimations[cardKey]!.value;

          // Determine which side to show
          final showFront = value < 0.5;

          // Create a subtle opacity animation
          final opacity = showFront
              ? 1.0 -
                  (value * 1.5).clamp(
                      0.0, 1.0) // Front fades out in first 70% of animation
              : (value - 0.5) * 2.0; // Back fades in in last 70% of animation

          return Container(
            width: boxWidth,
            height: 110,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              // Add light gray border when in edit mode (changed from teal)
              border: _isEditMode
                  ? Border.all(color: Color(0xFFD3D3D3), width: 1.3)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  // Front content
                  Opacity(
                    opacity: showFront ? opacity : 0,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'SF Pro Display',
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            SizedBox(height: 10),
                            Text(
                              displayAmount,
                              style: TextStyle(
                                fontSize: 16,
                                fontFamily: 'SF Pro Display',
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            SizedBox(height: 10),
                            Text(
                              displayCalories,
                              style: TextStyle(
                                fontSize: 16,
                                fontFamily: 'SF Pro Display',
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Back content
                  Opacity(
                    opacity: !showFront ? opacity : 0,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Protein: ${_formatMacroValue(protein)}",
                              style: TextStyle(
                                fontSize: 16,
                                fontFamily: 'SF Pro Display',
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 10),
                            Text(
                              "Fat: ${_formatMacroValue(fat)}",
                              style: TextStyle(
                                fontSize: 16,
                                fontFamily: 'SF Pro Display',
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 10),
                            Text(
                              "Carbs: ${_formatMacroValue(carbs)}",
                              style: TextStyle(
                                fontSize: 16,
                                fontFamily: 'SF Pro Display',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMoreOption(String title, String iconAsset) {
    // Base icon size for pencilicon.png
    double baseIconSize = 25.0;
    // Calculate 10% larger size for the other two icons
    double largerIconSize = baseIconSize * 1.1; // 27.5px

    // Determine the size for the current icon
    double iconSize = (iconAsset == 'nutrition.png' || iconAsset == 'bulb.png')
        ? largerIconSize
        : (iconAsset == 'globe.png' ? baseIconSize * 0.9 : baseIconSize);

    // Check if this is the "Fix Manually" button and we're in edit mode
    bool isFixManuallyInEditMode = title == 'Fix Manually' && _isEditMode;

    return GestureDetector(
      onTap: () {
        // Handle the click based on which option was selected
        if (title == 'Fix Manually') {
          if (_isEditMode) {
            // If already in edit mode, exit it
            setState(() {
              _isEditMode = false;
            });
          } else {
            // Show the fix manually dialog
            _showFixManuallyDialog();
          }
        } else if (title == 'Fix with AI') {
          // Show the Fix with AI dialog
          _showFixWithAIDialog();
        } else if (title == 'In-Depth Nutrition') {
          // Navigate to the Nutrition screen
          _openNutritionScreen();
        } else if (title == 'Publish') {
          // Implement publish meal functionality
          print('Publish Meal functionality not implemented yet.');
        }
        // Add other handlers for different options if needed
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 15), // Set gap between boxes to 15px
        padding: EdgeInsets.symmetric(vertical: 0, horizontal: 20),
        width: double.infinity,
        height: 45,
        decoration: BoxDecoration(
          // Change background to black when "Fix Manually" is in edit mode
          color: isFixManuallyInEditMode ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            // Add 40px padding before the icon alignment container (35 + 5)
            SizedBox(width: 40),
            // Container to ensure icons align vertically and have space
            SizedBox(
              width: 40, // Keep this width consistent for alignment
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: iconAsset == 'globe.png'
                      ? const EdgeInsets.only(left: 1.0)
                      : EdgeInsets.zero,
                  child: SizedBox(
                    width: iconSize,
                    height: iconSize,
                    child: Image.asset(
                      'assets/images/$iconAsset',
                      width: iconSize,
                      height: iconSize,
                      fit: BoxFit.contain,
                      color:
                          isFixManuallyInEditMode ? Colors.white : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Center(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16, // Matches Health Score text size
                    fontWeight: FontWeight.normal,
                    // Change text color to white when "Fix Manually" is in edit mode
                    color:
                        isFixManuallyInEditMode ? Colors.white : Colors.black,
                  ),
                  textAlign: TextAlign.center,
                  softWrap:
                      false, // Prevent text from wrapping to the next line
                  overflow: TextOverflow
                      .visible, // Allow text to overflow container bounds
                ),
              ),
            ),
            // Adjust balance spacing for the added left padding
            SizedBox(width: 88), // (40 padding + 40 icon area + 8 gap)
          ],
        ),
      ),
    );
  }

  // Build a responsive grid of ingredient boxes
  Widget _buildIngredientGrid() {
    if (_ingredients.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: _showAddIngredientDialog, // Make the entire box clickable
            child: _buildIngredient('Add', '', ''),
          ),
          SizedBox(), // Empty spacer
        ],
      );
    }

    // Organize ingredients in rows of 2 columns
    List<Widget> rows = [];

    // Process actual ingredients (all except possibly the last one to leave room for Add button)
    for (int i = 0; i < _ingredients.length; i += 2) {
      // Check if we have a pair or a single ingredient left
      if (i + 1 < _ingredients.length) {
        // We have a pair of ingredients
        rows.add(
          Padding(
            padding: EdgeInsets.only(bottom: 15), // Gap between rows
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildIngredient(
                  _ingredients[i]['name'],
                  _ingredients[i]['amount'],
                  _formatIngredientCalories(_ingredients[i]['calories']),
                  protein: _ingredients[i]['protein']?.toString() ?? "0",
                  fat: _ingredients[i]['fat']?.toString() ?? "0",
                  carbs: _ingredients[i]['carbs']?.toString() ?? "0",
                ),
                _buildIngredient(
                  _ingredients[i + 1]['name'],
                  _ingredients[i + 1]['amount'],
                  _formatIngredientCalories(_ingredients[i + 1]['calories']),
                  protein: _ingredients[i + 1]['protein']?.toString() ?? "0",
                  fat: _ingredients[i + 1]['fat']?.toString() ?? "0",
                  carbs: _ingredients[i + 1]['carbs']?.toString() ?? "0",
                ),
              ],
            ),
          ),
        );
      } else {
        // We have a single ingredient left, pair it with the Add button
        rows.add(
          Padding(
            padding: EdgeInsets.only(bottom: 15), // Gap between rows
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildIngredient(
                  _ingredients[i]['name'],
                  _ingredients[i]['amount'],
                  _formatIngredientCalories(_ingredients[i]['calories']),
                  protein: _ingredients[i]['protein']?.toString() ?? "0",
                  fat: _ingredients[i]['fat']?.toString() ?? "0",
                  carbs: _ingredients[i]['carbs']?.toString() ?? "0",
                ),
                // Add button with clickable box
                GestureDetector(
                  onTap: _isEditMode
                      ? null
                      : _showAddIngredientDialog, // Disable in edit mode
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Add box - modified to not get a border in edit mode
                      Container(
                        width: (MediaQuery.of(context).size.width - 78) / 2,
                        height: 110,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          // No border for Add box in edit mode
                          border: null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "Add",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  "",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  "",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Add icon overlay
                      Padding(
                        padding: const EdgeInsets.only(top: 20.0),
                        child: Image.asset(
                          'assets/images/add.png',
                          width: 29.0,
                          height: 29.0,
                          color:
                              Colors.black, // Always black, even in edit mode
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    // If we have an even number of ingredients, add a row with just the Add button
    if (_ingredients.length % 2 == 0) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: 15), // Gap between rows
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Add button with clickable box
              GestureDetector(
                onTap: _isEditMode
                    ? null
                    : _showAddIngredientDialog, // Disable in edit mode
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Add box - modified to not get a border in edit mode
                    Container(
                      width: (MediaQuery.of(context).size.width - 78) / 2,
                      height: 110,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        // No border for Add box in edit mode
                        border: null,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Add",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'SF Pro Display',
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              SizedBox(height: 10),
                              Text(
                                "",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontFamily: 'SF Pro Display',
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              SizedBox(height: 10),
                              Text(
                                "",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontFamily: 'SF Pro Display',
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Add icon overlay
                    Padding(
                      padding: const EdgeInsets.only(top: 20.0),
                      child: Image.asset(
                        'assets/images/add.png',
                        width: 29.0,
                        height: 29.0,
                        color: Colors.black, // Always black, even in edit mode
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: (MediaQuery.of(context).size.width - 78) / 2,
              ), // Empty spacer with same width as ingredient box
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  // Method to show add ingredient dialog
  void _showAddIngredientDialog() {
    // Create controllers for text fields
    TextEditingController foodController = TextEditingController();
    TextEditingController sizeController = TextEditingController();
    TextEditingController caloriesController = TextEditingController();

    // Track input validation
    bool isFormValid = false;

    print('INGREDIENT DIALOG: Opening Add Ingredient dialog');

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3), // Changed to lighter opacity
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            // Check form validity
            void updateFormValidity() {
              // Get trimmed values for validation
              String foodValue = foodController.text.trim();
              String sizeValue = sizeController.text.trim();

              // Food name must have at least one character
              bool foodValid = foodValue.isNotEmpty;

              // Size must contain at least one letter (a-z, A-Z) AND at least one number (0-9)
              bool sizeValid = sizeValue.isNotEmpty &&
                  RegExp(r'[a-zA-Z]').hasMatch(sizeValue) &&
                  RegExp(r'[0-9]').hasMatch(sizeValue);

              setDialogState(() {
                isFormValid = foodValid && sizeValid;
              });
            }

            // Function to validate ingredient name
            bool isValidFoodName(String name) {
              // Allow numbers and percent signs, just check for minimum length and not excessive special chars
              if (name.length < 3) return false;
              // Disallow if there are 3 or more consecutive special characters (not letter, number, space, or %)
              if (RegExp(r'[^a-zA-Z0-9\s%]{3,}').hasMatch(name)) return false;
              return true;
            }

            // Function to clean and format ingredient name
            String cleanAndFormatFoodName(String name) {
              // Trim whitespace
              String cleaned = name.trim();

              // Remove common prefixes
              final List<String> prefixesToRemove = [
                'it also had ',
                'it also contains ',
                'also add ',
                'and also ',
                'it had ',
                'it has ',
                'add ',
                'with '
              ];

              for (String prefix in prefixesToRemove) {
                if (cleaned.toLowerCase().startsWith(prefix)) {
                  cleaned = cleaned.substring(prefix.length);
                  break;
                }
              }

              // Proper title case formatting
              if (cleaned.isNotEmpty) {
                // Check if text is all uppercase
                bool isAllCaps = cleaned == cleaned.toUpperCase() &&
                    cleaned != cleaned.toLowerCase();

                // Convert all caps to lowercase before formatting
                if (isAllCaps) cleaned = cleaned.toLowerCase();

                // Apply title case formatting with improved handling
                List<String> words = cleaned.split(' ');
                for (int i = 0; i < words.length; i++) {
                  if (words[i].isNotEmpty) {
                    words[i] = words[i][0].toUpperCase() +
                        (words[i].length > 1 ? words[i].substring(1) : '');
                  }
                }
                cleaned = words.join(' ');
              }

              return cleaned;
            }

            // Function to handle form submission with nutrition calculation
            void handleSubmit() async {
              if (!isFormValid) return;

              print('INGREDIENT ADD: Starting handleSubmit function');

              // Get values from text fields
              String foodName = foodController.text.trim();
              String size = sizeController.text.trim();
              String caloriesText = caloriesController.text.trim();

              print(
                  'INGREDIENT ADD: Got form values - foodName: $foodName, size: $size, caloriesText: $caloriesText');

              // Clean and format the food name
              foodName = cleanAndFormatFoodName(foodName);
              print('INGREDIENT ADD: Cleaned food name: $foodName');

              // Validate food name for being a reasonable food
              if (!isValidFoodName(foodName)) {
                print('INGREDIENT ADD: Invalid food name detected: $foodName');
                // Close the original dialog first
                Navigator.of(dialogContext).pop();

                // Show unclear input dialog
                _showUnclearInputDialog();
                return;
              }

              // Format size by removing spaces before 'g' and 'kg'
              if (size.isNotEmpty) {
                // Handle '150 g' format
                size = size.replaceAll(' g', 'g');
                // Handle '1.5 kg' format
                size = size.replaceAll(' kg', 'kg');
                print('INGREDIENT ADD: Formatted size: $size');
              }

              // Initialize nutritional values
              double calories = 0;
              String protein = "0";
              String fat = "0";
              String carbs = "0";

              // Close the ingredient dialog first
              print('INGREDIENT ADD: Closing add ingredient dialog');
              Navigator.of(dialogContext).pop();

              // Handle empty calories field - calculate with AI
              if (caloriesText.isEmpty) {
                print(
                    'INGREDIENT ADD: Empty calories field, calculating with AI for $foodName ($size)');

                try {
                  // Show loading indicator with the same style as Fix with AI
                  BuildContext? loadingDialogContext;
                  showDialog(
                    context: context,
                    barrierColor: Colors.black
                        .withOpacity(0.3), // Consistent light opacity
                    barrierDismissible: false,
                    builder: (BuildContext ctx) {
                      loadingDialogContext = ctx;
                      return Dialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 0,
                        backgroundColor: Colors.white,
                        child: Container(
                          width: 270,
                          height: 136,
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 3,
                                ),
                              ),
                              SizedBox(height: 24),
                              Text(
                                "Calculating...",
                                style: TextStyle(
                                  fontFamily: 'SF Pro Display',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );

                  // Call the nutrition calculation API
                  print('INGREDIENT ADD: Calling _calculateNutritionWithAI');
                  final nutritionData =
                      await _calculateNutritionWithAI(foodName, size);

                  // Close loading dialog safely using the stored context
                  if (loadingDialogContext != null && mounted) {
                    try {
                      Navigator.of(loadingDialogContext!).pop();
                    } catch (e) {
                      print('Error dismissing loading dialog: $e');
                    }
                  }

                  print(
                      'INGREDIENT ADD: Received nutritionData: $nutritionData');

                  // Check if this was flagged as an invalid food by the API
                  if (nutritionData.containsKey('invalid_food') &&
                      nutritionData['invalid_food'] == true) {
                    print('INGREDIENT ADD: Invalid food name detected by API');
                    // Don't need to show dialog here - the _calculateNutritionWithAI function already shows it
                    return;
                  }
                  // If scan failed, do not add ingredient
                  if (nutritionData.containsKey('scan_failed') &&
                      nutritionData['scan_failed'] == true) {
                    print('INGREDIENT ADD: Scan failed, not adding ingredient');
                    return;
                  }

                  // Extract values with more careful parsing
                  calories =
                      double.tryParse(nutritionData['calories'].toString()) ??
                          0.0;
                  protein = (nutritionData['protein'] ?? 0.0).toString();
                  fat = (nutritionData['fat'] ?? 0.0).toString();
                  carbs = (nutritionData['carbs'] ?? 0.0).toString();

                  print(
                      'INGREDIENT ADD: Processed values - calories=$calories, protein=$protein, fat=$fat, carbs=$carbs');

                  // Check if we got valid calorie data
                  if (calories <= 0) {
                    print(
                        'INGREDIENT ADD: Invalid calories value received: $calories');
                    // Use default calorie estimate based on food type
                    calories = _estimateCaloriesForFood(foodName, size);
                    print(
                        'INGREDIENT ADD: Using estimated calories: $calories');
                  }

                  // Update main nutritional values - still on FoodCardOpen screen
                  if (mounted) {
                    print(
                        'INGREDIENT ADD: Widget is still mounted, updating state');

                    // Create new ingredient with calculated calories
                    Map<String, dynamic> newIngredient = {
                      'name': _truncateWithEllipsis(foodName, 16),
                      'amount': size,
                      'calories': calories,
                      'protein': protein,
                      'fat': fat,
                      'carbs': carbs
                    };

                    // Make sure we're using the addIngredientToList method that handles truncation
                    _addIngredientToList(newIngredient);

                    print(
                        'INGREDIENT ADD: Successfully added ingredient, waiting for save');
                  }
                } catch (e) {
                  print('CRITICAL ERROR in handleSubmit: $e');
                  if (mounted) {
                    print('INGREDIENT ADD: Showing error alert');

                    // Create the ingredient with estimated values
                    double estimatedCalories =
                        _estimateCaloriesForFood(foodName, size);
                    double estimatedProtein = estimatedCalories * 0.25 / 4;
                    double estimatedFat = estimatedCalories * 0.3 / 9;
                    double estimatedCarbs = estimatedCalories * 0.45 / 4;

                    // Add the ingredient with estimated values
                    setState(() {
                      Map<String, dynamic> newIngredient = {
                        'name': _truncateWithEllipsis(foodName, 16),
                        'amount': size,
                        'calories': estimatedCalories,
                        'protein': estimatedProtein.toStringAsFixed(1),
                        'fat': estimatedFat.toStringAsFixed(1),
                        'carbs': estimatedCarbs.toStringAsFixed(1)
                      };

                      // Use our dedicated method to add the ingredient
                      _addIngredientToList(newIngredient);
                    });

                    // Show error dialog after adding the ingredient
                    _showStandardDialog(
                      title: 'Calculation Error',
                      message:
                          'We couldn\'t calculate the nutrition for this ingredient. Using estimated values instead.',
                      positiveButtonText: 'OK',
                    );
                  }
                }
              } else {
                // User provided calories directly
                try {
                  print(
                      'INGREDIENT ADD: Using user-provided calories: $caloriesText');

                  // Parse provided calories
                  calories = double.tryParse(caloriesText) ?? 0;
                  print('INGREDIENT ADD: Parsed calories: $calories');

                  // Calculate reasonable default macros based on calories
                  // For a balanced food item: ~25% protein, ~30% fat, ~45% carbs
                  double defaultProtein =
                      (calories * 0.25 / 4); // 4 calories per gram of protein
                  double defaultFat =
                      (calories * 0.30 / 9); // 9 calories per gram of fat
                  double defaultCarbs =
                      (calories * 0.45 / 4); // 4 calories per gram of carbs

                  // Set default values for macros with 1 decimal place
                  protein = defaultProtein.toStringAsFixed(1);
                  fat = defaultFat.toStringAsFixed(1);
                  carbs = defaultCarbs.toStringAsFixed(1);
                  print(
                      'INGREDIENT ADD: Calculated macros - protein=$protein, fat=$fat, carbs=$carbs');

                  if (mounted) {
                    print(
                        'INGREDIENT ADD: Widget is still mounted, updating state with manual calories');

                    // Create new ingredient with user-provided calories
                    Map<String, dynamic> newIngredient = {
                      'name': foodName,
                      'amount': size,
                      'calories': calories,
                      'protein': protein,
                      'fat': fat,
                      'carbs': carbs
                    };

                    // Use our dedicated method to add the ingredient
                    _addIngredientToList(newIngredient);

                    print(
                        'INGREDIENT ADD: Added ingredient with provided calories, changes marked as unsaved');
                  }
                } catch (e) {
                  print('ERROR handling manual calories: $e');
                }
              }
            }

            return Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: TextSelectionThemeData(
                  selectionColor: Colors.grey.withOpacity(0.3),
                  cursorColor: Colors.black,
                  selectionHandleColor: Colors.black,
                ),
              ),
              child: Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
                backgroundColor: Colors.white,
                insetPadding: EdgeInsets.symmetric(horizontal: 32),
                child: Container(
                  width: 326, // Same width as Add dialog
                  height: 530, // Same height as Add dialog
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Title
                            SizedBox(height: 14),
                            Text(
                              "Add Ingredient",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),

                            // Plus icon
                            SizedBox(height: 29),
                            Image.asset(
                              'assets/images/add.png',
                              width: 45.0,
                              height: 45.0,
                            ),

                            // Food field
                            SizedBox(height: 25),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Food",
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  SizedBox(height: 7),
                                  Container(
                                    width: 280,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(25),
                                      border:
                                          Border.all(color: Colors.grey[300]!),
                                    ),
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 15),
                                    child: TextField(
                                      controller: foodController,
                                      cursorColor: Colors.black,
                                      cursorWidth: 1.2,
                                      onChanged: (value) {
                                        updateFormValidity();
                                      },
                                      style: TextStyle(
                                        fontSize: 13.6,
                                        fontFamily: '.SF Pro Display',
                                        color: Colors.black,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: "Pasta, Tomato, etc",
                                        hintStyle: TextStyle(
                                          color: Colors.grey[600]!
                                              .withOpacity(0.7),
                                          fontSize: 13.6,
                                          fontFamily: '.SF Pro Display',
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding:
                                            EdgeInsets.symmetric(vertical: 15),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Size field
                            SizedBox(height: 10),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Size",
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  SizedBox(height: 7),
                                  Container(
                                    width: 280,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(25),
                                      border:
                                          Border.all(color: Colors.grey[300]!),
                                    ),
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 15),
                                    child: TextField(
                                      controller: sizeController,
                                      cursorColor: Colors.black,
                                      cursorWidth: 1.2,
                                      onChanged: (value) {
                                        updateFormValidity();
                                      },
                                      style: TextStyle(
                                        fontSize: 13.6,
                                        fontFamily: '.SF Pro Display',
                                        color: Colors.black,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: "150g, 3/4 cup, etc",
                                        hintStyle: TextStyle(
                                          color: Colors.grey[600]!
                                              .withOpacity(0.7),
                                          fontSize: 13.6,
                                          fontFamily: '.SF Pro Display',
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding:
                                            EdgeInsets.symmetric(vertical: 15),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Calories field
                            SizedBox(height: 10),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        "Calories",
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'SF Pro Display',
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 1), // Moved up by 1px
                                        child: Text(
                                          "(optional)",
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w400,
                                            fontFamily: 'SF Pro Display',
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 7),
                                  Container(
                                    width: 280,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(25),
                                      border:
                                          Border.all(color: Colors.grey[300]!),
                                    ),
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 15),
                                    child: TextField(
                                      controller: caloriesController,
                                      cursorColor: Colors.black,
                                      cursorWidth: 1.2,
                                      style: TextStyle(
                                        fontSize: 13.6,
                                        fontFamily: '.SF Pro Display',
                                        color: Colors.black,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: "450 kcal",
                                        hintStyle: TextStyle(
                                          color: Colors.grey[600]!
                                              .withOpacity(0.7),
                                          fontSize: 13.6,
                                          fontFamily: '.SF Pro Display',
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding:
                                            EdgeInsets.symmetric(vertical: 15),
                                      ),
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Add button
                            SizedBox(height: 30),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Container(
                                width: 280,
                                height: 48,
                                margin: EdgeInsets.only(bottom: 24),
                                decoration: BoxDecoration(
                                  color: isFormValid
                                      ? Colors.black
                                      : Colors.grey[400],
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: TextButton(
                                  onPressed: isFormValid ? handleSubmit : null,
                                  style: ButtonStyle(
                                    overlayColor: MaterialStateProperty.all(
                                        Colors.transparent),
                                  ),
                                  child: const Text(
                                    'Add',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: '.SF Pro Display',
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Close button
                      Positioned(
                        top:
                            23, // Adjusted from 26 to 23 to align with the "Fix Manually" title
                        right: 20,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: Image.asset(
                            'assets/images/closeicon.png',
                            width: 19,
                            height: 19,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Method to add ingredient with better error handling and debugging
  void _addIngredientToList(Map<String, dynamic> newIngredient) {
    try {
      final name = newIngredient['name'] ?? '';

      if (name == null || name.trim().isEmpty) {
        print('INGREDIENT ADD: Skipping ingredient with empty name');
        return;
      }

      // Always truncate ingredient name to 16 characters if needed
      if (name.length > 16) {
        newIngredient['name'] = _truncateWithEllipsis(name, 16);
      }

      print('INGREDIENT ADD: Adding new ingredient: $newIngredient');

      // Add the ingredient
      setState(() {
        _ingredients.add(newIngredient);
        _hasUnsavedChanges = true; // Mark as having unsaved changes

        // Sort ingredients by calories (highest to lowest)
        _ingredients.sort((a, b) {
          final caloriesA = a.containsKey('calories')
              ? double.tryParse(a['calories'].toString()) ?? 0
              : 0;
          final caloriesB = b.containsKey('calories')
              ? double.tryParse(b['calories'].toString()) ?? 0
              : 0;
          return caloriesB.compareTo(caloriesA);
        });
      });

      // Debug the updated ingredients list after addition
      print('INGREDIENTS LIST AFTER ADDITION:');
      for (int i = 0; i < _ingredients.length; i++) {
        print(
            '[${i + 1}] ${_ingredients[i]['name']} - ${_ingredients[i]['amount']} - ${_ingredients[i]['calories']} kcal');
      }

      // Calculate total nutrition from all ingredients
      _calculateTotalNutrition();

      // Save the data immediately to ensure it's reflected in the Nutrition screen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _saveData();
      });
    } catch (e) {
      print('ERROR adding ingredient to list: $e');
    }
  }

  // Calculate total nutrition values from all ingredients
  void _calculateTotalNutrition() {
    if (_ingredients.isEmpty) {
      // If no ingredients, set default values
      String oldCalories = _calories;
      String oldProtein = _protein;
      String oldFat = _fat;
      String oldCarbs = _carbs;

      setState(() {
        _calories = "0";
        _protein = "0";
        _fat = "0";
        _carbs = "0";

        // Only mark as unsaved if values actually changed
        if (_calories != oldCalories ||
            _protein != oldProtein ||
            _fat != oldFat ||
            _carbs != oldCarbs) {
          print('Nutrition values changed, marking as unsaved');
          _hasUnsavedChanges = true;
        }
      });
      return;
    }

    // Sum up all nutritional values from ingredients - use more efficient loops and calculations
    double totalCalories = 0;
    double totalProtein = 0;
    double totalFat = 0;
    double totalCarbs = 0;

    // Save old values for comparison
    String oldCalories = _calories;
    String oldProtein = _protein;
    String oldFat = _fat;
    String oldCarbs = _carbs;

    // Process all ingredients in a single loop - more efficient
    final int ingredientCount = _ingredients.length;
    for (int i = 0; i < ingredientCount; i++) {
      final ingredient = _ingredients[i];

      // Add calories - multiply by counter
      if (ingredient.containsKey('calories')) {
        var calories = ingredient['calories'];
        if (calories is String) {
          totalCalories += (double.tryParse(calories) ?? 0) * _counter;
        } else if (calories is num) {
          totalCalories += calories.toDouble() * _counter;
        }
      }

      // Add protein - multiply by counter
      if (ingredient.containsKey('protein')) {
        var protein = ingredient['protein'];
        if (protein is String) {
          totalProtein += (double.tryParse(protein) ?? 0) * _counter;
        } else if (protein is num) {
          totalProtein += protein.toDouble() * _counter;
        }
      }

      // Add fat - multiply by counter
      if (ingredient.containsKey('fat')) {
        var fat = ingredient['fat'];
        if (fat is String) {
          totalFat += (double.tryParse(fat) ?? 0) * _counter;
        } else if (fat is num) {
          totalFat += fat.toDouble() * _counter;
        }
      }

      // Add carbs - multiply by counter
      if (ingredient.containsKey('carbs')) {
        var carbs = ingredient['carbs'];
        if (carbs is String) {
          totalCarbs += (double.tryParse(carbs) ?? 0) * _counter;
        } else if (carbs is num) {
          totalCarbs += carbs.toDouble() * _counter;
        }
      }
    }

    // Update state with calculated totals using standard rounding (0-0.4 down, 0.5-0.9 up)
    // Calculate new values before setState to minimize state updates
    final String newCalories = totalCalories.round().toString();
    final String newProtein = totalProtein.round().toString();
    final String newFat = totalFat.round().toString();
    final String newCarbs = totalCarbs.round().toString();

    // Check if values actually changed before updating state
    final bool hasChanged = (newCalories != oldCalories ||
        newProtein != oldProtein ||
        newFat != oldFat ||
        newCarbs != oldCarbs);

    setState(() {
      _calories = newCalories;
      _protein = newProtein;
      _fat = newFat;
      _carbs = newCarbs;

      // Only mark as unsaved if values actually changed
      if (hasChanged) {
        print('Nutrition values changed, marking as unsaved');
        _hasUnsavedChanges = true;
      }
    });

    print(
        'NUTRITION TOTALS: Calories=$_calories, Protein=$_protein, Fat=$_fat, Carbs=$_carbs');
  }

  // Helper method to show API error dialog in premium style
  void _showApiErrorDialog() {
    _showStandardDialog(
      title: "Service Unavailable",
      message:
          "The food modification service is currently unavailable. Please try again later.",
      positiveButtonText: "OK",
    );
  }

  // Helper method to show unclear input error dialog in premium style
  void _showUnclearInputDialog() {
    _showStandardDialog(
      title: "Invalid Ingredient",
      message:
          "Please enter a valid food name and serving size that we can calculate nutrition for",
      positiveButtonText: "Try Again",
      positiveButtonIcon:
          'assets/images/edit.png', // Make sure this asset exists
      onPositivePressed: () {
        Navigator.of(context).pop();
        _showAddIngredientDialog();
      },
    );
  }

  // Method to show the "Fix Manually" dialog
  void _showFixManuallyDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Theme(
          data: Theme.of(context).copyWith(
            textSelectionTheme: TextSelectionThemeData(
              selectionColor: Colors.grey.withOpacity(0.3),
              cursorColor: Colors.black,
              selectionHandleColor: Colors.black,
            ),
          ),
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 0,
            backgroundColor: Colors.white,
            insetPadding: EdgeInsets.symmetric(horizontal: 32),
            child: Container(
              width: 326, // Exactly 326px as specified
              height: 360, // Adjusted height for proper spacing
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Title
                        SizedBox(height: 14),
                        Text(
                          "Fix Manually",
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                          ),
                        ),

                        // Use Expanded to center the image and text as one group
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Pencil icon - exactly 43x43
                                Image.asset(
                                  'assets/images/pencilicon.png',
                                  width: 43.0,
                                  height: 43.0,
                                  color: Colors.black,
                                ),

                                // 28px gap between image and text
                                SizedBox(height: 28),

                                // Instructions text - already size 18
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 25),
                                  child: Text(
                                    "Tap any item to change its name, calories, macros or serving sizes",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontFamily: 'SF Pro Display',
                                      fontWeight: FontWeight.w400,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Fix Now button - match "Add" popup spacing
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            width: 280,
                            height: 48,
                            margin: EdgeInsets.only(
                                bottom: 24), // Same margin as Add popup
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: TextButton(
                              onPressed: () {
                                // Handle the "Fix Now" action
                                Navigator.pop(context);
                                // Set edit mode to show teal outlines
                                setState(() {
                                  _isEditMode = true;
                                });
                              },
                              style: ButtonStyle(
                                overlayColor: MaterialStateProperty.all(
                                    Colors.transparent),
                              ),
                              child: const Text(
                                'Fix Now',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: '.SF Pro Display',
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Close button
                  Positioned(
                    top:
                        23, // Adjusted from 26 to 23 to align with the "Fix Manually" title
                    right: 20,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                      child: Image.asset(
                        'assets/images/closeicon.png',
                        width: 19,
                        height: 19,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Method to show edit and delete options for an ingredient
  void _showIngredientEditOptions(String name, String amount, String calories,
      String protein, String fat, String carbs) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            width: 326,
            height: 175, // Changed from 185px to 175px
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Main content
                Container(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Title with padding
                      Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 15),
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'SF Pro Display',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      // Buttons container
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 29.5),
                        child: Column(
                          children: [
                            // Edit option
                            Container(
                              width: 267,
                              height: 40,
                              margin: EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Centered text
                                  Text(
                                    "Edit",
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                      fontFamily: 'SF Pro Display',
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  // Icon positioned to the left
                                  Positioned(
                                    left: 70,
                                    child: Image.asset(
                                      'assets/images/pencilicon.png',
                                      width: 20,
                                      height: 20,
                                      color: Colors.black,
                                    ),
                                  ),
                                  // Full-width button for tap area
                                  Positioned.fill(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () {
                                          Navigator.pop(context);
                                          // Show the edit ingredient dialog
                                          _showEditIngredientDialog(
                                              name,
                                              amount,
                                              calories,
                                              protein,
                                              fat,
                                              carbs);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Delete option
                            Container(
                              width: 267,
                              height: 40,
                              margin: EdgeInsets.only(
                                  bottom: 5), // Small margin added at bottom
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Centered text
                                  Text(
                                    "Delete",
                                    style: TextStyle(
                                      color: Color(0xFFE97372),
                                      fontSize: 16,
                                      fontFamily: 'SF Pro Display',
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  // Icon positioned to the left
                                  Positioned(
                                    left: 70,
                                    child: Image.asset(
                                      'assets/images/trashcan.png',
                                      width: 20,
                                      height: 20,
                                      color: Color(0xFFE97372),
                                    ),
                                  ),
                                  // Full-width button for tap area
                                  Positioned.fill(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _showDeleteIngredientConfirmation(
                                              name,
                                              amount,
                                              calories,
                                              protein,
                                              fat,
                                              carbs);
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Close button in top-right corner
                Positioned(
                  top: 24, // Align with the "Edit Ingredient" title text
                  right: 22 - 1, // Moved right by 1px
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: Image.asset(
                      'assets/images/closeicon.png',
                      width: 19, // Update to 19x19
                      height: 19, // Update to 19x19
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Method to show edit ingredient dialog
  void _showEditIngredientDialog(String name, String amount, String calories,
      String protein, String fat, String carbs) {
    // Format the values exactly as they appear on the box card (removing units)
    String proteinValue = protein.replaceAll("g", "").trim();
    String fatValue = fat.replaceAll("g", "").trim();
    String carbsValue = carbs.replaceAll("g", "").trim();

    // Apply custom rounding logic to ensure whole numbers
    // with X.0-0.4 = X, X.5-0.9 = X+1
    try {
      if (proteinValue.isNotEmpty && proteinValue.contains(".")) {
        double proteinNum = double.tryParse(proteinValue) ?? 0.0;
        double fractionalPart = proteinNum - proteinNum.floor();
        if (fractionalPart < 0.5) {
          proteinValue = proteinNum.floor().toString();
        } else {
          proteinValue = (proteinNum.floor() + 1).toString();
        }
      }

      if (fatValue.isNotEmpty && fatValue.contains(".")) {
        double fatNum = double.tryParse(fatValue) ?? 0.0;
        double fractionalPart = fatNum - fatNum.floor();
        if (fractionalPart < 0.5) {
          fatValue = fatNum.floor().toString();
        } else {
          fatValue = (fatNum.floor() + 1).toString();
        }
      }

      if (carbsValue.isNotEmpty && carbsValue.contains(".")) {
        double carbsNum = double.tryParse(carbsValue) ?? 0.0;
        double fractionalPart = carbsNum - carbsNum.floor();
        if (fractionalPart < 0.5) {
          carbsValue = carbsNum.floor().toString();
        } else {
          carbsValue = (carbsNum.floor() + 1).toString();
        }
      }
    } catch (e) {
      print("Error rounding macro values: $e");
    }

    // Create controllers for text fields
    TextEditingController foodController = TextEditingController(text: name);
    TextEditingController sizeController = TextEditingController(text: amount);
    TextEditingController caloriesController =
        TextEditingController(text: calories.replaceAll(" kcal", ""));

    // Use the values with custom rounding applied
    TextEditingController proteinController =
        TextEditingController(text: proteinValue);
    TextEditingController fatController = TextEditingController(text: fatValue);
    TextEditingController carbsController =
        TextEditingController(text: carbsValue);

    // Track active fields - start with primary fields active
    Map<String, bool> isActive = {
      'food': true,
      'protein': false,
      'size': true,
      'fat': false,
      'calories': true,
      'carbs': false,
    };

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          return Theme(
            data: Theme.of(context).copyWith(
              textSelectionTheme: TextSelectionThemeData(
                selectionColor: Colors.grey.withOpacity(0.3),
                cursorColor: Colors.black,
                selectionHandleColor: Colors.black,
              ),
            ),
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              backgroundColor: Colors.white,
              insetPadding: EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                width: 326, // Same width as Add dialog
                height: 530, // Same height as Add dialog
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Title
                          SizedBox(height: 14),
                          Text(
                            "Edit Ingredient",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),

                          // Pencil icon
                          SizedBox(height: 29),
                          Image.asset(
                            'assets/images/pencilicon.png',
                            width: 45.0,
                            height: 45.0,
                          ),

                          // Food field with Protein label
                          SizedBox(height: 25),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Stack(
                              children: [
                                // Food/Protein section
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              isActive['food'] = true;
                                              isActive['protein'] = false;
                                            });
                                          },
                                          child: Text(
                                            "Food",
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w500,
                                              fontFamily: 'SF Pro Display',
                                              color: isActive['food']!
                                                  ? Colors.black
                                                  : Colors.black
                                                      .withOpacity(0.5),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 7),
                                    Container(
                                      width: 280,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(25),
                                        border: Border.all(
                                            color: Colors.grey[300]!),
                                      ),
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 15),
                                      child: isActive['food']!
                                          ? TextField(
                                              controller: foodController,
                                              cursorColor: Colors.black,
                                              cursorWidth: 1.2,
                                              style: TextStyle(
                                                fontSize: 13.6,
                                                fontFamily: '.SF Pro Display',
                                                color: Colors.black,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: "Pasta, Tomato, etc",
                                                hintStyle: TextStyle(
                                                  color: Colors.grey[600]!
                                                      .withOpacity(0.7),
                                                  fontSize: 13.6,
                                                  fontFamily: '.SF Pro Display',
                                                ),
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        vertical: 15),
                                              ),
                                            )
                                          : TextField(
                                              controller: proteinController,
                                              cursorColor: Colors.black,
                                              cursorWidth: 1.2,
                                              style: TextStyle(
                                                fontSize: 13.6,
                                                fontFamily: '.SF Pro Display',
                                                color: Colors.black,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: "15",
                                                suffixText: "g",
                                                suffixStyle: TextStyle(
                                                  fontSize: 13.6,
                                                  fontFamily: '.SF Pro Display',
                                                  color: Colors.black,
                                                ),
                                                hintStyle: TextStyle(
                                                  color: Colors.grey[600]!
                                                      .withOpacity(0.7),
                                                  fontSize: 13.6,
                                                  fontFamily: '.SF Pro Display',
                                                ),
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        vertical: 15),
                                              ),
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly, // Only allow digits
                                              ],
                                            ),
                                    ),
                                  ],
                                ),

                                // Protein label positioned at the right edge of the input field
                                Positioned(
                                  top: 0,
                                  right:
                                      0, // Align with right edge of the input field
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        isActive['food'] = false;
                                        isActive['protein'] = true;
                                      });
                                    },
                                    child: Text(
                                      "Protein",
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'SF Pro Display',
                                        color: isActive['protein']!
                                            ? Colors.black
                                            : Colors.black.withOpacity(0.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Size field with Fat label
                          SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Stack(
                              children: [
                                // Size/Fat section
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          isActive['size'] = true;
                                          isActive['fat'] = false;
                                        });
                                      },
                                      child: Text(
                                        "Size",
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'SF Pro Display',
                                          color: isActive['size']!
                                              ? Colors.black
                                              : Colors.black.withOpacity(0.5),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 7),
                                    Container(
                                      width: 280,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(25),
                                        border: Border.all(
                                            color: Colors.grey[300]!),
                                      ),
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 15),
                                      child: isActive['size']!
                                          ? TextField(
                                              controller: sizeController,
                                              cursorColor: Colors.black,
                                              cursorWidth: 1.2,
                                              style: TextStyle(
                                                fontSize: 13.6,
                                                fontFamily: '.SF Pro Display',
                                                color: Colors.black,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: "150g, 3/4 cup, etc",
                                                hintStyle: TextStyle(
                                                  color: Colors.grey[600]!
                                                      .withOpacity(0.7),
                                                  fontSize: 13.6,
                                                  fontFamily: '.SF Pro Display',
                                                ),
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        vertical: 15),
                                              ),
                                            )
                                          : TextField(
                                              controller: fatController,
                                              cursorColor: Colors.black,
                                              cursorWidth: 1.2,
                                              style: TextStyle(
                                                fontSize: 13.6,
                                                fontFamily: '.SF Pro Display',
                                                color: Colors.black,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: "5",
                                                suffixText: "g",
                                                suffixStyle: TextStyle(
                                                  fontSize: 13.6,
                                                  fontFamily: '.SF Pro Display',
                                                  color: Colors.black,
                                                ),
                                                hintStyle: TextStyle(
                                                  color: Colors.grey[600]!
                                                      .withOpacity(0.7),
                                                  fontSize: 13.6,
                                                  fontFamily: '.SF Pro Display',
                                                ),
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        vertical: 15),
                                              ),
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly, // Only allow digits
                                              ],
                                            ),
                                    ),
                                  ],
                                ),

                                // Fat label positioned at the right edge of the input field
                                Positioned(
                                  top: 0,
                                  right:
                                      0, // Align with right edge of the input field
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        isActive['size'] = false;
                                        isActive['fat'] = true;
                                      });
                                    },
                                    child: Text(
                                      "Fat",
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'SF Pro Display',
                                        color: isActive['fat']!
                                            ? Colors.black
                                            : Colors.black.withOpacity(0.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Calories field with Carbs label
                          SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Stack(
                              children: [
                                // Calories/Carbs section
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          isActive['calories'] = true;
                                          isActive['carbs'] = false;
                                        });
                                      },
                                      child: Text(
                                        "Calories",
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w500,
                                          fontFamily: 'SF Pro Display',
                                          color: isActive['calories']!
                                              ? Colors.black
                                              : Colors.black.withOpacity(0.5),
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 7),
                                    Container(
                                      width: 280,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(25),
                                        border: Border.all(
                                            color: Colors.grey[300]!),
                                      ),
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 15),
                                      child: isActive['calories']!
                                          ? TextField(
                                              controller: caloriesController,
                                              cursorColor: Colors.black,
                                              cursorWidth: 1.2,
                                              style: TextStyle(
                                                fontSize: 13.6,
                                                fontFamily: '.SF Pro Display',
                                                color: Colors.black,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: "450",
                                                suffixText: "kcal",
                                                suffixStyle: TextStyle(
                                                  fontSize: 13.6,
                                                  fontFamily: '.SF Pro Display',
                                                  color: Colors.black,
                                                ),
                                                hintStyle: TextStyle(
                                                  color: Colors.grey[600]!
                                                      .withOpacity(0.7),
                                                  fontSize: 13.6,
                                                  fontFamily: '.SF Pro Display',
                                                ),
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        vertical: 15),
                                              ),
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly, // Only allow digits
                                              ],
                                            )
                                          : TextField(
                                              controller: carbsController,
                                              cursorColor: Colors.black,
                                              cursorWidth: 1.2,
                                              style: TextStyle(
                                                fontSize: 13.6,
                                                fontFamily: '.SF Pro Display',
                                                color: Colors.black,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: "30",
                                                suffixText: "g",
                                                suffixStyle: TextStyle(
                                                  fontSize: 13.6,
                                                  fontFamily: '.SF Pro Display',
                                                  color: Colors.black,
                                                ),
                                                hintStyle: TextStyle(
                                                  color: Colors.grey[600]!
                                                      .withOpacity(0.7),
                                                  fontSize: 13.6,
                                                  fontFamily: '.SF Pro Display',
                                                ),
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        vertical: 15),
                                              ),
                                              keyboardType:
                                                  TextInputType.number,
                                              inputFormatters: [
                                                FilteringTextInputFormatter
                                                    .digitsOnly, // Only allow digits
                                              ],
                                            ),
                                    ),
                                  ],
                                ),

                                // Carbs label positioned at the right edge of the input field
                                Positioned(
                                  top: 0,
                                  right:
                                      0, // Align with right edge of the input field
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        isActive['calories'] = false;
                                        isActive['carbs'] = true;
                                      });
                                    },
                                    child: Text(
                                      "Carbs",
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'SF Pro Display',
                                        color: isActive['carbs']!
                                            ? Colors.black
                                            : Colors.black.withOpacity(0.5),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Update button
                          SizedBox(height: 30),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Container(
                              width: 280,
                              height: 48,
                              margin: EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: TextButton(
                                onPressed: () {
                                  // Update the ingredient with the new values
                                  String newName = foodController.text.trim();
                                  String newAmount = sizeController.text.trim();

                                  // Convert all nutrient values to integer strings to ensure no decimals
                                  // with custom rounding logic: X.0-0.4 = X, X.5-0.9 = X+1
                                  String newCalories =
                                      caloriesController.text.trim();
                                  if (newCalories.isNotEmpty &&
                                      newCalories.contains(".")) {
                                    double calValue =
                                        double.tryParse(newCalories) ?? 0.0;
                                    double fractionalPart =
                                        calValue - calValue.floor();
                                    if (fractionalPart < 0.5) {
                                      newCalories = calValue.floor().toString();
                                    } else {
                                      newCalories =
                                          (calValue.floor() + 1).toString();
                                    }
                                  }

                                  String newProtein =
                                      proteinController.text.trim();
                                  if (newProtein.isNotEmpty &&
                                      newProtein.contains(".")) {
                                    double proteinValue =
                                        double.tryParse(newProtein) ?? 0.0;
                                    double fractionalPart =
                                        proteinValue - proteinValue.floor();
                                    if (fractionalPart < 0.5) {
                                      newProtein =
                                          proteinValue.floor().toString();
                                    } else {
                                      newProtein =
                                          (proteinValue.floor() + 1).toString();
                                    }
                                  }

                                  String newFat = fatController.text.trim();
                                  if (newFat.isNotEmpty &&
                                      newFat.contains(".")) {
                                    double fatValue =
                                        double.tryParse(newFat) ?? 0.0;
                                    double fractionalPart =
                                        fatValue - fatValue.floor();
                                    if (fractionalPart < 0.5) {
                                      newFat = fatValue.floor().toString();
                                    } else {
                                      newFat =
                                          (fatValue.floor() + 1).toString();
                                    }
                                  }

                                  String newCarbs = carbsController.text.trim();
                                  if (newCarbs.isNotEmpty &&
                                      newCarbs.contains(".")) {
                                    double carbsValue =
                                        double.tryParse(newCarbs) ?? 0.0;
                                    double fractionalPart =
                                        carbsValue - carbsValue.floor();
                                    if (fractionalPart < 0.5) {
                                      newCarbs = carbsValue.floor().toString();
                                    } else {
                                      newCarbs =
                                          (carbsValue.floor() + 1).toString();
                                    }
                                  }

                                  // Find and update the ingredient in the _ingredients list
                                  for (int i = 0;
                                      i < _ingredients.length;
                                      i++) {
                                    if (_ingredients[i]['name'] == name &&
                                        _ingredients[i]['amount'] == amount) {
                                      this.setState(() {
                                        _ingredients[i]['name'] = newName;
                                        _ingredients[i]['amount'] = newAmount;
                                        _ingredients[i]['calories'] =
                                            newCalories;
                                        _ingredients[i]['protein'] = newProtein;
                                        _ingredients[i]['fat'] = newFat;
                                        _ingredients[i]['carbs'] = newCarbs;
                                      });

                                      // Recalculate total nutrition
                                      _calculateTotalNutrition();

                                      // Don't save the data until the user clicks Save
                                      _markAsUnsaved();
                                      break;
                                    }
                                  }

                                  Navigator.pop(context);
                                },
                                style: ButtonStyle(
                                  overlayColor: MaterialStateProperty.all(
                                      Colors.transparent),
                                ),
                                child: const Text(
                                  'Update',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: '.SF Pro Display',
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Close button
                    Positioned(
                      top: 21, // Move up by 2px more (from 23 to 21)
                      right: 21, // Keep adjusted position
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                        },
                        child: Image.asset(
                          'assets/images/closeicon.png',
                          width: 19, // Update to 19x19
                          height: 19, // Update to 19x19
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  // Method to show delete ingredient confirmation
  void _showDeleteIngredientConfirmation(String name, String amount,
      String calories, String protein, String fat, String carbs) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.symmetric(horizontal: 32),
          child: Container(
            width: 326,
            height: 182,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text(
                    "Delete Ingredient?",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  SizedBox(height: 20),

                  // Delete button
                  Container(
                    width: 267,
                    height: 40,
                    margin: EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Centered text
                        Text(
                          "Delete",
                          style: TextStyle(
                            color: Color(0xFFE97372),
                            fontSize: 16,
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        // Icon positioned to the left with exact spacing
                        Positioned(
                          left: 70, // Position for 28px from text
                          child: Image.asset(
                            'assets/images/trashcan.png',
                            width: 20,
                            height: 20,
                            color: Color(0xFFE97372),
                          ),
                        ),
                        // Full-width button for tap area
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                Navigator.pop(context);
                                _deleteIngredient(name, amount, calories,
                                    protein, fat, carbs);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Cancel button
                  Container(
                    width: 267,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Centered text
                        Text(
                          "Cancel",
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 16,
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        // Icon positioned to match the delete icon's position
                        Positioned(
                          left: 70, // Same position as delete icon
                          child: Image.asset(
                            'assets/images/closeicon.png',
                            width: 18, // 10% smaller than 20
                            height: 18, // 10% smaller than 20
                            color: Colors.black54,
                          ),
                        ),
                        // Full-width button for tap area
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Method to delete an ingredient and update nutrition values
  void _deleteIngredient(String name, String amount, String calories,
      String protein, String fat, String carbs) {
    // Find the ingredient in the _ingredients list
    int indexToRemove = -1;

    for (int i = 0; i < _ingredients.length; i++) {
      if (_ingredients[i]['name'] == name &&
          _ingredients[i]['amount'] == amount) {
        indexToRemove = i;
        break;
      }
    }

    if (indexToRemove >= 0) {
      setState(() {
        // Remove the ingredient
        _ingredients.removeAt(indexToRemove);
        _markAsUnsaved(); // Mark as having unsaved changes

        // Recalculate total nutrition values
        _calculateTotalNutrition();

        // Log the deletion for debugging
        print(
            'Deleted ingredient: $name ($amount) - $calories kcal, P:$protein, F:$fat, C:$carbs');
      });

      // Instead of saving immediately, just update the Nutrition display
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Only update the nutrition display without permanently saving
        _updateNutritionDisplay();
      });
    }
  }

  // Method to update health score
  void _updateHealthScore(double value) {
    setState(() {
      _healthScoreValue = value;
      _healthScore = '${(value * 10).round()}/10';
      _markAsUnsaved(); // Mark as having unsaved changes
    });
  }

  // Method to show health score popup when in edit mode
  void _showHealthScorePopup() {
    // Local state for the slider value to allow immediate updates
    double localHealthScoreValue = _healthScoreValue;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: TextSelectionThemeData(
                  selectionColor: Colors.grey.withOpacity(0.3),
                  cursorColor: Colors.black,
                ),
              ),
              child: Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
                backgroundColor: Colors.white,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 326,
                      padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Title
                          Text(
                            'Fix Health Score',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          SizedBox(height: 24),

                          // Heart icon (increased by 20%)
                          Image.asset(
                            'assets/images/heart.png',
                            width: 57.6, // Increased from 48 by 20%
                            height: 57.6, // Increased from 48 by 20%
                          ),
                          SizedBox(height: 24),

                          // Slider
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 8,
                              activeTrackColor: Colors.black,
                              inactiveTrackColor: Colors.grey[300],
                              thumbColor: Colors.white,
                              thumbShape: RoundSliderThumbShape(
                                enabledThumbRadius: 11,
                                elevation: 4,
                              ),
                              // Make highlight 50% more subtle (reduce opacity by 50%)
                              overlayColor: Colors.black.withOpacity(
                                  0.04), // Changed from 0.08 to 0.04
                              overlayShape:
                                  RoundSliderOverlayShape(overlayRadius: 18),
                              tickMarkShape: SliderTickMarkShape.noTickMark,
                              showValueIndicator: ShowValueIndicator.never,
                            ),
                            child: Slider(
                              value: localHealthScoreValue,
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              onChanged: (value) {
                                setDialogState(() {
                                  localHealthScoreValue = value;
                                });
                              },
                            ),
                          ),

                          // Score display
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              '${(localHealthScoreValue * 10).round()} / 10',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),
                          ),

                          // Update button
                          Container(
                            width: double.infinity,
                            height: 50,
                            margin: EdgeInsets.only(top: 16),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: TextButton(
                              onPressed: () {
                                // Update the health score
                                _updateHealthScore(localHealthScoreValue);
                                Navigator.of(context).pop();
                              },
                              style: ButtonStyle(
                                overlayColor: MaterialStateProperty.all(
                                    Colors.transparent),
                              ),
                              child: Text(
                                'Update',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Close button aligned with the title text vertically, moved up by 2px more
                    Positioned(
                      top: 32, // Move up by 2px more (from 34 to 32)
                      right: 20,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                        },
                        child: Image.asset(
                          'assets/images/closeicon.png',
                          width: 19,
                          height: 19,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHealthScore() {
    return GestureDetector(
      onTap: _isEditMode ? _showHealthScorePopup : null,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          // Add light gray border when in edit mode
          border: _isEditMode
              ? Border.all(color: Color(0xFFD3D3D3), width: 1.3)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: EdgeInsets.only(left: 60, right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Health Score',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: Colors.black,
                        ),
                      ),
                      Spacer(),
                      Text(
                        _healthScore,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Color(0xFFDADADA),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: double.infinity,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _healthScoreValue,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Color(0xFF75D377),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: -4,
              top: -5,
              bottom: -5,
              child: Image.asset(
                'assets/images/heartpink.png',
                width: 45,
                height: 45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // When a field is edited, mark it as having unsaved changes
  void _markAsUnsaved() {
    print('_markAsUnsaved called from: ${StackTrace.current}');
    setState(() {
      _hasUnsavedChanges = true;
      print('Changes marked as unsaved');
    });
  }

  // Method to show Fix with AI dialog
  void _showFixWithAIDialog() {
    // Create controller for text field
    TextEditingController descriptionController = TextEditingController();

    // Track input validation
    bool isFormValid = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Check form validity
            void updateFormValidity() {
              // Description must have at least one character
              bool descriptionValid =
                  descriptionController.text.trim().isNotEmpty;

              setDialogState(() {
                isFormValid = descriptionValid;
              });
            }

            // Function to handle form submission
            void handleSubmit() async {
              if (!isFormValid) return;

              // Get description from text field
              String description = descriptionController.text.trim();

              // Close the dialog first
              Navigator.pop(context);

              // Call the AI to fix the food with a callback to handle the response
              _fixFoodWithAI(description, (result) {
                // Check if there was an error
                if (result.containsKey('error') && result['error'] == true) {
                  // Show error dialog
                  _showStandardDialog(
                    title: "Error",
                    message: result['message'] ?? "An unknown error occurred",
                    positiveButtonText: "OK",
                  );
                  return;
                }

                // Process the AI's response to update the food
                // Debug print entire response
                print('AI RESPONSE DATA: ${result.toString()}');

                // Handle any potentially capitalized keys
                Map<String, dynamic> normalizedData = Map.from(result);

                // Check for capitalized field names and normalize them
                if (normalizedData.containsKey('Ingredients') &&
                    !normalizedData.containsKey('ingredients')) {
                  print(
                      'HANDLER: Found capitalized "Ingredients" key, normalizing');
                  normalizedData['ingredients'] =
                      normalizedData.remove('Ingredients');
                }

                if (normalizedData.containsKey('Name') &&
                    !normalizedData.containsKey('name')) {
                  normalizedData['name'] = normalizedData.remove('Name');
                }

                if (normalizedData.containsKey('Calories') &&
                    !normalizedData.containsKey('calories')) {
                  normalizedData['calories'] =
                      normalizedData.remove('Calories');
                }

                if (normalizedData.containsKey('Protein') &&
                    !normalizedData.containsKey('protein')) {
                  normalizedData['protein'] = normalizedData.remove('Protein');
                }

                if (normalizedData.containsKey('Fat') &&
                    !normalizedData.containsKey('fat')) {
                  normalizedData['fat'] = normalizedData.remove('Fat');
                }

                if (normalizedData.containsKey('Carbs') &&
                    !normalizedData.containsKey('carbs')) {
                  normalizedData['carbs'] = normalizedData.remove('Carbs');
                }

                // Update the state with the new values
                setState(() {
                  // NEVER update the food name regardless of what the API returns
                  // This preserves the original name when using Fix with AI

                  // Update total nutrition values if provided
                  if (normalizedData.containsKey('calories')) {
                    _calories = normalizedData['calories'].toString();
                    print('Updated calories to: $_calories');
                  }
                  if (normalizedData.containsKey('protein')) {
                    _protein = normalizedData['protein'].toString();
                    print('Updated protein to: $_protein');
                  }
                  if (normalizedData.containsKey('fat')) {
                    _fat = normalizedData['fat'].toString();
                    print('Updated fat to: $_fat');
                  }
                  if (normalizedData.containsKey('carbs')) {
                    _carbs = normalizedData['carbs'].toString();
                    print('Updated carbs to: $_carbs');
                  }

                  // Update ingredients if provided
                  List<String> removedIngredients = [];
                  List<String> addedIngredients = [];

                  if (normalizedData.containsKey('ingredients') &&
                      normalizedData['ingredients'] is List) {
                    // Check if the instruction involves removing ingredients
                    bool isRemovalInstruction = description
                            .toLowerCase()
                            .contains("didnt have") ||
                        description.toLowerCase().contains("did not have") ||
                        description.toLowerCase().contains("doesn't have") ||
                        description.toLowerCase().contains("does not have");

                    // For removal instructions, identify which ingredients are being removed
                    if (isRemovalInstruction) {
                      // Find which ingredients were removed by comparing with original list
                      List<String> originalIngredientNames = _ingredients
                          .map((ing) => ing['name'].toString().toLowerCase())
                          .toList();

                      List<String> newIngredientNames =
                          (normalizedData['ingredients'] as List)
                              .map(
                                  (ing) => ing['name'].toString().toLowerCase())
                              .toList();

                      // Create a list of removed ingredients for logging
                      for (String origName in originalIngredientNames) {
                        if (!newIngredientNames.contains(origName)) {
                          removedIngredients.add(origName);
                        }
                      }
                    }

                    // Update the ingredient list
                    List<Map<String, dynamic>> newIngredients = [];
                    for (var ingredient in normalizedData['ingredients']) {
                      String ingredientName = ingredient['name'] ?? '';

                      // Skip empty ingredients or those with zero calories
                      if (_isEmpty(ingredientName) ||
                          ((ingredient['calories'] ?? 0) == 0 &&
                              isRemovalInstruction)) {
                        print(
                            'SKIPPING INGREDIENT: $ingredientName - zero calories or empty name');
                        continue;
                      }

                      // Truncate ingredient name if longer than 16 characters
                      if (ingredientName.length > 16) {
                        ingredientName =
                            _truncateWithEllipsis(ingredientName, 16);
                      }

                      Map<String, dynamic> cleanedIngredient = {
                        'name': ingredientName,
                        'amount': ingredient['amount'] ?? '1 serving',
                        'calories': ingredient['calories'] ?? 0,
                        'protein': ingredient['protein'] ?? 0,
                        'fat': ingredient['fat'] ?? 0,
                        'carbs': ingredient['carbs'] ?? 0,
                      };

                      newIngredients.add(cleanedIngredient);
                    }

                    _ingredients = newIngredients;
                  }

                  // Calculate total nutrition from ingredients
                  _calculateTotalNutrition();
                  // Mark as having unsaved changes
                  _hasUnsavedChanges = true;

                  // Show success message with details on what was changed
                  String changes = "";
                  if (removedIngredients.isNotEmpty) {
                    changes = "Removed: ${removedIngredients.join(', ')}.";
                  } else if (addedIngredients.isNotEmpty) {
                    changes = "Added: ${addedIngredients.join(', ')}.";
                  }

                  print("Food successfully modified with AI: $_foodName");
                  print("Changes: $changes");
                });
              });
            }

            return Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: TextSelectionThemeData(
                  selectionColor: Colors.grey.withOpacity(0.3),
                  cursorColor: Colors.black,
                  selectionHandleColor: Colors.black,
                ),
              ),
              child: Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
                backgroundColor: Colors.white,
                insetPadding: EdgeInsets.symmetric(horizontal: 32),
                child: Container(
                  width: 326,
                  height: 350, // Adjusted height back to original value
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Title
                            SizedBox(height: 14),
                            Text(
                              "Fix with AI",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'SF Pro Display',
                              ),
                            ),

                            // Adjusted spacing for proper vertical centering
                            SizedBox(height: 30),

                            // Bulb icon with increased size to 50x50
                            Image.asset(
                              'assets/images/bulb.png',
                              width: 50.0,
                              height: 50.0,
                            ),

                            // Adjusted spacing for proper vertical centering
                            SizedBox(height: 30),

                            // Description field
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Describe what you'd like to improve",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                  SizedBox(height: 15),
                                  Container(
                                    width: 280,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(25),
                                      border:
                                          Border.all(color: Colors.grey[300]!),
                                    ),
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 15),
                                    child: TextField(
                                      controller: descriptionController,
                                      cursorColor: Colors.black,
                                      cursorWidth: 1.2,
                                      onChanged: (value) {
                                        updateFormValidity();
                                      },
                                      style: TextStyle(
                                        fontSize: 13.6,
                                        fontFamily: '.SF Pro Display',
                                        color: Colors.black,
                                      ),
                                      decoration: InputDecoration(
                                        hintText:
                                            "e.g. Remove sugar & reduce kcal",
                                        hintStyle: TextStyle(
                                          color: Colors.grey[600]!
                                              .withOpacity(0.7),
                                          fontSize: 13.6,
                                          fontFamily: '.SF Pro Display',
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding:
                                            EdgeInsets.symmetric(vertical: 15),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Fix Now button
                            SizedBox(height: 30), // Restore original spacing
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Container(
                                width: 280,
                                height: 48,
                                margin: EdgeInsets.only(bottom: 24),
                                decoration: BoxDecoration(
                                  color: isFormValid
                                      ? Colors.black
                                      : Colors.grey[400],
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: TextButton(
                                  onPressed: isFormValid ? handleSubmit : null,
                                  style: ButtonStyle(
                                    overlayColor: MaterialStateProperty.all(
                                        Colors.transparent),
                                  ),
                                  child: const Text(
                                    'Fix Now',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: '.SF Pro Display',
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Close button
                      Positioned(
                        top: 21, // Match the position in Add Ingredient popup
                        right: 21, // Match the position in Add Ingredient popup
                        child: GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: Image.asset(
                            'assets/images/closeicon.png',
                            width: 19,
                            height: 19,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Function to fix food with AI and recalculate nutrition
  Future<void> _fixFoodWithAI(
      String instructions, Function(Map<String, dynamic>) callback) async {
    // Store a local copy of the context to avoid BuildContext issues
    BuildContext? localContext = context;
    BuildContext? dialogContext;
    bool isDialogShowing = false;

    try {
      print('STARTING AI fix for: $_foodName with instructions: $instructions');

      // Preprocessing instruction string to remove typical patterns
      String preprocessedInstructions = instructions
          .replaceAll('could you', '')
          .replaceAll('could we', '')
          .replaceAll('can you', '')
          .replaceAll('can we', '')
          .replaceAll('please', '')
          .replaceAll('make it', '')
          .trim();

      // Detect operation type based on the instruction
      String operationType = 'GENERAL';

      if (instructions.toLowerCase().contains('less calorie') ||
          instructions.toLowerCase().contains('fewer calorie')) {
        operationType = 'REDUCE_CALORIES';
      } else if (instructions.toLowerCase().contains('more calorie') ||
          instructions.toLowerCase().contains('higher calorie')) {
        operationType = 'INCREASE_CALORIES';
      } else if (instructions.toLowerCase().contains('remove ') ||
          instructions.toLowerCase().contains('without ') ||
          instructions.toLowerCase().contains('did not have') ||
          instructions.toLowerCase().contains('no ')) {
        operationType = 'REMOVE_INGREDIENT';
      } else if (instructions.toLowerCase().contains('less ') ||
          instructions.toLowerCase().contains('fewer ') ||
          instructions.toLowerCase().contains('smaller amount')) {
        operationType = 'REDUCE_AMOUNT';
      } else if (instructions.toLowerCase().contains('more ') ||
          instructions.toLowerCase().contains('larger amount') ||
          instructions.toLowerCase().contains('bigger portion')) {
        operationType = 'INCREASE_AMOUNT';
      } else if (instructions.toLowerCase().contains('add ') ||
          instructions.toLowerCase().contains('with ') ||
          instructions.toLowerCase().contains('it had ') ||
          instructions.toLowerCase().contains('it has ')) {
        operationType = 'ADD_INGREDIENT';
      }

      print('Preprocessed instructions: $preprocessedInstructions');
      print('Detected operation type: $operationType');

      // Show loading dialog if context is still valid
      if (mounted && localContext != null) {
        isDialogShowing = true;
        try {
          // Show loading indicator as a simple dialog
          showDialog(
            context: localContext,
            barrierDismissible: false,
            builder: (BuildContext ctx) {
              dialogContext = ctx;
              return Dialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Container(
                  width: 110,
                  height: 110,
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 3,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        "Calculating...",
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        } catch (dialogError) {
          print('Error showing dialog: $dialogError');
          // Continue without dialog
          isDialogShowing = false;
          dialogContext = null;
        }
      }

      // Create a description of the current food with all ingredients
      String currentFoodDescription = "Food: $_foodName\n";
      currentFoodDescription += "Total calories: $_calories\n";
      currentFoodDescription += "Total protein: $_protein\n";
      currentFoodDescription += "Total fat: $_fat\n";
      currentFoodDescription += "Total carbs: $_carbs\n";
      currentFoodDescription += "Ingredients:\n";

      for (var ingredient in _ingredients) {
        currentFoodDescription +=
            "- ${ingredient['name']} (${ingredient['amount']}): ${ingredient['calories']} calories, ${ingredient['protein']}g protein, ${ingredient['fat']}g fat, ${ingredient['carbs']}g carbs\n";
      }

      // Add the specific instruction about what to fix
      currentFoodDescription +=
          "\nPlease analyze and update the food according to the following instruction: '$preprocessedInstructions' (Operation type: $operationType)";
      print("Full content for AI: $currentFoodDescription");

      // Print request data for debugging
      final requestData = {
        'food_name': _foodName,
        'current_data': {
          'calories': _calories,
          'protein': _protein,
          'fat': _fat,
          'carbs': _carbs,
          'ingredients': _ingredients
        },
        'instructions': preprocessedInstructions,
        'operation_type': operationType
      };
      print('FOOD FIXER: Request data: ${jsonEncode(requestData)}');

      try {
        // Attempt to call the Render.com DeepSeek service
        print(
            'FOOD FIXER: Creating request to Render.com DeepSeek service for fixing food');

        // Store a local copy of the context to avoid issues
        final BuildContext localContext = context;

        final response = await http
            .post(
          Uri.parse('https://deepseek-uhrc.onrender.com/api/nutrition'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode(requestData),
        )
            .timeout(const Duration(minutes: 1), onTimeout: () {
          print('FOOD FIXER: Request timed out');
          // Safely show error dialog on timeout without navigating away
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _safelyDismissDialog(dialogContext, isDialogShowing);
              showDialog(
                context: localContext,
                barrierDismissible: false,
                barrierColor: Colors.black.withOpacity(0.75),
                builder: (BuildContext context) {
                  return Dialog(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24.0),
                    ),
                    child: Container(
                      width: 311,
                      padding:
                          EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Service Unavailable',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'The food modification service is currently unavailable. Please try again later.',
                            style: TextStyle(
                              fontSize: 17,
                              fontFamily: 'SF Pro Display',
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 32),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              child: Text(
                                'OK',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.red.shade400,
                                  fontFamily: 'SF Pro Display',
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }
          });

          // Call the callback with the error
          callback({
            'error': true,
            'message':
                'The food modification service timed out. Please try again later.'
          });

          // Then throw an exception to prevent further execution - no return needed
          throw Exception('Request timed out');
        });

        // Check if the dialog is still showing and dismiss it
        _safelyDismissDialog(dialogContext, isDialogShowing);
        isDialogShowing = false;

        print(
            'FOOD FIXER: Received Render.com service response with status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final Map<String, dynamic> responseData = jsonDecode(response.body);

          // Check if responseData has a data field (our new API format)
          if (responseData.containsKey('data') &&
              responseData['success'] == true) {
            // New API format - use callback instead of return
            callback(responseData['data']);
          } else if (responseData.containsKey('success') &&
              responseData['success'] == true) {
            // Legacy format - use callback instead of return
            callback(responseData);
          } else {
            // Handle error in response
            print('FOOD FIXER: Received error in response: ${response.body}');

            // Safely show error dialog without navigating away
            if (mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showDialog(
                  context: localContext,
                  barrierDismissible: false,
                  barrierColor: Colors.black.withOpacity(0.75),
                  builder: (BuildContext context) {
                    return Dialog(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24.0),
                      ),
                      child: Container(
                        width: 311,
                        padding:
                            EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Service Unavailable',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'SF Pro Display',
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'The food modification service is currently unavailable. Please try again later.',
                              style: TextStyle(
                                fontSize: 17,
                                fontFamily: 'SF Pro Display',
                                color: Colors.black87,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 32),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                child: Text(
                                  'OK',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.red.shade400,
                                    fontFamily: 'SF Pro Display',
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              });
            }

            // Use callback instead of return
            callback({
              'error': true,
              'message':
                  'The food modification service returned an error. Please try again later.'
            });
          }
        } else {
          print(
              'FOOD FIXER: HTTP error: ${response.statusCode}, ${response.body}');

          // Safely show error dialog without navigating away
          if (mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showDialog(
                context: localContext,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Service Error'),
                    content: Text(
                        'HTTP error ${response.statusCode}. Please try again later.'),
                    actions: [
                      TextButton(
                        child: const Text('OK'),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  );
                },
              );
            });
          }

          // Use callback instead of return
          callback({
            'error': true,
            'message':
                'The food modification service returned an error. Please try again later.'
          });
        }
      } catch (networkError) {
        print('FOOD FIXER: Network error: $networkError');
        // Safely dismiss the loading dialog
        _safelyDismissDialog(dialogContext, isDialogShowing);

        // Check if we've already called the callback in the timeout handler
        if (!(networkError.toString().contains('timed out'))) {
          // Use callback instead of return
          callback({
            'error': true,
            'message':
                'The food modification service is currently unavailable. Please try again later.',
          });
        }
      }
    } catch (e) {
      print('FOOD FIXER error: $e');

      // Safely dismiss the loading dialog if it's showing
      _safelyDismissDialog(dialogContext, isDialogShowing);

      // Use callback instead of return
      callback({
        'error': true,
        'message': 'Failed to modify food with AI: $e',
      });
    }
  }

  // Calculate total nutrition from all ingredients
  void _recalculateNutrition() {
    if (_ingredients.isEmpty) return;

    double totalCalories = 0;
    double totalProtein = 0;
    double totalFat = 0;
    double totalCarbs = 0;

    for (var ingredient in _ingredients) {
      // Handle both int and double values safely
      totalCalories += _parseNutritionValue(ingredient['calories']);
      totalProtein += _parseNutritionValue(ingredient['protein']);
      totalFat += _parseNutritionValue(ingredient['fat']);
      totalCarbs += _parseNutritionValue(ingredient['carbs']);
    }

    // Update the nutrition values
    setState(() {
      _calories = totalCalories.round().toString();
      _protein = totalProtein.round().toString();
      _fat = totalFat.round().toString();
      _carbs = totalCarbs.round().toString();
    });

    // Log for debugging
    print(
        'NUTRITION TOTALS: Calories=$_calories, Protein=$_protein, Fat=$_fat, Carbs=$_carbs');
  }

  // Helper method to parse nutrition values which might be strings, ints, or doubles
  double _parseNutritionValue(dynamic value) {
    if (value == null) return 0;

    if (value is int) {
      return value.toDouble();
    } else if (value is double) {
      return value;
    } else if (value is String) {
      return double.tryParse(value) ?? 0;
    }

    return 0;
  }

  // Method to show a success dialog after food modification
  void _showSuccessDialog(String message, {String? details}) {
    _showStandardDialog(
      title: "Success",
      message: details != null ? "$message\n\n$details" : message,
      positiveButtonText: "OK",
      negativeButtonText: "OK",
      onNegativePressed: () => Navigator.of(context).pop(),
    );
  }

  // Delete the meal
  void _deleteMeal() {
    final prefs = SharedPreferences.getInstance();
    prefs.then((prefs) {
      final String foodId = _foodName.replaceAll(' ', '_').toLowerCase();

      // First: Delete all food-specific data
      prefs.remove('food_liked_$foodId');
      prefs.remove('food_bookmarked_$foodId');
      prefs.remove('food_counter_$foodId');
      prefs.remove('food_calories_$foodId');
      prefs.remove('food_protein_$foodId');
      prefs.remove('food_fat_$foodId');
      prefs.remove('food_carbs_$foodId');
      prefs.remove('food_health_score_$foodId');
      prefs.remove('food_image_$foodId');
      prefs.remove('food_ingredients_$foodId'); // Don't forget ingredients

      print('Deleted all data for food: $foodId');

      // Second: Remove this meal from the food_cards list in SharedPreferences
      final List<String>? storedCards = prefs.getStringList('food_cards');
      if (storedCards != null && storedCards.isNotEmpty) {
        List<String> updatedCardsList = [];

        for (String cardJson in storedCards) {
          try {
            Map<String, dynamic> cardData = jsonDecode(cardJson);
            String cardName = cardData['name'] ?? '';

            // Only keep cards with a different name
            if (cardName.toLowerCase() != _foodName.toLowerCase()) {
              updatedCardsList.add(cardJson);
            } else {
              print('Removing card: $cardName from food_cards list');
            }
          } catch (e) {
            print("Error parsing food card JSON: $e");
            // Keep cards that can't be parsed (just in case)
            updatedCardsList.add(cardJson);
          }
        }

        // Save the updated list back to SharedPreferences
        prefs.setStringList('food_cards', updatedCardsList);
        print('Updated food_cards list, removed deleted meal');
      }

      // Navigate to main CodiaPage (not Nutrition) with pushReplacement
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => CodiaPage()),
      );
    });
  }

  // Standardized error dialog that matches the Delete Meal confirmation style
  void _showStandardDialog({
    required String title,
    required String message,
    String? positiveButtonText,
    String? positiveButtonIcon,
    VoidCallback? onPositivePressed,
    String negativeButtonText = "Cancel",
    VoidCallback? onNegativePressed,
  }) {
    // Use the external helper to avoid syntax issues
    DialogHelper.showStandardDialog(
      context: context,
      title: title,
      message: message,
      positiveButtonText: positiveButtonText,
      positiveButtonIcon: positiveButtonIcon,
      onPositivePressed: onPositivePressed,
      negativeButtonText: negativeButtonText,
      onNegativePressed: onNegativePressed,
    );
  }

  // Method to check if a string is empty
  bool _isEmpty(String? str) {
    return str == null || str.trim().isEmpty;
  }

  // Method to check if an ingredient exists by name
  bool _hasIngredientWithName(String name) {
    if (_isEmpty(name)) return false;

    final normalizedName = name.trim().toLowerCase();
    for (var ingredient in _ingredients) {
      if (ingredient['name'].toString().toLowerCase() == normalizedName) {
        return true;
      }
    }
    return false;
  }

  // Method to truncate a string with ellipsis if it exceeds a certain length
  String _truncateWithEllipsis(String str, int maxLength) {
    if (str.length > maxLength) {
      return str.substring(0, maxLength) + "...";
    } else {
      return str;
    }
  }

  // Open the Nutrition screen to see updated nutrient values
  void _openNutritionScreen() async {
    // Create a map with basic nutrition data
    Map<String, dynamic> nutritionData = {
      'protein': _protein,
      'fat': _fat,
      'carbs': _carbs,
    };

    // Handle micronutrients based on ingredient count
    if (_ingredients.isEmpty) {
      // If all ingredients are deleted, don't show any micronutrients
      print("No ingredients left, clearing all micronutrient data");
    } else if (_ingredients.length == 1 &&
        widget.ingredients != null &&
        widget.ingredients!.length > 1 &&
        widget.additionalNutrients != null) {
      // Special case: If we had multiple ingredients before but now have only one,
      // the micronutrients should be adjusted to reflect that only one ingredient remains

      // Calculate the proportion of the remaining ingredient's calories to original total
      double originalTotalCalories = 0;
      for (var ingredient in widget.ingredients!) {
        var calories = ingredient['calories'];
        if (calories is String) {
          originalTotalCalories += double.tryParse(calories) ?? 0;
        } else if (calories is num) {
          originalTotalCalories += calories.toDouble();
        }
      }

      // Get current calories of the remaining ingredient
      double remainingCalories = 0;
      var calories = _ingredients[0]['calories'];
      if (calories is String) {
        remainingCalories = double.tryParse(calories) ?? 0;
      } else if (calories is num) {
        remainingCalories = calories.toDouble();
      }

      // Calculate ratio for scaling micronutrients
      double ratio = originalTotalCalories > 0
          ? remainingCalories / originalTotalCalories
          : 0.5;

      // Adjust micronutrients by ratio
      print(
          "Scaling micronutrients by ratio: $ratio (1 ingredient remaining out of ${widget.ingredients!.length})");

      if (widget.additionalNutrients != null &&
          widget.additionalNutrients!.isNotEmpty) {
        Map<String, dynamic> scaledNutrients = {};

        widget.additionalNutrients!.forEach((key, value) {
          if (value is num) {
            scaledNutrients[key] = (value * ratio).round();
          } else if (value is String) {
            double? numValue = double.tryParse(value);
            if (numValue != null) {
              scaledNutrients[key] = (numValue * ratio).round().toString();
            } else {
              scaledNutrients[key] = value; // Keep non-numeric values unchanged
            }
          } else {
            scaledNutrients[key] = value; // Keep other types unchanged
          }
        });

        print("Adding scaled micronutrients: $scaledNutrients");
        nutritionData.addAll(scaledNutrients);
      }
    } else if (widget.additionalNutrients != null &&
        widget.additionalNutrients!.isNotEmpty) {
      // Regular case: Add micronutrients directly from the widget parameter if available
      print(
          "Adding micronutrients from widget parameter: ${widget.additionalNutrients}");
      nutritionData.addAll(widget.additionalNutrients!);
    }

    // Extract and add additional nutrition data from ingredients if available
    if (_ingredients.isNotEmpty) {
      // Check if ingredients contain additional micronutrient information
      Map<String, dynamic> otherNutrients = _extractOtherNutrients();

      // Add any nutrients found in ingredients that weren't already added
      otherNutrients.forEach((key, value) {
        if (!nutritionData.containsKey(key)) {
          nutritionData[key] = value;
        }
      });
    }

    // Create a truly consistent ID for this specific food that will never change
    // This ensures we always update and display the same persisted data for this food
    String foodName = _foodName.toLowerCase().trim().replaceAll(' ', '_');
    String caloriesId = _calories.replaceAll('.', '_');
    // Construct a simple deterministic ID that will be the same every time for this food
    String foodSpecificScanId = "food_nutrition_${foodName}_${caloriesId}";

    print("Passing nutrition data to Nutrition.dart: $nutritionData");
    print("Using PERSISTENT food-specific scan ID: $foodSpecificScanId");

    // Pre-save the nutrition data with this ID to ensure it's never lost
    final prefs = await SharedPreferences.getInstance();

    // Save the nutrition data under multiple keys for redundancy
    try {
      // Create a data object with all nutrition details
      Map<String, dynamic> allData = {
        'scanId': foodSpecificScanId,
        'lastSaved': DateTime.now().millisecondsSinceEpoch,
        'nutritionData': nutritionData
      };

      // Convert to JSON and save in a single operation
      String dataJson = jsonEncode(allData);

      // Save under multiple keys for redundancy and different lookup patterns
      await prefs.setString('nutrition_data_$foodSpecificScanId', dataJson);
      await prefs.setString('food_nutrition_$foodName', dataJson);
      await prefs.setString('food_scanid_$foodName', foodSpecificScanId);

      print(
          'Pre-saved nutrition data for permanent storage with ID: $foodSpecificScanId');

      // Also save this ID in a master list of food scan IDs for discovery
      List<String> foodScanIds = prefs.getStringList('all_food_scan_ids') ?? [];
      if (!foodScanIds.contains(foodSpecificScanId)) {
        foodScanIds.add(foodSpecificScanId);
        await prefs.setStringList('all_food_scan_ids', foodScanIds);
      }
    } catch (e) {
      print('Error pre-saving nutrition data: $e');
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => nutrition_page.CodiaPage(
          nutritionData: nutritionData,
          scanId: foodSpecificScanId, // Pass the unique scan ID
        ),
      ),
    ).then((_) {
      print("Returned from Nutrition.dart");
    });
  }

  // Helper method to generate a scanId specific to this food
  String generateFoodSpecificScanId() {
    // Create a CONSISTENT ID based on this food's properties
    // Don't use a timestamp which changes each time and causes data loss
    String foodIdentifier = _foodName.replaceAll(' ', '_').toLowerCase();
    String calIdentifier = _calories.replaceAll('.', '_');

    // Create a stable ID that won't change between visits
    String scanId = 'food_nutrition_${foodIdentifier}_${calIdentifier}';
    print("Generated PERSISTENT food-specific scanId: $scanId");
    return scanId;
  }

  // Helper method to extract other nutrients from ingredients
  Map<String, dynamic> _extractOtherNutrients() {
    Map<String, dynamic> result = {};

    if (_ingredients.isEmpty) return result;

    // Common nutrient fields to extract from ingredients
    const List<String> commonNutrients = [
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
      'magnesium',
      'zinc',
      'selenium',
      'phosphorus',
      'copper',
      'manganese',
      'iodine',
      'chromium',
      'fluoride',
      'chloride',
      'molybdenum'
    ];

    // Pre-compute vitamin mappings
    const Map<String, String> vitaminMappings = {
      'vitamin_a': 'vitamin_a',
      'vitamin a': 'vitamin_a',
      'a': 'vitamin_a',
      'vitamin_c': 'vitamin_c',
      'vitamin c': 'vitamin_c',
      'c': 'vitamin_c',
      'vitamin_d': 'vitamin_d',
      'vitamin d': 'vitamin_d',
      'd': 'vitamin_d',
      'vitamin_e': 'vitamin_e',
      'vitamin e': 'vitamin_e',
      'e': 'vitamin_e',
      'vitamin_k': 'vitamin_k',
      'vitamin k': 'vitamin_k',
      'k': 'vitamin_k',
      'vitamin_b1': 'vitamin_b1',
      'vitamin b1': 'vitamin_b1',
      'b1': 'vitamin_b1',
      'thiamin': 'vitamin_b1',
      'thiamine': 'vitamin_b1',
      'vitamin_b2': 'vitamin_b2',
      'vitamin b2': 'vitamin_b2',
      'b2': 'vitamin_b2',
      'riboflavin': 'vitamin_b2',
      'vitamin_b3': 'vitamin_b3',
      'vitamin b3': 'vitamin_b3',
      'b3': 'vitamin_b3',
      'niacin': 'vitamin_b3',
      'vitamin_b5': 'vitamin_b5',
      'vitamin b5': 'vitamin_b5',
      'b5': 'vitamin_b5',
      'pantothenic_acid': 'vitamin_b5',
      'vitamin_b6': 'vitamin_b6',
      'vitamin b6': 'vitamin_b6',
      'b6': 'vitamin_b6',
      'pyridoxine': 'vitamin_b6',
      'vitamin_b7': 'vitamin_b7',
      'vitamin b7': 'vitamin_b7',
      'b7': 'vitamin_b7',
      'biotin': 'vitamin_b7',
      'vitamin_b9': 'vitamin_b9',
      'vitamin b9': 'vitamin_b9',
      'b9': 'vitamin_b9',
      'folate': 'vitamin_b9',
      'folic_acid': 'vitamin_b9',
      'vitamin_b12': 'vitamin_b12',
      'vitamin b12': 'vitamin_b12',
      'b12': 'vitamin_b12',
      'cobalamin': 'vitamin_b12'
    };

    // More efficient processing of ingredients - use indexing
    final int ingredientCount = _ingredients.length;
    for (int i = 0; i < ingredientCount; i++) {
      final ingredient = _ingredients[i];

      // First check for common nutrient fields - use direct indexing
      for (int j = 0; j < commonNutrients.length; j++) {
        final String field = commonNutrients[j];
        if (ingredient.containsKey(field) && ingredient[field] != null) {
          // If the field exists in the current result, add the values
          if (result.containsKey(field)) {
            // Parse both values and add them
            double existingValue = _parseNutritionValue(result[field]);
            double newValue = _parseNutritionValue(ingredient[field]);
            result[field] = (existingValue + newValue).toString();
          } else {
            // Just add the field directly
            result[field] = ingredient[field].toString();
          }
        }
      }

      // Check for vitamins with different naming formats - use direct map access
      ingredient.forEach((key, value) {
        if (value == null) return;

        String? targetKey = vitaminMappings[key.toLowerCase()];
        if (targetKey != null) {
          // If this vitamin exists in the result under the standardized key, add the values
          if (result.containsKey(targetKey)) {
            double existingValue = _parseNutritionValue(result[targetKey]);
            double newValue = _parseNutritionValue(value);
            result[targetKey] = (existingValue + newValue).toString();
          } else {
            // Add the vitamin with the standardized key
            result[targetKey] = value.toString();
          }
        }
        // Check for any keys that contain "vitamin" but aren't in our mapping
        else if (key.toLowerCase().contains('vitamin')) {
          // Standardize the key format: replace spaces with underscores
          String standardKey = key.toLowerCase().replaceAll(' ', '_');

          // If this vitamin exists in the result under the standardized key, add the values
          if (result.containsKey(standardKey)) {
            double existingValue = _parseNutritionValue(result[standardKey]);
            double newValue = _parseNutritionValue(value);
            result[standardKey] = (existingValue + newValue).toString();
          } else {
            // Add the vitamin with the standardized key
            result[standardKey] = value.toString();
          }
        }
      });
    }

    print("Extracted additional nutrients from ingredients: $result");
    return result;
  }

  // Method to update nutrition display without permanently saving data
  void _updateNutritionDisplay() {
    // Create a map with basic nutrition data
    Map<String, dynamic> nutritionData = {
      'protein': _protein,
      'fat': _fat,
      'carbs': _carbs,
    };

    // Handle micronutrients based on ingredient count
    if (_ingredients.isEmpty) {
      // If all ingredients are deleted, don't show any micronutrients
      print("No ingredients left, clearing all micronutrient data");
    } else if (_ingredients.length == 1 &&
        widget.ingredients != null &&
        widget.ingredients!.length > 1 &&
        widget.additionalNutrients != null) {
      // Special case: If we had multiple ingredients before but now have only one,
      // the micronutrients should be adjusted to reflect that only one ingredient remains

      // Calculate the proportion of the remaining ingredient's calories to original total
      double originalTotalCalories = 0;
      for (var ingredient in widget.ingredients!) {
        var calories = ingredient['calories'];
        if (calories is String) {
          originalTotalCalories += double.tryParse(calories) ?? 0;
        } else if (calories is num) {
          originalTotalCalories += calories.toDouble();
        }
      }

      // Get current calories of the remaining ingredient
      double remainingCalories = 0;
      var calories = _ingredients[0]['calories'];
      if (calories is String) {
        remainingCalories = double.tryParse(calories) ?? 0;
      } else if (calories is num) {
        remainingCalories = calories.toDouble();
      }

      // Calculate ratio for scaling micronutrients
      double ratio = originalTotalCalories > 0
          ? remainingCalories / originalTotalCalories
          : 0.5;

      // Adjust micronutrients by ratio
      print(
          "Scaling micronutrients by ratio: $ratio (1 ingredient remaining out of ${widget.ingredients!.length})");

      if (widget.additionalNutrients != null &&
          widget.additionalNutrients!.isNotEmpty) {
        Map<String, dynamic> scaledNutrients = {};

        widget.additionalNutrients!.forEach((key, value) {
          if (value is num) {
            scaledNutrients[key] = (value * ratio).round();
          } else if (value is String) {
            double? numValue = double.tryParse(value);
            if (numValue != null) {
              scaledNutrients[key] = (numValue * ratio).round().toString();
            } else {
              scaledNutrients[key] = value; // Keep non-numeric values unchanged
            }
          } else {
            scaledNutrients[key] = value; // Keep other types unchanged
          }
        });

        print("Adding scaled micronutrients: $scaledNutrients");
        nutritionData.addAll(scaledNutrients);
      }
    } else if (widget.additionalNutrients != null &&
        widget.additionalNutrients!.isNotEmpty) {
      // Regular case: Add micronutrients directly from the widget parameter if available
      print(
          "Adding micronutrients from widget parameter: ${widget.additionalNutrients}");
      nutritionData.addAll(widget.additionalNutrients!);
    }

    // Extract and add additional nutrition data from ingredients if available
    if (_ingredients.isNotEmpty) {
      // Check if ingredients contain additional micronutrient information
      Map<String, dynamic> otherNutrients = _extractOtherNutrients();

      // Add any nutrients found in ingredients that weren't already added
      otherNutrients.forEach((key, value) {
        if (!nutritionData.containsKey(key)) {
          nutritionData[key] = value;
        }
      });
    }

    // Create a truly consistent ID for this specific food that will never change
    String foodName = _foodName.toLowerCase().trim().replaceAll(' ', '_');
    String caloriesId = _calories.replaceAll('.', '_');
    String foodSpecificScanId = "food_nutrition_${foodName}_${caloriesId}";

    print("Updating local nutrition data without navigation: $nutritionData");

    // Just update the widget's additionalNutrients value without navigating
    if (mounted) {
      setState(() {
        widget.additionalNutrients?.clear();
        widget.additionalNutrients?.addAll(nutritionData);
      });
    }

    // Pre-save nutrition data for when user actually opens the Nutrition screen
    SharedPreferences.getInstance().then((prefs) {
      try {
        Map<String, dynamic> allData = {
          'scanId': foodSpecificScanId,
          'lastSaved': DateTime.now().millisecondsSinceEpoch,
          'nutritionData': nutritionData
        };

        String dataJson = jsonEncode(allData);
        prefs.setString('nutrition_data_$foodSpecificScanId', dataJson);
        print('Updated temporary nutrition data for ID: $foodSpecificScanId');
      } catch (e) {
        print('Error updating temporary nutrition data: $e');
      }
    });
  }
}
