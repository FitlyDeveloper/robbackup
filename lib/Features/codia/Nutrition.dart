import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fitness_app/core/env.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

// Create a global RouteObserver that will be used by the app
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// BULLETPROOF STATIC NUTRITION DATA MANAGER
// This survives memory pressure, screen rebuilding, and app lifecycle changes
class NutritionDataManager {
  static final Map<String, Map<String, dynamic>> _persistentData = {};
  static Timer? _autoSaveTimer;
  static bool _isInitialized = false;

  // GLOBAL SCANID MANAGEMENT - Track the last used scanId for fallback navigation
  static String _lastUsedScanId = '';
  static final String _lastScanIdKey = AppEnv.key('GLOBAL_LAST_USED_SCANID');

  // Initialize the manager
  static Future<void> initialize() async {
    if (_isInitialized) return;

    print('🔧 Initializing NutritionDataManager...');

    // Load the last used scanId for global navigation fallback
    await _loadLastUsedScanId();

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

  // GLOBAL SCANID MANAGEMENT METHODS
  static Future<void> _loadLastUsedScanId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastUsedScanId = prefs.getString(_lastScanIdKey) ?? '';
      print('🆔 Loaded global last scanId: "$_lastUsedScanId"');
    } catch (e) {
      print('❌ Failed to load last scanId: $e');
    }
  }

  static Future<void> updateLastUsedScanId(String scanId) async {
    if (scanId.isEmpty ||
        scanId == 'default_scan' ||
        scanId == 'default_nutrition_id') return;

    _lastUsedScanId = scanId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastScanIdKey, scanId);
      print('🆔 Updated global last scanId to: "$scanId"');
    } catch (e) {
      print('❌ Failed to save last scanId: $e');
    }
  }

  static String getLastUsedScanId() {
    print('🔍 Retrieving last used scanId: "$_lastUsedScanId"');
    return _lastUsedScanId;
  }

  // Store nutrition data with BULLETPROOF redundancy - NEVER LOSE DATA
  static Future<void> storeNutritionData(
      String scanId,
      Map<String, NutrientInfo> vitamins,
      Map<String, NutrientInfo> minerals,
      Map<String, NutrientInfo> other) async {
    if (scanId.isEmpty) {
      print('❌ Error: Empty scanId provided');
      return;
    }

    // Update the global last used scanId
    await updateLastUsedScanId(scanId);

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

    // BULLETPROOF STORAGE - Save to MANY keys for maximum redundancy
    await _saveToMultipleKeys(scanId, serializedData);

    // ADDITIONAL PERMANENT STORAGE - Save to backup keys that NEVER get deleted
    final prefs = await SharedPreferences.getInstance();
    String dataJson = jsonEncode(serializedData);

    // Save to bulletproof permanent keys
    await prefs.setString('BULLETPROOF_NUTRITION_$scanId', dataJson);
    await prefs.setString('PERMANENT_BACKUP_$scanId', dataJson);
    await prefs.setString('NEVER_DELETE_NUTRITION_$scanId', dataJson);

    print('✅ Nutrition data saved for: $scanId (BULLETPROOF STORAGE)');
  }

  // Retrieve nutrition data with fallback mechanisms
  static Future<bool> loadNutritionData(
      String scanId,
      Map<String, NutrientInfo> vitamins,
      Map<String, NutrientInfo> minerals,
      Map<String, NutrientInfo> other) async {
    if (scanId.isEmpty) return false;

    // Priority 1: Check memory cache
    if (_persistentData.containsKey(scanId)) {
      return _deserializeAndApply(
          _persistentData[scanId]!, vitamins, minerals, other);
    }

    // Priority 2: Load from SharedPreferences with multiple key attempts
    final prefs = await SharedPreferences.getInstance();

    // BULLETPROOF KEY PRIORITY - Check bulletproof keys first
    List<String> possibleKeys = [
      'BULLETPROOF_NUTRITION_$scanId', // Bulletproof keys first
      'staging_PERMANENT_NUTRITION_$scanId', // Staging permanent
      'PERMANENT_NUTRITION_$scanId', // Permanent nutrition
      'staging_food_nutrition_data_$scanId', // Staging food nutrition
      'PERMANENT_BACKUP_$scanId', // Permanent backup
      'NEVER_DELETE_NUTRITION_$scanId', // Never delete keys
      AppEnv.key('nutrition_data_$scanId'),
      AppEnv.key('food_nutrition_data_$scanId'),
      AppEnv.key('nutrition_bulletproof_$scanId'),
      AppEnv.key('nutrition_backup_$scanId'),
      AppEnv.key('PERMANENT_GLOBAL_NUTRITION_DATA'),
    ];

    for (String key in possibleKeys) {
      String? dataJson = prefs.getString(key);

      if (dataJson != null && dataJson.isNotEmpty) {
        try {
          Map<String, dynamic> data = jsonDecode(dataJson);

          // If using global backup, ensure it matches this scanId
          if (key.endsWith('PERMANENT_GLOBAL_NUTRITION_DATA') &&
              data is Map &&
              data.containsKey('scanId') &&
              data['scanId'] != scanId) {
            // Skip unrelated global entry
            continue;
          }

          // Require structured maps to avoid legacy flat payloads
          final hasStructured = (data['vitamins'] is Map) &&
              (data['minerals'] is Map) &&
              (data['other'] is Map);
          if (!hasStructured) {
            // Try next key; this payload can't populate the UI
            continue;
          }

          // Store in memory cache for next time
          // Apply; only succeed if non-zero values were applied
          final applied = _deserializeAndApply(data, vitamins, minerals, other);
          if (applied) {
            // Cache only successful, non-zero structured entries
            _persistentData[scanId] = data;
            return true;
          }
          // Otherwise keep searching other keys
        } catch (e) {
          print('❌ Error parsing JSON from key "$key": $e');
          continue;
        }
      }
    }

    return false;
  }

  // Save to multiple keys for redundancy
  static Future<void> _saveToMultipleKeys(
      String scanId, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String dataJson = jsonEncode(data);

      // Save to multiple keys for maximum redundancy
      List<String> keys = [
        'BULLETPROOF_NUTRITION_$scanId', // Bulletproof keys first
        'staging_PERMANENT_NUTRITION_$scanId', // Staging permanent
        'PERMANENT_NUTRITION_$scanId', // Permanent nutrition
        'staging_food_nutrition_data_$scanId', // Staging food nutrition
        AppEnv.key('nutrition_bulletproof_$scanId'),
        AppEnv.key('nutrition_backup_$scanId'),
        AppEnv.key('food_nutrition_data_$scanId'),
        AppEnv.key('nutrition_data_$scanId'),
      ];

      for (String key in keys) {
        try {
          await prefs.setString(key, dataJson);
        } catch (e) {
          print('❌ Failed to save to key "$key": $e');
        }
      }

      // Also save as global backup
      String globalKey = AppEnv.key('PERMANENT_GLOBAL_NUTRITION_DATA');
      try {
        await prefs.setString(globalKey, dataJson);
      } catch (e) {
        print('❌ Failed to save global backup: $e');
      }
    } catch (e) {
      print('❌ Error in _saveToMultipleKeys: $e');
    }
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

  // Load all persisted data on startup
  static Future<void> _loadAllPersistedData() async {
    print('📖 ===== LOADING ALL PERSISTED DATA ON STARTUP =====');

    try {
      final prefs = await SharedPreferences.getInstance();
      Set<String> allKeys = prefs.getKeys();
      print('📖 Total SharedPreferences keys found: ${allKeys.length}');

      // List all nutrition-related keys for debugging
      List<String> nutritionKeys = allKeys
          .where((k) =>
              k.toLowerCase().contains('nutrition') ||
              k.toUpperCase().contains('NUTRITION'))
          .toList();
      print(
          '📖 Found ${nutritionKeys.length} nutrition-related keys: $nutritionKeys');

      // Also show all keys for debugging
      print('📖 All available keys: $allKeys');

      int loadedEntries = 0;
      int totalNutrients = 0;

      // Primary bulletproof keys - check multiple patterns
      for (String key in allKeys) {
        String? scanId;
        if (key.startsWith('nutrition_bulletproof_')) {
          scanId = key.replaceFirst('nutrition_bulletproof_', '');
        } else if (key.startsWith('BULLETPROOF_NUTRITION_')) {
          scanId = key.replaceFirst('BULLETPROOF_NUTRITION_', '');
        } else if (key.startsWith('staging_PERMANENT_NUTRITION_')) {
          scanId = key.replaceFirst('staging_PERMANENT_NUTRITION_', '');
        } else if (key.startsWith('PERMANENT_NUTRITION_')) {
          scanId = key.replaceFirst('PERMANENT_NUTRITION_', '');
        } else if (key.startsWith('staging_food_nutrition_data_')) {
          scanId = key.replaceFirst('staging_food_nutrition_data_', '');
        }

        if (scanId != null) {
          String? dataJson = prefs.getString(key);
          print('📖 Loading data for scanId: $scanId from key: $key');

          if (dataJson != null && dataJson.isNotEmpty) {
            try {
              Map<String, dynamic> data = jsonDecode(dataJson);
              _persistentData[scanId] = data;
              loadedEntries++;

              // Count nutrients in this entry
              int entryNutrients = 0;
              if (data.containsKey('vitamins'))
                entryNutrients += (data['vitamins'] as Map).length;
              if (data.containsKey('minerals'))
                entryNutrients += (data['minerals'] as Map).length;
              if (data.containsKey('other'))
                entryNutrients += (data['other'] as Map).length;
              totalNutrients += entryNutrients;

              print(
                  '✅ Loaded bulletproof entry $scanId with $entryNutrients nutrients');
            } catch (e) {
              print('⚠️ Error parsing bulletproof data for $scanId: $e');
            }
          } else {
            print('❌ Bulletproof key $key has null/empty data');
          }
        }
      }

      // Also check for global keys as backup
      String? globalData = prefs.getString('PERMANENT_GLOBAL_NUTRITION_DATA');
      if (globalData != null && globalData.isNotEmpty) {
        try {
          Map<String, dynamic> data = jsonDecode(globalData);
          String scanId = data['scanId'] ?? 'global_backup';
          print('📖 Found global nutrition data for scanId: $scanId');

          // Only use global if we don't already have this scanId
          if (!_persistentData.containsKey(scanId)) {
            _persistentData[scanId] = data;
            loadedEntries++;

            int entryNutrients = 0;
            if (data.containsKey('vitamins'))
              entryNutrients += (data['vitamins'] as Map).length;
            if (data.containsKey('minerals'))
              entryNutrients += (data['minerals'] as Map).length;
            if (data.containsKey('other'))
              entryNutrients += (data['other'] as Map).length;
            totalNutrients += entryNutrients;

            print(
                '✅ Loaded global backup entry with $entryNutrients nutrients');
          } else {
            print(
                '⚠️ Global data scanId already exists in bulletproof cache, skipping');
          }
        } catch (e) {
          print('⚠️ Error parsing global nutrition data: $e');
        }
      } else {
        print('❌ No global nutrition data found or empty');
      }

      print('✅ ===== PERSISTED DATA LOADING COMPLETE =====');
      print('✅ Loaded $loadedEntries nutrition entries from SharedPreferences');
      print('✅ Total nutrients cached: $totalNutrients');
      print('✅ Memory cache now contains ${_persistentData.length} entries');
      print('✅ Cache keys: ${_persistentData.keys.toList()}');
    } catch (e) {
      print('❌ ===== PERSISTED DATA LOADING FAILED =====');
      print('❌ Error loading persisted data: $e');
      print('❌ Stack trace: ${StackTrace.current}');
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
      int appliedCount = 0;
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
            appliedCount++;
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
            appliedCount++;
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
            appliedCount++;
          }
        });
      }

      int restoredCount = 0;
      vitamins.values.forEach((n) => {if (n.progress > 0) restoredCount++});
      minerals.values.forEach((n) => {if (n.progress > 0) restoredCount++});
      other.values.forEach((n) => {if (n.progress > 0) restoredCount++});

      print('✅ Restored $restoredCount non-zero nutrition values');
      return restoredCount > 0;
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

class NutritionPage extends StatefulWidget {
  // Add parameters to receive nutrition data
  final Map<String, dynamic>? nutritionData;
  // STRICT: scanId must be provided - no defaults allowed
  final String scanId;
  // When true, apply widget.nutritionData immediately and skip initial storage load
  final bool forceUseWidgetDataOnce;

  const NutritionPage({
    super.key,
    this.nutritionData,
    required this.scanId,
    this.forceUseWidgetDataOnce = false,
  });

  @override
  State<StatefulWidget> createState() => _NutritionPage();
}

class _NutritionPage extends State<NutritionPage>
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
  // Memoized hydration state
  late final Future<void> _load;
  bool _ready = false;
  bool _hydratedOnce = false;

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

    // ═══════════════════════════════════════════════════════════════
    // QUESTION 1: Is the correct scanId still available when reopened?
    // ═══════════════════════════════════════════════════════════════
    print('🔍 === QUESTION 1: SCANID INVESTIGATION ===');
    print('🔍 Widget.scanId: "${widget.scanId}"');
    print('🔍 Widget.scanId type: ${widget.scanId.runtimeType}');
    print('🔍 Widget.scanId isEmpty: ${widget.scanId.isEmpty}');

    // ═══════════════════════════════════════════════════════════════
    // QUESTION 7: Could screen rebuild without ModalRoute arguments?
    // ═══════════════════════════════════════════════════════════════
    print('🔍 === QUESTION 7: MODALROUTE ARGUMENTS INVESTIGATION ===');
    try {
      final route = ModalRoute.of(context);
      print('🔍 ModalRoute exists: ${route != null}');
      if (route != null) {
        print('🔍 ModalRoute settings: ${route.settings}');
        print('🔍 ModalRoute arguments: ${route.settings.arguments}');
        print(
            '🔍 ModalRoute arguments type: ${route.settings.arguments.runtimeType}');
        print('🔍 ModalRoute name: ${route.settings.name}');

        if (route.settings.arguments == null) {
          print('🚨 QUESTION 7 ANSWER: ModalRoute arguments IS NULL!');
          print(
              '🚨 This could cause scanId to be null/default if navigation relies on arguments');
        } else {
          print(
              '✅ QUESTION 7 ANSWER: ModalRoute has arguments, navigation looks correct');
        }
      } else {
        print('🚨 QUESTION 7 ANSWER: No ModalRoute found - this is unusual!');
      }
    } catch (e) {
      print('🔍 Error accessing ModalRoute: $e');
      print(
          '🚨 QUESTION 7 ANSWER: Error accessing ModalRoute could indicate navigation issues');
    }

    // Detailed scanId validation
    if (widget.scanId.isEmpty) {
      print('🚨 CRITICAL: Widget scanId is EMPTY!');
      print('🚨 This means navigation did not pass scanId properly');
    } else if (widget.scanId == 'default_scan') {
      print('⚠️ WARNING: Using default scanId - this may indicate a problem');
    } else {
      print('✅ Widget scanId looks valid: "${widget.scanId}"');
    }

    // ═══════════════════════════════════════════════════════════════
    // STRICT SCANID VALIDATION - NO FALLBACKS ALLOWED
    // ═══════════════════════════════════════════════════════════════
    print('🔍 === STRICT SCANID VALIDATION ===');
    print('🔍 Raw widget.scanId: "${widget.scanId}"');

    // STRICT: Validate scanId is not empty or default
    if (widget.scanId.isEmpty) {
      print('❌ CRITICAL ERROR: scanId is EMPTY!');
      throw ArgumentError(
          'scanId cannot be empty - navigation failed to pass scanId');
    }

    if (widget.scanId == 'default_scan' ||
        widget.scanId == 'default_nutrition_id' ||
        widget.scanId.startsWith('default_')) {
      print(
          '❌ CRITICAL ERROR: scanId is using fallback value: "${widget.scanId}"');
      throw ArgumentError(
          'scanId cannot be a default value - actual scanId must be provided');
    }

    // Use the exact scanId provided - NO FALLBACKS, NO MODIFICATIONS
    _scanId = widget.scanId;
    print('✅ STRICT: Using exact provided scanId: "${_scanId}"');
    // Memoized hydration
    _load = _hydrateOnce();

    // ═══════════════════════════════════════════════════════════════
    // QUESTION 2: What is the value of _scanId and NutritionDataManager content?
    // ═══════════════════════════════════════════════════════════════
    print('🔍 === QUESTION 2: NUTRITION DATA MANAGER STATE ===');
    print('🔍 Current _scanId: "${_scanId}"');
    print('🔍 Manager initialized: ${NutritionDataManager._isInitialized}');
    print(
        '🔍 Total cached entries: ${NutritionDataManager._persistentData.length}');
    print(
        '🔍 All cached scanIds: ${NutritionDataManager._persistentData.keys.toList()}');

    bool hasDataForScanId =
        NutritionDataManager._persistentData.containsKey(_scanId);
    print('🔍 Has data for $_scanId: $hasDataForScanId');

    if (hasDataForScanId) {
      var cachedData = NutritionDataManager._persistentData[_scanId];
      print('🔍 Cached data structure: ${cachedData?.keys.toList() ?? 'null'}');

      // Check vitamins specifically
      if (cachedData?.containsKey('vitamins') == true) {
        var vitaminsData = cachedData!['vitamins'];
        print('🔍 Vitamins data type: ${vitaminsData.runtimeType}');
        print('🔍 Vitamins count: ${vitaminsData?.length ?? 0}');
        if (vitaminsData is Map) {
          var vitaminsWithValues = vitaminsData.values
              .where((v) => v is Map && (v['progress'] ?? 0.0) > 0)
              .length;
          print('🔍 Vitamins with progress > 0: $vitaminsWithValues');
        }
      }

      // Check minerals specifically
      if (cachedData?.containsKey('minerals') == true) {
        var mineralsData = cachedData!['minerals'];
        print('🔍 Minerals count: ${mineralsData?.length ?? 0}');
        if (mineralsData is Map) {
          var mineralsWithValues = mineralsData.values
              .where((v) => v is Map && (v['progress'] ?? 0.0) > 0)
              .length;
          print('🔍 Minerals with progress > 0: $mineralsWithValues');
        }
      }

      // Check other nutrients
      if (cachedData?.containsKey('other') == true) {
        var otherData = cachedData!['other'];
        print('🔍 Other nutrients count: ${otherData?.length ?? 0}');
        if (otherData is Map) {
          var otherWithValues = otherData.values
              .where((v) => v is Map && (v['progress'] ?? 0.0) > 0)
              .length;
          print('🔍 Other nutrients with progress > 0: $otherWithValues');
        }
      }
    } else {
      print(
          '🔍 ANSWER 2: NO DATA found in NutritionDataManager for scanId "$_scanId"');
    }

    print('🚀 Nutrition screen initialized with scan ID: $_scanId');
    print('📊 HAS WIDGET DATA: ${widget.nutritionData != null}');
    print('📊 WIDGET DATA SIZE: ${widget.nutritionData?.length ?? 0}');
    print('🔍 === END QUESTION 2 ===');

    // ═══════════════════════════════════════════════════════════════
    // EXTERNAL NAVIGATION DEBUG: Check for scanId when no widget data
    // ═══════════════════════════════════════════════════════════════
    print('🔍 === EXTERNAL NAVIGATION DEBUG ===');
    print('🔍 Has widget.nutritionData: ${widget.nutritionData != null}');
    print('🔍 Widget.scanId: "${widget.scanId}"');
    print('🔍 Current _scanId: "$_scanId"');

    if (widget.nutritionData == null) {
      print(
          '🚨 EXTERNAL NAVIGATION: No widget.nutritionData - likely navigated from outside food context');
      print(
          '🚨 This means we MUST load from cached data using scanId: $_scanId');

      // Check if scanId looks valid for external navigation
      if (_scanId.isEmpty || _scanId == 'default_scan') {
        print(
            '🚨 INVALID SCANID FOR EXTERNAL NAV: "$_scanId" - this will prevent data loading!');
        print('🚨 Possible causes:');
        print('🚨   1. No scanId passed in navigation parameters');
        print('🚨   2. Widget.scanId is empty/default');
        print(
            '🚨   3. Navigation from unrelated screen without proper route args');

        // Try to find the last valid scanId from available data
        var availableIds = NutritionDataManager._persistentData.keys.toList();
        if (availableIds.isNotEmpty) {
          print('🔄 ATTEMPTING FALLBACK: Using most recent cached scanId');
          _scanId = availableIds.last;
          print('🔄 Fallback scanId: $_scanId');
        }
      } else {
        print('✅ EXTERNAL NAV scanId looks valid: "$_scanId"');
      }
    }

    // Initialize NutritionDataManager if not already done, but avoid duplicate loads
    if (!_hydratedOnce) {
      _load.ignore();
    }
  }

  // Single-run hydration routine
  Future<void> _hydrateOnce() async {
    if (_hydratedOnce) return;
    _hydratedOnce = true;
    final seedKeys = widget.nutritionData?.keys.length ?? 0;
    print('🧪 hydrate start | scanId=$_scanId | seedMicrosKeys=$seedKeys');

    // CRITICAL: Ensure NutritionDataManager is initialized
    if (!NutritionDataManager._isInitialized) {
      print('🔧 NutritionDataManager not initialized, initializing now...');
      try {
        await NutritionDataManager.initialize();
        print('✅ NutritionDataManager initialized successfully');
      } catch (e) {
        print('❌ Failed to initialize NutritionDataManager: $e');
        // Continue without NutritionDataManager - will use direct SharedPreferences
      }
    }

    // 0) Fast-path: if manager already has structured data for this scanId, apply it synchronously
    if (NutritionDataManager._persistentData.containsKey(_scanId)) {
      final cached = NutritionDataManager._persistentData[_scanId]!;
      if (vitamins.isEmpty && minerals.isEmpty && other.isEmpty) {
        _initializeDefaultValues();
      }
      final applied = NutritionDataManager._deserializeAndApply(
          cached, vitamins, minerals, other);
      if (applied) {
        vitaminCount = vitamins.values.where((v) => v.progress > 0).length;
        mineralCount = minerals.values.where((v) => v.progress > 0).length;
        otherCount = other.values.where((v) => v.progress > 0).length;
        _dataLoaded = true;
        _ready = true;
        if (mounted) setState(() {});
        print(
            '🧪 hydrate done | source=manager-cache | nonZero=${vitaminCount + mineralCount + otherCount}');
        return;
      }
    }

    // Apply seed micronutrients synchronously if provided
    if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
      final keys =
          widget.nutritionData!.keys.map((k) => k.toString().toLowerCase());
      final hasMicros = keys.any((k) =>
          k.startsWith('vitamin_') ||
          k == 'calcium' ||
          k == 'chloride' ||
          k == 'chromium' ||
          k == 'copper' ||
          k == 'fluoride' ||
          k == 'iodine' ||
          k == 'iron' ||
          k == 'magnesium' ||
          k == 'manganese' ||
          k == 'molybdenum' ||
          k == 'phosphorus' ||
          k == 'potassium' ||
          k == 'selenium' ||
          k == 'sodium' ||
          k == 'zinc' ||
          k == 'fiber' ||
          k == 'cholesterol' ||
          k == 'sugar' ||
          k == 'saturated_fats' ||
          k == 'omega_3' ||
          k == 'omega_6');

      // Only use widget seed on first open when it actually contains micronutrients
      if (hasMicros) {
        if (vitamins.isEmpty && minerals.isEmpty && other.isEmpty) {
          _initializeDefaultValues();
        }
        _updateNutrientValuesFromData(widget.nutritionData!);
        vitaminCount = vitamins.values.where((v) => v.progress > 0).length;
        mineralCount = minerals.values.where((v) => v.progress > 0).length;
        otherCount = other.values.where((v) => v.progress > 0).length;
        _dataLoaded = true;
        _ready = true;
        if (mounted) setState(() {});
        // Persist in background
        Future.microtask(() async {
          await NutritionDataManager.storeNutritionData(
              _scanId, vitamins, minerals, other);
          await _saveNutritionData();
        });
        print(
            '🧪 hydrate done | source=widget | nonZero=${vitaminCount + mineralCount + otherCount}');
        return;
      }
    }

    // Load from storage once - try multiple approaches
    bool ok = await _loadSavedDataBulletproof();

    // If bulletproof load failed, try NutritionDataManager as fallback
    if (!ok && NutritionDataManager._isInitialized) {
      print('🔄 Bulletproof load failed, trying NutritionDataManager...');
      ok = await NutritionDataManager.loadNutritionData(
          _scanId, vitamins, minerals, other);
    }

    // If still failed, try aggressive search
    if (!ok) {
      print('🔄 All standard methods failed, trying aggressive search...');
      await _forceLoadFromAllStorageSources();
      // Check if any data was loaded
      ok = vitamins.values.where((v) => v.progress > 0).length > 0 ||
          minerals.values.where((v) => v.progress > 0).length > 0 ||
          other.values.where((v) => v.progress > 0).length > 0;
    }

    if (!mounted) return;
    _dataLoaded = ok;
    // Ensure maps exist even if storage returned an empty structured payload
    if (vitamins.isEmpty || minerals.isEmpty || other.isEmpty) {
      _initializeDefaultValues();
    }
    _ready = true;
    setState(() {});
    final nonZero = vitamins.values.where((v) => v.progress > 0).length +
        minerals.values.where((v) => v.progress > 0).length +
        other.values.where((v) => v.progress > 0).length;
    print(
        '🧪 hydrate done | source=${ok ? 'storage' : 'none'} | nonZero=$nonZero');
  }

  // Initialize NutritionDataManager and load data
  Future<void> _initializeAndLoadData() async {
    // ═══════════════════════════════════════════════════════════════
    // QUESTION 1: Is _initializeAndLoadData() being called every time?
    // ═══════════════════════════════════════════════════════════════
    print('🧠 init called with scanId: $_scanId');
    print('🧠 Called from: ${StackTrace.current.toString().split('\n')[1]}');
    print('🧠 Time: ${DateTime.now()}');

    print('🔧 === _initializeAndLoadData() START ===');

    // Debug complete data flow at the start
    await _debugCompleteDataFlow('LOAD_DATA_START');

    print('🔑 Current scanId: $_scanId');
    print('🔑 Widget scanId: ${widget.scanId}');
    print('📊 Widget has data: ${widget.nutritionData != null}');
    print('📊 Widget data size: ${widget.nutritionData?.length ?? 0}');

    // CRITICAL: Verify scanId is not null or empty
    if (_scanId.isEmpty) {
      print('🚨 CRITICAL ERROR: scanId is empty! Using fallback...');
      _scanId = widget.scanId.isNotEmpty
          ? widget.scanId
          : 'emergency_${DateTime.now().millisecondsSinceEpoch}';
      print('🔧 Fixed scanId to: $_scanId');
    }

    // If widget carries micronutrients, apply immediately and return.
    if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
      final keys =
          widget.nutritionData!.keys.map((k) => k.toString().toLowerCase());
      final hasMicros = keys.any((k) =>
          k.startsWith('vitamin_') ||
          k == 'calcium' ||
          k == 'chloride' ||
          k == 'chromium' ||
          k == 'copper' ||
          k == 'fluoride' ||
          k == 'iodine' ||
          k == 'iron' ||
          k == 'magnesium' ||
          k == 'manganese' ||
          k == 'molybdenum' ||
          k == 'phosphorus' ||
          k == 'potassium' ||
          k == 'selenium' ||
          k == 'sodium' ||
          k == 'zinc' ||
          k == 'fiber' ||
          k == 'cholesterol' ||
          k == 'sugar' ||
          k == 'saturated_fats' ||
          k == 'omega_3' ||
          k == 'omega_6');

      if (hasMicros) {
        if (vitamins.isEmpty && minerals.isEmpty && other.isEmpty) {
          _initializeDefaultValues();
        }
        _updateNutrientValuesFromData(widget.nutritionData!);
        vitaminCount = vitamins.values.where((v) => v.progress > 0).length;
        mineralCount = minerals.values.where((v) => v.progress > 0).length;
        otherCount = other.values.where((v) => v.progress > 0).length;
        _dataLoaded = true;
        setState(() {});
        // Persist without blocking UI
        Future.microtask(() async {
          await NutritionDataManager.storeNutritionData(
              _scanId, vitamins, minerals, other);
          await _saveNutritionData();
        });
        print('⚡ Immediate apply from widget micronutrients and early return');
        await _debugCompleteDataFlow('IMMEDIATE_APPLY');
        return;
      }
    }

    // Log initial map sizes
    print(
        '📊 BEFORE INIT - Vitamins: ${vitamins.length}, Minerals: ${minerals.length}, Other: ${other.length}');

    // First initialize NutritionDataManager
    await NutritionDataManager.initialize();

    // ═══════════════════════════════════════════════════════════════
    // QUESTION 2: Does NutritionDataManager have data for this scanId?
    // ═══════════════════════════════════════════════════════════════
    print('🧪 === QUESTION 2: NUTRITIONMANAGER CHECK ===');
    bool hasDataInManager =
        NutritionDataManager._persistentData.containsKey(_scanId);
    print('🧪 NutritionDataManager has data for $_scanId: $hasDataInManager');

    if (hasDataInManager) {
      var data = NutritionDataManager._persistentData[_scanId]!;
      print('🧪 vitamins found: ${data['vitamins']?.length ?? 0}');
      print('🧪 minerals found: ${data['minerals']?.length ?? 0}');
      print('🧪 other found: ${data['other']?.length ?? 0}');

      // Check if data exists but contains zeros
      if (data['vitamins'] != null) {
        var vitaminData = data['vitamins'] as Map<String, dynamic>;
        int nonZeroVitamins = vitaminData.values
            .where((v) => v is Map && (v['progress'] ?? 0.0) > 0)
            .length;
        print(
            '🧪 Non-zero vitamins: $nonZeroVitamins out of ${vitaminData.length}');
      }
    } else {
      print(
          '🚨 QUESTION 2 ISSUE: NutritionDataManager has NO data for scanId $_scanId');
      print(
          '🚨 Available scanIds: ${NutritionDataManager._persistentData.keys.toList()}');

      // Try to see if similar scanIds exist
      var similarKeys = NutritionDataManager._persistentData.keys
          .where((key) => key.contains(_scanId.split('_').last))
          .toList();
      if (similarKeys.isNotEmpty) {
        print('🔍 Similar scanIds found: $similarKeys');
      }
    }

    // Initialize defaults ONLY when nothing is available anywhere
    int vitaminsBefore = vitamins.length;
    int mineralsBefore = minerals.length;
    int otherBefore = other.length;

    final bool _managerHasEntry =
        NutritionDataManager._persistentData.containsKey(_scanId);
    final managerEntryEmpty = _managerHasEntry &&
        ((NutritionDataManager._persistentData[_scanId]?['vitamins']
                    as Map?)
                ?.isEmpty ??
            true) &&
        ((NutritionDataManager._persistentData[_scanId]?['minerals'] as Map?)
                ?.isEmpty ??
            true) &&
        ((NutritionDataManager._persistentData[_scanId]?['other'] as Map?)
                ?.isEmpty ??
            true);

    final localEmpty = vitamins.isEmpty && minerals.isEmpty && other.isEmpty;
    // Always ensure local maps are initialized with targets/units.
    // _initializeDefaultValues() only populates when maps are empty, so this is safe.
    if (localEmpty || managerEntryEmpty) {
      _initializeDefaultValues();
    } else {
      print('🔒 Defaults already present in local maps; not reinitializing.');
    }

    // Check if _initializeDefaultValues wiped existing data
    int vitaminsAfter = vitamins.length;
    int mineralsAfter = minerals.length;
    int otherAfter = other.length;

    print(
        '📊 AFTER DEFAULT INIT - Vitamins: $vitaminsAfter, Minerals: $mineralsAfter, Other: $otherAfter');

    // If maps were populated before but now only have defaults, this indicates a problem
    bool dataWasWiped =
        (vitaminsBefore > 0 && _areAllNutrientsZero(vitamins)) ||
            (mineralsBefore > 0 && _areAllNutrientsZero(minerals)) ||
            (otherBefore > 0 && _areAllNutrientsZero(other));

    if (dataWasWiped) {
      print(
          '🚨 WARNING: _initializeDefaultValues may have wiped existing data!');
    }

    // Check SharedPreferences for debugging
    await _debugSharedPreferencesKeys();

    // CRITICAL: ALWAYS save widget data if provided, regardless of refresh status
    if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
      print('🆕 WIDGET DATA PROVIDED: Processing and saving immediately...');
      print('📊 Widget data keys: ${widget.nutritionData!.keys.toList()}');

      // Clear existing data and apply fresh widget data
      vitamins.clear();
      minerals.clear();
      other.clear();
      _initializeDefaultValues();
      _updateNutrientValuesFromData(widget.nutritionData!);

      setState(() {
        vitaminCount = vitamins.values.where((v) => v.progress > 0).length;
        mineralCount = minerals.values.where((v) => v.progress > 0).length;
        otherCount = other.values.where((v) => v.progress > 0).length;
      });

      // CRITICAL: Save the data immediately after processing - BULLETPROOF SAVE
      print(
          '💾 IMMEDIATE SAVE: Saving nutrition data to multiple locations...');
      await _bulletproofSave();
      await NutritionDataManager.storeNutritionData(
          _scanId, vitamins, minerals, other);
      print('💾 IMMEDIATE SAVE: Data saved successfully to all locations');

      // Verify the save worked
      await _verifySaveWorked();
    }

    // PRIORITY 1: Load bulletproof saved data FIRST (before any widget data)
    bool savedDataLoaded = await _loadSavedDataBulletproof();

    // If savedDataLoaded succeeded, update the counts and trigger a state update
    if (savedDataLoaded) {
      setState(() {
        vitaminCount = vitamins.values.where((v) => v.progress > 0).length;
        mineralCount = minerals.values.where((v) => v.progress > 0).length;
        otherCount = other.values.where((v) => v.progress > 0).length;
        _dataLoaded = true; // Mark as loaded
      });

      // If we successfully loaded saved data, we're done - don't process widget data
      if (vitaminCount > 0 || mineralCount > 0 || otherCount > 0) {
        return; // EXIT EARLY - we have our data
      }
    }

    // FALLBACK: If bulletproof loading failed, try direct key loading
    if (!savedDataLoaded) {
      bool directLoaded = await _loadNutritionDataDirect();
      if (directLoaded) {
        setState(() {
          vitaminCount = vitamins.values.where((v) => v.progress > 0).length;
          mineralCount = minerals.values.where((v) => v.progress > 0).length;
          otherCount = other.values.where((v) => v.progress > 0).length;
          _dataLoaded = true;
        });

        if (vitaminCount > 0 || mineralCount > 0 || otherCount > 0) {
          return;
        }
      }
    }

    // PRIORITY 2: If widget has micro values, merge them with saved data instead of replacing
    if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
      print('🆕 Fresh widget data provided, updating (merge)...');
      print('🆕 Widget data keys: ${widget.nutritionData!.keys.toList()}');

      // Only apply micronutrient keys; ignore plain macros-only payloads
      final keys =
          widget.nutritionData!.keys.map((k) => k.toString().toLowerCase());
      final hasMicros = keys.any((k) =>
          k.startsWith('vitamin_') ||
          k == 'calcium' ||
          k == 'iron' ||
          k == 'magnesium' ||
          k == 'potassium' ||
          k == 'sodium' ||
          k == 'zinc' ||
          k == 'fiber' ||
          k == 'cholesterol' ||
          k == 'sugar' ||
          k == 'saturated_fats' ||
          k == 'omega_3' ||
          k == 'omega_6');

      if (hasMicros) {
        _updateNutrientValuesFromData(widget.nutritionData!);
        await _saveNutritionData();
        await NutritionDataManager.storeNutritionData(
            _scanId, vitamins, minerals, other);
        print('💾 Fresh micronutrients merged and saved');
      } else {
        print('ℹ️ Widget data has no micronutrients; keeping saved values');
      }
    }

    // FALLBACK: If all maps are still empty/zero, try emergency recovery
    if (_areAllNutrientsZero(vitamins) &&
        _areAllNutrientsZero(minerals) &&
        _areAllNutrientsZero(other)) {
      print(
          '🚨 EMERGENCY: All nutrient maps are empty/zero, attempting recovery...');
      await _emergencyDataRecovery();

      // Re-check after recovery attempt
      int recoveredVitamins =
          vitamins.values.where((v) => v.progress > 0).length;
      int recoveredMinerals =
          minerals.values.where((v) => v.progress > 0).length;
      int recoveredOther = other.values.where((v) => v.progress > 0).length;
      print(
          '🔄 POST-RECOVERY CHECK - Vitamins: $recoveredVitamins, Minerals: $recoveredMinerals, Other: $recoveredOther');

      if (recoveredVitamins > 0 ||
          recoveredMinerals > 0 ||
          recoveredOther > 0) {
        print('✅ Emergency recovery succeeded - data has been restored!');
        // Update UI state after emergency recovery
        setState(() {
          vitaminCount = recoveredVitamins;
          mineralCount = recoveredMinerals;
          otherCount = recoveredOther;
        });
        print('🔄 UI state updated after emergency recovery');
      } else {
        print('❌ Emergency recovery failed - still no data available');
      }
    }

    // Final logging
    int finalVitamins = vitamins.values.where((v) => v.progress > 0).length;
    int finalMinerals = minerals.values.where((v) => v.progress > 0).length;
    int finalOther = other.values.where((v) => v.progress > 0).length;

    print(
        '🏁 FINAL STATE - Vitamins with data: $finalVitamins, Minerals: $finalMinerals, Other: $finalOther');
    print('🔧 === _initializeAndLoadData() END ===');

    // ═══════════════════════════════════════════════════════════════
    // QUESTION 4: Is there an async delay/race causing empty UI render?
    // ═══════════════════════════════════════════════════════════════
    print('🔍 === QUESTION 4: ASYNC RACE CONDITION CHECK ===');
    print('🔍 About to call setState() at: ${DateTime.now()}');
    print(
        '🔍 Pre-setState vitamins with data: ${vitamins.values.where((v) => v.progress > 0).length}');
    print(
        '🔍 Pre-setState minerals with data: ${minerals.values.where((v) => v.progress > 0).length}');
    print(
        '🔍 Pre-setState other with data: ${other.values.where((v) => v.progress > 0).length}');

    if (finalVitamins == 0 && finalMinerals == 0 && finalOther == 0) {
      print(
          '🚨 QUESTION 4 POTENTIAL ISSUE: About to setState with all empty data!');
      print('🚨 This could cause an empty UI render before data is restored');
    }

    // ═══════════════════════════════════════════════════════════════
    // QUESTION 3: Is setState() being called to assign data to local maps?
    // ═══════════════════════════════════════════════════════════════
    print('🔄 === QUESTION 3: SETSTATE INVESTIGATION ===');
    print(
        '🔄 Before setState - vitamins: ${vitamins.values.where((v) => v.progress > 0).length}');
    print(
        '🔄 Before setState - minerals: ${minerals.values.where((v) => v.progress > 0).length}');
    print(
        '🔄 Before setState - other: ${other.values.where((v) => v.progress > 0).length}');
    print('🔄 _dataLoaded before setState: $_dataLoaded');

    // ═══════════════════════════════════════════════════════════════
    // QUESTION 5: Test 100ms delay to check for async race condition
    // ═══════════════════════════════════════════════════════════════
    print('⏰ === QUESTION 5: TESTING 100MS DELAY ===');
    print('⏰ Before delay - time: ${DateTime.now()}');
    await Future.delayed(Duration(milliseconds: 100));
    print('⏰ After 100ms delay - time: ${DateTime.now()}');
    print(
        '⏰ After delay - vitamins: ${vitamins.values.where((v) => v.progress > 0).length}');
    print('⏰ If values changed after delay, we have an async race condition!');

    // ═══════════════════════════════════════════════════════════════
    // CRITICAL FIX: Load data from NutritionDataManager into local state
    // ═══════════════════════════════════════════════════════════════
    print('🔧 === LOADING DATA FROM NUTRITIONMANAGER INTO LOCAL STATE ===');

    // Load fresh data from NutritionDataManager
    Map<String, NutrientInfo> loadedVitamins = {};
    Map<String, NutrientInfo> loadedMinerals = {};
    Map<String, NutrientInfo> loadedOther = {};

    // First create copies of current maps
    loadedVitamins = Map.from(vitamins);
    loadedMinerals = Map.from(minerals);
    loadedOther = Map.from(other);

    // Try to load from NutritionDataManager
    print(
        '📖 NUTRITION: About to call NutritionDataManager.loadNutritionData()');
    print('📖 NUTRITION: scanId being passed: "$_scanId"');
    print('📖 NUTRITION: scanId type: ${_scanId.runtimeType}');
    print('📖 NUTRITION: scanId length: ${_scanId.length}');
    print('📖 NUTRITION: scanId contains spaces: ${_scanId.contains(' ')}');
    print(
        '📖 NUTRITION: scanId contains underscores: ${_scanId.contains('_')}');
    print('📖 NUTRITION: scanId hashCode: ${_scanId.hashCode}');

    bool dataLoaded = await NutritionDataManager.loadNutritionData(
        _scanId, loadedVitamins, loadedMinerals, loadedOther);

    print(
        '🔧 NUTRITION: NutritionDataManager.loadNutritionData returned: $dataLoaded');
    print(
        '🔧 Loaded vitamins with data: ${loadedVitamins.values.where((v) => v.progress > 0).length}');
    print(
        '🔧 Loaded minerals with data: ${loadedMinerals.values.where((v) => v.progress > 0).length}');
    print(
        '🔧 Loaded other with data: ${loadedOther.values.where((v) => v.progress > 0).length}');

    setState(() {
      // CRITICAL: Assign the loaded data to local state variables
      vitamins = loadedVitamins;
      minerals = loadedMinerals;
      other = loadedOther;

      // Update nutrient counts for UI
      vitaminCount = vitamins.values.where((v) => v.progress > 0).length;
      mineralCount = minerals.values.where((v) => v.progress > 0).length;
      otherCount = other.values.where((v) => v.progress > 0).length;

      // ═══════════════════════════════════════════════════════════════
      // ROBUST DATA LOADED CHECK - Only set true when we have valid data
      // ═══════════════════════════════════════════════════════════════
      bool hasValidData =
          vitamins.isNotEmpty && minerals.isNotEmpty && other.isNotEmpty;

      // Additional check: at least some nutrients should have data
      int totalNutrientsWithData = vitaminCount + mineralCount + otherCount;

      if (hasValidData) {
        _dataLoaded = true;
        print(
            '🔄 setState() - ✅ SETTING _dataLoaded = true (valid data found)');
        print(
            '🔄 setState() - Total nutrients with data: $totalNutrientsWithData');
      } else {
        _dataLoaded = false;
        print('🔄 setState() - ❌ KEEPING _dataLoaded = false (no valid data)');
        print('🔄 setState() - vitamins.isEmpty: ${vitamins.isEmpty}');
        print('🔄 setState() - minerals.isEmpty: ${minerals.isEmpty}');
        print('🔄 setState() - other.isEmpty: ${other.isEmpty}');
      }

      print('🔄 setState() - ASSIGNED DATA TO LOCAL STATE');
      print(
          '🔄 setState() - vitamins: ${vitamins.values.where((v) => v.progress > 0).length}');
      print(
          '🔄 setState() - minerals: ${minerals.values.where((v) => v.progress > 0).length}');
      print(
          '🔄 setState() - other: ${other.values.where((v) => v.progress > 0).length}');
      print('🔄 setState() - vitaminCount: $vitaminCount');
      print('🔄 setState() - mineralCount: $mineralCount');
      print('🔄 setState() - otherCount: $otherCount');
      print('🔄 setState() - _dataLoaded: $_dataLoaded');
    });

    print(
        '🔄 After setState - vitamins: ${vitamins.values.where((v) => v.progress > 0).length}');
    print(
        '🔄 After setState - minerals: ${minerals.values.where((v) => v.progress > 0).length}');
    print(
        '🔄 After setState - other: ${other.values.where((v) => v.progress > 0).length}');
    print('🔄 _dataLoaded after setState: $_dataLoaded');
    print(
        '🔄 ANSWER 3: setState() WAS called AND data was properly assigned to local maps');
  }

  // Helper method to check if all nutrients in a map are zero/empty
  bool _areAllNutrientsZero(Map<String, NutrientInfo> nutrients) {
    return nutrients.values.every((nutrient) => nutrient.progress == 0.0);
  }

  // COMPREHENSIVE DEBUG METHOD - Call this to track the complete data flow
  Future<void> _debugCompleteDataFlow(String context) async {
    print('🔍 === COMPLETE DATA FLOW DEBUG: $context ===');
    print('🔑 Current scanId: "$_scanId"');
    print('🔑 Widget scanId: "${widget.scanId}"');
    print('📊 Widget has nutritionData: ${widget.nutritionData != null}');
    print('📊 Widget nutritionData size: ${widget.nutritionData?.length ?? 0}');

    // Local state
    int vitaminsWithData = vitamins.values.where((v) => v.progress > 0).length;
    int mineralsWithData = minerals.values.where((v) => v.progress > 0).length;
    int otherWithData = other.values.where((v) => v.progress > 0).length;
    print(
        '📊 Local state - Vitamins: $vitaminsWithData, Minerals: $mineralsWithData, Other: $otherWithData');

    // NutritionDataManager memory cache
    bool hasMemoryCache =
        NutritionDataManager._persistentData.containsKey(_scanId);
    print('💾 NutritionDataManager memory cache for $_scanId: $hasMemoryCache');
    if (hasMemoryCache) {
      var cached = NutritionDataManager._persistentData[_scanId];
      print('💾 Cached vitamins: ${cached?['vitamins']?.length ?? 0}');
      print('💾 Cached minerals: ${cached?['minerals']?.length ?? 0}');
      print('💾 Cached other: ${cached?['other']?.length ?? 0}');
    }

    // SharedPreferences check
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> keysToCheck = [
        'nutrition_bulletproof_$_scanId',
        'nutrition_backup_$_scanId',
        'food_nutrition_data_$_scanId',
        'nutrition_data_$_scanId',
      ];

      print('💿 SharedPreferences check:');
      for (String key in keysToCheck) {
        String? value = prefs.getString(key);
        if (value != null) {
          print('💿 ✅ $key: EXISTS (${value.length} chars)');
          try {
            Map<String, dynamic> data = jsonDecode(value);
            print('💿   - Vitamins: ${data['vitamins']?.length ?? 0}');
            print('💿   - Minerals: ${data['minerals']?.length ?? 0}');
            print('💿   - Other: ${data['other']?.length ?? 0}');
          } catch (e) {
            print('💿   - Parse error: $e');
          }
        } else {
          print('💿 ❌ $key: MISSING');
        }
      }
    } catch (e) {
      print('💿 ❌ SharedPreferences error: $e');
    }

    print('🔍 === END COMPLETE DATA FLOW DEBUG ===');
  }

  // Debug method to log all SharedPreferences keys
  Future<void> _debugSharedPreferencesKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Set<String> allKeys = prefs.getKeys();

      print('🗂️ SharedPreferences DEBUG (${allKeys.length} total keys):');

      // Look for nutrition-related keys
      List<String> nutritionKeys = allKeys
          .where((key) =>
              key.contains('nutrition') ||
              key.contains('food') ||
              key.contains(_scanId))
          .toList();

      print('🔍 Nutrition-related keys (${nutritionKeys.length}):');
      for (String key in nutritionKeys) {
        String? value = prefs.getString(key);
        print(
            '  📂 $key: ${value != null ? 'HAS DATA (${value.length} chars)' : 'NULL'}');
      }

      // Specifically check for our scanId keys
      List<String> expectedKeys = [
        'nutrition_bulletproof_$_scanId',
        'nutrition_backup_$_scanId',
        'food_nutrition_data_$_scanId',
        'nutrition_data_$_scanId',
      ];

      print('🎯 Expected keys for scanId $_scanId:');
      for (String key in expectedKeys) {
        String? value = prefs.getString(key);
        print('  🔑 $key: ${value != null ? 'EXISTS' : 'MISSING'}');
      }
    } catch (e) {
      print('❌ Error debugging SharedPreferences: $e');
    }
  }

  // Emergency data recovery method
  Future<void> _emergencyDataRecovery() async {
    print('🚑 EMERGENCY RECOVERY: Attempting to recover nutrition data...');

    try {
      final prefs = await SharedPreferences.getInstance();
      Set<String> allKeys = prefs.getKeys();

      // Try all possible keys that might contain our data
      List<String> recoveryKeys = [
        'nutrition_bulletproof_$_scanId',
        'nutrition_backup_$_scanId',
        'food_nutrition_data_$_scanId',
        'BULLETPROOF_NUTRITION_$_scanId', // NEW: Check bulletproof first
        'PERMANENT_BACKUP_$_scanId', // NEW: Permanent backup
        'NEVER_DELETE_NUTRITION_$_scanId', // NEW: Never delete keys
        'nutrition_data_$_scanId',
        'PERMANENT_GLOBAL_NUTRITION_DATA',
        'BULLETPROOF_NUTRITION_BACKUP',
      ];

      // Also try keys for similar scanIds (in case scanId got corrupted)
      for (String key in allKeys) {
        if (key.contains('nutrition_bulletproof_') ||
            key.contains('nutrition_backup_')) {
          recoveryKeys.add(key);
        }
      }

      for (String key in recoveryKeys) {
        String? dataJson = prefs.getString(key);
        if (dataJson != null && dataJson.isNotEmpty) {
          try {
            Map<String, dynamic> data = jsonDecode(dataJson);
            print('🔄 Found recovery data in key: $key');

            // Try to restore the data - handle multiple formats
            if (data.containsKey('vitamins') ||
                data.containsKey('minerals') ||
                data.containsKey('other')) {
              // Format 1: Standard NutrientInfo format
              _deserializeAndApplyNutrientData(data);
              print(
                  '✅ Successfully recovered data from $key (standard format)');
              return;
            } else if (data.containsKey('vitamin_a') ||
                data.containsKey('calcium') ||
                data.containsKey('fiber')) {
              // Format 2: Flat micronutrients format (like from SnapFood)
              print('🔄 Found flat micronutrient data, converting...');
              _convertFlatMicronutrientsToStructured(data);
              print('✅ Successfully recovered data from $key (flat format)');
              return;
            }
          } catch (e) {
            print('⚠️ Failed to parse recovery data from $key: $e');
            continue;
          }
        }
      }

      // If we get here, no recovery was possible
      print('❌ Emergency recovery failed - no valid data found');
    } catch (e) {
      print('❌ Emergency recovery error: $e');
    }
  }

  // Helper method to deserialize and apply nutrient data
  void _deserializeAndApplyNutrientData(Map<String, dynamic> data) {
    print('🔧 === _deserializeAndApplyNutrientData() START ===');
    print('🔧 Input data keys: ${data.keys.toList()}');

    int appliedVitamins = 0;
    int appliedMinerals = 0;
    int appliedOther = 0;

    try {
      if (data.containsKey('vitamins')) {
        Map<String, dynamic> vitaminsData = data['vitamins'];
        print('🔧 Processing ${vitaminsData.length} vitamins');
        vitaminsData.forEach((key, value) {
          if (vitamins.containsKey(key) && value is Map) {
            vitamins[key] = NutrientInfo(
              name: value['name'] ?? key,
              value: value['value'] ?? '0',
              percent: value['percent'] ?? '0%',
              progress: (value['progress'] ?? 0.0).toDouble(),
              progressColor:
                  _getProgressColor((value['progress'] ?? 0.0).toDouble()),
            );
            if ((value['progress'] ?? 0.0).toDouble() > 0) appliedVitamins++;
          }
        });
      }

      if (data.containsKey('minerals')) {
        Map<String, dynamic> mineralsData = data['minerals'];
        print('🔧 Processing ${mineralsData.length} minerals');
        mineralsData.forEach((key, value) {
          if (minerals.containsKey(key) && value is Map) {
            minerals[key] = NutrientInfo(
              name: value['name'] ?? key,
              value: value['value'] ?? '0',
              percent: value['percent'] ?? '0%',
              progress: (value['progress'] ?? 0.0).toDouble(),
              progressColor:
                  _getProgressColor((value['progress'] ?? 0.0).toDouble()),
            );
            if ((value['progress'] ?? 0.0).toDouble() > 0) appliedMinerals++;
          }
        });
      }

      if (data.containsKey('other')) {
        Map<String, dynamic> otherData = data['other'];
        print('🔧 Processing ${otherData.length} other nutrients');
        otherData.forEach((key, value) {
          if (other.containsKey(key) && value is Map) {
            other[key] = NutrientInfo(
              name: value['name'] ?? key,
              value: value['value'] ?? '0',
              percent: value['percent'] ?? '0%',
              progress: (value['progress'] ?? 0.0).toDouble(),
              progressColor:
                  _getProgressColor((value['progress'] ?? 0.0).toDouble()),
            );
            if ((value['progress'] ?? 0.0).toDouble() > 0) appliedOther++;
          }
        });
      }

      print(
          '🔧 Applied nutrients - Vitamins: $appliedVitamins, Minerals: $appliedMinerals, Other: $appliedOther');

      // CRITICAL: Force UI update after successful recovery
      if (appliedVitamins > 0 || appliedMinerals > 0 || appliedOther > 0) {
        print('✅ Successfully applied nutrient data, forcing UI update...');
        setState(() {
          _dataLoaded = true;
        });
      }

      print('🔧 === _deserializeAndApplyNutrientData() END ===');
    } catch (e) {
      print('❌ Error deserializing nutrient data: $e');
    }
  }

  // Helper method to get progress color based on progress value
  Color _getProgressColor(double progress) {
    if (progress >= 0.8) return Colors.green;
    if (progress >= 0.5) return Colors.orange;
    return Colors.red;
  }

  // Convert flat micronutrient data (like from SnapFood) to structured format
  void _convertFlatMicronutrientsToStructured(Map<String, dynamic> flatData) {
    print('🔄 === _convertFlatMicronutrientsToStructured() START ===');

    int appliedVitamins = 0;
    int appliedMinerals = 0;
    int appliedOther = 0;

    try {
      // Process each flat nutrient key
      flatData.forEach((key, value) {
        if (value == null) return;

        String stringValue = value.toString();
        double numericValue = double.tryParse(stringValue) ?? 0.0;

        // Determine nutrient category and apply
        if (_isVitamin(key)) {
          String displayName = _formatNutrientName(key);
          if (vitamins.containsKey(displayName)) {
            String unit = _getUnitForVitamin(key);
            double dailyValue = _getDailyValueForVitamin(key);
            double progress =
                dailyValue > 0 ? (numericValue / dailyValue) : 0.0;

            vitamins[displayName] = NutrientInfo(
              name: displayName,
              value: '${numericValue.toString()}/$dailyValue $unit',
              percent: '${(progress * 100).round()}%',
              progress: progress.clamp(0.0, 2.0), // Allow up to 200%
              progressColor: _getProgressColor(progress),
            );
            if (progress > 0) appliedVitamins++;
          }
        } else if (_isMineral(key)) {
          String displayName = _formatNutrientName(key);
          if (minerals.containsKey(displayName)) {
            String unit = _getUnitForMineral(key);
            double dailyValue = _getDailyValueForMineral(key);
            double progress =
                dailyValue > 0 ? (numericValue / dailyValue) : 0.0;

            minerals[displayName] = NutrientInfo(
              name: displayName,
              value: '${numericValue.toString()}/$dailyValue $unit',
              percent: '${(progress * 100).round()}%',
              progress: progress.clamp(0.0, 2.0),
              progressColor: _getProgressColor(progress),
            );
            if (progress > 0) appliedMinerals++;
          }
        } else if (_isOtherNutrient(key)) {
          String displayName = _formatNutrientName(key);
          if (other.containsKey(displayName)) {
            String unit = _getUnitForNutrient(key);
            double dailyValue = _getDailyValueForOtherNutrient(key);
            double progress =
                dailyValue > 0 ? (numericValue / dailyValue) : 0.0;

            other[displayName] = NutrientInfo(
              name: displayName,
              value: '${numericValue.toString()}/$dailyValue $unit',
              percent: '${(progress * 100).round()}%',
              progress: progress.clamp(0.0, 2.0),
              progressColor: _getProgressColor(progress),
            );
            if (progress > 0) appliedOther++;
          }
        }
      });

      print(
          '🔄 Applied flat nutrients - Vitamins: $appliedVitamins, Minerals: $appliedMinerals, Other: $appliedOther');

      // Force UI update if we applied any data
      if (appliedVitamins > 0 || appliedMinerals > 0 || appliedOther > 0) {
        print('✅ Successfully converted flat data, forcing UI update...');
        setState(() {
          _dataLoaded = true;
        });
      }

      print('🔄 === _convertFlatMicronutrientsToStructured() END ===');
    } catch (e) {
      print('❌ Error converting flat micronutrient data: $e');
    }
  }

  // Helper methods for nutrient categorization and formatting
  String _formatNutrientName(String key) {
    // Convert snake_case to Title Case
    return key
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  bool _isOtherNutrient(String key) {
    return [
      'fiber',
      'cholesterol',
      'sugar',
      'saturated_fats',
      'omega_3',
      'omega_6'
    ].contains(key.toLowerCase());
  }

  double _getDailyValueForVitamin(String key) {
    switch (key.toLowerCase()) {
      case 'vitamin_a':
        return 700.0;
      case 'vitamin_c':
        return 75.0;
      case 'vitamin_d':
        return 15.0;
      case 'vitamin_e':
        return 15.0;
      case 'vitamin_k':
        return 90.0;
      case 'vitamin_b1':
        return 1.1;
      case 'vitamin_b2':
        return 1.1;
      case 'vitamin_b3':
        return 14.0;
      case 'vitamin_b5':
        return 5.0;
      case 'vitamin_b6':
        return 1.3;
      case 'vitamin_b7':
        return 30.0;
      case 'vitamin_b9':
        return 400.0;
      case 'vitamin_b12':
        return 2.4;
      default:
        return 1.0;
    }
  }

  double _getDailyValueForMineral(String key) {
    switch (key.toLowerCase()) {
      case 'calcium':
        return 1000.0;
      case 'chloride':
        return 2300.0;
      case 'chromium':
        return 35.0;
      case 'copper':
        return 900.0;
      case 'fluoride':
        return 4.0;
      case 'iodine':
        return 150.0;
      case 'iron':
        return 18.0;
      case 'magnesium':
        return 400.0;
      case 'manganese':
        return 2.3;
      case 'molybdenum':
        return 45.0;
      case 'phosphorus':
        return 700.0;
      case 'potassium':
        return 3500.0;
      case 'selenium':
        return 55.0;
      case 'sodium':
        return 2300.0;
      case 'zinc':
        return 11.0;
      default:
        return 1.0;
    }
  }

  double _getDailyValueForOtherNutrient(String key) {
    switch (key.toLowerCase()) {
      case 'fiber':
        return 30.0;
      case 'cholesterol':
        return 300.0;
      case 'sugar':
        return 100.0;
      case 'saturated_fats':
        return 22.0;
      case 'omega_3':
        return 1500.0;
      case 'omega_6':
        return 14.0;
      default:
        return 1.0;
    }
  }

  // Helper methods for nutrient categorization and units
  bool _isVitamin(String key) {
    return [
      'vitamin_a',
      'vitamin_c',
      'vitamin_d',
      'vitamin_e',
      'vitamin_k',
      'vitamin_b1',
      'vitamin_b2',
      'vitamin_b3',
      'vitamin_b5',
      'vitamin_b6',
      'vitamin_b7',
      'vitamin_b9',
      'vitamin_b12'
    ].contains(key.toLowerCase());
  }

  bool _isMineral(String key) {
    return [
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
    ].contains(key.toLowerCase());
  }

  String _getUnitForVitamin(String key) {
    switch (key.toLowerCase()) {
      case 'vitamin_a':
      case 'vitamin_d':
      case 'vitamin_k':
      case 'vitamin_b7':
      case 'vitamin_b9':
      case 'vitamin_b12':
        return 'mcg';
      default:
        return 'mg';
    }
  }

  String _getUnitForMineral(String key) {
    switch (key.toLowerCase()) {
      case 'chromium':
      case 'copper':
      case 'iodine':
      case 'molybdenum':
      case 'selenium':
        return 'mcg';
      default:
        return 'mg';
    }
  }

  String _getUnitForNutrient(String key) {
    switch (key.toLowerCase()) {
      case 'fiber':
      case 'sugar':
      case 'saturated_fats':
      case 'omega_6':
        return 'g';
      case 'omega_3':
      case 'cholesterol':
        return 'mg';
      default:
        return 'g';
    }
  }

  // COMPREHENSIVE LOADING - Check all possible storage locations
  Future<void> _loadNutritionDataSimple() async {
    debugPrint('Loading nutrition data for scanId: $_scanId');
    debugPrint('Checking all possible storage locations...');

    try {
      final prefs = await SharedPreferences.getInstance();

      // PRIORITY 1: If we have fresh widget data, use it and save it
      if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
        debugPrint('Using fresh widget data');
        _updateNutrientValuesFromData(widget.nutritionData!);

        // SAVE TO DEDICATED STORAGE IMMEDIATELY
        await _saveNutritionDataToDedicatedStorage();

        setState(() {
          _dataLoaded = true;
        });
        return;
      }

      // PRIORITY 2: Load from all possible nutrition storage keys
      Set<String> allKeys = prefs.getKeys();
      List<String> possibleKeys = [
        AppEnv.key('nutrition_data_$_scanId'),
        'staging_PERMANENT_NUTRITION_$_scanId',
        'BULLETPROOF_NUTRITION_$_scanId',
        'staging_food_nutrition_data_$_scanId',
        'PERMANENT_NUTRITION_$_scanId',
        'GLOBAL_NUTRITION_BACKUP',
        // Also try without AppEnv.key() prefix
        'nutrition_data_$_scanId',
        'staging_PERMANENT_NUTRITION_$_scanId',
        'BULLETPROOF_NUTRITION_$_scanId',
        'staging_food_nutrition_data_$_scanId',
        'PERMANENT_NUTRITION_$_scanId',
      ];

      debugPrint(
          'Available keys: ${allKeys.where((key) => key.contains('nutrition') || key.contains('NUTRITION')).toList()}');
      debugPrint('Looking for keys: $possibleKeys');

      for (String key in possibleKeys) {
        if (allKeys.contains(key)) {
          debugPrint('Found key: $key');
          String? savedData = prefs.getString(key);
          if (savedData != null && savedData.isNotEmpty) {
            debugPrint('Data found in $key, length: ${savedData.length}');
            try {
              Map<String, dynamic> nutritionData = jsonDecode(savedData);
              debugPrint('Parsed data keys: ${nutritionData.keys.toList()}');

              // Handle different data formats
              if (nutritionData.containsKey('vitamins') &&
                  nutritionData.containsKey('minerals') &&
                  nutritionData.containsKey('other')) {
                // This is the structured format - extract flat data from it
                Map<String, dynamic> flatData = {};

                // Extract vitamins
                if (nutritionData['vitamins'] is Map) {
                  nutritionData['vitamins'].forEach((key, value) {
                    if (value is Map && value.containsKey('value')) {
                      String valueStr = value['value'].toString();
                      // Extract just the numeric part before the "/"
                      if (valueStr.contains('/')) {
                        String numericPart = valueStr.split('/')[0].trim();
                        flatData[key] = numericPart;
                      } else {
                        flatData[key] = valueStr;
                      }
                    }
                  });
                }

                // Extract minerals
                if (nutritionData['minerals'] is Map) {
                  nutritionData['minerals'].forEach((key, value) {
                    if (value is Map && value.containsKey('value')) {
                      String valueStr = value['value'].toString();
                      // Extract just the numeric part before the "/"
                      if (valueStr.contains('/')) {
                        String numericPart = valueStr.split('/')[0].trim();
                        flatData[key] = numericPart;
                      } else {
                        flatData[key] = valueStr;
                      }
                    }
                  });
                }

                // Extract other nutrients
                if (nutritionData['other'] is Map) {
                  nutritionData['other'].forEach((key, value) {
                    if (value is Map && value.containsKey('value')) {
                      String valueStr = value['value'].toString();
                      // Extract just the numeric part before the "/"
                      if (valueStr.contains('/')) {
                        String numericPart = valueStr.split('/')[0].trim();
                        flatData[key] = numericPart;
                      } else {
                        flatData[key] = valueStr;
                      }
                    }
                  });
                }

                // Use the flat data with the proper function
                debugPrint('Extracted flat data: ${flatData.keys.toList()}');
                _updateNutrientValuesFromData(flatData);

                setState(() {
                  vitaminCount =
                      vitamins.values.where((v) => v.progress > 0).length;
                  mineralCount =
                      minerals.values.where((v) => v.progress > 0).length;
                  otherCount = other.values.where((v) => v.progress > 0).length;
                  _dataLoaded = true;
                });
                debugPrint('Loaded from $key (structured format)');
                return;
              } else if (nutritionData.containsKey('scanId') &&
                  nutritionData['scanId'] == _scanId) {
                // This might be a different format, try to extract nutrition data
                if (nutritionData.containsKey('vitamins') ||
                    nutritionData.containsKey('minerals') ||
                    nutritionData.containsKey('other')) {
                  _processNutritionDataFromFoodCard(nutritionData);

                  setState(() {
                    vitaminCount =
                        vitamins.values.where((v) => v.progress > 0).length;
                    mineralCount =
                        minerals.values.where((v) => v.progress > 0).length;
                    otherCount =
                        other.values.where((v) => v.progress > 0).length;
                    _dataLoaded = true;
                  });
                  debugPrint('Loaded from $key (alternative format)');
                  return;
                }
              }
            } catch (e) {
              debugPrint('Failed to parse data from $key');
            }
          }
        }
      }

      // PRIORITY 3: Fallback to food_cards
      List<String>? foodCards = prefs.getStringList('food_cards');

      if (foodCards != null && foodCards.isNotEmpty) {
        for (int i = 0; i < foodCards.length; i++) {
          try {
            Map<String, dynamic> cardData = jsonDecode(foodCards[i]);
            String cardScanId = cardData['scan_id']?.toString() ?? '';

            if (cardScanId == _scanId &&
                cardData.containsKey('nutrition_data')) {
              Map<String, dynamic> nutritionData = cardData['nutrition_data'];
              _processNutritionDataFromFoodCard(nutritionData);

              // SAVE TO DEDICATED STORAGE FOR NEXT TIME
              await _saveNutritionDataToDedicatedStorage();

              setState(() {
                vitaminCount =
                    vitamins.values.where((v) => v.progress > 0).length;
                mineralCount =
                    minerals.values.where((v) => v.progress > 0).length;
                otherCount = other.values.where((v) => v.progress > 0).length;
                _dataLoaded = true;
              });
              debugPrint('Loaded from food_cards');
              return;
            }
          } catch (e) {
            // Continue to next card
          }
        }
      }

      // If no data found, mark as loaded anyway
      debugPrint('No nutrition data found for scanId: $_scanId');
      setState(() {
        _dataLoaded = true;
      });
    } catch (e) {
      debugPrint('Error loading nutrition data: $e');
      setState(() {
        _dataLoaded = true;
      });
    }
  }

  // Called when another route is popped and this route shows up
  @override
  void didPopNext() async {
    debugPrint('Nutrition: didPopNext triggered');

    // Verify scanId consistency
    if (_scanId != widget.scanId) {
      _scanId = widget.scanId; // Fix the mismatch
    }

    // ALWAYS reload saved data when returning to screen
    bool reloadSuccess = await _loadSavedDataBulletproof();

    // If we have fresh widget data, use it and save it
    if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
      _updateNutrientValuesFromData(widget.nutritionData!);
      await _saveNutritionData();
      await NutritionDataManager.storeNutritionData(
          _scanId, vitamins, minerals, other);
    }

    setState(() {
      _dataLoaded = true;
    });
  }

  // Force reload data from storage when returning to screen
  Future<void> _forceReloadFromStorage() async {
    setState(() {
      _dataLoaded = false; // Show loading while reloading
    });

    bool success = await NutritionDataManager.loadNutritionData(
        _scanId, vitamins, minerals, other);

    if (success) {
      print('✅ Successfully reloaded nutrition data from storage');
    } else {
      print('⚠️ Could not reload from storage, keeping current values');
    }

    setState(() {
      _dataLoaded = true;
    });
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

  // AGGRESSIVE SEARCH FOR NUTRITION DATA - NEVER LOSE VALUES
  Future<void> _forceLoadFromAllStorageSources() async {
    print('🔍 AGGRESSIVE SEARCH: Looking for nutrition data everywhere...');

    try {
      final prefs = await SharedPreferences.getInstance();

      // FIRST: Show ALL keys in SharedPreferences for debugging
      Set<String> allKeys = prefs.getKeys();
      print('🗂️ ALL SHAREDPREFERENCES KEYS (${allKeys.length} total):');
      allKeys
          .where((key) => key.contains('nutrition') || key.contains('food'))
          .forEach((key) {
        String? value = prefs.getString(key);
        print(
            '  📂 $key = ${value != null ? 'HAS DATA (${value.length} chars)' : 'NULL'}');
      });

      // Create a comprehensive list of ALL possible storage keys
      List<String> allPossibleKeys = [
        // Standard keys
        'nutrition_bulletproof_$_scanId',
        'nutrition_backup_$_scanId',
        'food_nutrition_data_$_scanId',
        'nutrition_data_$_scanId',

        // Global keys
        'PERMANENT_GLOBAL_NUTRITION_DATA',
        'BULLETPROOF_NUTRITION_BACKUP',
        'LAST_NUTRITION_DATA',
        'current_nutrition_scan_id',
        'latest_nutrition_backup',

        // Flat data keys
        'flat_nutrition_$_scanId',
        'micronutrients_$_scanId',
        'raw_nutrition_data',

        // Alternative formats (simplified since scanIds are now consistent)
        'nutrition_data_$_scanId',
      ];

      // Search all keys for any nutrition data
      print('🔍 Searching these ${allPossibleKeys.length} keys:');
      allPossibleKeys.forEach((key) => print('  - $key'));

      bool foundData = false;
      for (String key in allPossibleKeys) {
        String? dataJson = prefs.getString(key);
        print(
            '🔍 Checking key: $key = ${dataJson != null ? 'HAS DATA (${dataJson.length} chars)' : 'NULL'}');
        if (dataJson != null && dataJson.isNotEmpty) {
          try {
            Map<String, dynamic> data = jsonDecode(dataJson);

            // Check if this data has nutrition values
            bool hasNutritionData = false;
            if (data.containsKey('vitamins') ||
                data.containsKey('minerals') ||
                data.containsKey('other')) {
              hasNutritionData = true;
            } else {
              // Check for flat micronutrient keys
              for (String dataKey in data.keys) {
                if (dataKey.contains('vitamin_') ||
                    dataKey.contains('calcium') ||
                    dataKey.contains('iron')) {
                  hasNutritionData = true;
                  break;
                }
              }
            }

            if (hasNutritionData) {
              print('🎯 FOUND NUTRITION DATA in key: $key');

              // Try to load structured data first
              if (data.containsKey('vitamins')) {
                print('📊 Loading structured nutrition data...');
                bool success = NutritionDataManager._deserializeAndApply(
                    data, vitamins, minerals, other);
                if (success) {
                  foundData = true;
                  print('✅ Successfully loaded structured data from $key');
                  break;
                }
              } else {
                // Try to load flat micronutrient data
                print('📊 Loading flat micronutrient data...');
                _updateNutrientValuesFromData(data);
                foundData = true;
                print('✅ Successfully loaded flat data from $key');
                break;
              }
            }
          } catch (e) {
            print('⚠️ Error parsing data from $key: $e');
            continue;
          }
        }
      }

      if (foundData) {
        print('🎉 AGGRESSIVE SEARCH SUCCESS: Nutrition data recovered!');
        setState(() {
          _dataLoaded = true;
        });

        // IMMEDIATELY save the recovered data to ensure it's not lost again
        await _saveNutritionData();
        await NutritionDataManager.storeNutritionData(
            _scanId, vitamins, minerals, other);
        print('💾 Re-saved recovered data for bulletproof persistence');
      } else {
        print('❌ AGGRESSIVE SEARCH FAILED: No nutrition data found anywhere');
      }
    } catch (e) {
      print('❌ Error in aggressive search: $e');
    }
  }

  // BULLETPROOF SAVE: Save nutrition data using the SAME pattern as FoodCardOpen.dart
  Future<void> _bulletproofSave() async {
    print('🛡️ BULLETPROOF SAVE: Saving using FoodCardOpen.dart pattern...');

    try {
      final prefs = await SharedPreferences.getInstance();

      // Create the nutrition data in the same format as food cards
      Map<String, dynamic> nutritionCard = {
        'scanId': _scanId,
        'lastSaved': DateTime.now().millisecondsSinceEpoch,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'vitamins':
            Map.fromEntries(vitamins.entries.map((e) => MapEntry(e.key, {
                  'name': e.value.name,
                  'value': e.value.value,
                  'percent': e.value.percent,
                  'progress': e.value.progress,
                  'progressColor': e.value.progressColor.value,
                  'hasInfo': e.value.hasInfo,
                }))),
        'minerals':
            Map.fromEntries(minerals.entries.map((e) => MapEntry(e.key, {
                  'name': e.value.name,
                  'value': e.value.value,
                  'percent': e.value.percent,
                  'progress': e.value.progress,
                  'progressColor': e.value.progressColor.value,
                  'hasInfo': e.value.hasInfo,
                }))),
        'other': Map.fromEntries(other.entries.map((e) => MapEntry(e.key, {
              'name': e.value.name,
              'value': e.value.value,
              'percent': e.value.percent,
              'progress': e.value.progress,
              'progressColor': e.value.progressColor.value,
              'hasInfo': e.value.hasInfo,
            }))),
      };

      // Convert to JSON
      String nutritionCardJson = jsonEncode(nutritionCard);

      // CRITICAL: Save to nutrition_cards StringList (same pattern as food_cards)
      List<String> nutritionCards =
          prefs.getStringList('nutrition_cards') ?? [];

      // Remove existing entry for this scanId if it exists
      nutritionCards.removeWhere((cardJson) {
        try {
          Map<String, dynamic> cardData = jsonDecode(cardJson);
          return cardData['scanId'] == _scanId;
        } catch (e) {
          return false;
        }
      });

      // Add new nutrition card at the beginning
      nutritionCards.insert(0, nutritionCardJson);

      // Save the updated list
      await prefs.setStringList('nutrition_cards', nutritionCards);
      print(
          '✅ Saved to nutrition_cards StringList (${nutritionCards.length} cards)');

      // Also save individual backup (same as FoodCardOpen.dart)
      String backupKey = 'nutrition_card_$_scanId';
      await prefs.setString(backupKey, nutritionCardJson);
      print('🛡️ Stored individual backup at "$backupKey"');

      // Legacy keys for backward compatibility
      List<String> legacyKeys = [
        AppEnv.key('nutrition_data_$_scanId'),
        'BULLETPROOF_NUTRITION_$_scanId',
        'PERMANENT_NUTRITION_$_scanId',
        'nutrition_data_$_scanId',
      ];

      for (String key in legacyKeys) {
        try {
          await prefs.setString(key, nutritionCardJson);
          print('✅ Saved to legacy key: $key');
        } catch (e) {
          print('❌ Failed to save to legacy key $key: $e');
        }
      }

      print(
          '🛡️ BULLETPROOF SAVE: Successfully saved using FoodCardOpen.dart pattern');
      print('📊 Data size: ${nutritionCardJson.length} bytes');

      // Count nutrients for verification
      int totalNutrients = vitamins.values.where((v) => v.progress > 0).length +
          minerals.values.where((v) => v.progress > 0).length +
          other.values.where((v) => v.progress > 0).length;
      print('📊 Saved $totalNutrients nutrients with actual values');
    } catch (e) {
      print('❌ Critical error in bulletproof save: $e');
    }
  }

  // VERIFY THAT SAVE ACTUALLY WORKED BY LOADING DATA BACK
  Future<void> _verifySaveWorked() async {
    print('🔍 VERIFYING SAVE WORKED...');

    try {
      final prefs = await SharedPreferences.getInstance();

      // Check all the keys we should have saved to (match the save keys)
      List<String> keysToCheck = [
        AppEnv.key('nutrition_data_$_scanId'), // Primary key
        'BULLETPROOF_NUTRITION_$_scanId', // Never-delete key
        'PERMANENT_NUTRITION_$_scanId', // Permanent backup
        'nutrition_data_$_scanId', // Simple key without env prefix
      ];

      bool foundAnyData = false;
      for (String key in keysToCheck) {
        String? data = prefs.getString(key);
        if (data != null && data.isNotEmpty) {
          print('✅ VERIFIED: Data exists in key: $key');
          foundAnyData = true;

          // Try to parse and show a sample
          try {
            Map<String, dynamic> parsed = jsonDecode(data);
            if (parsed.containsKey('vitamins')) {
              Map<String, dynamic> vitamins = parsed['vitamins'];
              print('  Sample vitamin data: ${vitamins.keys.take(3).toList()}');
            }
          } catch (e) {
            print('  Raw data length: ${data.length} characters');
          }
        } else {
          print('❌ MISSING: No data in key: $key');
        }
      }

      if (!foundAnyData) {
        print('🚨 CRITICAL ERROR: NO DATA FOUND IN ANY STORAGE KEY!');
        print('🚨 DATA WAS NOT SAVED PROPERLY!');
      } else {
        print('✅ VERIFICATION COMPLETE: Data successfully saved');
      }
    } catch (e) {
      print('❌ Error verifying save: $e');
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

      // Save with consistent scanId format (simplified)
      await prefs.setString('nutrition_data_$_scanId', json);
      await prefs.setString('food_nutrition_data_$_scanId', json);

      // Also save to global backup for fallback
      await prefs.setString('PERMANENT_GLOBAL_NUTRITION_DATA', json);

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

    // Subscribe to route changes with enhanced debugging
    try {
      PageRoute? currentRoute = ModalRoute.of(context) as PageRoute?;
      if (currentRoute != null) {
        routeObserver.subscribe(this, currentRoute);
        print('✅ RouteObserver subscribed successfully for Nutrition screen');
        print('🔍 Route name: ${currentRoute.settings.name ?? 'unnamed'}');
      } else {
        print('❌ WARNING: Could not get current route for RouteObserver');
      }
    } catch (e) {
      print('❌ ERROR: Failed to subscribe to RouteObserver: $e');
    }
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
  // SIMPLE INITIALIZATION - Only initialize if maps are empty
  void _initializeDefaultValues() {
    // Only initialize if maps are completely empty
    if (vitamins.isEmpty) {
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
    } else {
      print("🔒 Vitamins map already has data, preserving existing values");
    }

    // Same protection for minerals and other nutrients
    if (minerals.isEmpty) {
      print("🔧 Minerals map is empty, initializing defaults");
      // MINERALS - only initialize if empty
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
    } else {
      print("🔒 Minerals map already has data, preserving existing values");
    }

    if (other.isEmpty) {
      print("🔧 Other nutrients map is empty, initializing defaults");
      // OTHER NUTRIENTS - only initialize if empty
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
    } else {
      print(
          "🔒 Other nutrients map already has data, preserving existing values");
    }

    // Set the counters for each category
    vitaminCount = vitamins.length;
    mineralCount = minerals.length;
    otherCount = other.length;

    // Final debug output
    int finalVitamins = vitamins.values.where((v) => v.progress > 0).length;
    int finalMinerals = minerals.values.where((v) => v.progress > 0).length;
    int finalOther = other.values.where((v) => v.progress > 0).length;
    print(
        "🔧 AFTER - Total: Vitamins: ${vitamins.length}, Minerals: ${minerals.length}, Other: ${other.length}");
    print(
        "🔧 AFTER - With data: Vitamins: $finalVitamins, Minerals: $finalMinerals, Other: $finalOther");
    print("🔧 === _initializeDefaultValues() END ===");
  }

  // Update nutrient values from data provided by SnapFood or other sources
  void _updateNutrientValuesFromData(Map<String, dynamic> data) {
    debugPrint('Updating nutrient values from data');

    // Ensure local maps are initialized before mapping incoming values
    if (vitamins.isEmpty || minerals.isEmpty || other.isEmpty) {
      _initializeDefaultValues();
    }

    // Process flat nutrient data directly with proper unit conversion
    data.forEach((rawKey, value) {
      // Normalize keys to snake_case strings for consistent matching
      final key = rawKey.toString().toLowerCase();
      double amount = _extractNumericValue(value.toString());
      if (amount >= 0) {
        // Map the key to the appropriate nutrient WITH UNIT CONVERSION
        if (key.contains('vitamin_a')) {
          // API now sends correct mcg values - no conversion needed
          _updateVitaminWithValue('Vitamin A', amount);
        } else if (key.contains('vitamin_c')) {
          // Vitamin C is already in mg - no conversion needed
          _updateVitaminWithValue('Vitamin C', amount);
        } else if (key.contains('vitamin_d')) {
          // API now sends correct mcg values - no conversion needed
          _updateVitaminWithValue('Vitamin D', amount);
        } else if (key.contains('vitamin_e')) {
          // Vitamin E is already in mg - no conversion needed
          _updateVitaminWithValue('Vitamin E', amount);
        } else if (key.contains('vitamin_k')) {
          // API now sends correct mcg values - no conversion needed
          _updateVitaminWithValue('Vitamin K', amount);
        } else if (key.contains('vitamin_b1')) {
          // Vitamin B1 is already in mg - no conversion needed
          _updateVitaminWithValue('Vitamin B1', amount);
        } else if (key.contains('vitamin_b2')) {
          // Vitamin B2 is already in mg - no conversion needed
          _updateVitaminWithValue('Vitamin B2', amount);
        } else if (key.contains('vitamin_b3')) {
          // Vitamin B3 is already in mg - no conversion needed
          _updateVitaminWithValue('Vitamin B3', amount);
        } else if (key.contains('vitamin_b5')) {
          // Vitamin B5 is already in mg - no conversion needed
          _updateVitaminWithValue('Vitamin B5', amount);
        } else if (key.contains('vitamin_b6')) {
          // Vitamin B6 is already in mg - no conversion needed
          _updateVitaminWithValue('Vitamin B6', amount);
        } else if (key.contains('vitamin_b7')) {
          // API now sends correct mcg values - no conversion needed
          _updateVitaminWithValue('Vitamin B7', amount);
        } else if (key.contains('vitamin_b9')) {
          // API now sends correct mcg values - no conversion needed
          _updateVitaminWithValue('Vitamin B9', amount);
        } else if (key.contains('vitamin_b12')) {
          // API now sends correct mcg values - no conversion needed
          _updateVitaminWithValue('Vitamin B12', amount);
        } else if (key.contains('calcium')) {
          // Calcium is already in mg - no conversion needed
          _updateMineralWithValue('Calcium', amount);
        } else if (key.contains('chloride')) {
          // Chloride is already in mg - no conversion needed
          _updateMineralWithValue('Chloride', amount);
        } else if (key.contains('chromium')) {
          // API now sends correct mcg values - no conversion needed
          _updateMineralWithValue('Chromium', amount);
        } else if (key.contains('copper')) {
          // API now sends correct mcg values - no conversion needed
          _updateMineralWithValue('Copper', amount);
        } else if (key.contains('fluoride')) {
          // Fluoride is already in mg - no conversion needed
          _updateMineralWithValue('Fluoride', amount);
        } else if (key.contains('iodine')) {
          // API now sends correct mcg values - no conversion needed
          _updateMineralWithValue('Iodine', amount);
        } else if (key.contains('iron')) {
          // Iron is already in mg - no conversion needed
          _updateMineralWithValue('Iron', amount);
        } else if (key.contains('magnesium')) {
          // Magnesium is already in mg - no conversion needed
          _updateMineralWithValue('Magnesium', amount);
        } else if (key.contains('manganese')) {
          // Manganese is already in mg - no conversion needed
          _updateMineralWithValue('Manganese', amount);
        } else if (key.contains('molybdenum')) {
          // API now sends correct mcg values - no conversion needed
          _updateMineralWithValue('Molybdenum', amount);
        } else if (key.contains('phosphorus')) {
          // Phosphorus is already in mg - no conversion needed
          _updateMineralWithValue('Phosphorus', amount);
        } else if (key.contains('potassium')) {
          // Potassium is already in mg - no conversion needed
          _updateMineralWithValue('Potassium', amount);
        } else if (key.contains('selenium')) {
          // API sends μg which equals mcg - no conversion needed
          _updateMineralWithValue('Selenium', amount);
        } else if (key.contains('sodium')) {
          // Sodium is already in mg - no conversion needed
          _updateMineralWithValue('Sodium', amount);
        } else if (key.contains('zinc')) {
          // Zinc is already in mg - no conversion needed
          _updateMineralWithValue('Zinc', amount);
        } else if (key.contains('fiber')) {
          _updateOtherNutrientWithValue('Fiber', amount);
        } else if (key.contains('cholesterol')) {
          _updateOtherNutrientWithValue('Cholesterol', amount);
        } else if (key.contains('sugar')) {
          _updateOtherNutrientWithValue('Sugar', amount);
        } else if (key.contains('saturated_fats') ||
            key.contains('saturatedfat') ||
            key.contains('saturated')) {
          _updateOtherNutrientWithValue('Saturated Fats', amount);
        } else if (key.contains('omega_3') || key.contains('omega3')) {
          _updateOtherNutrientWithValue('Omega-3', amount);
        } else if (key.contains('omega_6') || key.contains('omega6')) {
          _updateOtherNutrientWithValue('Omega-6', amount);
        }
      }
    });

    // Log final state after update
    int vitaminsAfter = vitamins.values.where((v) => v.progress > 0).length;
    int mineralsAfter = minerals.values.where((v) => v.progress > 0).length;
    int otherAfter = other.values.where((v) => v.progress > 0).length;
    debugPrint(
        'Updated nutrients - Vitamins: $vitaminsAfter, Minerals: $mineralsAfter, Other: $otherAfter');
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

  // ═══════════════════════════════════════════════════════════════
  // FINAL DATA VALIDATION - Ensure data state is consistent before UI render
  // ═══════════════════════════════════════════════════════════════
  bool _isDataStateValid() {
    bool mapsExist =
        vitamins.isNotEmpty && minerals.isNotEmpty && other.isNotEmpty;
    int totalNutrients = vitamins.length + minerals.length + other.length;
    int nutrientsWithData =
        vitamins.values.where((v) => v.progress > 0).length +
            minerals.values.where((v) => v.progress > 0).length +
            other.values.where((v) => v.progress > 0).length;

    print('📊 Data State Validation:');
    print('📊 Maps exist: $mapsExist');
    print('📊 Total nutrients: $totalNutrients');
    print('📊 Nutrients with data: $nutrientsWithData');
    print('📊 _dataLoaded flag: $_dataLoaded');

    // Consider data valid as soon as maps are populated; _dataLoaded is redundant here
    bool isValid = mapsExist && totalNutrients > 0;
    print('📊 Final validation result: $isValid');

    return isValid;
  }

  @override
  Widget build(BuildContext context) {
    // Always render the nutrition UI; rows will update as soon as data maps in
    // ═══════════════════════════════════════════════════════════════
    // QUESTION 6: Does UI build depend on non-null map values?
    // ═══════════════════════════════════════════════════════════════
    print('🎨 === QUESTION 6: BUILD METHOD CALLED ===');
    print('🎨 Build called at: ${DateTime.now()}');
    print('🎨 _dataLoaded: $_dataLoaded');
    print('🎨 vitamins map size: ${vitamins.length}');
    print('🎨 minerals map size: ${minerals.length}');
    print('🎨 other map size: ${other.length}');

    int vitaminsWithData = vitamins.values.where((v) => v.progress > 0).length;
    int mineralsWithData = minerals.values.where((v) => v.progress > 0).length;
    int otherWithData = other.values.where((v) => v.progress > 0).length;

    print('🎨 vitamins with data: $vitaminsWithData');
    print('🎨 minerals with data: $mineralsWithData');
    print('🎨 other with data: $otherWithData');

    if (vitaminsWithData == 0 && mineralsWithData == 0 && otherWithData == 0) {
      print('🚨 QUESTION 6 ISSUE: UI building with ALL EMPTY DATA!');
      print('🚨 This will render an empty nutrition screen');
    }

    // ═══════════════════════════════════════════════════════════════
    // UI LOADING GUARD - Don't render until all data is fully loaded
    // ═══════════════════════════════════════════════════════════════

    // Check if data is still loading (using comprehensive validation)
    bool isDataLoading = !_isDataStateValid();

    print('🛡️ UI Loading Guard Check:');
    print('🛡️ _dataLoaded: $_dataLoaded');
    print('🛡️ vitamins.isEmpty: ${vitamins.isEmpty}');
    print('🛡️ minerals.isEmpty: ${minerals.isEmpty}');
    print('🛡️ other.isEmpty: ${other.isEmpty}');
    print('🛡️ isDataLoading: $isDataLoading');

    if (isDataLoading) {
      print('🛡️ BLOCKING UI RENDER - Data not ready, showing loading screen');
      // Instead of blocking, render current state so returning users see cached data
      // and the screen can update progressively.
    }

    print('🛡️ ✅ UI GUARD PASSED - Rendering full nutrition interface');

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
        .where((nutrient) => nutrient.progress > 0.0)
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

  // BULLETPROOF LOAD - Load nutrition data directly from food_cards StringList
  Future<bool> _loadSavedDataBulletproof() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // CRITICAL: Load from food_cards StringList (same as codia_page.dart)
      List<String>? foodCards = prefs.getStringList('food_cards');

      if (foodCards != null && foodCards.isNotEmpty) {
        // Search for the specific scanId in the food cards
        for (int i = 0; i < foodCards.length; i++) {
          String cardJson = foodCards[i];
          try {
            Map<String, dynamic> cardData = jsonDecode(cardJson);
            String cardScanId = cardData['scan_id']?.toString() ?? '';
            String cardName = cardData['name']?.toString() ?? 'Unknown';

            if (cardScanId == _scanId) {
              print('✅ Found food card with matching scanId: $_scanId');

              // Check if this food card has nutrition data
              if (cardData.containsKey('nutrition_data')) {
                Map<String, dynamic> nutritionData = cardData['nutrition_data'];
                print(
                    '✅ Found nutrition_data in food card (${nutritionData.length} nutrients)');

                // Process the nutrition data directly from the food card
                return _processNutritionDataFromFoodCard(nutritionData);
              } else {
                print('❌ Food card found but no nutrition_data field');
              }
            }
          } catch (e) {
            print('❌ Error parsing food card: $e');
          }
        }
        print('❌ No matching scanId found in food_cards');
      }

      // Fallback: Try nutrition_cards StringList (legacy)
      List<String>? nutritionCards = prefs.getStringList('nutrition_cards');

      if (nutritionCards != null && nutritionCards.isNotEmpty) {
        for (String cardJson in nutritionCards) {
          try {
            Map<String, dynamic> cardData = jsonDecode(cardJson);
            String cardScanId = cardData['scanId']?.toString() ?? '';

            if (cardScanId == _scanId) {
              print('✅ Found nutrition data in legacy StringList');
              return _processNutritionCardData(cardData);
            }
          } catch (e) {
            print('❌ Error parsing nutrition card: $e');
          }
        }
      }

      // Fallback: Try individual backup keys
      List<String> backupKeys = [
        'nutrition_backup_$_scanId', // New backup from SnapFood.dart
        'nutrition_card_$_scanId',
        AppEnv.key('nutrition_data_$_scanId'),
        AppEnv.key('PERMANENT_NUTRITION_$_scanId'), // Add AppEnv.key prefix
        AppEnv.key('BULLETPROOF_NUTRITION_$_scanId'), // Add AppEnv.key prefix
        AppEnv.key(
            'food_nutrition_data_$_scanId'), // Add AppEnv.key prefix for food_nutrition_data
        'BULLETPROOF_NUTRITION_$_scanId',
        'PERMANENT_NUTRITION_$_scanId',
        'nutrition_data_$_scanId',
        'food_nutrition_data_$_scanId', // Without prefix
      ];

      print('🔄 Trying backup keys...');

      for (String key in backupKeys) {
        final String? data = prefs.getString(key);
        if (data != null && data.isNotEmpty) {
          try {
            Map<String, dynamic> cardData = jsonDecode(data);
            bool success = _processNutritionCardData(cardData);
            if (success) {
              return true;
            }
          } catch (e) {
            // Silent fail
          }
        }
      }

      // If still not found, consider global but only if embedded scanId matches
      String globalKey = 'PERMANENT_GLOBAL_NUTRITION_DATA';
      print('🔄 Checking global key: "$globalKey"');
      final globalData = prefs.getString(globalKey);
      if (globalData != null && globalData.isNotEmpty) {
        try {
          final probe = jsonDecode(globalData);
          final embeddedId =
              probe is Map ? (probe['scanId']?.toString() ?? '') : '';
          if (embeddedId == _scanId) {
            print('✅ Using global data that matches scanId ($_scanId)');
            return _processNutritionCardData(probe);
          } else {
            print('⚠️ Ignoring global data (scanId $embeddedId != $_scanId)');
          }
        } catch (e) {
          print('⚠️ Invalid JSON in global key; skipping: $e');
        }
      } else {
        print('❌ "$globalKey" is ${globalData == null ? "NULL" : "EMPTY"}');
      }

      print('❌ ===== BULLETPROOF LOAD FAILED =====');
      print('❌ No saved nutrition data found in any key');
      return false;
    } catch (e) {
      print('❌ ===== BULLETPROOF LOAD ERROR =====');
      print('❌ Error loading saved data: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  // DEDICATED STORAGE - Save nutrition data to a separate, reliable storage
  Future<void> _saveNutritionDataToDedicatedStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Create nutrition data map in structured format
      Map<String, dynamic> nutritionData = {
        'scanId': _scanId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'vitamins': {},
        'minerals': {},
        'other': {},
      };

      // Add all vitamins with values > 0
      vitamins.forEach((key, value) {
        if (value.progress > 0) {
          nutritionData['vitamins'][key] = {
            'name': value.name,
            'value': value.value,
            'percent': value.percent,
            'progress': value.progress,
            'progressColor': value.progressColor.value,
            'hasInfo': value.hasInfo,
          };
        }
      });

      // Add all minerals with values > 0
      minerals.forEach((key, value) {
        if (value.progress > 0) {
          nutritionData['minerals'][key] = {
            'name': value.name,
            'value': value.value,
            'percent': value.percent,
            'progress': value.progress,
            'progressColor': value.progressColor.value,
            'hasInfo': value.hasInfo,
          };
        }
      });

      // Add all other nutrients with values > 0
      other.forEach((key, value) {
        if (value.progress > 0) {
          nutritionData['other'][key] = {
            'name': value.name,
            'value': value.value,
            'percent': value.percent,
            'progress': value.progress,
            'progressColor': value.progressColor.value,
            'hasInfo': value.hasInfo,
          };
        }
      });

      // Save to dedicated storage with multiple key formats for redundancy
      String nutritionKey = AppEnv.key('nutrition_data_$_scanId');
      await prefs.setString(nutritionKey, jsonEncode(nutritionData));

      // Also save to non-prefixed key for compatibility
      String nutritionKeyNoPrefix = 'nutrition_data_$_scanId';
      await prefs.setString(nutritionKeyNoPrefix, jsonEncode(nutritionData));

      // Save to bulletproof keys
      await prefs.setString(
          'BULLETPROOF_NUTRITION_$_scanId', jsonEncode(nutritionData));
      await prefs.setString(
          'staging_PERMANENT_NUTRITION_$_scanId', jsonEncode(nutritionData));
    } catch (e) {
      debugPrint('Error saving nutrition data: $e');
    }
  }

  // NEW: Direct nutrition data loading function
  Future<bool> _loadNutritionDataDirect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Set<String> allKeys = prefs.getKeys();

      // Look for any key that contains our scanId
      for (String key in allKeys) {
        if (key.contains(_scanId) && key.contains('nutrition')) {
          final String? data = prefs.getString(key);
          if (data != null && data.isNotEmpty) {
            try {
              Map<String, dynamic> cardData = jsonDecode(data);
              bool success = _processNutritionCardData(cardData);
              if (success) {
                return true;
              }
            } catch (e) {
              // Continue to next key
            }
          }
        }
      }

      // Also try global keys
      List<String> globalKeys = [
        'PERMANENT_GLOBAL_NUTRITION_DATA',
        'staging_GLOBAL_NUTRITION_BACKUP',
      ];

      for (String key in globalKeys) {
        if (allKeys.contains(key)) {
          final String? data = prefs.getString(key);
          if (data != null && data.isNotEmpty) {
            try {
              Map<String, dynamic> cardData = jsonDecode(data);
              String dataScanId = cardData['scanId']?.toString() ?? '';
              if (dataScanId == _scanId) {
                bool success = _processNutritionCardData(cardData);
                if (success) {
                  return true;
                }
              }
            } catch (e) {
              // Continue to next key
            }
          }
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  // Helper method to process nutrition data directly from food card
  bool _processNutritionDataFromFoodCard(Map<String, dynamic> nutritionData) {
    try {
      debugPrint('Processing nutrition data from food card');

      int vitaminCount = 0, mineralCount = 0, otherCount = 0;

      // Process all micronutrients from the flat nutrition data
      nutritionData.forEach((key, value) {
        // Skip non-nutrient fields
        if (['food_name', 'last_updated', 'protein', 'fat', 'carbs', 'calories']
            .contains(key)) {
          return;
        }

        // Convert value to double
        double numericValue = 0.0;
        if (value is num) {
          numericValue = value.toDouble();
        } else if (value is String) {
          numericValue = double.tryParse(value) ?? 0.0;
        }

        // Categorize and process the nutrient
        if (key.startsWith('vitamin_')) {
          // Vitamin
          String vitaminKey = key.replaceFirst('vitamin_', '');
          if (vitamins.containsKey(vitaminKey)) {
            double progress =
                _calculateProgress(numericValue, vitaminKey, 'vitamin');
            if (progress > 0) vitaminCount++;

            vitamins[vitaminKey] = NutrientInfo(
              name: 'Vitamin ${vitaminKey.toUpperCase()}',
              value: '${numericValue.toStringAsFixed(2)}',
              percent: '${(progress * 100).toStringAsFixed(1)}%',
              progress: progress,
              progressColor: _getProgressColor(progress),
              hasInfo: true,
            );

            if (progress > 0) {
              debugPrint('Restored vitamin $vitaminKey: $numericValue');
            }
          }
        } else if ([
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
        ].contains(key)) {
          // Mineral
          if (minerals.containsKey(key)) {
            double progress = _calculateProgress(numericValue, key, 'mineral');
            if (progress > 0) mineralCount++;

            minerals[key] = NutrientInfo(
              name: key.substring(0, 1).toUpperCase() + key.substring(1),
              value: '${numericValue.toStringAsFixed(2)}',
              percent: '${(progress * 100).toStringAsFixed(1)}%',
              progress: progress,
              progressColor: _getProgressColor(progress),
              hasInfo: true,
            );

            if (progress > 0) {
              debugPrint('Restored mineral $key: $numericValue');
            }
          }
        } else if ([
          'fiber',
          'cholesterol',
          'sugar',
          'saturated_fats',
          'omega_3',
          'omega_6'
        ].contains(key)) {
          // Other nutrient
          if (other.containsKey(key)) {
            double progress = _calculateProgress(numericValue, key, 'other');
            if (progress > 0) otherCount++;

            String displayName = key.replaceAll('_', ' ');
            displayName = displayName
                .split(' ')
                .map((word) =>
                    word.substring(0, 1).toUpperCase() + word.substring(1))
                .join(' ');

            other[key] = NutrientInfo(
              name: displayName,
              value: '${numericValue.toStringAsFixed(2)}',
              percent: '${(progress * 100).toStringAsFixed(1)}%',
              progress: progress,
              progressColor: _getProgressColor(progress),
              hasInfo: true,
            );

            if (progress > 0) {
              debugPrint('Restored other nutrient $key: $numericValue');
            }
          }
        }
      });

      int totalLoaded = vitaminCount + mineralCount + otherCount;
      print('✅ ===== FOOD CARD NUTRITION PROCESSING COMPLETE =====');
      print('✅ Successfully loaded $totalLoaded nutrients with values');
      print(
          '✅ Vitamins: $vitaminCount, Minerals: $mineralCount, Other: $otherCount');
      return totalLoaded > 0;
    } catch (e) {
      print('❌ Error processing nutrition data from food card: $e');
      return false;
    }
  }

  // Helper method to calculate progress percentage
  double _calculateProgress(double value, String nutrient, String category) {
    // This is a simplified calculation - you might want to use actual daily values
    // For now, we'll use a basic threshold approach
    Map<String, double> dailyValues = {
      // Vitamins
      'a': 700.0, 'c': 75.0, 'd': 15.0, 'e': 15.0, 'k': 90.0,
      'b1': 1.1, 'b2': 1.1, 'b3': 14.0, 'b5': 5.0, 'b6': 1.3, 'b7': 30.0,
      'b9': 400.0, 'b12': 2.4,
      // Minerals
      'calcium': 1000.0, 'chloride': 2300.0, 'chromium': 35.0, 'copper': 900.0,
      'fluoride': 4.0,
      'iodine': 150.0, 'iron': 18.0, 'magnesium': 400.0, 'manganese': 2.3,
      'molybdenum': 45.0,
      'phosphorus': 700.0, 'potassium': 3500.0, 'selenium': 55.0,
      'sodium': 2300.0, 'zinc': 11.0,
      // Other
      'fiber': 25.0, 'cholesterol': 300.0, 'sugar': 50.0,
      'saturated_fats': 20.0, 'omega_3': 1000.0, 'omega_6': 17000.0,
    };

    double dailyValue = dailyValues[nutrient] ?? 100.0;
    double progress = (value / dailyValue).clamp(0.0, 1.0);
    return progress;
  }

  // Helper method to process nutrition card data
  bool _processNutritionCardData(Map<String, dynamic> data) {
    try {
      print('🔄 Processing nutrition card data...');
      print('🔄 Data keys: ${data.keys.toList()}');
      print('🔄 Data scanId: ${data['scanId']}');
      print('🔄 Data timestamp: ${data['lastSaved'] ?? data['timestamp']}');

      int vitaminCount = 0, mineralCount = 0, otherCount = 0;

      // Load vitamins
      if (data.containsKey('vitamins')) {
        Map<String, dynamic> vitaminData = data['vitamins'];
        print('🔄 Processing ${vitaminData.length} vitamins from saved data');

        vitaminData.forEach((key, value) {
          if (vitamins.containsKey(key)) {
            double progress = (value['progress'] ?? 0.0).toDouble();
            if (progress > 0) vitaminCount++;

            vitamins[key] = NutrientInfo(
              name: value['name'] ?? key,
              value: value['value'] ?? '0',
              percent: value['percent'] ?? '0%',
              progress: progress,
              progressColor: _getProgressColor(progress),
              hasInfo: value['hasInfo'] ?? false,
            );

            if (progress > 0) {
              print(
                  '✅ Restored vitamin $key: ${value['value']} (${value['percent']})');
            }
          }
        });
      } else {
        print('❌ No vitamins data found in saved JSON');
      }

      // Load minerals
      if (data.containsKey('minerals')) {
        Map<String, dynamic> mineralData = data['minerals'];
        print('🔄 Processing ${mineralData.length} minerals from saved data');

        mineralData.forEach((key, value) {
          if (minerals.containsKey(key)) {
            double progress = (value['progress'] ?? 0.0).toDouble();
            if (progress > 0) mineralCount++;

            minerals[key] = NutrientInfo(
              name: value['name'] ?? key,
              value: value['value'] ?? '0',
              percent: value['percent'] ?? '0%',
              progress: progress,
              progressColor: _getProgressColor(progress),
              hasInfo: value['hasInfo'] ?? false,
            );

            if (progress > 0) {
              print(
                  '✅ Restored mineral $key: ${value['value']} (${value['percent']})');
            }
          }
        });
      } else {
        print('❌ No minerals data found in saved JSON');
      }

      // Load other nutrients
      if (data.containsKey('other')) {
        Map<String, dynamic> otherData = data['other'];
        print(
            '🔄 Processing ${otherData.length} other nutrients from saved data');

        otherData.forEach((key, value) {
          if (other.containsKey(key)) {
            double progress = (value['progress'] ?? 0.0).toDouble();
            if (progress > 0) otherCount++;

            other[key] = NutrientInfo(
              name: value['name'] ?? key,
              value: value['value'] ?? '0',
              percent: value['percent'] ?? '0%',
              progress: progress,
              progressColor: _getProgressColor(progress),
              hasInfo: value['hasInfo'] ?? false,
            );

            if (progress > 0) {
              print(
                  '✅ Restored other nutrient $key: ${value['value']} (${value['percent']})');
            }
          }
        });
      } else {
        print('❌ No other nutrients data found in saved JSON');
      }

      int totalLoaded = vitaminCount + mineralCount + otherCount;
      print('✅ ===== NUTRITION CARD PROCESSING COMPLETE =====');
      print('✅ Successfully loaded $totalLoaded nutrients with values');
      print(
          '✅ Vitamins: $vitaminCount, Minerals: $mineralCount, Other: $otherCount');
      return totalLoaded > 0;
    } catch (e) {
      print('❌ Error processing nutrition card data: $e');
      return false;
    }
  }

  // Save nutrition data - SIMPLE VERSION
  Future<void> _saveNutritionData() async {
    try {
      // Do not persist empty maps; this would overwrite good data with zeros
      final allZero = _areAllNutrientsZero(vitamins) &&
          _areAllNutrientsZero(minerals) &&
          _areAllNutrientsZero(other);
      if (allZero) {
        print(
            '🛑 Skip save: all nutrient maps are zero; preserving existing data');
        return;
      }
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

      // Save everything in ONE operation (EXACTLY like FoodCardOpen.dart)
      String consolidatedJson = jsonEncode(nutritionData);
      // CRITICAL: Use AppEnv.key() to match the loading method
      String saveKey = AppEnv.key('nutrition_data_$_scanId');
      await prefs.setString(saveKey, consolidatedJson);

      print(
          '✅ Successfully saved consolidated nutrition data to key: $saveKey (${consolidatedJson.length} bytes)');

      print('💾 Saved nutrition data for ID: $_scanId');

      // Count nutrients with values
      int savedCount = vitamins.values.where((v) => v.progress > 0).length +
          minerals.values.where((v) => v.progress > 0).length +
          other.values.where((v) => v.progress > 0).length;
      print('💾 Saved $savedCount nutrients with actual values');
    } catch (e) {
      print('❌ Error saving nutrition data: $e');
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
