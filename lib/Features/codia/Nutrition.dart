import 'package:flutter/material.dart';
import '../codia/codia_page.dart' as main_codia;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

// Create a global RouteObserver that will be used by the app
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// BULLETPROOF STATIC NUTRITION DATA MANAGER
// This survives memory pressure, screen rebuilding, and app lifecycle changes
class NutritionDataManager {
  static final Map<String, Map<String, dynamic>> _persistentData = {};
  static Timer? _autoSaveTimer;
  static bool _isInitialized = false;

  // Initialize the manager
  static Future<void> initialize() async {
    if (_isInitialized) return;

    print('🔧 Initializing NutritionDataManager...');

    // Load all existing data from SharedPreferences
    await _loadAllPersistedData();

    // Set up aggressive auto-save every 10 seconds
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _saveAllDataToStorage();
    });

    _isInitialized = true;
    print(
        '✅ NutritionDataManager initialized with ${_persistentData.length} cached entries');
  }

  // Store nutrition data with multiple redundancy layers
  static Future<void> storeNutritionData(
      String scanId,
      Map<String, NutrientInfo> vitamins,
      Map<String, NutrientInfo> minerals,
      Map<String, NutrientInfo> other) async {
    print('💾 STORING nutrition data for scan ID: $scanId');

    // Convert to serializable format
    Map<String, dynamic> serializedData = {
      'scanId': scanId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'vitamins': _serializeNutrients(vitamins),
      'minerals': _serializeNutrients(minerals),
      'other': _serializeNutrients(other),
    };

    // Store in memory (highest priority)
    _persistentData[scanId] = serializedData;

    // Immediately save to SharedPreferences with multiple keys for redundancy
    await _saveToMultipleKeys(scanId, serializedData);

    print(
        '💾 Stored nutrition data with ${vitamins.length + minerals.length + other.length} nutrients');
  }

  // Retrieve nutrition data with fallback mechanisms
  static Future<bool> loadNutritionData(
      String scanId,
      Map<String, NutrientInfo> vitamins,
      Map<String, NutrientInfo> minerals,
      Map<String, NutrientInfo> other) async {
    print('📖 LOADING nutrition data for scan ID: $scanId');

    // Priority 1: Check memory cache
    if (_persistentData.containsKey(scanId)) {
      print('✅ Found data in memory cache');
      return _deserializeAndApply(
          _persistentData[scanId]!, vitamins, minerals, other);
    }

    // Priority 2: Load from SharedPreferences with multiple key attempts
    final prefs = await SharedPreferences.getInstance();

    List<String> possibleKeys = [
      'nutrition_bulletproof_$scanId',
      'nutrition_backup_$scanId',
      'food_nutrition_data_$scanId',
      'nutrition_data_$scanId',
      'PERMANENT_GLOBAL_NUTRITION_DATA',
    ];

    for (String key in possibleKeys) {
      String? dataJson = prefs.getString(key);
      if (dataJson != null && dataJson.isNotEmpty) {
        try {
          Map<String, dynamic> data = jsonDecode(dataJson);
          print('✅ Found data in SharedPreferences key: $key');

          // Store in memory cache for next time
          _persistentData[scanId] = data;

          return _deserializeAndApply(data, vitamins, minerals, other);
        } catch (e) {
          print('❌ Error parsing data from key $key: $e');
          continue;
        }
      }
    }

    print('❌ No nutrition data found for scan ID: $scanId');
    return false;
  }

  // Force save all data to storage
  static Future<void> _saveAllDataToStorage() async {
    if (_persistentData.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      for (String scanId in _persistentData.keys) {
        await _saveToMultipleKeys(scanId, _persistentData[scanId]!);
      }

      print(
          '💾 Auto-saved ${_persistentData.length} nutrition entries to storage');
    } catch (e) {
      print('❌ Error auto-saving nutrition data: $e');
    }
  }

  // Save to multiple keys for redundancy
  static Future<void> _saveToMultipleKeys(
      String scanId, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String dataJson = jsonEncode(data);

      // Save to multiple keys for maximum redundancy
      List<String> keys = [
        'nutrition_bulletproof_$scanId',
        'nutrition_backup_$scanId',
        'food_nutrition_data_$scanId',
        'nutrition_data_$scanId',
      ];

      for (String key in keys) {
        try {
          await prefs.setString(key, dataJson);
        } catch (e) {
          print('⚠️ Failed to save to key $key: $e');
          // Continue with other keys even if one fails
        }
      }

      // Also save as global backup
      try {
        await prefs.setString('PERMANENT_GLOBAL_NUTRITION_DATA', dataJson);
      } catch (e) {
        print('⚠️ Failed to save global backup: $e');
      }
    } catch (e) {
      print('❌ Error saving to multiple keys: $e');
    }
  }

  // Load all persisted data on startup
  static Future<void> _loadAllPersistedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Set<String> allKeys = prefs.getKeys();

      for (String key in allKeys) {
        if (key.startsWith('nutrition_bulletproof_')) {
          String scanId = key.replaceFirst('nutrition_bulletproof_', '');
          String? dataJson = prefs.getString(key);

          if (dataJson != null && dataJson.isNotEmpty) {
            try {
              Map<String, dynamic> data = jsonDecode(dataJson);
              _persistentData[scanId] = data;
            } catch (e) {
              print('⚠️ Error loading persisted data for $scanId: $e');
            }
          }
        }
      }

      print('📖 Loaded ${_persistentData.length} persisted nutrition entries');
    } catch (e) {
      print('❌ Error loading persisted data: $e');
    }
  }

  // Serialize nutrients to JSON-safe format
  static Map<String, dynamic> _serializeNutrients(
      Map<String, NutrientInfo> nutrients) {
    Map<String, dynamic> serialized = {};

    nutrients.forEach((key, nutrient) {
      serialized[key] = {
        'name': nutrient.name,
        'value': nutrient.value,
        'percent': nutrient.percent,
        'progress': nutrient.progress,
        'progressColor': nutrient.progressColor.value,
        'hasInfo': nutrient.hasInfo,
      };
    });

    return serialized;
  }

  // Deserialize and apply to nutrient maps
  static bool _deserializeAndApply(
      Map<String, dynamic> data,
      Map<String, NutrientInfo> vitamins,
      Map<String, NutrientInfo> minerals,
      Map<String, NutrientInfo> other) {
    try {
      // Apply vitamins
      if (data.containsKey('vitamins')) {
        Map<String, dynamic> vitaminData = data['vitamins'];
        vitaminData.forEach((key, value) {
          if (vitamins.containsKey(key)) {
            vitamins[key] = NutrientInfo(
              name: value['name'],
              value: value['value'],
              percent: value['percent'],
              progress: value['progress'],
              progressColor: Color(value['progressColor']),
              hasInfo: value['hasInfo'],
            );
          }
        });
      }

      // Apply minerals
      if (data.containsKey('minerals')) {
        Map<String, dynamic> mineralData = data['minerals'];
        mineralData.forEach((key, value) {
          if (minerals.containsKey(key)) {
            minerals[key] = NutrientInfo(
              name: value['name'],
              value: value['value'],
              percent: value['percent'],
              progress: value['progress'],
              progressColor: Color(value['progressColor']),
              hasInfo: value['hasInfo'],
            );
          }
        });
      }

      // Apply other nutrients
      if (data.containsKey('other')) {
        Map<String, dynamic> otherData = data['other'];
        otherData.forEach((key, value) {
          if (other.containsKey(key)) {
            other[key] = NutrientInfo(
              name: value['name'],
              value: value['value'],
              percent: value['percent'],
              progress: value['progress'],
              progressColor: Color(value['progressColor']),
              hasInfo: value['hasInfo'],
            );
          }
        });
      }

      int restoredCount = 0;
      vitamins.values.forEach((n) => {if (n.progress > 0) restoredCount++});
      minerals.values.forEach((n) => {if (n.progress > 0) restoredCount++});
      other.values.forEach((n) => {if (n.progress > 0) restoredCount++});

      print('✅ Restored $restoredCount non-zero nutrition values');
      return true;
    } catch (e) {
      print('❌ Error deserializing nutrition data: $e');
      return false;
    }
  }

  // Clear data for a specific scan ID (used when ingredients are deleted)
  static Future<void> clearDataForScanId(String scanId) async {
    print('🗑️ CLEARING nutrition data for scan ID: $scanId');

    // Remove from memory
    _persistentData.remove(scanId);

    // Remove from SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> keys = [
        'nutrition_bulletproof_$scanId',
        'nutrition_backup_$scanId',
        'food_nutrition_data_$scanId',
        'nutrition_data_$scanId',
      ];

      for (String key in keys) {
        await prefs.remove(key);
      }

      print('🗑️ Cleared nutrition data for scan ID: $scanId');
    } catch (e) {
      print('❌ Error clearing nutrition data: $e');
    }
  }

  // Dispose method
  static void dispose() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _isInitialized = false;
  }
}

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

    print('🚀 Nutrition screen initialized with scan ID: $_scanId');

    // Initialize default nutrient values
    _initializeDefaultValues();

    // SIMPLE APPROACH: Load data in priority order
    _loadNutritionData();
  }

  // Load nutrition data from SharedPreferences or cache
  Future<void> _loadNutritionData() async {
    print('📖 Loading nutrition data for scan ID: $_scanId');

    // PRIORITY 1: If we have fresh widget data, use it immediately
    if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
      print('🆕 Fresh widget data provided, using it...');
      _updateNutrientValuesFromData(widget.nutritionData!);
      setState(() {
        _dataLoaded = true;
      });
      await _saveNutritionData();
      return;
    }

    // PRIORITY 2: Try to load from NutritionDataManager (memory cache + SharedPreferences)
    bool success = await NutritionDataManager.loadNutritionData(
        _scanId, vitamins, minerals, other);
    if (success) {
      setState(() {
        _dataLoaded = true;
      });
      print('✅ Successfully loaded nutrition data from NutritionDataManager');
      return;
    }

    // PRIORITY 3: Only initialize defaults if no data exists anywhere
    print('❌ No data found, initializing defaults');
    _initializeDefaultValues();
    setState(() {
      _dataLoaded = true;
    });
  }

  // Called when another route is popped and this route shows up
  @override
  void didPopNext() {
    print('🔄 User returned to nutrition screen');

    // Only reload if we have fresh widget data, otherwise keep existing data
    if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
      print('🆕 Fresh widget data available, updating...');
      _updateNutrientValuesFromData(widget.nutritionData!);
      setState(() {
        _dataLoaded = true;
      });
      _saveNutritionData();
    } else {
      print('🔄 No fresh data, keeping existing nutrition values');
      // Don't reload - keep the current data to prevent resets
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.paused:
        if (_dataLoaded) {
          print('📱 App going to background, saving nutrition data...');
          await NutritionDataManager.storeNutritionData(
              _scanId, vitamins, minerals, other);
          await _saveNutritionData();
        }
        break;
      case AppLifecycleState.resumed:
        print('📱 App resumed - keeping existing nutrition data');
        // Don't reload on resume - keep existing data to prevent resets
        break;
      case AppLifecycleState.detached:
        if (_dataLoaded) {
          print('📱 App terminating, emergency save...');
          await NutritionDataManager.storeNutritionData(
              _scanId, vitamins, minerals, other);
          await _saveNutritionData();
        }
        break;
      default:
        break;
    }
  }

  // Helper method to immediately try loading from the global permanent key
  Future<bool> _tryLoadFromGlobalKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();

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

          // Process the data using the simplified update method
          if (loadedData.containsKey('vitamins') ||
              loadedData.containsKey('minerals') ||
              loadedData.containsKey('other')) {
            _updateNutrientValuesFromData(loadedData);

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
    // Save to memory cache before disposing to prevent data loss
    if (_dataLoaded) {
      print('💾 Saving to memory cache before dispose...');
      NutritionDataManager.storeNutritionData(
          _scanId, vitamins, minerals, other);
      _saveNutritionData();
    }

    // Cancel auto-save timer
    _autoSaveTimer?.cancel();

    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Unsubscribe from route observer
    routeObserver.unsubscribe(this);

    super.dispose();
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
          value: '0/100 g',
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

  // Update nutrient values from data provided by SnapFood or other sources
  void _updateNutrientValuesFromData(Map<String, dynamic> data) {
    print('Updating nutrient values from data, keys: ${data.keys.toList()}');

    // Process flat nutrient data directly
    data.forEach((key, value) {
      double amount = _extractNumericValue(value.toString());
      if (amount >= 0) {
        // Map the key to the appropriate nutrient
        if (key.contains('vitamin_a')) {
          _updateVitaminWithValue('Vitamin A', amount);
        } else if (key.contains('vitamin_c')) {
          _updateVitaminWithValue('Vitamin C', amount);
        } else if (key.contains('vitamin_d')) {
          _updateVitaminWithValue('Vitamin D', amount);
        } else if (key.contains('vitamin_e')) {
          _updateVitaminWithValue('Vitamin E', amount);
        } else if (key.contains('vitamin_k')) {
          _updateVitaminWithValue('Vitamin K', amount);
        } else if (key.contains('vitamin_b1')) {
          _updateVitaminWithValue('Vitamin B1', amount);
        } else if (key.contains('vitamin_b2')) {
          _updateVitaminWithValue('Vitamin B2', amount);
        } else if (key.contains('vitamin_b3')) {
          _updateVitaminWithValue('Vitamin B3', amount);
        } else if (key.contains('vitamin_b5')) {
          _updateVitaminWithValue('Vitamin B5', amount);
        } else if (key.contains('vitamin_b6')) {
          _updateVitaminWithValue('Vitamin B6', amount);
        } else if (key.contains('vitamin_b7')) {
          _updateVitaminWithValue('Vitamin B7', amount);
        } else if (key.contains('vitamin_b9')) {
          _updateVitaminWithValue('Vitamin B9', amount);
        } else if (key.contains('vitamin_b12')) {
          _updateVitaminWithValue('Vitamin B12', amount);
        } else if (key.contains('calcium')) {
          _updateMineralWithValue('Calcium', amount);
        } else if (key.contains('chloride')) {
          _updateMineralWithValue('Chloride', amount);
        } else if (key.contains('chromium')) {
          _updateMineralWithValue('Chromium', amount);
        } else if (key.contains('copper')) {
          _updateMineralWithValue('Copper', amount);
        } else if (key.contains('fluoride')) {
          _updateMineralWithValue('Fluoride', amount);
        } else if (key.contains('iodine')) {
          _updateMineralWithValue('Iodine', amount);
        } else if (key.contains('iron')) {
          _updateMineralWithValue('Iron', amount);
        } else if (key.contains('magnesium')) {
          _updateMineralWithValue('Magnesium', amount);
        } else if (key.contains('manganese')) {
          _updateMineralWithValue('Manganese', amount);
        } else if (key.contains('molybdenum')) {
          _updateMineralWithValue('Molybdenum', amount);
        } else if (key.contains('phosphorus')) {
          _updateMineralWithValue('Phosphorus', amount);
        } else if (key.contains('potassium')) {
          _updateMineralWithValue('Potassium', amount);
        } else if (key.contains('selenium')) {
          _updateMineralWithValue('Selenium', amount);
        } else if (key.contains('sodium')) {
          _updateMineralWithValue('Sodium', amount);
        } else if (key.contains('zinc')) {
          _updateMineralWithValue('Zinc', amount);
        } else if (key.contains('fiber')) {
          _updateOtherNutrientWithValue('Fiber', amount);
        } else if (key.contains('cholesterol')) {
          _updateOtherNutrientWithValue('Cholesterol', amount);
        } else if (key.contains('sugar')) {
          _updateOtherNutrientWithValue('Sugar', amount);
        } else if (key.contains('saturated_fats')) {
          _updateOtherNutrientWithValue('Saturated Fats', amount);
        } else if (key.contains('omega_3')) {
          _updateOtherNutrientWithValue('Omega-3', amount);
        } else if (key.contains('omega_6')) {
          _updateOtherNutrientWithValue('Omega-6', amount);
        }
      }
    });
  }

  // Helper method to extract a numeric value from a string
  double _extractNumericValue(String input) {
    try {
      double? directValue = double.tryParse(input);
      if (directValue != null) {
        return directValue;
      }
      RegExp numericRegExp = RegExp(r'(\d+\.?\d*)');
      RegExpMatch? match = numericRegExp.firstMatch(input);
      if (match != null && match.group(1) != null) {
        return double.tryParse(match.group(1)!) ?? 0.0;
      }
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  // Helper method to extract target value from formatted string like "0/700 mcg"
  double _extractTargetValue(String formattedValue) {
    try {
      if (formattedValue.contains('/')) {
        String targetPart = formattedValue.split('/')[1];
        String numericPart = targetPart.replaceAll(RegExp(r'[^0-9.]'), '');
        return double.tryParse(numericPart) ?? 100.0;
      }
      return 100.0;
    } catch (e) {
      return 100.0;
    }
  }

  // Helper method to extract unit from a formatted string like "10/100 mg"
  String _extractUnit(String formattedValue) {
    try {
      List<String> parts = formattedValue.split(' ');
      if (parts.length > 1) {
        return parts.last;
      }
      RegExp unitRegExp = RegExp(r'[a-zA-Z]+');
      RegExpMatch? match = unitRegExp.firstMatch(formattedValue);
      if (match != null) {
        return match.group(0) ?? 'g';
      }
      return 'g';
    } catch (e) {
      return 'g';
    }
  }

  // Helper method to extract current value from a nutrient value string
  double _extractCurrentValue(String valueString) {
    try {
      List<String> parts = valueString.split('/');
      if (parts.isNotEmpty) {
        String currentPart = parts[0].trim();
        String numericString = currentPart.replaceAll(RegExp(r'[^0-9.]'), '');
        return double.tryParse(numericString) ?? 0.0;
      }
    } catch (e) {
      print('Error extracting current value from "$valueString": $e');
    }
    return 0.0;
  }

  // Helper method to update a vitamin with a numeric value
  void _updateVitaminWithValue(String vitaminKey, double currentAmount,
      {bool accumulate = false}) {
    if (vitamins.containsKey(vitaminKey)) {
      double finalAmount = currentAmount;
      if (accumulate) {
        String currentValue = vitamins[vitaminKey]!.value;
        double existingAmount = _extractCurrentValue(currentValue);
        finalAmount = existingAmount + currentAmount;
        finalAmount = finalAmount < 0 ? 0 : finalAmount;
      }

      String currentValue = vitamins[vitaminKey]!.value;
      String unit = _extractUnit(currentValue);
      double targetValue = _extractTargetValue(currentValue);
      double progress = targetValue > 0 ? (finalAmount / targetValue) : 0;
      int percentage = (progress * 100).round();
      Color progressColor = _getColorBasedOnProgress(progress);

      if (mounted) {
        setState(() {
          vitamins[vitaminKey] = NutrientInfo(
              name: vitaminKey,
              value:
                  "${finalAmount.toStringAsFixed(1)}/${targetValue.toStringAsFixed(1)} $unit",
              percent: "$percentage%",
              progress: progress,
              progressColor: progressColor);
        });
      }
    }
  }

  // Helper method to update a mineral with a numeric value
  void _updateMineralWithValue(String mineralKey, double currentAmount,
      {bool accumulate = false}) {
    if (minerals.containsKey(mineralKey)) {
      double finalAmount = currentAmount;
      if (accumulate) {
        String currentValue = minerals[mineralKey]!.value;
        double existingAmount = _extractCurrentValue(currentValue);
        finalAmount = existingAmount + currentAmount;
        finalAmount = finalAmount < 0 ? 0 : finalAmount;
      }

      String currentValue = minerals[mineralKey]!.value;
      String unit = _extractUnit(currentValue);
      double targetValue = _extractTargetValue(currentValue);
      double progress = targetValue > 0 ? (finalAmount / targetValue) : 0;
      int percentage = (progress * 100).round();
      Color progressColor = _getColorBasedOnProgress(progress);

      if (mounted) {
        setState(() {
          minerals[mineralKey] = NutrientInfo(
              name: mineralKey,
              value:
                  "${finalAmount.toStringAsFixed(1)}/${targetValue.toStringAsFixed(1)} $unit",
              percent: "$percentage%",
              progress: progress,
              progressColor: progressColor);
        });
      }
    }
  }

  // Helper method to update another nutrient with a numeric value
  void _updateOtherNutrientWithValue(String nutrientKey, double currentAmount,
      {bool accumulate = false}) {
    if (other.containsKey(nutrientKey)) {
      double finalAmount = currentAmount;
      if (accumulate) {
        String currentValue = other[nutrientKey]!.value;
        double existingAmount = _extractCurrentValue(currentValue);
        finalAmount = existingAmount + currentAmount;
        finalAmount = finalAmount < 0 ? 0 : finalAmount;
      }

      String currentValue = other[nutrientKey]!.value;
      String unit = _extractUnit(currentValue);
      double targetValue = _extractTargetValue(currentValue);
      double progress = targetValue > 0 ? (finalAmount / targetValue) : 0;
      int percentage = (progress * 100).round();
      Color progressColor = _getColorBasedOnProgress(progress);

      if (mounted) {
        setState(() {
          other[nutrientKey] = NutrientInfo(
              name: nutrientKey,
              value:
                  "${finalAmount.toStringAsFixed(1)}/${targetValue.toStringAsFixed(1)} $unit",
              percent: "$percentage%",
              progress: progress,
              progressColor: progressColor);
        });
      }
    }
  }

  // Add a helper method to determine color based on progress
  Color _getColorBasedOnProgress(double progress) {
    if (progress < 0.4) {
      return Colors.red;
    } else if (progress < 0.8) {
      return yellowColor;
    } else {
      return greenColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }

  int _countNonZeroValues(Map<String, NutrientInfo> nutrientMap) {
    return nutrientMap.values
        .where((nutrient) => nutrient.progress >= 1.0)
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
                          // Info dialog implementation
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
                          // Value
                          Expanded(
                            flex: 2,
                            child: Text(
                              nutrient.value,
                              style: const TextStyle(
                                fontSize: 13,
                                fontFamily: 'SF Pro',
                                color: Colors.black,
                              ),
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
                          value: nutrient.progress.clamp(0.0, 1.0),
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

  // Save nutrition data - SIMPLE VERSION
  Future<void> _saveNutritionData() async {
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

      // Convert to JSON
      String dataJson = jsonEncode(nutritionData);

      // Save to multiple keys for redundancy
      await prefs.setString('PERMANENT_GLOBAL_NUTRITION_DATA', dataJson);
      await prefs.setString('nutrition_data_$_scanId', dataJson);

      print('Saved nutrition data for ID: $_scanId');
    } catch (e) {
      print('Error saving nutrition data: $e');
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
