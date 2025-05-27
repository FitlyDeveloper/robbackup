import 'package:flutter/material.dart';
import '../codia/codia_page.dart' as main_codia;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

// Create a global RouteObserver that will be used by the app
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class CodiaPage extends StatefulWidget {
  // Add parameters to receive nutrition data
  final Map<String, dynamic>? nutritionData;
  // Always accept a scan ID parameter, defaulting to a generated value if none provided
  final String scanId;

  const CodiaPage(
      {super.key, this.nutritionData, this.scanId = 'default_nutrition_id'});

  @override
  State<StatefulWidget> createState() => _CodiaPage();
}

class _CodiaPage extends State<CodiaPage>
    with WidgetsBindingObserver, RouteAware {
  // Define color constants with the specified hex codes
  final Color yellowColor = const Color(0xFFF3D960);
  final Color redColor = const Color(0xFFDA7C7C);
  final Color greenColor = const Color(0xFF78C67A);

  // Maps for nutrition values storage
  late Map<String, NutrientInfo> vitamins = {};
  late Map<String, NutrientInfo> minerals = {};
  late Map<String, NutrientInfo> other = {};

  // The unique ID for this scan, used in SharedPreferences keys
  late String _scanId;

  // Track whether data was loaded successfully
  bool _dataLoaded = false;

  // Flag to track if there are unsaved changes
  bool _hasUnsavedChanges = false;

  // Track nutrient counts
  int vitaminCount = 0;
  int mineralCount = 0;
  int otherCount = 0;

  // Timer to periodically save data while screen is visible
  Timer? _autoSaveTimer;

  @override
  void initState() {
    super.initState();

    // Register as a lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize scan ID - this is critical for data persistence
    // Always use the widget's scanId directly - it's now non-nullable with a default
    _scanId = widget.scanId;

    print('Nutrition screen initialized with scan ID: $_scanId');

    // Initialize default nutrient values
    _initializeDefaultValues();

    // Immediately try to load data from the global key first
    _tryLoadFromGlobalKey().then((success) {
      if (!success) {
        // If global key fails, start regular data loading process
        _loadData();
      }

      // Load personalized targets for all nutrients after data is loaded
      _loadNutrientTargets();
    });

    // Set up periodic auto-save
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_hasUnsavedChanges) {
        _saveNutritionData();
        _hasUnsavedChanges = false;
      }
    });

    // Pre-save any data that came from widget.nutritionData to ensure it's not lost
    if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _saveToFoodCardStorage(widget.nutritionData!);
      });
    }
  }

  // Helper method to immediately try loading from the global permanent key
  Future<bool> _tryLoadFromGlobalKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // First, try to load data specific to this food scan ID (highest priority)
      if (_scanId.startsWith('food_nutrition_')) {
        // Try food-specific storage paths
        String? foodSpecificData =
            prefs.getString('food_nutrition_data_$_scanId') ??
                prefs.getString('nutrition_data_$_scanId');

        if (foodSpecificData != null && foodSpecificData.isNotEmpty) {
          try {
            Map<String, dynamic> loadedData = jsonDecode(foodSpecificData);
            print('Successfully loaded food-specific data for $_scanId');

            // Process the data
            if (_processLoadedNutritionData(loadedData)) {
              // Update UI if data was loaded successfully
              if (mounted) {
                setState(() {
                  _dataLoaded = true;
                });
              }

              // Immediately save to ensure consistent formats but preserve the specific scan ID
              await _saveNutritionData(useGlobalKey: false);

              return true;
            }
          } catch (e) {
            print('Error processing food-specific nutrition data: $e');
          }
        }
      }

      // Only use the global key if we're not dealing with a food-specific scan
      if (!_scanId.startsWith('food_nutrition_')) {
        // Try to load from the global permanent key
        String? globalData = prefs.getString('PERMANENT_GLOBAL_NUTRITION_DATA');

        if (globalData != null && globalData.isNotEmpty) {
          try {
            Map<String, dynamic> loadedData = jsonDecode(globalData);
            print(
                'Successfully loaded data from PERMANENT_GLOBAL_NUTRITION_DATA');

            // If this global data has a scanId, update our scanId to match
            if (loadedData.containsKey('scanId')) {
              _scanId = loadedData['scanId'];
              print('Updated scan ID from global data: $_scanId');
            }

            // Process the data
            if (_processLoadedNutritionData(loadedData)) {
              // Update UI if data was loaded successfully
              if (mounted) {
                setState(() {
                  _dataLoaded = true;
                });
              }

              // Immediately save to ensure consistent formats and redundant storage
              await _saveNutritionData();

              return true;
            }
          } catch (e) {
            print('Error processing global nutrition data: $e');
          }
        }
      }

      return false;
    } catch (e) {
      print('Error loading from global key: $e');
      return false;
    }
  }

  // Helper method to save nutrition data to FoodCardOpen format
  Future<void> _saveToFoodCardStorage(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Create a container object with the scan ID and data
      Map<String, dynamic> storageData = {
        'scanId': _scanId,
        'lastSaved': DateTime.now().millisecondsSinceEpoch,
        'nutritionData': data
      };

      // Save the data to multiple keys for redundancy
      String json = jsonEncode(storageData);

      // Save to food-specific keys (not global)
      if (_scanId.startsWith('food_nutrition_')) {
        // For food-specific scan IDs, avoid using the global key
        await prefs.setString('nutrition_data_$_scanId', json);
        await prefs.setString('food_nutrition_data_$_scanId', json);

        // Extract food name to save with alternative key
        try {
          List<String> parts = _scanId.split('_');
          if (parts.length >= 3) {
            String foodName = parts.sublist(2, parts.length - 1).join('_');
            await prefs.setString('food_nutrition_$foodName', json);
          }
        } catch (e) {
          print('Error extracting food name from scan ID: $e');
        }
      } else {
        // Only use the global key for non-food specific scan IDs
        await prefs.setString('PERMANENT_GLOBAL_NUTRITION_DATA', json);
        await prefs.setString('nutrition_data_$_scanId', json);
      }

      // Also update the master scan ID
      await prefs.setString('current_nutrition_scan_id', _scanId);

      // Process data into our format
      _updateNutrientValuesFromData(data);

      print(
          'Saved nutrition data from widget to food card storage with ID: $_scanId');
    } catch (e) {
      print('Error saving to food card storage: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route changes
    routeObserver.subscribe(this, ModalRoute.of(context) as PageRoute);
  }

  @override
  void dispose() {
    // Cancel auto-save timer
    _autoSaveTimer?.cancel();

    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Unsubscribe from route observer
    routeObserver.unsubscribe(this);

    // Save current data state to ensure no data is lost
    if (_dataLoaded) {
      _saveNutritionData();
    }

    super.dispose();
  }

  // Called when this route is pushed on top of another route
  @override
  void didPush() {
    // This route is now the top-most route on navigator
  }

  // Called when another route is pushed on top of this route
  @override
  void didPushNext() {
    // User is navigating away from this screen to another screen
    if (_dataLoaded) {
      _saveNutritionData();
    }
  }

  // Called when this route is popped off the navigator
  @override
  void didPop() {
    // This route is being popped off the navigator
    if (_dataLoaded) {
      _saveNutritionData();
    }
  }

  // Called when another route is popped and this route shows up
  @override
  void didPopNext() {
    // User returned to this screen from another screen
    _reloadSavedData();
  }

  // Handle app lifecycle changes to ensure data isn't lost
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App is going to background or inactive, save current data
      if (_dataLoaded) {
        _saveNutritionData();
      }
    } else if (state == AppLifecycleState.resumed) {
      // App came back to foreground, reload data to ensure consistency
      _reloadSavedData();
    } else if (state == AppLifecycleState.detached) {
      // App is being terminated, save data urgently
      if (_dataLoaded) {
        _saveNutritionData();
      }
    }
  }

  // Separate method to handle all async loading
  Future<void> _loadData() async {
    try {
      await _initializeNutrientData();
      if (mounted) {
        setState(() {
          print("Refreshing UI after data initialized");
          _dataLoaded = true;
        });
      }

      // Force an immediate save after loading to ensure data is immediately persisted
      if (_dataLoaded) {
        await _saveNutritionData();
        print("Initial data save completed after loading");
      }
    } catch (e) {
      print("Error loading nutrition data: $e");

      // Attempt recovery by using the global nutrition data
      try {
        final prefs = await SharedPreferences.getInstance();
        String? globalData = prefs.getString('global_nutrition_data');

        if (globalData != null && globalData.isNotEmpty) {
          print("Attempting recovery using global nutrition data");
          Map<String, dynamic> loadedData = jsonDecode(globalData);

          // Update scan ID to match the loaded data to maintain consistency
          if (loadedData.containsKey('scanId')) {
            _scanId = loadedData['scanId'];
            print("Updated scan ID to match recovered data: $_scanId");
          }

          _processLoadedNutritionData(loadedData);

          if (mounted) {
            setState(() {
              _dataLoaded = true;
              print("Recovery successful - UI refreshed with global data");
            });
          }

          // Save the recovered data to ensure it's properly stored
          await _saveNutritionData();
        }
      } catch (recoveryError) {
        print("Error during recovery attempt: $recoveryError");
      }
    }
  }

  // Method to reload saved data - ULTRA RELIABLE
  Future<void> _reloadSavedData() async {
    try {
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();

      // ALWAYS try the global permanent key first
      String? savedData = prefs.getString('PERMANENT_GLOBAL_NUTRITION_DATA');

      // If not found by global key, try scan-specific key
      if (savedData == null || savedData.isEmpty) {
        savedData = prefs.getString('food_nutrition_data_$_scanId');
      }

      // Process the data if found
      if (savedData != null && savedData.isNotEmpty) {
        try {
          Map<String, dynamic> loadedData = jsonDecode(savedData);

          // Reset data structures to avoid stale data
          _initializeDefaultValues();

          // Process the loaded data
          _processLoadedNutritionData(loadedData);

          if (mounted) {
            setState(() {
              _dataLoaded = true;
            });

            // Re-save to ensure consistent storage format
            await _saveNutritionData();
          }
        } catch (e) {
          print('Error processing loaded nutrition data: $e');
        }
      } else if (widget.nutritionData != null &&
          widget.nutritionData!.isNotEmpty) {
        // If we have widget data, use it as a fallback
        _updateNutrientValuesFromData(widget.nutritionData!);

        if (mounted) {
          setState(() {
            _dataLoaded = true;
          });
        }

        // Save this data
        await _saveNutritionData();
      }
    } catch (e) {
      print('Error during data reload: $e');
    }
  }

  // Helper method to process loaded nutrition data
  bool _processLoadedNutritionData(Map<String, dynamic> loadedData) {
    try {
      // Process data in direct vitamins/minerals/other format
      if (loadedData.containsKey('vitamins')) {
        Map<String, dynamic> vitaminData = loadedData['vitamins'];
        vitaminData.forEach((key, value) {
          if (vitamins.containsKey(key) && value is Map) {
            double progress = 0.0;
            if (value.containsKey('progress')) {
              progress = value['progress'] is double
                  ? value['progress']
                  : double.tryParse(value['progress'].toString()) ?? 0.0;
            }

            Color progressColor = _getColorBasedOnProgress(progress);
            vitamins[key] = NutrientInfo(
              name: value['name'] ?? key,
              value: value['value'] ?? '0/0 g',
              percent: value['percent'] ?? '0%',
              progress: progress,
              progressColor: progressColor,
              hasInfo: value['hasInfo'] ?? false,
            );
          }
        });
      }

      // Process minerals
      if (loadedData.containsKey('minerals')) {
        Map<String, dynamic> mineralData = loadedData['minerals'];
        mineralData.forEach((key, value) {
          if (minerals.containsKey(key) && value is Map) {
            double progress = 0.0;
            if (value.containsKey('progress')) {
              progress = value['progress'] is double
                  ? value['progress']
                  : double.tryParse(value['progress'].toString()) ?? 0.0;
            }

            Color progressColor = _getColorBasedOnProgress(progress);
            minerals[key] = NutrientInfo(
              name: value['name'] ?? key,
              value: value['value'] ?? '0/0 g',
              percent: value['percent'] ?? '0%',
              progress: progress,
              progressColor: progressColor,
              hasInfo: value['hasInfo'] ?? false,
            );
          }
        });
      }

      // Process other nutrients
      if (loadedData.containsKey('other')) {
        Map<String, dynamic> otherData = loadedData['other'];
        otherData.forEach((key, value) {
          if (other.containsKey(key) && value is Map) {
            double progress = 0.0;
            if (value.containsKey('progress')) {
              progress = value['progress'] is double
                  ? value['progress']
                  : double.tryParse(value['progress'].toString()) ?? 0.0;
            }

            Color progressColor = _getColorBasedOnProgress(progress);
            other[key] = NutrientInfo(
              name: value['name'] ?? key,
              value: value['value'] ?? '0/0 g',
              percent: value['percent'] ?? '0%',
              progress: progress,
              progressColor: progressColor,
              hasInfo: value['hasInfo'] ?? false,
            );
          }
        });
      }

      return true;
    } catch (e) {
      print('Error in _processLoadedNutritionData: $e');
      return false;
    }
  }

  // Helper method to process a nutrient category (vitamins, minerals, other)
  void _processNutrientCategory(
      dynamic categoryData, Map<String, NutrientInfo> targetMap) {
    if (categoryData is! Map) return;

    Map<String, dynamic> data = categoryData as Map<String, dynamic>;
    data.forEach((key, value) {
      if (targetMap.containsKey(key) && value is Map) {
        double progress = 0.0;
        if (value.containsKey('progress')) {
          progress = value['progress'] is double
              ? value['progress']
              : double.tryParse(value['progress'].toString()) ?? 0.0;
        }

        Color progressColor = _getColorBasedOnProgress(progress);
        targetMap[key] = NutrientInfo(
          name: value['name'] ?? key,
          value: value['value'] ?? '0/0 g',
          percent: value['percent'] ?? '0%',
          progress: progress,
          progressColor: progressColor,
          hasInfo: value['hasInfo'] ?? false,
        );
      }
    });
  }

  // Initialize nutrient data for all categories (vitamins, minerals, other)
  Future<void> _initializeNutrientData() async {
    // First initialize all nutrients with default values
    _initializeDefaultValues();

    // Also load any saved data from past runs
    final prefs = await SharedPreferences.getInstance();
    String? savedData;

    // DIAGNOSTIC: Print the scan ID being used to load data
    print('\n====== LOADING NUTRIENT DATA ======');
    print('Current scan ID: $_scanId');

    // For food-specific scan IDs, prioritize food-specific data
    if (_scanId.startsWith('food_nutrition_')) {
      // Try food-specific keys first
      savedData = prefs.getString('food_nutrition_data_$_scanId') ??
          prefs.getString('nutrition_data_$_scanId');

      if (savedData != null && savedData.isNotEmpty) {
        print(
            '✓ FOUND FOOD-SPECIFIC DATA using ID: $_scanId (${savedData.length} bytes)');
      } else {
        // Extract food name as fallback
        try {
          List<String> parts = _scanId.split('_');
          if (parts.length >= 3) {
            String foodName = parts.sublist(2, parts.length - 1).join('_');
            savedData = prefs.getString('food_nutrition_$foodName');

            if (savedData != null && savedData.isNotEmpty) {
              print(
                  '✓ FOUND FOOD-SPECIFIC DATA using food name: $foodName (${savedData.length} bytes)');
            }
          }
        } catch (e) {
          print('Error extracting food name from scan ID: $e');
        }
      }
    } else {
      // Try multiple key formats to find saved data with highest priority first
      List<String> possibleDataKeys = [
        // Direct food scan ID format
        'nutrition_data_$_scanId', // Primary storage key
        'backup_nutrition_$_scanId', // Backup for redundancy
        'nutrition_${_scanId}_final', // Final backup storage
        'simple_nutrition_$_scanId', // Simplified emergency format

        // Extract food name from scan ID for alternative lookup
        'food_nutrition_${_scanId.replaceFirst('food_nutrition_', '')}', // By food name
      ];

      print('CHECKING for data using keys:');
      for (String key in possibleDataKeys) {
        print('- $key');
      }

      // Try each possible key to find saved data
      for (String key in possibleDataKeys) {
        savedData = prefs.getString(key);
        if (savedData != null && savedData.isNotEmpty) {
          print('✓ FOUND DATA using key: $key (${savedData.length} bytes)');
          break;
        }
      }

      // Fallback to global storage if no specific data found
      if (savedData == null || savedData.isEmpty) {
        savedData = prefs.getString('PERMANENT_GLOBAL_NUTRITION_DATA');
        if (savedData != null && savedData.isNotEmpty) {
          print('✓ FOUND DATA in global storage (${savedData.length} bytes)');
        }
      }
    }

    bool loadedExistingData = false;

    // If we found saved data, use it
    if (savedData != null && savedData.isNotEmpty) {
      try {
        Map<String, dynamic> data = jsonDecode(savedData);

        // Check if this is the new format with nutritionData field
        if (data.containsKey('nutritionData') &&
            data['nutritionData'] is Map<String, dynamic>) {
          print('Loading newer data format with nutritionData field');
          _updateNutrientValuesFromData(data['nutritionData']);
          loadedExistingData = true;
        }
        // Otherwise check for vitamins/minerals direct format
        else if (data.containsKey('vitamins') ||
            data.containsKey('minerals') ||
            data.containsKey('other')) {
          // Process vitamins
          if (data.containsKey('vitamins')) {
            Map<String, dynamic> vitaminData = data['vitamins'];
            vitaminData.forEach((key, value) {
              if (vitamins.containsKey(key) && value is Map) {
                vitamins[key] = NutrientInfo(
                  name: value['name'] ?? key,
                  value: value['value'] ?? '0/0 g',
                  percent: value['percent'] ?? '0%',
                  progress: value['progress'] is double
                      ? value['progress']
                      : double.tryParse(value['progress'].toString()) ?? 0.0,
                  progressColor: _getColorBasedOnProgress(value['progress']
                          is double
                      ? value['progress']
                      : double.tryParse(value['progress'].toString()) ?? 0.0),
                );
              }
            });
          }

          // Process minerals
          if (data.containsKey('minerals')) {
            Map<String, dynamic> mineralData = data['minerals'];
            mineralData.forEach((key, value) {
              if (minerals.containsKey(key) && value is Map) {
                minerals[key] = NutrientInfo(
                  name: value['name'] ?? key,
                  value: value['value'] ?? '0/0 g',
                  percent: value['percent'] ?? '0%',
                  progress: value['progress'] is double
                      ? value['progress']
                      : double.tryParse(value['progress'].toString()) ?? 0.0,
                  progressColor: _getColorBasedOnProgress(value['progress']
                          is double
                      ? value['progress']
                      : double.tryParse(value['progress'].toString()) ?? 0.0),
                );
              }
            });
          }

          // Process other nutrients
          if (data.containsKey('other')) {
            Map<String, dynamic> otherData = data['other'];
            otherData.forEach((key, value) {
              if (other.containsKey(key) && value is Map) {
                other[key] = NutrientInfo(
                  name: value['name'] ?? key,
                  value: value['value'] ?? '0/0 g',
                  percent: value['percent'] ?? '0%',
                  progress: value['progress'] is double
                      ? value['progress']
                      : double.tryParse(value['progress'].toString()) ?? 0.0,
                  progressColor: _getColorBasedOnProgress(value['progress']
                          is double
                      ? value['progress']
                      : double.tryParse(value['progress'].toString()) ?? 0.0),
                );
              }
            });
          }

          loadedExistingData = true;
          print('SUCCESSFULLY LOADED saved nutrition data');
        }
      } catch (e) {
        print('Error loading saved nutrition data: $e');
      }
    }

    // If no saved data OR we have widget data, use that (prioritize new data)
    if (!loadedExistingData ||
        (widget.nutritionData != null && widget.nutritionData!.isNotEmpty)) {
      if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
        print('Using nutrition data from widget parameter');
        _updateNutrientValuesFromData(widget.nutritionData!);

        // Also SAVE this data immediately to ensure it's not lost
        // For food-specific IDs, don't save to global key to avoid overwriting other foods' data
        await _saveNutritionData(
            useGlobalKey: !_scanId.startsWith('food_nutrition_'));
      } else if (!loadedExistingData) {
        // Last resort, try to get data from NutritionTracker
        print('No saved data or widget data, trying NutritionTracker');
        await _loadDataFromNutritionTracker();
      }
    }

    // Load nutrient targets from SharedPreferences
    await _loadNutrientTargets();

    // Save after loading and refreshing targets - preserve food-specific data
    await _saveNutritionData(
        useGlobalKey: !_scanId.startsWith('food_nutrition_'));
  }

  Future<void> _loadDataFromNutritionTracker() async {
    try {
      // Access the NutritionTracker singleton through the main_codia module
      final nutritionTracker = main_codia.NutritionTracker();

      print("Loading nutrition data from tracker:");
      print("- Protein: ${nutritionTracker.currentProtein}g");
      print("- Fat: ${nutritionTracker.currentFat}g");
      print("- Carbs: ${nutritionTracker.currentCarb}g");
      print("- Calories: ${nutritionTracker.consumedCalories}kcal");

      // We're not including protein, fat, or carbs in the detailed nutrition screen anymore
      // Save the updated data
      await _saveNutritionData();
    } catch (e) {
      print("Error loading data from NutritionTracker: $e");
    }
  }

  // Initialize default values for vitamins, minerals, and other nutrients
  void _initializeDefaultValues() {
    print("Initializing default nutrient values...");

    // VITAMINS
    vitamins = {
      'Vitamin A': NutrientInfo(
          name: 'Vitamin A',
          value: '0/700 mcg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin C': NutrientInfo(
          name: 'Vitamin C',
          value: '0/75 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin D': NutrientInfo(
          name: 'Vitamin D',
          value: '0/15 mcg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin E': NutrientInfo(
          name: 'Vitamin E',
          value: '0/15 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin K': NutrientInfo(
          name: 'Vitamin K',
          value: '0/90 mcg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin B1': NutrientInfo(
          name: 'Vitamin B1',
          value: '0/1.1 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin B2': NutrientInfo(
          name: 'Vitamin B2',
          value: '0/1.1 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin B3': NutrientInfo(
          name: 'Vitamin B3',
          value: '0/14 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin B5': NutrientInfo(
          name: 'Vitamin B5',
          value: '0/5 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin B6': NutrientInfo(
          name: 'Vitamin B6',
          value: '0/1.3 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin B7': NutrientInfo(
          name: 'Vitamin B7',
          value: '0/30 mcg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin B9': NutrientInfo(
          name: 'Vitamin B9',
          value: '0/400 mcg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Vitamin B12': NutrientInfo(
          name: 'Vitamin B12',
          value: '0/2.4 mcg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
    };

    // MINERALS
    minerals = {
      'Calcium': NutrientInfo(
          name: 'Calcium',
          value: '0/1000 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Chloride': NutrientInfo(
          name: 'Chloride',
          value: '0/2300 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Chromium': NutrientInfo(
          name: 'Chromium',
          value: '0/35 mcg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Copper': NutrientInfo(
          name: 'Copper',
          value: '0/900 mcg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Fluoride': NutrientInfo(
          name: 'Fluoride',
          value: '0/4 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Iodine': NutrientInfo(
          name: 'Iodine',
          value: '0/150 mcg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Iron': NutrientInfo(
          name: 'Iron',
          value: '0/18 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Magnesium': NutrientInfo(
          name: 'Magnesium',
          value: '0/400 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Manganese': NutrientInfo(
          name: 'Manganese',
          value: '0/2.3 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Molybdenum': NutrientInfo(
          name: 'Molybdenum',
          value: '0/45 mcg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Phosphorus': NutrientInfo(
          name: 'Phosphorus',
          value: '0/700 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Potassium': NutrientInfo(
          name: 'Potassium',
          value: '0/3500 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Selenium': NutrientInfo(
          name: 'Selenium',
          value: '0/55 mcg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Sodium': NutrientInfo(
          name: 'Sodium',
          value: '0/2300 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Zinc': NutrientInfo(
          name: 'Zinc',
          value: '0/11 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
    };

    // OTHER NUTRIENTS
    other = {
      'Fiber': NutrientInfo(
          name: 'Fiber',
          value: '0/30 g',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Cholesterol': NutrientInfo(
          name: 'Cholesterol',
          value: '0/300 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Sugar': NutrientInfo(
          name: 'Sugar',
          value: '0/50 g',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Saturated Fats': NutrientInfo(
          name: 'Saturated Fats',
          value: '0/22 g',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Omega-3': NutrientInfo(
          name: 'Omega-3',
          value: '0/1500 mg',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
      'Omega-6': NutrientInfo(
          name: 'Omega-6',
          value: '0/14 g',
          percent: '0%',
          progress: 0.0,
          progressColor: Colors.red),
    };

    // Set the counters for each category
    vitaminCount = vitamins.length;
    mineralCount = minerals.length;
    otherCount = other.length;
  }

  // Diagnostic function to print all available nutrient target keys
  Future<void> _printAvailableNutrientTargetKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      print('\n========== AVAILABLE NUTRIENT TARGET KEYS ==========');

      // Get all keys
      Set<String> allKeys = prefs.getKeys();

      // Filter keys related to nutrient targets
      List<String> targetKeys = allKeys
          .where((key) =>
              key.contains('target_') ||
              key.contains('vitamin_') ||
              key.contains('mineral_'))
          .toList();

      // Sort the keys for easier reading
      targetKeys.sort();

      // Print all target keys and their values
      for (String key in targetKeys) {
        var value = prefs.get(key);
        print('$key = $value');
      }

      print('=================================================\n');
    } catch (e) {
      print('Error printing nutrient target keys: $e');
    }
  }

  // Update nutrient values from data provided by SnapFood or other sources
  void _updateNutrientValuesFromData(Map<String, dynamic> data) {
    print('Updating nutrient values from data, keys: ${data.keys.toList()}');

    // FIRST - Process nested structure from comprehensive API response
    // Check for vitamins object
    if (data.containsKey('vitamins') && data['vitamins'] is Map) {
      Map<String, dynamic> vitaminsData =
          Map<String, dynamic>.from(data['vitamins']);
      print('Found vitamins object with keys: ${vitaminsData.keys.toList()}');

      vitaminsData.forEach((apiKey, value) {
        String vitaminKey = _mapVitaminKey(apiKey);
        if (vitamins.containsKey(vitaminKey)) {
          double amount = _extractNumericValue(value.toString());
          if (amount >= 0) {
            // Include 0 values
            _updateVitaminWithValue(vitaminKey, amount);
            print('Updated $vitaminKey: $amount from vitamins object');
          }
        }
      });
    }

    // Check for minerals object
    if (data.containsKey('minerals') && data['minerals'] is Map) {
      Map<String, dynamic> mineralsData =
          Map<String, dynamic>.from(data['minerals']);
      print('Found minerals object with keys: ${mineralsData.keys.toList()}');

      mineralsData.forEach((apiKey, value) {
        String mineralKey = _mapMineralKey(apiKey);
        if (minerals.containsKey(mineralKey)) {
          double amount = _extractNumericValue(value.toString());
          if (amount >= 0) {
            // Include 0 values
            _updateMineralWithValue(mineralKey, amount);
            print('Updated $mineralKey: $amount from minerals object');
          }
        }
      });
    }

    // Check for other nutrients object
    if (data.containsKey('other') && data['other'] is Map) {
      Map<String, dynamic> otherData = Map<String, dynamic>.from(data['other']);
      print(
          'Found other nutrients object with keys: ${otherData.keys.toList()}');

      otherData.forEach((apiKey, value) {
        String nutrientKey = _mapOtherNutrientKey(apiKey);
        if (other.containsKey(nutrientKey)) {
          double amount = _extractNumericValue(value.toString());
          if (amount >= 0) {
            // Include 0 values
            _updateOtherNutrientWithValue(nutrientKey, amount);
            print('Updated $nutrientKey: $amount from other nutrients object');
          }
        }
      });
    }

    // SECOND - let's check for values directly in the root object (legacy support)
    // This is how SnapFood.dart is sending the flattened data
    Map<String, String> rootKeyToVitaminMap = {
      // Direct vitamin mapping from SnapFood API response
      'vitamin_a': 'Vitamin A',
      'vitamin_c': 'Vitamin C',
      'vitamin_d': 'Vitamin D',
      'vitamin_e': 'Vitamin E',
      'vitamin_k': 'Vitamin K',
      'vitamin_b1': 'Vitamin B1',
      'vitamin_b2': 'Vitamin B2',
      'vitamin_b3': 'Vitamin B3',
      'vitamin_b5': 'Vitamin B5',
      'vitamin_b6': 'Vitamin B6',
      'vitamin_b7': 'Vitamin B7',
      'vitamin_b9': 'Vitamin B9',
      'vitamin_b12': 'Vitamin B12',
    };

    // Process root level vitamins (direct format from SnapFood)
    try {
      rootKeyToVitaminMap.forEach((apiKey, vitaminKey) {
        if (data.containsKey(apiKey) && vitamins.containsKey(vitaminKey)) {
          double amount = _extractNumericValue(data[apiKey].toString());
          if (amount >= 0) {
            // Include 0 values
            _updateVitaminWithValue(vitaminKey, amount);
            print('Found $vitaminKey: $amount directly in root data');
          }
        }
      });
    } catch (e) {
      print('Error processing direct root vitamins: $e');
    }

    // Process root level minerals (direct format from SnapFood)
    Map<String, String> rootKeyToMineralMap = {
      // Direct mineral mapping from SnapFood API response
      'calcium': 'Calcium',
      'chloride': 'Chloride',
      'chromium': 'Chromium',
      'copper': 'Copper',
      'fluoride': 'Fluoride',
      'iodine': 'Iodine',
      'iron': 'Iron',
      'magnesium': 'Magnesium',
      'manganese': 'Manganese',
      'molybdenum': 'Molybdenum',
      'phosphorus': 'Phosphorus',
      'potassium': 'Potassium',
      'selenium': 'Selenium',
      'sodium': 'Sodium',
      'zinc': 'Zinc',
    };

    try {
      rootKeyToMineralMap.forEach((apiKey, mineralKey) {
        if (data.containsKey(apiKey) && minerals.containsKey(mineralKey)) {
          double amount = _extractNumericValue(data[apiKey].toString());
          if (amount >= 0) {
            // Include 0 values
            _updateMineralWithValue(mineralKey, amount);
            print('Found $mineralKey: $amount directly in root data');
          }
        }
      });
    } catch (e) {
      print('Error processing direct root minerals: $e');
    }

    // Process root level other nutrients (direct format from SnapFood)
    Map<String, String> rootKeyToOtherMap = {
      'fiber': 'Fiber',
      'cholesterol': 'Cholesterol',
      'sugar': 'Sugar',
      'saturated_fats': 'Saturated Fats',
      'omega_3': 'Omega-3',
      'omega_6': 'Omega-6',
    };

    try {
      rootKeyToOtherMap.forEach((apiKey, nutrientKey) {
        if (data.containsKey(apiKey) && other.containsKey(nutrientKey)) {
          double amount = _extractNumericValue(data[apiKey].toString());
          if (amount >= 0) {
            // Include 0 values
            _updateOtherNutrientWithValue(nutrientKey, amount);
            print('Found $nutrientKey: $amount directly in root data');
          }
        }
      });
    } catch (e) {
      print('Error processing direct root other nutrients: $e');
    }

    // Process each nutrient individually to prevent one error affecting others
    _processSingleOtherNutrient(data, 'Cholesterol', ['cholesterol', 'chol']);
    _processSingleOtherNutrient(
        data, 'Fiber', ['fiber', 'dietary_fiber', 'dietary fiber', 'fibre']);
    _processSingleOtherNutrient(
        data, 'Sugar', ['sugar', 'sugars', 'total_sugar', 'total sugar']);
    _processSingleOtherNutrient(data, 'Saturated Fats',
        ['saturated_fats', 'saturated_fat', 'saturated fat', 'sat_fat']);
    _processSingleOtherNutrient(
        data, 'Omega-3', ['omega_3', 'omega 3', 'omega3']);
    _processSingleOtherNutrient(
        data, 'Omega-6', ['omega_6', 'omega 6', 'omega6']);
  }

  // Helper method to map API vitamin keys to nutrition.dart keys
  String _mapVitaminKey(String apiKey) {
    switch (apiKey.toLowerCase()) {
      case 'vitamin_a':
        return 'Vitamin A';
      case 'vitamin_c':
        return 'Vitamin C';
      case 'vitamin_d':
        return 'Vitamin D';
      case 'vitamin_e':
        return 'Vitamin E';
      case 'vitamin_k':
        return 'Vitamin K';
      case 'vitamin_b1':
        return 'Vitamin B1';
      case 'vitamin_b2':
        return 'Vitamin B2';
      case 'vitamin_b3':
        return 'Vitamin B3';
      case 'vitamin_b5':
        return 'Vitamin B5';
      case 'vitamin_b6':
        return 'Vitamin B6';
      case 'vitamin_b7':
        return 'Vitamin B7';
      case 'vitamin_b9':
        return 'Vitamin B9';
      case 'vitamin_b12':
        return 'Vitamin B12';
      default:
        return apiKey; // Return as-is if no mapping found
    }
  }

  // Helper method to map API mineral keys to nutrition.dart keys
  String _mapMineralKey(String apiKey) {
    switch (apiKey.toLowerCase()) {
      case 'calcium':
        return 'Calcium';
      case 'chloride':
        return 'Chloride';
      case 'chromium':
        return 'Chromium';
      case 'copper':
        return 'Copper';
      case 'fluoride':
        return 'Fluoride';
      case 'iodine':
        return 'Iodine';
      case 'iron':
        return 'Iron';
      case 'magnesium':
        return 'Magnesium';
      case 'manganese':
        return 'Manganese';
      case 'molybdenum':
        return 'Molybdenum';
      case 'phosphorus':
        return 'Phosphorus';
      case 'potassium':
        return 'Potassium';
      case 'selenium':
        return 'Selenium';
      case 'sodium':
        return 'Sodium';
      case 'zinc':
        return 'Zinc';
      default:
        return apiKey; // Return as-is if no mapping found
    }
  }

  // Helper method to map API other nutrient keys to nutrition.dart keys
  String _mapOtherNutrientKey(String apiKey) {
    switch (apiKey.toLowerCase()) {
      case 'fiber':
        return 'Fiber';
      case 'cholesterol':
        return 'Cholesterol';
      case 'sugar':
        return 'Sugar';
      case 'saturated_fats':
        return 'Saturated Fats';
      case 'omega_3':
        return 'Omega-3';
      case 'omega_6':
        return 'Omega-6';
      default:
        return apiKey; // Return as-is if no mapping found
    }
  }

  // Helper method to extract a numeric value from a string like "123mg" or "45 g"
  double _extractNumericValue(String input) {
    try {
      // If it's already a number, just convert it
      double? directValue = double.tryParse(input);
      if (directValue != null) {
        return directValue;
      }

      // Extract numeric part
      RegExp numericRegExp = RegExp(r'(\d+\.?\d*)');
      RegExpMatch? match = numericRegExp.firstMatch(input);
      if (match != null && match.group(1) != null) {
        return double.tryParse(match.group(1)!) ?? 0.0;
      }

      return 0.0;
    } catch (e) {
      print('Error extracting numeric value from "$input": $e');
      return 0.0;
    }
  }

  // Helper method to extract unit from a formatted string like "10/100 mg"
  String _extractUnit(String formattedValue) {
    try {
      // Extract unit part (everything after the last space)
      List<String> parts = formattedValue.split(' ');
      if (parts.length > 1) {
        return parts.last;
      }

      // If no space found, try to find the first non-numeric character sequence
      RegExp unitRegExp = RegExp(r'[a-zA-Z]+');
      RegExpMatch? match = unitRegExp.firstMatch(formattedValue);
      if (match != null) {
        return match.group(0) ?? 'g';
      }

      return 'g'; // Default unit
    } catch (e) {
      print('Error extracting unit from "$formattedValue": $e');
      return 'g';
    }
  }

  // Helper method to parse current value from formatted string like "0/0 mg"
  double _parseCurrentValue(String formattedValue) {
    try {
      // Extract the part before the slash
      if (formattedValue.contains('/')) {
        String currentValue = formattedValue.split('/')[0];
        return double.tryParse(currentValue) ?? 0.0;
      }
      return 0.0;
    } catch (e) {
      print("Error parsing current value from '$formattedValue': $e");
      return 0.0;
    }
  }

  // Helper method to update a vitamin with a numeric value
  void _updateVitaminWithValue(String vitaminKey, double currentAmount) {
    if (vitamins.containsKey(vitaminKey)) {
      // Get target value and unit from the existing value
      String currentValue = vitamins[vitaminKey]!.value;
      String unit = _extractUnit(currentValue);

      // Get target value from SharedPreferences
      _loadTargetValueFromPrefs(
              "vitamin_target_" + vitaminKey.toLowerCase().replaceAll(' ', '_'))
          .then((targetValue) {
        // Ensure target value is valid to prevent division by zero
        if (targetValue <= 0) {
          print('Warning: Invalid target value for $vitaminKey, using default');
          // Use default targets based on vitamin type
          switch (vitaminKey) {
            case 'Vitamin A':
              targetValue = 700;
              break;
            case 'Vitamin C':
              targetValue = 75;
              break;
            case 'Vitamin D':
              targetValue = 15;
              break;
            case 'Vitamin E':
              targetValue = 15;
              break;
            case 'Vitamin K':
              targetValue = 90;
              break;
            case 'Vitamin B1':
              targetValue = 1.1;
              break;
            case 'Vitamin B2':
              targetValue = 1.1;
              break;
            case 'Vitamin B3':
              targetValue = 14;
              break;
            case 'Vitamin B5':
              targetValue = 5;
              break;
            case 'Vitamin B6':
              targetValue = 1.3;
              break;
            case 'Vitamin B7':
              targetValue = 30;
              break;
            case 'Vitamin B9':
              targetValue = 400;
              break;
            case 'Vitamin B12':
              targetValue = 2.4;
              break;
            default:
              targetValue = 100;
              break;
          }
        }

        // Calculate progress and percentage (safely)
        double progress = targetValue > 0 ? (currentAmount / targetValue) : 0;
        int percentage = (progress * 100).round();

        // Update the vitamin info
        Color progressColor = _getColorBasedOnProgress(progress);

        if (mounted) {
          setState(() {
            vitamins[vitaminKey] = NutrientInfo(
                name: vitaminKey,
                value: "$currentAmount/${targetValue.toStringAsFixed(1)} $unit",
                percent: "$percentage%",
                progress: progress,
                progressColor: progressColor);
          });
        }

        print(
            'Updated $vitaminKey: $currentAmount/$targetValue $unit = $percentage%');
      });
    }
  }

  // Helper method to update a mineral with a numeric value
  void _updateMineralWithValue(String mineralKey, double currentAmount) {
    if (minerals.containsKey(mineralKey)) {
      // Get target value and unit from the existing value
      String currentValue = minerals[mineralKey]!.value;
      String unit = _extractUnit(currentValue);

      // Get target value from SharedPreferences
      _loadTargetValueFromPrefs(
              "mineral_target_" + mineralKey.toLowerCase().replaceAll(' ', '_'))
          .then((targetValue) {
        // Ensure target value is valid to prevent division by zero
        if (targetValue <= 0) {
          print('Warning: Invalid target value for $mineralKey, using default');
          // Use default targets based on mineral type
          switch (mineralKey) {
            case 'Calcium':
              targetValue = 1000;
              break;
            case 'Chloride':
              targetValue = 2300;
              break;
            case 'Chromium':
              targetValue = 35;
              break;
            case 'Copper':
              targetValue = 900;
              break;
            case 'Fluoride':
              targetValue = 4;
              break;
            case 'Iodine':
              targetValue = 150;
              break;
            case 'Iron':
              targetValue = 18;
              break;
            case 'Magnesium':
              targetValue = 400;
              break;
            case 'Manganese':
              targetValue = 2.3;
              break;
            case 'Molybdenum':
              targetValue = 45;
              break;
            case 'Phosphorus':
              targetValue = 700;
              break;
            case 'Potassium':
              targetValue = 3500;
              break;
            case 'Selenium':
              targetValue = 55;
              break;
            case 'Sodium':
              targetValue = 2300;
              break;
            case 'Zinc':
              targetValue = 11;
              break;
            default:
              targetValue = 100;
              break;
          }
        }

        // Calculate progress and percentage (safely)
        double progress = targetValue > 0 ? (currentAmount / targetValue) : 0;
        int percentage = (progress * 100).round();

        // Update the mineral info
        Color progressColor = _getColorBasedOnProgress(progress);

        if (mounted) {
          setState(() {
            minerals[mineralKey] = NutrientInfo(
                name: mineralKey,
                value: "$currentAmount/${targetValue.toStringAsFixed(1)} $unit",
                percent: "$percentage%",
                progress: progress,
                progressColor: progressColor);
          });
        }

        print(
            'Updated $mineralKey: $currentAmount/$targetValue $unit = $percentage%');
      });
    }
  }

  // Helper method to update another nutrient with a numeric value
  void _updateOtherNutrientWithValue(String nutrientKey, double currentAmount) {
    if (other.containsKey(nutrientKey)) {
      // Get target value and unit from the existing value
      String currentValue = other[nutrientKey]!.value;
      String unit = _extractUnit(currentValue);

      // Determine target unit based on nutrient type for correct display
      if (nutrientKey == 'Omega-3') {
        unit = 'mg';
      } else if (nutrientKey == 'Saturated Fats' || nutrientKey == 'Omega-6') {
        unit = 'g';
      } else if (nutrientKey == 'Cholesterol') {
        unit = 'mg';
      }

      // Get target value from SharedPreferences
      _loadTargetValueFromPrefs(nutrientKey).then((targetValue) {
        // Ensure target value is valid to prevent division by zero
        if (targetValue <= 0) {
          print(
              'Warning: Invalid target value for $nutrientKey, using default');
          // Use default targets based on nutrient type
          switch (nutrientKey) {
            case 'Fiber':
              targetValue = 30;
              break;
            case 'Cholesterol':
              targetValue = 300;
              break;
            case 'Omega-3':
              targetValue = 1500;
              break;
            case 'Omega-6':
              targetValue = 14;
              break;
            case 'Saturated Fats':
              targetValue = 22;
              break;
            default:
              targetValue = 100;
              break;
          }
        }

        // Calculate progress and percentage (safely)
        double progress = targetValue > 0 ? (currentAmount / targetValue) : 0;
        int percentage = (progress * 100).round();

        // Update the nutrient info
        Color progressColor = _getColorBasedOnProgress(progress);

        if (mounted) {
          setState(() {
            other[nutrientKey] = NutrientInfo(
                name: nutrientKey,
                value:
                    "$currentAmount/${targetValue.toStringAsFixed(unit == 'mg' ? 0 : 1)} $unit",
                percent: "$percentage%",
                progress: progress,
                progressColor: progressColor);
          });
        }

        print(
            'Updated $nutrientKey: $currentAmount/$targetValue $unit = $percentage%');
      });
    }
  }

  // Helper method to get the target value from SharedPreferences
  Future<double> _loadTargetValueFromPrefs(String nutrientKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String prefKey = '';

      // Map nutrient key to the correct preference key
      switch (nutrientKey) {
        case 'Fiber':
          prefKey = 'nutrient_target_fiber';
          break;
        case 'Cholesterol':
          prefKey = 'nutrient_target_cholesterol';
          break;
        case 'Omega-3':
          prefKey = 'nutrient_target_omega3';
          break;
        case 'Omega-6':
          prefKey = 'nutrient_target_omega6';
          break;
        case 'Saturated Fats':
          prefKey = 'nutrient_target_saturated_fat';
          break;
        default:
          prefKey =
              'nutrient_target_${nutrientKey.toLowerCase().replaceAll(' ', '_')}';
      }

      // Try to get the value as int or double
      int? intValue = prefs.getInt(prefKey);
      if (intValue != null) {
        return intValue.toDouble();
      }

      double? doubleValue = prefs.getDouble(prefKey);
      if (doubleValue != null) {
        return doubleValue;
      }

      // Not found
      return 0.0;
    } catch (e) {
      print('Error loading target for $nutrientKey: $e');
      return 0.0;
    }
  }

  // Helper method to load personalized targets and properly update nutrient displays
  Future<void> _loadNutrientTargets() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Debug output to identify available targets
      print("\n===== AVAILABLE PERSONALIZED TARGETS =====");
      Set<String> keys = prefs.getKeys();
      List<String> targetKeys = keys
          .where((key) =>
              key.contains('target_') ||
              key.contains('vitamin_') ||
              key.contains('mineral_') ||
              key.contains('nutrient_'))
          .toList();

      for (String key in targetKeys) {
        var value = prefs.get(key);
        print("$key = $value (${value.runtimeType})");
      }
      print("========================================\n");

      // VITAMINS - Load all vitamins with their proper personalized targets
      Map<String, String> vitaminKeyMapping = {
        'Vitamin A': 'vitamin_target_vitamin_a',
        'Vitamin C': 'vitamin_target_vitamin_c',
        'Vitamin D': 'vitamin_target_vitamin_d',
        'Vitamin E': 'vitamin_target_vitamin_e',
        'Vitamin K': 'vitamin_target_vitamin_k',
        'Vitamin B1': 'vitamin_target_vitamin_b1',
        'Vitamin B2': 'vitamin_target_vitamin_b2',
        'Vitamin B3': 'vitamin_target_vitamin_b3',
        'Vitamin B5': 'vitamin_target_vitamin_b5',
        'Vitamin B6': 'vitamin_target_vitamin_b6',
        'Vitamin B7': 'vitamin_target_vitamin_b7',
        'Vitamin B9': 'vitamin_target_vitamin_b9',
        'Vitamin B12': 'vitamin_target_vitamin_b12',
      };

      // Units mapping for vitamins
      Map<String, String> vitaminUnits = {
        'Vitamin A': 'mcg',
        'Vitamin C': 'mg',
        'Vitamin D': 'mcg',
        'Vitamin E': 'mg',
        'Vitamin K': 'mcg',
        'Vitamin B1': 'mg',
        'Vitamin B2': 'mg',
        'Vitamin B3': 'mg',
        'Vitamin B5': 'mg',
        'Vitamin B6': 'mg',
        'Vitamin B7': 'mcg',
        'Vitamin B9': 'mcg',
        'Vitamin B12': 'mcg',
      };

      // Process each vitamin
      vitaminKeyMapping.forEach((vitaminName, prefsKey) {
        try {
          // Try to load int target first, then double, with fallback to default
          int? intTarget = prefs.getInt(prefsKey);
          double? doubleTarget =
              intTarget?.toDouble() ?? prefs.getDouble(prefsKey);

          if (doubleTarget != null && doubleTarget > 0) {
            // Target found in preferences, use it
            double currentValue =
                _parseCurrentValue(vitamins[vitaminName]!.value);
            String unit = vitaminUnits[vitaminName] ?? 'mg';

            // Calculate progress and formatting
            double progress = currentValue / doubleTarget;
            int percentage = (progress * 100).round();
            Color progressColor = _getColorBasedOnProgress(progress);

            // Update the vitamin display
            vitamins[vitaminName] = NutrientInfo(
                name: vitaminName,
                value:
                    "$currentValue/${doubleTarget.toStringAsFixed(unit == 'mcg' ? 0 : 1)} $unit",
                percent: "$percentage%",
                progress: progress,
                progressColor: progressColor,
                hasInfo: vitamins[vitaminName]!.hasInfo);

            print(
                'Updated $vitaminName with personalized target: $doubleTarget $unit');
          }
        } catch (e) {
          print('Error processing $vitaminName target: $e');
        }
      });

      // MINERALS - Process all minerals with their personalized targets
      Map<String, String> mineralKeyMapping = {
        'Calcium': 'mineral_target_calcium',
        'Chloride': 'mineral_target_chloride',
        'Chromium': 'mineral_target_chromium',
        'Copper': 'mineral_target_copper',
        'Fluoride': 'mineral_target_fluoride',
        'Iodine': 'mineral_target_iodine',
        'Iron': 'mineral_target_iron',
        'Magnesium': 'mineral_target_magnesium',
        'Manganese': 'mineral_target_manganese',
        'Molybdenum': 'mineral_target_molybdenum',
        'Phosphorus': 'mineral_target_phosphorus',
        'Potassium': 'mineral_target_potassium',
        'Selenium': 'mineral_target_selenium',
        'Sodium': 'mineral_target_sodium',
        'Zinc': 'mineral_target_zinc',
      };

      // Units mapping for minerals
      Map<String, String> mineralUnits = {
        'Calcium': 'mg',
        'Chloride': 'mg',
        'Chromium': 'mcg',
        'Copper': 'mcg',
        'Fluoride': 'mg',
        'Iodine': 'mcg',
        'Iron': 'mg',
        'Magnesium': 'mg',
        'Manganese': 'mg',
        'Molybdenum': 'mcg',
        'Phosphorus': 'mg',
        'Potassium': 'mg',
        'Selenium': 'mcg',
        'Sodium': 'mg',
        'Zinc': 'mg',
      };

      // Process each mineral
      mineralKeyMapping.forEach((mineralName, prefsKey) {
        try {
          // Try to load int target first, then double, with fallback to default
          int? intTarget = prefs.getInt(prefsKey);
          double? doubleTarget =
              intTarget?.toDouble() ?? prefs.getDouble(prefsKey);

          if (doubleTarget != null && doubleTarget > 0) {
            // Target found in preferences, use it
            double currentValue =
                _parseCurrentValue(minerals[mineralName]!.value);
            String unit = mineralUnits[mineralName] ?? 'mg';

            // Calculate progress and formatting
            double progress = currentValue / doubleTarget;
            int percentage = (progress * 100).round();
            Color progressColor = _getColorBasedOnProgress(progress);

            // Update the mineral display
            minerals[mineralName] = NutrientInfo(
                name: mineralName,
                value:
                    "$currentValue/${doubleTarget.toStringAsFixed(unit == 'mcg' ? 0 : 1)} $unit",
                percent: "$percentage%",
                progress: progress,
                progressColor: progressColor,
                hasInfo: minerals[mineralName]!.hasInfo);

            print(
                'Updated $mineralName with personalized target: $doubleTarget $unit');
          }
        } catch (e) {
          print('Error processing $mineralName target: $e');
        }
      });

      // OTHER NUTRIENTS - Process all other nutrients with their personalized targets
      Map<String, String> otherKeyMapping = {
        'Fiber': 'nutrient_target_fiber',
        'Cholesterol': 'nutrient_target_cholesterol',
        'Omega-3': 'nutrient_target_omega3',
        'Omega-6': 'nutrient_target_omega6',
        'Saturated Fats': 'nutrient_target_saturated_fat',
      };

      // Units mapping for other nutrients
      Map<String, String> otherUnits = {
        'Fiber': 'g',
        'Cholesterol': 'mg',
        'Omega-3': 'mg',
        'Omega-6': 'g',
        'Saturated Fats': 'g',
      };

      // Process each other nutrient
      otherKeyMapping.forEach((nutrientName, prefsKey) {
        try {
          // Try to load int target first, then double, with fallback to default
          int? intTarget = prefs.getInt(prefsKey);
          double? doubleTarget =
              intTarget?.toDouble() ?? prefs.getDouble(prefsKey);

          if (doubleTarget != null && doubleTarget > 0) {
            // Target found in preferences, use it
            double currentValue =
                _parseCurrentValue(other[nutrientName]!.value);
            String unit = otherUnits[nutrientName] ?? 'g';

            // Calculate progress and formatting
            double progress = currentValue / doubleTarget;
            int percentage = (progress * 100).round();
            Color progressColor = _getColorBasedOnProgress(progress);

            // Update the other nutrient display
            other[nutrientName] = NutrientInfo(
                name: nutrientName,
                value:
                    "$currentValue/${doubleTarget.toStringAsFixed(unit == 'mg' ? 0 : 1)} $unit",
                percent: "$percentage%",
                progress: progress,
                progressColor: progressColor,
                hasInfo: other[nutrientName]!.hasInfo);

            print(
                'Updated $nutrientName with personalized target: $doubleTarget $unit');
          }
        } catch (e) {
          print('Error processing $nutrientName target: $e');
        }
      });

      // Save the updated nutrient data
      await _saveNutritionData();

      // Update the UI to reflect the changes
      if (mounted) {
        setState(() {});
      }

      print("Successfully loaded all personalized nutrient targets");
    } catch (e) {
      print("Error loading nutrient targets: $e");
    }
  }

  // Helper method to load personalized targets for other nutrients
  Future<Map<String, double>> _loadPersonalizedOtherNutrientTargets() async {
    Map<String, double> targets = {};

    try {
      SharedPreferences.getInstance().then((prefs) {
        // Try to load each nutrient target from SharedPreferences

        // Fiber
        double? fiberTarget = prefs.getDouble('nutrient_target_fiber');
        if (fiberTarget != null) {
          targets['fiber'] = fiberTarget;
          print('Loaded personalized fiber target: $fiberTarget g');
        }

        // Cholesterol
        double? cholesterolTarget =
            prefs.getDouble('nutrient_target_cholesterol');
        if (cholesterolTarget != null) {
          targets['cholesterol'] = cholesterolTarget;
          print(
              'Loaded personalized cholesterol target: $cholesterolTarget mg');
        }

        // Omega-3
        double? omega3Target = prefs.getDouble('nutrient_target_omega3');
        if (omega3Target != null) {
          targets['omega3'] = omega3Target;
          print('Loaded personalized omega-3 target: $omega3Target mg');
        }

        // Omega-6
        double? omega6Target = prefs.getDouble('nutrient_target_omega6');
        if (omega6Target != null) {
          targets['omega6'] = omega6Target;
          print('Loaded personalized omega-6 target: $omega6Target g');
        }

        // Saturated fats
        double? saturatedFatTarget =
            prefs.getDouble('nutrient_target_saturated_fat');
        if (saturatedFatTarget != null) {
          targets['saturated_fat'] = saturatedFatTarget;
          print(
              'Loaded personalized saturated fat target: $saturatedFatTarget g');
        }

        // Protein
        double? proteinTarget = prefs.getDouble('nutrient_target_protein');
        if (proteinTarget != null) {
          targets['protein'] = proteinTarget;
          print('Loaded personalized protein target: $proteinTarget g');
        }

        // Fat
        double? fatTarget = prefs.getDouble('nutrient_target_fat');
        if (fatTarget != null) {
          targets['fat'] = fatTarget;
          print('Loaded personalized fat target: $fatTarget g');
        }

        // Carbs
        double? carbsTarget = prefs.getDouble('nutrient_target_carbs');
        if (carbsTarget != null) {
          targets['carbs'] = carbsTarget;
          print('Loaded personalized carbs target: $carbsTarget g');
        }
      });
    } catch (e) {
      print('Error loading personalized other nutrient targets: $e');
    }

    return targets;
  }

  void _updateVitaminsFromData(Map<String, dynamic> data) {
    Map<String, Map<String, dynamic>> vitaminInfo = {
      'vitamin_a': {
        'key': 'Vitamin A',
        'target': 900, // mcg
        'unit': 'mcg',
        'color': greenColor
      },
      'vitamin_c': {
        'key': 'Vitamin C',
        'target': 90, // mg
        'unit': 'mg',
        'color': redColor
      },
      'vitamin_d': {
        'key': 'Vitamin D',
        'target': 20, // mcg
        'unit': 'mcg',
        'color': yellowColor,
        'hasInfo': true
      },
      'vitamin_e': {
        'key': 'Vitamin E',
        'target': 15, // mg
        'unit': 'mg',
        'color': redColor
      },
      'vitamin_k': {
        'key': 'Vitamin K',
        'target': 120, // mcg
        'unit': 'mcg',
        'color': yellowColor
      },
      'thiamin': {
        'key': 'Vitamin B1',
        'target': 1.2, // mg
        'unit': 'mg',
        'color': redColor
      },
      'riboflavin': {
        'key': 'Vitamin B2',
        'target': 1.3, // mg
        'unit': 'mg',
        'color': yellowColor
      },
      'niacin': {
        'key': 'Vitamin B3',
        'target': 16, // mg
        'unit': 'mg',
        'color': redColor
      },
      'pantothenic_acid': {
        'key': 'Vitamin B5',
        'target': 5, // mg
        'unit': 'mg',
        'color': yellowColor
      },
      'pyridoxine': {
        'key': 'Vitamin B6',
        'target': 1.3, // mg
        'unit': 'mg',
        'color': redColor
      },
      'biotin': {
        'key': 'Vitamin B7',
        'target': 30, // mcg
        'unit': 'mcg',
        'color': yellowColor
      },
      'folate': {
        'key': 'Vitamin B9',
        'target': 400, // mcg
        'unit': 'mcg',
        'color': redColor
      },
      'cobalamin': {
        'key': 'Vitamin B12',
        'target': 2.4, // mcg
        'unit': 'mcg',
        'color': redColor
      }
    };

    // Add alternative keys to handle different API naming conventions - using null-safe operator
    Map<String, Map<String, dynamic>> alternativeKeys = {
      // Alternative keys for B vitamins that might be in the response
      'b1': vitaminInfo['thiamin'] ?? {},
      'b2': vitaminInfo['riboflavin'] ?? {},
      'b3': vitaminInfo['niacin'] ?? {},
      'b5': vitaminInfo['pantothenic_acid'] ?? {},
      'b6': vitaminInfo['pyridoxine'] ?? {},
      'b7': vitaminInfo['biotin'] ?? {},
      'b9': vitaminInfo['folate'] ?? {},
      'b12': vitaminInfo['cobalamin'] ?? {},
      'vitamin_b1': vitaminInfo['thiamin'] ?? {},
      'vitamin_b2': vitaminInfo['riboflavin'] ?? {},
      'vitamin_b3': vitaminInfo['niacin'] ?? {},
      'vitamin_b5': vitaminInfo['pantothenic_acid'] ?? {},
      'vitamin_b6': vitaminInfo['pyridoxine'] ?? {},
      'vitamin_b7': vitaminInfo['biotin'] ?? {},
      'vitamin_b9': vitaminInfo['folate'] ?? {},
      'vitamin_b12': vitaminInfo['cobalamin'] ?? {},
      'thiamine': vitaminInfo['thiamin'] ?? {},
      'folic_acid': vitaminInfo['folate'] ?? {},
      'folacin': vitaminInfo['folate'] ?? {},
      'pantothenate': vitaminInfo['pantothenic_acid'] ?? {},
      'cyanocobalamin': vitaminInfo['cobalamin'] ?? {}
    };

    // Try to load personalized vitamin targets from SharedPreferences first
    _loadPersonalizedVitaminTargets(vitaminInfo);

    // First try the primary keys
    vitaminInfo.forEach((dataKey, info) {
      if (data.containsKey(dataKey)) {
        double value = _parseNutrientValue(data[dataKey]);
        double target = info['target'] as double;
        double progress = (value / target); // Removed clamp
        String unit = info['unit'] as String;
        bool hasInfo =
            info.containsKey('hasInfo') ? info['hasInfo'] as bool : false;

        // Determine color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);

        vitamins[info['key'] as String] = NutrientInfo(
            name: info['key'] as String,
            value: "$value/$target $unit",
            percent: "${(progress * 100).toStringAsFixed(0)}%",
            progress: progress,
            progressColor: progressColor,
            hasInfo: hasInfo);
      }
    });

    // Then try the alternative keys
    data.forEach((key, value) {
      // Check if this is an alternative key we recognize
      if (alternativeKeys.containsKey(key.toLowerCase())) {
        // Get the info for this vitamin
        Map<String, dynamic> info = alternativeKeys[key.toLowerCase()]!;

        // Skip if empty (means the vitamin wasn't in primary map)
        if (info.isEmpty) {
          return; // Skip this iteration using return instead of continue
        }

        String vitaminKey = info['key'] as String;

        // Only process if we haven't already set this vitamin from a primary key
        if (!vitamins[vitaminKey]!.value.startsWith('0/')) {
          return; // Skip this iteration using return instead of continue
        }

        double valueNum = _parseNutrientValue(value);
        double target = info['target'] as double;
        double progress = (valueNum / target); // Removed clamp
        String unit = info['unit'] as String;
        bool hasInfo =
            info.containsKey('hasInfo') ? info['hasInfo'] as bool : false;

        // Determine color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);

        vitamins[vitaminKey] = NutrientInfo(
            name: vitaminKey,
            value: "$valueNum/$target $unit",
            percent: "${(progress * 100).toStringAsFixed(0)}%",
            progress: progress,
            progressColor: progressColor,
            hasInfo: hasInfo);

        print('Updated vitamin $vitaminKey from alternative key $key');
      }
    });

    // Directly check for B vitamins since they might be coded differently
    _checkForBVitamins(data);
  }

  // Helper method to specifically look for B vitamins in various formats
  void _checkForBVitamins(Map<String, dynamic> data) {
    print("Checking for B vitamins in special formats...");

    // Map of B vitamin keys in our system with their units and default targets
    Map<String, Map<String, dynamic>> bVitamins = {
      'Vitamin B1': {'target': 1.2, 'unit': 'mg'},
      'Vitamin B2': {'target': 1.3, 'unit': 'mg'},
      'Vitamin B3': {'target': 16, 'unit': 'mg'},
      'Vitamin B5': {'target': 5, 'unit': 'mg'},
      'Vitamin B6': {'target': 1.3, 'unit': 'mg'},
      'Vitamin B7': {'target': 30, 'unit': 'mcg'},
      'Vitamin B9': {'target': 400, 'unit': 'mcg'},
      'Vitamin B12': {'target': 2.4, 'unit': 'mcg'}
    };

    // Check for various patterns in the data keys
    data.forEach((key, value) {
      // Try to extract B vitamin number and value
      RegExp regExp =
          RegExp(r'vitamin[_\s]*b(\d+)|b(\d+)', caseSensitive: false);
      Match? match = regExp.firstMatch(key.toLowerCase());

      if (match != null) {
        // Extract the B vitamin number
        String? number = match.group(1) ?? match.group(2);
        if (number != null) {
          String vitaminKey = 'Vitamin B$number';

          // Check if this is a B vitamin we track
          if (vitamins.containsKey(vitaminKey)) {
            // Get the target and unit for this vitamin
            Map<String, dynamic>? vitaminInfo = bVitamins[vitaminKey];
            if (vitaminInfo != null) {
              double valueNum = _parseNutrientValue(value);
              double target = vitaminInfo['target'] as double;
              String unit = vitaminInfo['unit'] as String;

              // Only update if better than current value
              if (valueNum > 0 &&
                  vitamins[vitaminKey]!.value.startsWith('0/')) {
                double progress = (valueNum / target);
                Color progressColor = _getColorBasedOnProgress(progress);

                vitamins[vitaminKey] = NutrientInfo(
                    name: vitaminKey,
                    value: "$valueNum/$target $unit",
                    percent: "${(progress * 100).toStringAsFixed(0)}%",
                    progress: progress,
                    progressColor: progressColor);

                print(
                    'Updated $vitaminKey from pattern match key $key with value $valueNum');
              }
            }
          }
        }
      }
    });

    // Check if we have a nutrients array with specific B vitamin information
    if (data.containsKey('nutrients') && data['nutrients'] is List) {
      print("Found nutrients array, checking for B vitamins...");
      List nutrientsList = data['nutrients'] as List;

      for (var nutrient in nutrientsList) {
        if (nutrient is Map) {
          String? name = nutrient['name']?.toString().toLowerCase();
          dynamic amount = nutrient['amount'];

          if (name != null && amount != null) {
            // Check if this is a B vitamin
            RegExp regExp =
                RegExp(r'vitamin[_\s]*b(\d+)|b(\d+)', caseSensitive: false);
            Match? match = regExp.firstMatch(name);

            if (match != null) {
              String? number = match.group(1) ?? match.group(2);
              if (number != null) {
                String vitaminKey = 'Vitamin B$number';

                // If we track this B vitamin, update its value
                if (vitamins.containsKey(vitaminKey)) {
                  Map<String, dynamic>? vitaminInfo = bVitamins[vitaminKey];
                  if (vitaminInfo != null) {
                    double valueNum = _parseNutrientValue(amount);
                    double target = vitaminInfo['target'] as double;
                    String unit = vitaminInfo['unit'] as String;

                    if (valueNum > 0 &&
                        vitamins[vitaminKey]!.value.startsWith('0/')) {
                      double progress = (valueNum / target);
                      Color progressColor = _getColorBasedOnProgress(progress);

                      vitamins[vitaminKey] = NutrientInfo(
                          name: vitaminKey,
                          value: "$valueNum/$target $unit",
                          percent: "${(progress * 100).toStringAsFixed(0)}%",
                          progress: progress,
                          progressColor: progressColor);

                      print(
                          'Updated $vitaminKey from nutrients array with value $valueNum');
                    }
                  }
                }
              }
            } else if (name.contains('thiamin') || name.contains('b1')) {
              _updateBVitaminFromNutrient('Vitamin B1', amount, bVitamins);
            } else if (name.contains('riboflavin') || name.contains('b2')) {
              _updateBVitaminFromNutrient('Vitamin B2', amount, bVitamins);
            } else if (name.contains('niacin') || name.contains('b3')) {
              _updateBVitaminFromNutrient('Vitamin B3', amount, bVitamins);
            } else if (name.contains('pantothenic') || name.contains('b5')) {
              _updateBVitaminFromNutrient('Vitamin B5', amount, bVitamins);
            } else if (name.contains('pyridoxine') || name.contains('b6')) {
              _updateBVitaminFromNutrient('Vitamin B6', amount, bVitamins);
            } else if (name.contains('biotin') || name.contains('b7')) {
              _updateBVitaminFromNutrient('Vitamin B7', amount, bVitamins);
            } else if (name.contains('folate') ||
                name.contains('folic') ||
                name.contains('b9')) {
              _updateBVitaminFromNutrient('Vitamin B9', amount, bVitamins);
            } else if (name.contains('cobalamin') || name.contains('b12')) {
              _updateBVitaminFromNutrient('Vitamin B12', amount, bVitamins);
            }
          }
        }
      }
    }
  }

  // Helper method to update B vitamins from nutrient array
  void _updateBVitaminFromNutrient(String vitaminKey, dynamic amount,
      Map<String, Map<String, dynamic>> bVitamins) {
    if (vitamins.containsKey(vitaminKey) && bVitamins.containsKey(vitaminKey)) {
      double valueNum = _parseNutrientValue(amount);
      double target = bVitamins[vitaminKey]!['target'] as double;
      String unit = bVitamins[vitaminKey]!['unit'] as String;

      if (valueNum > 0 && vitamins[vitaminKey]!.value.startsWith('0/')) {
        double progress = (valueNum / target);
        Color progressColor = _getColorBasedOnProgress(progress);

        vitamins[vitaminKey] = NutrientInfo(
            name: vitaminKey,
            value: "$valueNum/$target $unit",
            percent: "${(progress * 100).toStringAsFixed(0)}%",
            progress: progress,
            progressColor: progressColor);

        print(
            'Updated $vitaminKey from nutrients array detailed match with value $valueNum');
      }
    }
  }

  void _updateMineralsFromData(Map<String, dynamic> data) {
    Map<String, Map<String, dynamic>> mineralInfo = {
      'calcium': {
        'key': 'Calcium',
        'target': 1000, // mg
        'unit': 'mg',
        'color': yellowColor
      },
      'iron': {
        'key': 'Iron',
        'target': 18, // mg
        'unit': 'mg',
        'color': yellowColor
      },
      'sodium': {
        'key': 'Sodium',
        'target': 2300, // mg
        'unit': 'mg',
        'color': yellowColor
      },
      'potassium': {
        'key': 'Potassium',
        'target': 3500, // mg
        'unit': 'mg',
        'color': yellowColor
      },
      'magnesium': {
        'key': 'Magnesium',
        'target': 400, // mg
        'unit': 'mg',
        'color': yellowColor
      },
      'zinc': {
        'key': 'Zinc',
        'target': 11, // mg
        'unit': 'mg',
        'color': yellowColor
      },
      'selenium': {
        'key': 'Selenium',
        'target': 55, // mcg
        'unit': 'mcg',
        'color': yellowColor
      },
      'copper': {
        'key': 'Copper',
        'target': 900, // mcg
        'unit': 'mcg',
        'color': yellowColor
      },
      'manganese': {
        'key': 'Manganese',
        'target': 2.3, // mg
        'unit': 'mg',
        'color': yellowColor
      },
      'phosphorus': {
        'key': 'Phosphorus',
        'target': 700, // mg
        'unit': 'mg',
        'color': yellowColor
      },
      'iodine': {
        'key': 'Iodine',
        'target': 150, // mcg
        'unit': 'mcg',
        'color': yellowColor
      },
      'chromium': {
        'key': 'Chromium',
        'target': 35, // mcg
        'unit': 'mcg',
        'color': yellowColor
      },
      'molybdenum': {
        'key': 'Molybdenum',
        'target': 45, // mcg
        'unit': 'mcg',
        'color': yellowColor
      },
      'chloride': {
        'key': 'Chloride',
        'target': 2300, // mg
        'unit': 'mg',
        'color': yellowColor
      },
      'fluoride': {
        'key': 'Fluoride',
        'target': 4, // mg
        'unit': 'mg',
        'color': yellowColor
      }
    };

    // Try to load personalized mineral targets from SharedPreferences first
    _loadPersonalizedMineralTargets(mineralInfo);

    mineralInfo.forEach((dataKey, info) {
      if (data.containsKey(dataKey)) {
        double value = _parseNutrientValue(data[dataKey]);
        double target = info['target'] as double;
        double progress = (value / target); // Removed clamp
        String unit = info['unit'] as String;

        // Determine color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);

        minerals[info['key'] as String] = NutrientInfo(
            name: info['key'] as String,
            value: "$value/$target $unit",
            percent: "${(progress * 100).toStringAsFixed(0)}%",
            progress: progress,
            progressColor: progressColor);
      }
    });
  }

  // Helper method to load personalized mineral targets from SharedPreferences
  Future<void> _loadPersonalizedMineralTargets(
      Map<String, Map<String, dynamic>> mineralInfo) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Update targets from SharedPreferences where available
      for (var entry in mineralInfo.entries) {
        String dataKey = entry.key;
        Map<String, dynamic> info = entry.value;
        String uiKey = info['key'] as String;
        String prefsKey = uiKey.toLowerCase().replaceAll(' ', '_');

        // Try to load from SharedPreferences - use mineral_target_X format to match calculation_screen.dart
        double? target = prefs.getDouble('mineral_target_$prefsKey');

        // If found, update the target in the mineralInfo map
        if (target != null) {
          mineralInfo[dataKey]!['target'] = target;
          print(
              'Loaded personalized mineral target: $uiKey = $target ${info['unit']}');
        } else {
          print(
              'No personalized target found for $uiKey, using default: ${info['target']} ${info['unit']}');
        }
      }
    } catch (e) {
      print('Error loading personalized mineral targets: $e');
    }
  }

  double _parseNutrientValue(dynamic value) {
    if (value == null) return 0.0;

    // Debug print to see actual value and type
    print("Parsing nutrient value: '$value' of type ${value.runtimeType}");

    if (value is int) return value.toDouble();
    if (value is double) return value;

    if (value is String) {
      try {
        // First try direct parsing
        double? parsed = double.tryParse(value);
        if (parsed != null) return parsed;

        // Try removing non-numeric characters except decimal point
        String cleanedValue = value.replaceAll(RegExp(r'[^0-9.]'), '');
        if (cleanedValue.isNotEmpty) {
          double? cleanedParsed = double.tryParse(cleanedValue);
          if (cleanedParsed != null) return cleanedParsed;
        }

        // Check for specific patterns like "45/100"
        if (value.contains('/')) {
          List<String> parts = value.split('/');
          if (parts.length == 2) {
            double? numerator = double.tryParse(parts[0].trim());
            if (numerator != null) return numerator;
          }
        }

        print("Failed to parse numeric value from '$value', using 0.0");
        return 0.0;
      } catch (e) {
        print("Error parsing value '$value': $e");
        return 0.0;
      }
    }

    print("Unhandled value type ${value.runtimeType} for '$value', using 0.0");
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Add WillPopScope to intercept back button presses
      onWillPop: () async {
        // Save data before allowing navigation
        await _saveNutritionData();

        // Double-save to the global key for extra reliability
        try {
          final prefs = await SharedPreferences.getInstance();

          // Create a data object with nutrition data
          Map<String, dynamic> nutritionData = {
            'scanId': _scanId,
            'lastSaved': DateTime.now().millisecondsSinceEpoch,
            'vitamins':
                Map.fromEntries(vitamins.entries.map((e) => MapEntry(e.key, {
                      'name': e.value.name,
                      'value': e.value.value,
                      'percent': e.value.percent,
                      'progress': e.value.progress,
                      'hasInfo': e.value.hasInfo,
                    }))),
            'minerals':
                Map.fromEntries(minerals.entries.map((e) => MapEntry(e.key, {
                      'name': e.value.name,
                      'value': e.value.value,
                      'percent': e.value.percent,
                      'progress': e.value.progress,
                      'hasInfo': e.value.hasInfo,
                    }))),
            'other': Map.fromEntries(other.entries.map((e) => MapEntry(e.key, {
                  'name': e.value.name,
                  'value': e.value.value,
                  'percent': e.value.percent,
                  'progress': e.value.progress,
                  'hasInfo': e.value.hasInfo,
                }))),
          };

          String json = jsonEncode(nutritionData);
          await prefs.setString('PERMANENT_GLOBAL_NUTRITION_DATA', json);
        } catch (e) {
          print('Error during extra save: $e');
        }

        return true;
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/background4.jpg'),
              fit: BoxFit.cover,
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with back button and title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 29)
                        .copyWith(top: 16, bottom: 8.5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Back button
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.black, size: 24),
                          onPressed: () async {
                            // Save nutrition data before navigation
                            await _saveNutritionData();

                            // Double-save to the global key for extra reliability
                            try {
                              final prefs =
                                  await SharedPreferences.getInstance();

                              // Create a data object with nutrition data
                              Map<String, dynamic> nutritionData = {
                                'scanId': _scanId,
                                'lastSaved':
                                    DateTime.now().millisecondsSinceEpoch,
                                'vitamins': Map.fromEntries(vitamins.entries
                                    .map((e) => MapEntry(e.key, {
                                          'name': e.value.name,
                                          'value': e.value.value,
                                          'percent': e.value.percent,
                                          'progress': e.value.progress,
                                          'hasInfo': e.value.hasInfo,
                                        }))),
                                'minerals': Map.fromEntries(minerals.entries
                                    .map((e) => MapEntry(e.key, {
                                          'name': e.value.name,
                                          'value': e.value.value,
                                          'percent': e.value.percent,
                                          'progress': e.value.progress,
                                          'hasInfo': e.value.hasInfo,
                                        }))),
                                'other': Map.fromEntries(
                                    other.entries.map((e) => MapEntry(e.key, {
                                          'name': e.value.name,
                                          'value': e.value.value,
                                          'percent': e.value.percent,
                                          'progress': e.value.progress,
                                          'hasInfo': e.value.hasInfo,
                                        }))),
                              };

                              String json = jsonEncode(nutritionData);
                              await prefs.setString(
                                  'PERMANENT_GLOBAL_NUTRITION_DATA', json);
                            } catch (e) {
                              print('Error during extra save: $e');
                            }

                            if (mounted) {
                              Navigator.pop(context);
                            }
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),

                        // In-Depth Nutrition title
                        const Text(
                          'In-Depth Nutrition',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro',
                            color: Colors.black,
                          ),
                        ),

                        // Empty space to balance the header
                        const SizedBox(width: 24),
                      ],
                    ),
                  ),

                  // Slim gray divider line
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 29),
                    height: 1,
                    color: const Color(0xFFBDBDBD),
                  ),

                  const SizedBox(height: 20),

                  // Vitamins Section
                  _buildNutrientSection(
                    title: "Vitamins",
                    count: "${_countNonZeroValues(vitamins)}/13",
                    nutrients: vitamins.values.toList(),
                    centerTitle: true,
                  ),

                  const SizedBox(height: 20),

                  // Minerals Section
                  _buildNutrientSection(
                    title: "Minerals",
                    count: "${_countNonZeroValues(minerals)}/15",
                    nutrients: minerals.values.toList(),
                    centerTitle: true,
                  ),

                  const SizedBox(height: 20),

                  // Other Nutrients Section
                  _buildNutrientSection(
                    title: "Other",
                    count: "${_countNonZeroValues(other)}/6",
                    nutrients: other.values.toList(),
                    centerTitle: true,
                  ),

                  // Bottom padding
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _countNonZeroValues(Map<String, NutrientInfo> nutrientMap) {
    return nutrientMap.values
        .where((nutrient) =>
            nutrient.progress >=
            1.0) // Only count as filled if progress is 100% or higher
        .length;
  }

  // Class to hold nutrient information
  Widget _buildNutrientSection({
    required String title,
    required String count,
    required List<NutrientInfo> nutrients,
    bool centerTitle = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 29),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header section with divider
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 20, right: 20),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Title in exact center
                  Center(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'SF Pro',
                      ),
                    ),
                  ),
                  // Row for info icon, spacer, and count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Info icon on left
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            barrierColor: Colors.black.withOpacity(0.6),
                            builder: (context) {
                              return Dialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                backgroundColor: Colors.white,
                                insetPadding:
                                    EdgeInsets.symmetric(horizontal: 32),
                                child: Container(
                                  width: 326,
                                  height: 310,
                                  child: Stack(
                                    children: [
                                      // Close icon
                                      Positioned(
                                        top: 21,
                                        right: 21,
                                        child: GestureDetector(
                                          onTap: () =>
                                              Navigator.of(context).pop(),
                                          child: Image.asset(
                                            'assets/images/closeicon.png',
                                            width: 19,
                                            height: 19,
                                          ),
                                        ),
                                      ),
                                      // Content
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(height: 21),
                                          // Info headline horizontally centered and moved up by 6px
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 0),
                                            child: Align(
                                              alignment: Alignment.topCenter,
                                              child: Transform.translate(
                                                offset: Offset(0, -6),
                                                child: Text(
                                                  'Info',
                                                  style: TextStyle(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.w600,
                                                    fontFamily:
                                                        'SF Pro Display',
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Spacer(),
                                          // Vertically centered, left-aligned subtext/checkmark group
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              SizedBox(width: 32),
                                              Transform.translate(
                                                offset: Offset(0, -10),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        CustomPaint(
                                                          size: Size(22, 22),
                                                          painter:
                                                              _CheckmarkPainter(
                                                                  size: 22),
                                                        ),
                                                        SizedBox(width: 16),
                                                        Text(
                                                          'Aim for 100% daily intake',
                                                          style: TextStyle(
                                                            fontSize: 18,
                                                            fontFamily:
                                                                'SF Pro Display',
                                                            color: Colors.black,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 18),
                                                    Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .center,
                                                      children: [
                                                        CustomPaint(
                                                          size: Size(22, 22),
                                                          painter:
                                                              _CheckmarkPainter(
                                                                  size: 22),
                                                        ),
                                                        SizedBox(width: 16),
                                                        Text(
                                                          'Individual needs may differ',
                                                          style: TextStyle(
                                                            fontSize: 18,
                                                            fontFamily:
                                                                'SF Pro Display',
                                                            color: Colors.black,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          Spacer(),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 20),
                                            child: Container(
                                              width: 280,
                                              height: 48,
                                              margin:
                                                  EdgeInsets.only(bottom: 24),
                                              decoration: BoxDecoration(
                                                color: Colors.black,
                                                borderRadius:
                                                    BorderRadius.circular(28),
                                              ),
                                              child: TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context).pop(),
                                                style: ButtonStyle(
                                                  overlayColor:
                                                      MaterialStateProperty.all(
                                                          Colors.transparent),
                                                ),
                                                child: const Text(
                                                  'Continue',
                                                  style: TextStyle(
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.w500,
                                                    fontFamily:
                                                        'SF Pro Display',
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 1),
                          ),
                          child: Center(
                            child: Text(
                              "i",
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'SF Pro',
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Counter on right
                      Text(
                        count,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                          fontFamily: 'SF Pro',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Divider line under header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Divider(
                height: 1,
                thickness: 1,
                color: Colors.grey.withOpacity(0.3),
              ),
            ),

            // Nutrients list
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: nutrients.map((nutrient) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Nutrient name and values row
                      Row(
                        children: [
                          // Name
                          Expanded(
                            flex: 2,
                            child: Text(
                              nutrient.name,
                              style: const TextStyle(
                                fontSize: 17,
                                color: Colors.black,
                                fontFamily: 'SF Pro',
                              ),
                            ),
                          ),
                          // Value with aligned slash
                          Expanded(
                            flex: 2,
                            child: Row(
                              children: [
                                // Use RichText to align the slash character
                                RichText(
                                  text: TextSpan(
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontFamily: 'SF Pro',
                                      color: Colors.black,
                                    ),
                                    children:
                                        _formatValueWithSlash(nutrient.value),
                                  ),
                                ),
                                if (nutrient.hasInfo)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Image.asset(
                                      'assets/images/questionmark.png',
                                      width: 15,
                                      height: 15,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          // Percentage
                          Text(
                            nutrient.percent,
                            style: const TextStyle(
                              fontSize: 14,
                              fontFamily: 'SF Pro',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      // Progress bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: nutrient.progress.clamp(0.0,
                              1.0), // Clamp only for UI display, still show >100% in text
                          minHeight: 8,
                          backgroundColor: Colors.grey.withOpacity(0.3),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              nutrient.progressColor),
                        ),
                      ),

                      const SizedBox(height: 12),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to format the value with aligned slash
  List<TextSpan> _formatValueWithSlash(String value) {
    // If the value contains a slash, split it and align
    if (value.contains('/')) {
      List<String> parts = value.split('/');
      String leftPart = parts[0];
      String rightPart = parts.length > 1 ? parts[1] : '';

      return [
        TextSpan(
          text: leftPart,
          style: const TextStyle(
            fontSize: 13,
            fontFamily: 'SF Pro',
          ),
        ),
        const TextSpan(
          text: '/',
          style: TextStyle(
            fontSize: 14, // Increased by 1
            fontFamily: 'SF Pro',
          ),
        ),
        TextSpan(
          text: rightPart,
          style: const TextStyle(
            fontSize: 13,
            fontFamily: 'SF Pro',
          ),
        ),
      ];
    } else {
      // If no slash, just return the value as is
      return [
        TextSpan(
          text: value,
          style: const TextStyle(
            fontSize: 13,
            fontFamily: 'SF Pro',
          ),
        ),
      ];
    }
  }

  // Save nutrition data - ULTRA RELIABLE with one global key
  Future<void> _saveNutritionData({bool useGlobalKey = true}) async {
    try {
      // Get SharedPreferences instance
      final prefs = await SharedPreferences.getInstance();

      // Create a data object with nutrition data
      Map<String, dynamic> nutritionData = {
        'scanId': _scanId,
        'lastSaved': DateTime.now().millisecondsSinceEpoch,
        'vitamins':
            Map.fromEntries(vitamins.entries.map((e) => MapEntry(e.key, {
                  'name': e.value.name,
                  'value': e.value.value,
                  'percent': e.value.percent,
                  'progress': e.value.progress,
                  'hasInfo': e.value.hasInfo,
                }))),
        'minerals':
            Map.fromEntries(minerals.entries.map((e) => MapEntry(e.key, {
                  'name': e.value.name,
                  'value': e.value.value,
                  'percent': e.value.percent,
                  'progress': e.value.progress,
                  'hasInfo': e.value.hasInfo,
                }))),
        'other': Map.fromEntries(other.entries.map((e) => MapEntry(e.key, {
              'name': e.value.name,
              'value': e.value.value,
              'percent': e.value.percent,
              'progress': e.value.progress,
              'hasInfo': e.value.hasInfo,
            }))),
      };

      // Convert to JSON
      String dataJson = jsonEncode(nutritionData);

      // For food-specific scan IDs, don't save to global key
      if (_scanId.startsWith('food_nutrition_')) {
        // FOOD-SPECIFIC: Save only to food-specific keys
        await prefs.setString('food_nutrition_data_$_scanId', dataJson);
        await prefs.setString('nutrition_data_$_scanId', dataJson);

        // If this is a food-specific scan ID from FoodCardOpen.dart
        try {
          // Format is "food_nutrition_foodname_calories"
          List<String> parts = _scanId.split('_');
          if (parts.length >= 3) {
            // Everything after "food_nutrition_" and before the last part (calories)
            String foodName = parts.sublist(2, parts.length - 1).join('_');

            // Also store by food name for compatibility with FoodCardOpen.dart
            await prefs.setString('food_nutrition_$foodName', dataJson);

            // Update the food_cards list if this food exists there
            await _updateFoodCardWithNutrition(foodName, nutritionData);
          }
        } catch (e) {
          print('Error extracting food name from scan ID: $e');
        }
      } else if (useGlobalKey) {
        // GLOBAL: For non-food specific or when explicitly requested to use global key
        await prefs.setString('PERMANENT_GLOBAL_NUTRITION_DATA', dataJson);
        await prefs.setString('food_nutrition_data_$_scanId', dataJson);
        await prefs.setString('nutrition_data_$_scanId', dataJson);
      }

      // Always store the current scan ID globally
      await prefs.setString('current_nutrition_scan_id', _scanId);

      print(
          'Saved nutrition data for ID: $_scanId (useGlobalKey=$useGlobalKey)');
    } catch (e) {
      print('Error saving nutrition data: $e');
    }
  }

  // Helper method to update a food card's nutrition data if it exists
  Future<void> _updateFoodCardWithNutrition(
      String foodName, Map<String, dynamic> nutritionData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String>? foodCards = prefs.getStringList('food_cards');

      if (foodCards == null || foodCards.isEmpty) return;

      bool updated = false;
      List<String> updatedCards = [];

      // Find the matching food card
      for (String cardJson in foodCards) {
        try {
          Map<String, dynamic> card = jsonDecode(cardJson);
          String cardName = (card['name'] ?? '')
              .toString()
              .toLowerCase()
              .trim()
              .replaceAll(' ', '_');

          if (cardName == foodName ||
              cardName.contains(foodName) ||
              foodName.contains(cardName)) {
            // Found a matching food card, update its nutrition data
            print(
                'Found matching food card for nutrition update: ${card['name']}');

            // Add vitamin/mineral data to the card
            if (nutritionData.containsKey('vitamins')) {
              card['vitamins'] = nutritionData['vitamins'];
            }
            if (nutritionData.containsKey('minerals')) {
              card['minerals'] = nutritionData['minerals'];
            }
            if (nutritionData.containsKey('other')) {
              card['other'] = nutritionData['other'];
            }

            // Add scan_id if it doesn't exist
            if (!card.containsKey('scan_id')) {
              card['scan_id'] = _scanId;
            }

            // Update the card
            updatedCards.add(jsonEncode(card));
            updated = true;
          } else {
            // Keep unchanged cards
            updatedCards.add(cardJson);
          }
        } catch (e) {
          print('Error processing food card: $e');
          // Keep original card if there's an error
          updatedCards.add(cardJson);
        }
      }

      // Save the updated food cards
      if (updated) {
        await prefs.setStringList('food_cards', updatedCards);
        print('Updated food card with nutrition data');
      }
    } catch (e) {
      print('Error updating food card with nutrition: $e');
    }
  }

  // Load saved nutrition data - ULTRA RELIABLE with global key
  Future<bool> _loadSavedNutritionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ALWAYS try the global permanent key first
      String? savedData = prefs.getString('PERMANENT_GLOBAL_NUTRITION_DATA');

      // If not found by global key, try scan-specific key
      if (savedData == null || savedData.isEmpty) {
        savedData = prefs.getString('food_nutrition_data_$_scanId');
      }

      // Process the data if found by any key
      if (savedData != null && savedData.isNotEmpty) {
        Map<String, dynamic> loadedData = jsonDecode(savedData);

        // Process vitamins data
        if (loadedData.containsKey('vitamins')) {
          Map<String, dynamic> vitaminData = loadedData['vitamins'];
          vitaminData.forEach((key, value) {
            if (!vitamins.containsKey(key)) return;

            double progress = 0.0;
            if (value is Map) {
              if (value.containsKey('progress')) {
                progress = value['progress'] is double
                    ? value['progress']
                    : double.parse(value['progress'].toString());
              }

              Color progressColor = _getColorBasedOnProgress(progress);
              vitamins[key] = NutrientInfo(
                name: value['name'] ?? key,
                value: value['value'] ?? "0/0 g",
                percent: value['percent'] ?? "0%",
                progress: progress,
                progressColor: progressColor,
                hasInfo: value['hasInfo'] == true,
              );
            }
          });
        }

        // Process minerals data
        if (loadedData.containsKey('minerals')) {
          Map<String, dynamic> mineralData = loadedData['minerals'];
          mineralData.forEach((key, value) {
            if (!minerals.containsKey(key)) return;

            double progress = 0.0;
            if (value is Map) {
              if (value.containsKey('progress')) {
                progress = value['progress'] is double
                    ? value['progress']
                    : double.parse(value['progress'].toString());
              }

              Color progressColor = _getColorBasedOnProgress(progress);
              minerals[key] = NutrientInfo(
                name: value['name'] ?? key,
                value: value['value'] ?? "0/0 g",
                percent: value['percent'] ?? "0%",
                progress: progress,
                progressColor: progressColor,
                hasInfo: value['hasInfo'] == true,
              );
            }
          });
        }

        // Process other nutrients data
        if (loadedData.containsKey('other')) {
          Map<String, dynamic> otherData = loadedData['other'];
          otherData.forEach((key, value) {
            if (!other.containsKey(key)) return;

            double progress = 0.0;
            if (value is Map) {
              if (value.containsKey('progress')) {
                progress = value['progress'] is double
                    ? value['progress']
                    : double.parse(value['progress'].toString());
              }

              Color progressColor = _getColorBasedOnProgress(progress);
              other[key] = NutrientInfo(
                name: value['name'] ?? key,
                value: value['value'] ?? "0/0 g",
                percent: value['percent'] ?? "0%",
                progress: progress,
                progressColor: progressColor,
                hasInfo: value['hasInfo'] == true,
              );
            }
          });
        }

        // Immediately re-save to ensure consistent formats
        await _saveNutritionData();

        return true;
      } else if (widget.nutritionData != null &&
          widget.nutritionData!.isNotEmpty) {
        // If no saved data but widget provided data, use that
        _updateNutrientValuesFromData(widget.nutritionData!);

        // Save this data right away
        await _saveNutritionData();
        return true;
      }

      return false;
    } catch (e) {
      print('Error loading saved nutrition data: $e');
      return false;
    }
  }

  // Helper method to process simplified data format
  void _processSimplifiedData(Map<String, dynamic> simplifiedData,
      Map<String, NutrientInfo> targetMap) {
    simplifiedData.forEach((key, value) {
      if (targetMap.containsKey(key)) {
        List<String> parts = value.toString().split('/');
        double currentValue = double.tryParse(parts[0]) ?? 0;
        double targetValue = 0;
        String unit = "g";

        if (parts.length > 1) {
          String rest = parts[1];
          // Extract the target value and unit
          RegExp regex = RegExp(r'(\d+\.?\d*)\s*(\w+)');
          Match? match = regex.firstMatch(rest);
          if (match != null) {
            targetValue = double.tryParse(match.group(1) ?? "0") ?? 0;
            unit = match.group(2) ?? "g";
          }
        }

        double progress = targetValue > 0
            ? (currentValue / targetValue)
            : 0.0; // Removed clamp
        Color progressColor = _getColorBasedOnProgress(progress);

        targetMap[key] = NutrientInfo(
          name: key,
          value: "$currentValue/$targetValue $unit",
          percent: "${(progress * 100).round()}%",
          progress: progress,
          progressColor: progressColor,
        );
      }
    });
  }

  // Helper method to check if data structure seems valid despite ID mismatch
  bool _isMostLikelyValidNutritionData(Map<String, dynamic> data) {
    // Basic validation: ensure it has expected top-level keys
    bool hasExpectedKeys = data.containsKey('vitamins') ||
        data.containsKey('minerals') ||
        data.containsKey('other');

    if (!hasExpectedKeys && data.containsKey('data')) {
      // Check simplified format
      if (data['data'] is Map) {
        Map dataMap = data['data'] as Map;
        hasExpectedKeys = dataMap.containsKey('vitamins') ||
            dataMap.containsKey('minerals') ||
            dataMap.containsKey('other');
      }
    }

    return hasExpectedKeys;
  }

  // Add a helper method to determine color based on progress
  Color _getColorBasedOnProgress(double progress) {
    if (progress < 0.4) {
      return Colors.red; // Red for 0-40%
    } else if (progress < 0.8) {
      return yellowColor; // Yellow for 40-80%
    } else {
      return greenColor; // Green for 80-100%+ (anything above 0.8 is good)
    }
  }

  // Helper method to load personalized vitamin targets from SharedPreferences
  Future<void> _loadPersonalizedVitaminTargets(
      Map<String, Map<String, dynamic>> vitaminInfo) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Update targets from SharedPreferences where available
      for (var entry in vitaminInfo.entries) {
        String dataKey = entry.key;
        Map<String, dynamic> info = entry.value;
        String uiKey = info['key'] as String;
        String prefsKey = uiKey.toLowerCase().replaceAll(' ', '_');

        // Try to load from SharedPreferences - IMPORTANT: Use vitamin_target_X format to match calculation_screen.dart
        double? target = prefs.getDouble('vitamin_target_$prefsKey');

        // If found, update the target in the vitaminInfo map
        if (target != null) {
          vitaminInfo[dataKey]!['target'] = target;
          print(
              'Loaded personalized vitamin target: $uiKey = $target ${info['unit']}');
        } else {
          print(
              'No personalized target found for $uiKey, using default: ${info['target']} ${info['unit']}');
        }
      }
    } catch (e) {
      print('Error loading personalized vitamin targets: $e');
    }
  }

  Future<void> _refreshDisplaysWithPersonalizedTargets() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if we have personalized targets
      String? calculationDate =
          prefs.getString('nutrient_targets_calculation_date');
      if (calculationDate != null) {
        print(
            'Refreshing all displays with personalized targets calculated on: $calculationDate');

        // UPDATE OTHER NUTRIENTS
        // Fiber
        double fiberTarget = prefs.getDouble('nutrient_target_fiber') ?? 30.0;
        if (other.containsKey('Fiber')) {
          double currentValue = _parseCurrentValue(other['Fiber']!.value);
          _updateNutrientDisplay(
              'Fiber', currentValue, fiberTarget, 'g', other);
        }

        // Cholesterol - FIXED to use the proper SharedPreferences key
        double cholesterolTarget =
            prefs.getDouble('nutrient_target_cholesterol') ?? 300.0;
        if (other.containsKey('Cholesterol')) {
          double currentValue = _parseCurrentValue(other['Cholesterol']!.value);
          _updateNutrientDisplay(
              'Cholesterol', currentValue, cholesterolTarget, 'mg', other);
        }

        // Omega-3
        double omega3Target =
            prefs.getDouble('nutrient_target_omega3') ?? 1500.0;
        if (other.containsKey('Omega-3')) {
          double currentValue = _parseCurrentValue(other['Omega-3']!.value);
          _updateNutrientDisplay(
              'Omega-3', currentValue, omega3Target, 'mg', other);
        }

        // Omega-6
        double omega6Target = prefs.getDouble('nutrient_target_omega6') ?? 14.0;
        if (other.containsKey('Omega-6')) {
          double currentValue = _parseCurrentValue(other['Omega-6']!.value);
          _updateNutrientDisplay(
              'Omega-6', currentValue, omega6Target, 'g', other);
        }

        // Saturated Fats
        double saturatedFatTarget =
            prefs.getDouble('nutrient_target_saturated_fat') ?? 22.0;
        if (other.containsKey('Saturated Fats')) {
          double currentValue =
              _parseCurrentValue(other['Saturated Fats']!.value);
          _updateNutrientDisplay(
              'Saturated Fats', currentValue, saturatedFatTarget, 'g', other);
        }

        // UPDATE VITAMINS
        // Process each vitamin using direct target lookup
        vitamins.forEach((key, info) {
          String prefsKey = key.toLowerCase().replaceAll(' ', '_');
          String basicName = prefsKey.replaceAll('vitamin_', '');

          // Try all possible key formats for vitamins
          double? storedTarget;

          // Try direct format with underscores
          storedTarget = prefs.getDouble('vitamin_target_$prefsKey');

          // Try with spaces as saved by calculation_screen.dart
          if (storedTarget == null) {
            storedTarget =
                prefs.getDouble('vitamin_target_${key.toLowerCase()}');
          }

          // Try with basic name and various prefixes
          if (storedTarget == null) {
            for (String prefix in [
              'vitamin_target_',
              'vitamin_target_vitamin_',
              'vitamin_target_vitamin '
            ]) {
              storedTarget = prefs.getDouble('$prefix$basicName');
              if (storedTarget != null) break;
            }
          }

          if (storedTarget != null) {
            // Use the personalized target
            double currentValue = _parseCurrentValue(info.value);
            String unit = key.contains('A') ||
                    key.contains('D') ||
                    key.contains('B7') ||
                    key.contains('B9') ||
                    key.contains('B12') ||
                    key.contains('K')
                ? 'mcg'
                : 'mg';

            _updateNutrientDisplay(
                key, currentValue, storedTarget, unit, vitamins);
            print('Using personalized target for $key: $storedTarget $unit');
          } else {
            // No personalized target found - should never happen if calculation worked correctly
            print(
                'WARNING: No personalized target found for $key, using existing value');
          }
        });

        // UPDATE MINERALS
        // Process each mineral using direct target lookup
        minerals.forEach((key, info) {
          String prefsKey = key.toLowerCase().replaceAll(' ', '_');

          // Try all possible key formats for minerals
          double? storedTarget;

          // Try various prefix formats
          for (String prefix in ['mineral_target_', 'nutrient_target_']) {
            storedTarget = prefs.getDouble('$prefix$prefsKey');
            if (storedTarget != null) break;
          }

          // Try with raw key format
          if (storedTarget == null) {
            storedTarget =
                prefs.getDouble('mineral_target_${key.toLowerCase()}');
          }

          if (storedTarget != null) {
            // Use the personalized target
            double currentValue = _parseCurrentValue(info.value);
            String unit = key == 'Chromium' ||
                    key == 'Copper' ||
                    key == 'Iodine' ||
                    key == 'Molybdenum' ||
                    key == 'Selenium'
                ? 'mcg'
                : 'mg';

            _updateNutrientDisplay(
                key, currentValue, storedTarget, unit, minerals);
            print('Using personalized target for $key: $storedTarget $unit');
          } else {
            // No personalized target found - should never happen if calculation worked correctly
            print(
                'WARNING: No personalized target found for $key, using existing value');
          }
        });

        print(
            'Successfully refreshed all nutrient displays with personalized targets');
      } else {
        print(
            'No personalized targets calculation date found - targets may not be fully personalized');
      }
    } catch (e) {
      print('Error refreshing displays with personalized targets: $e');
    }
  }

  // Helper method to update nutrient displays consistently
  void _updateNutrientDisplay(String key, double currentValue, double target,
      String unit, Map<String, NutrientInfo> nutrientMap) {
    double progress = (currentValue / target); // No clamping
    int percentage = (progress * 100).round();
    Color progressColor = _getColorBasedOnProgress(progress);

    // Format target value based on unit type
    String formattedTarget;
    if (unit == 'mcg' || unit == 'mg') {
      formattedTarget = target.toStringAsFixed(0);
    } else {
      formattedTarget = target.toStringAsFixed(1);
    }

    nutrientMap[key] = NutrientInfo(
        name: key,
        value: "$currentValue/$formattedTarget $unit",
        percent: "$percentage%",
        progress: progress,
        progressColor: progressColor,
        hasInfo: nutrientMap[key]?.hasInfo ?? false);
  }

  // Save nutrition data to food cards list for permanent storage
  Future<void> _saveToFoodCards(
      Map<String, dynamic> nutritionData, String foodName) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get all existing food cards
      List<String> foodCards = prefs.getStringList('food_cards') ?? [];
      List<String> updatedCards = []; // Initialize the list of updated cards
      bool updated = false;

      // Look for the specific food card that matches this scan ID
      for (int i = 0; i < foodCards.length; i++) {
        String cardJson = foodCards[i]; // Store current card JSON for reference
        try {
          Map<String, dynamic> card = jsonDecode(cardJson);

          // Check if this is the card for our current food (by name or ID)
          if ((card.containsKey('name') &&
                  card['name'].toString().toLowerCase() ==
                      foodName.toLowerCase()) ||
              (card.containsKey('scan_id') && card['scan_id'] == _scanId)) {
            // Update the card with our latest nutrition data
            print(
                'Found matching food card for nutrition update: ${card['name']}');

            // Add vitamin/mineral data to the card
            if (nutritionData.containsKey('vitamins')) {
              card['vitamins'] = nutritionData['vitamins'];
            }
            if (nutritionData.containsKey('minerals')) {
              card['minerals'] = nutritionData['minerals'];
            }
            if (nutritionData.containsKey('other')) {
              card['other'] = nutritionData['other'];
            }

            // Add scan_id if it doesn't exist
            if (!card.containsKey('scan_id')) {
              card['scan_id'] = _scanId;
            }

            // Update the card
            updatedCards.add(jsonEncode(card));
            updated = true;
          } else {
            // Keep unchanged cards
            updatedCards.add(cardJson);
          }
        } catch (e) {
          print('Error processing food card: $e');
          // Keep original card if there's an error
          updatedCards.add(cardJson);
        }
      }

      // Save the updated food cards
      if (updated) {
        await prefs.setStringList('food_cards', updatedCards);
        print('Saved updated food cards list with nutrition data');
      }
    } catch (e) {
      print('Error saving to food cards: $e');
    }
  }

  // Helper method to extract an other nutrient value using multiple possible key variants
  void _extractOtherNutrientByVariants(Map<String, dynamic> data,
      String nutrientKey, List<String> possibleKeys) {
    for (String key in possibleKeys) {
      // Check for the key in both original and lowercase forms
      if (data.containsKey(key) || data.containsKey(key.toLowerCase())) {
        String actualKey = data.containsKey(key) ? key : key.toLowerCase();
        double amount = _extractNumericValue(data[actualKey].toString());
        if (amount > 0) {
          _updateOtherNutrientWithValue(nutrientKey, amount);
          print('Found $nutrientKey: $amount using key: $actualKey');
          return; // Stop after the first match
        }
      }
    }
  }

  // Process a single other nutrient safely - prevents one error from affecting others
  void _processSingleOtherNutrient(Map<String, dynamic> data,
      String nutrientKey, List<String> possibleKeys) {
    try {
      _extractOtherNutrientByVariants(data, nutrientKey, possibleKeys);
    } catch (e) {
      print('Error processing nutrient $nutrientKey: $e');
    }
  }
}

// Simple class to hold nutrient info
class NutrientInfo {
  final String name;
  final String value;
  final String percent;
  final double progress;
  final Color progressColor;
  final bool hasInfo;

  NutrientInfo({
    required this.name,
    required this.value,
    required this.percent,
    required this.progress,
    required this.progressColor,
    this.hasInfo = false,
  });
}

class _CheckmarkPainter extends CustomPainter {
  final double size;
  _CheckmarkPainter({this.size = 22});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint circlePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    final Paint checkPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    // Draw circle
    canvas.drawCircle(
        Offset(size.width / 2, size.height / 2), size.width / 2, circlePaint);
    // Draw checkmark
    final Path path = Path();
    path.moveTo(size.width * 0.32, size.height * 0.55);
    path.lineTo(size.width * 0.48, size.height * 0.7);
    path.lineTo(size.width * 0.72, size.height * 0.36);
    canvas.drawPath(path, checkPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
