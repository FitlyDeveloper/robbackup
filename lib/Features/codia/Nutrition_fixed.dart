import 'package:flutter/material.dart';
import '../codia/codia_page.dart' as main_codia;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

class CodiaPage extends StatefulWidget {
  // Add parameters to receive nutrition data
  final Map<String, dynamic>? nutritionData;
  // Add a scan ID parameter to uniquely identify each scan
  final String? scanId;

  const CodiaPage({super.key, this.nutritionData, this.scanId});

  @override
  State<StatefulWidget> createState() => _CodiaPage();
}

class _CodiaPage extends State<CodiaPage> {
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
  
  @override
  void initState() {
    super.initState();
    
    // Always use the scanId provided in the widget
    // If none provided, generate a new one (though this shouldn't happen in normal use)
    _scanId = widget.scanId ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    // Log the incoming nutrition data
    print("Nutrition.dart initState called");
    print("Using scan ID: $_scanId");
    if (widget.nutritionData != null) {
      print("Received nutrition data: ${widget.nutritionData}");
    } else {
      print("No nutrition data received");
    }
    
    // Initialize data right away to prevent UI flicker
    _initializeDefaultValues();
    
    // Schedule the asynchronous data loading for after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }
  
  // Separate method to handle all async loading
  Future<void> _loadData() async {
    try {
      await _initializeNutrientData();
      if (mounted) {
        setState(() {
          print("Refreshing UI after data initialized");
        });
      }
    } catch (e) {
      print("Error loading nutrition data: $e");
    }
  }
  
  Future<void> _initializeNutrientData() async {
    // First initialize all nutrients with default values
    _initializeDefaultValues();
    
    // Extract food name from scan ID for direct loading
    String foodPart = _scanId.contains('food_nutrition_') 
        ? _scanId.replaceFirst('food_nutrition_', '') 
        : _scanId.split('_')[0];
        
    print('Trying to load nutrition data for food: $foodPart');
    
    // Try to load saved data using our simple direct keys
    final prefs = await SharedPreferences.getInstance();
    String? savedData;
    
    // Try our direct keys first
    List<String> directKeys = [
      'NUTRITION_$foodPart',
      'DIRECT_NUTRITION_$foodPart', 
      'DIRECT_SAVE_$_scanId'
    ];
    
    for (String key in directKeys) {
      savedData = prefs.getString(key);
      if (savedData != null && savedData.isNotEmpty) {
        print('FOUND DATA using direct key: $key (${savedData.length} bytes)');
        break;
      }
    }
    
    bool loadedExistingData = false;
    
    // If we found saved data, use it
    if (savedData != null && savedData.isNotEmpty) {
      try {
        Map<String, dynamic> data = jsonDecode(savedData);
        
        // Process vitamins
        if (data.containsKey('vitamins')) {
          Map<String, dynamic> vitaminData = data['vitamins'];
          vitaminData.forEach((key, value) {
            if (vitamins.containsKey(key) && value is Map) {
              vitamins[key] = NutrientInfo(
                name: value['name'] ?? key,
                value: value['value'] ?? '0/0 g',
                percent: value['percent'] ?? '0%',
                progress: value['progress'] is double ? value['progress'] : double.tryParse(value['progress'].toString()) ?? 0.0,
                progressColor: _getColorBasedOnProgress(value['progress'] is double ? value['progress'] : double.tryParse(value['progress'].toString()) ?? 0.0),
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
                progress: value['progress'] is double ? value['progress'] : double.tryParse(value['progress'].toString()) ?? 0.0,
                progressColor: _getColorBasedOnProgress(value['progress'] is double ? value['progress'] : double.tryParse(value['progress'].toString()) ?? 0.0),
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
                progress: value['progress'] is double ? value['progress'] : double.tryParse(value['progress'].toString()) ?? 0.0,
                progressColor: _getColorBasedOnProgress(value['progress'] is double ? value['progress'] : double.tryParse(value['progress'].toString()) ?? 0.0),
              );
            }
          });
        }
        
        loadedExistingData = true;
        print('SUCCESSFULLY LOADED saved nutrition data using direct key');
      } catch (e) {
        print('Error loading saved nutrition data: $e');
      }
    }
    
    // If no saved data OR we have widget data, use that (prioritize new data)
    if (!loadedExistingData || (widget.nutritionData != null && widget.nutritionData!.isNotEmpty)) {
      if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
        print('Using nutrition data from widget parameter');
        _updateNutrientValuesFromData(widget.nutritionData!);
      } else if (!loadedExistingData) {
        // Last resort, try to get data from NutritionTracker
        print('No saved data or widget data, trying NutritionTracker');
        await _loadDataFromNutritionTracker();
      }
    }
    
    // Load nutrient targets from SharedPreferences
    await _loadNutrientTargets();
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
  
  void _initializeDefaultValues() {
    // Initialize vitamins
    vitamins = {
      'Vitamin A': NutrientInfo(
        name: "Vitamin A",
        value: "0/0 mcg",
        percent: "0%",
        progress: 0,
        progressColor: greenColor
      ),
      'Vitamin C': NutrientInfo(
        name: "Vitamin C",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: redColor
      ),
      'Vitamin D': NutrientInfo(
        name: "Vitamin D",
        value: "0/0 mcg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor,
        hasInfo: true
      ),
      'Vitamin E': NutrientInfo(
        name: "Vitamin E",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: redColor
      ),
      'Vitamin K': NutrientInfo(
        name: "Vitamin K",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Vitamin B1': NutrientInfo(
        name: "Vitamin B1",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: redColor
      ),
      'Vitamin B2': NutrientInfo(
        name: "Vitamin B2",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Vitamin B3': NutrientInfo(
        name: "Vitamin B3",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: redColor
      ),
      'Vitamin B5': NutrientInfo(
        name: "Vitamin B5",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Vitamin B6': NutrientInfo(
        name: "Vitamin B6",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: redColor
      ),
      'Vitamin B7': NutrientInfo(
        name: "Vitamin B7",
        value: "0/0 mcg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Vitamin B9': NutrientInfo(
        name: "Vitamin B9",
        value: "0/0 mcg",
        percent: "0%",
        progress: 0,
        progressColor: redColor
      ),
      'Vitamin B12': NutrientInfo(
        name: "Vitamin B12",
        value: "0/0 mcg",
        percent: "0%",
        progress: 0,
        progressColor: redColor
      ),
    };
    
    // Initialize minerals
    minerals = {
      'Calcium': NutrientInfo(
        name: "Calcium",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Chloride': NutrientInfo(
        name: "Chloride",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Chromium': NutrientInfo(
        name: "Chromium",
        value: "0/0 mcg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Copper': NutrientInfo(
        name: "Copper",
        value: "0/0 mcg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Fluoride': NutrientInfo(
        name: "Fluoride",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Iodine': NutrientInfo(
        name: "Iodine",
        value: "0/0 mcg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Iron': NutrientInfo(
        name: "Iron",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Magnesium': NutrientInfo(
        name: "Magnesium",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Manganese': NutrientInfo(
        name: "Manganese",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Molybdenum': NutrientInfo(
        name: "Molybdenum",
        value: "0/0 mcg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Phosphorus': NutrientInfo(
        name: "Phosphorus",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Potassium': NutrientInfo(
        name: "Potassium",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Selenium': NutrientInfo(
        name: "Selenium",
        value: "0/0 mcg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Sodium': NutrientInfo(
        name: "Sodium",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Zinc': NutrientInfo(
        name: "Zinc",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
    };
    
    // Initialize other nutrients
    other = {
      'Fiber': NutrientInfo(
        name: "Fiber",
        value: "0/0 g",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Cholesterol': NutrientInfo(
        name: "Cholesterol",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Omega-3': NutrientInfo(
        name: "Omega-3",
        value: "0/0 mg",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Omega-6': NutrientInfo(
        name: "Omega-6",
        value: "0/0 g",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
      'Saturated Fats': NutrientInfo(
        name: "Saturated Fats",
        value: "0/0 g",
        percent: "0%",
        progress: 0,
        progressColor: yellowColor
      ),
    };
  }
  
  void _updateNutrientValuesFromData(Map<String, dynamic> data) {
    print("Updating nutrient values from data: $data");
    
    // Try to load personalized targets first - MAKE THIS AN ASYNC CALL
    _loadPersonalizedOtherNutrientTargets().then((personalizedTargets) {
      // Update fiber if available
      if (data.containsKey('fiber')) {
        double fiber = _parseNutrientValue(data['fiber']);
        double target = personalizedTargets['fiber'] ?? 30; // Target in grams
        double progress = (fiber / target); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Fiber'] = NutrientInfo(
          name: "Fiber",
          value: "$fiber/$target g",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
        print("Updated fiber value: ${fiber.round()}g, progress: $percentage%");
      }
      
      // Update cholesterol if available - will be overridden by _loadNutrientTargets
      if (data.containsKey('cholesterol')) {
        double cholesterol = _parseNutrientValue(data['cholesterol']);
        double target = personalizedTargets['cholesterol'] ?? 300; // Target in mg
        double progress = (cholesterol / target); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Cholesterol'] = NutrientInfo(
          name: "Cholesterol",
          value: "$cholesterol/$target mg",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
        print("Updated cholesterol value: ${cholesterol.round()}mg, progress: $percentage%");
      }
      
      // Update omega-3 if available - will be overridden by _loadNutrientTargets
      if (data.containsKey('omega3') || data.containsKey('omega_3')) {
        double omega3 = data.containsKey('omega3') 
            ? _parseNutrientValue(data['omega3']) 
            : _parseNutrientValue(data['omega_3']);
        double target = personalizedTargets['omega3'] ?? 1500; // Target in mg
        double progress = (omega3 / target); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Omega-3'] = NutrientInfo(
          name: "Omega-3",
          value: "$omega3/$target mg",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
        print("Updated omega-3 value: ${omega3.round()}mg, progress: $percentage%");
      }
      
      // Update omega-6 if available - will be overridden by _loadNutrientTargets
      if (data.containsKey('omega6') || data.containsKey('omega_6')) {
        double omega6 = data.containsKey('omega6') 
            ? _parseNutrientValue(data['omega6']) 
            : _parseNutrientValue(data['omega_6']);
        double target = personalizedTargets['omega6'] ?? 14.0; // Target in g
        double progress = (omega6 / target); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Omega-6'] = NutrientInfo(
          name: "Omega-6",
          value: "$omega6/$target g",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
        print("Updated omega-6 value: ${omega6.round()}g, progress: $percentage%");
      }
      
      // Update saturated fats if available - will be overridden by _loadNutrientTargets
      if (data.containsKey('saturated_fat') || data.containsKey('saturated_fats')) {
        double saturatedFat = data.containsKey('saturated_fat') 
            ? _parseNutrientValue(data['saturated_fat']) 
            : _parseNutrientValue(data['saturated_fats']);
        double target = personalizedTargets['saturated_fat'] ?? 22.0; // Target in g
        double progress = (saturatedFat / target); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Saturated Fats'] = NutrientInfo(
          name: "Saturated Fats",
          value: "$saturatedFat/$target g",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
        print("Updated saturated fats value: ${saturatedFat.round()}g, progress: $percentage%");
      }
      
      // Update remaining nutrient targets from SharedPreferences
      _loadNutrientTargets();
      
      // Update vitamins if available
      _updateVitaminsFromData(data);
      
      // Update minerals if available
      _updateMineralsFromData(data);
      
      // Save the updated data to SharedPreferences
      _saveNutritionData();
    });
    
    // Always refresh with personalized targets to ensure consistency
    _refreshDisplaysWithPersonalizedTargets();
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
        double? cholesterolTarget = prefs.getDouble('nutrient_target_cholesterol');
        if (cholesterolTarget != null) {
          targets['cholesterol'] = cholesterolTarget;
          print('Loaded personalized cholesterol target: $cholesterolTarget mg');
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
        double? saturatedFatTarget = prefs.getDouble('nutrient_target_saturated_fat');
        if (saturatedFatTarget != null) {
          targets['saturated_fat'] = saturatedFatTarget;
          print('Loaded personalized saturated fat target: $saturatedFatTarget g');
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
        bool hasInfo = info.containsKey('hasInfo') ? info['hasInfo'] as bool : false;
        
        // Determine color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        vitamins[info['key'] as String] = NutrientInfo(
          name: info['key'] as String,
          value: "$value/$target $unit",
          percent: "${(progress * 100).toStringAsFixed(0)}%",
          progress: progress,
          progressColor: progressColor,
          hasInfo: hasInfo
        );
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
        bool hasInfo = info.containsKey('hasInfo') ? info['hasInfo'] as bool : false;
        
        // Determine color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        vitamins[vitaminKey] = NutrientInfo(
          name: vitaminKey,
          value: "$valueNum/$target $unit",
          percent: "${(progress * 100).toStringAsFixed(0)}%",
          progress: progress,
          progressColor: progressColor,
          hasInfo: hasInfo
        );
        
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
      RegExp regExp = RegExp(r'vitamin[_\s]*b(\d+)|b(\d+)', caseSensitive: false);
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
              if (valueNum > 0 && vitamins[vitaminKey]!.value.startsWith('0/')) {
                double progress = (valueNum / target);
                Color progressColor = _getColorBasedOnProgress(progress);
                
                vitamins[vitaminKey] = NutrientInfo(
                  name: vitaminKey,
                  value: "$valueNum/$target $unit",
                  percent: "${(progress * 100).toStringAsFixed(0)}%",
                  progress: progress,
                  progressColor: progressColor
                );
                
                print('Updated $vitaminKey from pattern match key $key with value $valueNum');
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
            RegExp regExp = RegExp(r'vitamin[_\s]*b(\d+)|b(\d+)', caseSensitive: false);
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
                    
                    if (valueNum > 0 && vitamins[vitaminKey]!.value.startsWith('0/')) {
                      double progress = (valueNum / target);
                      Color progressColor = _getColorBasedOnProgress(progress);
                      
                      vitamins[vitaminKey] = NutrientInfo(
                        name: vitaminKey,
                        value: "$valueNum/$target $unit",
                        percent: "${(progress * 100).toStringAsFixed(0)}%",
                        progress: progress,
                        progressColor: progressColor
                      );
                      
                      print('Updated $vitaminKey from nutrients array with value $valueNum');
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
            } else if (name.contains('folate') || name.contains('folic') || name.contains('b9')) {
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
  void _updateBVitaminFromNutrient(String vitaminKey, dynamic amount, Map<String, Map<String, dynamic>> bVitamins) {
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
          progressColor: progressColor
        );
        
        print('Updated $vitaminKey from nutrients array detailed match with value $valueNum');
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
          progressColor: progressColor
        );
      }
    });
  }
  
  // Helper method to load personalized mineral targets from SharedPreferences
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
          print('Loaded personalized mineral target: $uiKey = $target ${info['unit']}');
        } else {
          print('No personalized target found for $uiKey, using default: ${info['target']} ${info['unit']}');
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
                          print('BACK BUTTON PRESSED - SAVING DATA WITH DIRECT KEY');
                          
                          try {
                            // Remove snackbar but keep saving logic
                            // Use a super simple approach with ONE reliable key
                            final prefs = await SharedPreferences.getInstance();
                            
                            // Create a clean map with current nutrient values
                            Map<String, dynamic> directSaveData = {
                              'vitamins': Map.fromEntries(vitamins.entries.map((e) => MapEntry(e.key, {
                                'name': e.value.name,
                                'value': e.value.value, 
                                'percent': e.value.percent,
                                'progress': e.value.progress
                              }))),
                              'minerals': Map.fromEntries(minerals.entries.map((e) => MapEntry(e.key, {
                                'name': e.value.name,
                                'value': e.value.value, 
                                'percent': e.value.percent,
                                'progress': e.value.progress
                              }))),
                              'other': Map.fromEntries(other.entries.map((e) => MapEntry(e.key, {
                                'name': e.value.name,
                                'value': e.value.value, 
                                'percent': e.value.percent,
                                'progress': e.value.progress
                              }))),
                            };
                            
                            // Save with a very simple key format based on scan ID
                            String json = jsonEncode(directSaveData);
                            
                            // Extract food name from scan ID - it's the most reliable part
                            String foodPart = _scanId.contains('food_nutrition_') 
                                ? _scanId.replaceFirst('food_nutrition_', '') 
                                : _scanId.split('_')[0];
                            
                            // Save with multiple super-simple keys for redundancy
                            await prefs.setString('NUTRITION_$foodPart', json);
                            await prefs.setString('DIRECT_NUTRITION_$foodPart', json);
                            await prefs.setString('DIRECT_SAVE_$_scanId', json);
                            
                            print('SAVED DATA with keys: NUTRITION_$foodPart, DIRECT_NUTRITION_$foodPart, DIRECT_SAVE_$_scanId');
                            print('Data size: ${json.length} bytes');
                            
                            // Verify just to be sure
                            String? check = prefs.getString('NUTRITION_$foodPart');
                            if (check != null && check.isNotEmpty) {
                              print('VERIFIED: Data saved successfully');
                            } else {
                              print('WARNING: Data verification failed!');
                            }
                            
                            // Small delay to ensure writes complete
                            await Future.delayed(const Duration(milliseconds: 300));
                          } catch (e) {
                            print('Error saving nutrition data: $e');
                          } finally {
                            if (mounted) {
                              Navigator.pop(context);
                            }
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
                ),

                const SizedBox(height: 20),

                // Minerals Section
                _buildNutrientSection(
                  title: "Minerals",
                  count: "${_countNonZeroValues(minerals)}/15",
                  nutrients: minerals.values.toList(),
                ),

                const SizedBox(height: 20),

                // Other Nutrients Section
                _buildNutrientSection(
                  title: "Other",
                  count: "${_countNonZeroValues(other)}/10",
                  nutrients: other.values.toList(),
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
        .where((nutrient) => nutrient.progress >= 1.0)  // Only count as filled if progress is 100% or higher
        .length;
  }

  // Class to hold nutrient information
  Widget _buildNutrientSection({
    required String title,
    required String count,
    required List<NutrientInfo> nutrients,
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
                child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                  // Info icon on left
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    child: const Center(
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

                  // Title in center
                      Expanded(
                    child: Center(
                          child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SF Pro',
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
                          value: nutrient.progress.clamp(0.0, 1.0), // Clamp only for UI display, still show >100% in text
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

  // New method to load nutrient targets from SharedPreferences
  Future<void> _loadNutrientTargets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      print("Loading personalized nutrient targets from SharedPreferences...");
      
      // Check if we have a calculation date to confirm that personalized targets exist
      String? calculationDate = prefs.getString('nutrient_targets_calculation_date');
      if (calculationDate != null) {
        print("Found personalized targets calculated on: $calculationDate");
      } else {
        print("No personalized targets date found, using default values if necessary");
      }
      
      // LOAD MAIN MACRONUTRIENT TARGETS
      // -------------------------------
      
      // Protein target
      double proteinTarget = prefs.getDouble('nutrient_target_protein') ?? 100.0;
      if (other.containsKey('Protein')) {
        double currentValue = _parseCurrentValue(other['Protein']!.value);
        double progress = (currentValue / proteinTarget); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Protein'] = NutrientInfo(
          name: "Protein",
          value: "$currentValue/${proteinTarget.toStringAsFixed(0)} g",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
      }
      
      // Fat target
      double fatTarget = prefs.getDouble('nutrient_target_fat') ?? 70.0;
      if (other.containsKey('Fat')) {
        double currentValue = _parseCurrentValue(other['Fat']!.value);
        double progress = (currentValue / fatTarget); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Fat'] = NutrientInfo(
          name: "Fat",
          value: "$currentValue/${fatTarget.toStringAsFixed(0)} g",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
      }
      
      // Carbs target
      double carbsTarget = prefs.getDouble('nutrient_target_carbs') ?? 200.0;
      if (other.containsKey('Carbs')) {
        double currentValue = _parseCurrentValue(other['Carbs']!.value);
        double progress = (currentValue / carbsTarget); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Carbs'] = NutrientInfo(
          name: "Carbs",
          value: "$currentValue/${carbsTarget.toStringAsFixed(0)} g",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
      }
      
      // LOAD VITAMIN TARGETS
      // -------------------
      await _loadVitaminTargets(prefs);
      
      // LOAD MINERAL TARGETS
      // -------------------
      await _loadMineralTargets(prefs);
      
      // LOAD OTHER NUTRIENT TARGETS
      // --------------------------
      
      // Fiber target
      double fiberTarget = prefs.getDouble('nutrient_target_fiber') ?? 30.0;
      if (other.containsKey('Fiber')) {
        double currentValue = _parseCurrentValue(other['Fiber']!.value);
        double progress = (currentValue / fiberTarget); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Fiber'] = NutrientInfo(
          name: "Fiber",
          value: "$currentValue/${fiberTarget.toStringAsFixed(1)} g",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
      }
      
      // Cholesterol target (default: 300 mg)
      double cholesterolTarget = prefs.getDouble('nutrient_target_cholesterol') ?? 300.0;
      if (other.containsKey('Cholesterol')) {
        double currentValue = _parseCurrentValue(other['Cholesterol']!.value);
        double progress = (currentValue / cholesterolTarget); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Cholesterol'] = NutrientInfo(
          name: "Cholesterol",
          value: "$currentValue/${cholesterolTarget.toStringAsFixed(0)} mg",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
      }
      
      // Omega-3 target
      double omega3Target = prefs.getDouble('nutrient_target_omega3') ?? 1500.0;
      if (other.containsKey('Omega-3')) {
        double currentValue = _parseCurrentValue(other['Omega-3']!.value);
        double progress = (currentValue / omega3Target); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Omega-3'] = NutrientInfo(
          name: "Omega-3",
          value: "$currentValue/${omega3Target.toStringAsFixed(0)} mg",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
      }
      
      // Omega-6 target
      double omega6Target = prefs.getDouble('nutrient_target_omega6') ?? 14.0;
      if (other.containsKey('Omega-6')) {
        double currentValue = _parseCurrentValue(other['Omega-6']!.value);
        double progress = (currentValue / omega6Target); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Omega-6'] = NutrientInfo(
          name: "Omega-6",
          value: "$currentValue/${omega6Target.toStringAsFixed(1)} g",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
      }
      
      // Saturated fat target
      double saturatedFatTarget = prefs.getDouble('nutrient_target_saturated_fat') ?? 22.0;
      if (other.containsKey('Saturated Fats')) {
        double currentValue = _parseCurrentValue(other['Saturated Fats']!.value);
        double progress = (currentValue / saturatedFatTarget); // Removed clamp
        int percentage = (progress * 100).round();
        
        // Get color based on progress
        Color progressColor = _getColorBasedOnProgress(progress);
        
        other['Saturated Fats'] = NutrientInfo(
          name: "Saturated Fats",
          value: "$currentValue/${saturatedFatTarget.toStringAsFixed(1)} g",
          percent: "$percentage%",
          progress: progress,
          progressColor: progressColor
        );
      }
      
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
  
  // Helper method to load vitamin targets
  Future<void> _loadVitaminTargets(SharedPreferences prefs) async {
    try {
      // Map of vitamin keys in the UI to their keys in SharedPreferences
      Map<String, String> vitaminKeyMap = {
        'Vitamin A': 'vitamin_target_vitamin a',
        'Vitamin C': 'vitamin_target_vitamin c',
        'Vitamin D': 'vitamin_target_vitamin d',
        'Vitamin E': 'vitamin_target_vitamin e',
        'Vitamin K': 'vitamin_target_vitamin k',
        'Vitamin B1': 'vitamin_target_vitamin b1',
        'Vitamin B2': 'vitamin_target_vitamin b2',
        'Vitamin B3': 'vitamin_target_vitamin b3',
        'Vitamin B5': 'vitamin_target_vitamin b5',
        'Vitamin B6': 'vitamin_target_vitamin b6',
        'Vitamin B7': 'vitamin_target_vitamin b7',
        'Vitamin B9': 'vitamin_target_vitamin b9',
        'Vitamin B12': 'vitamin_target_vitamin b12',
      };
      
      // Map of vitamin units
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
      
      // Default vitamin values if not found in SharedPreferences
      Map<String, double> defaultValues = {
        'Vitamin A': 900.0,
        'Vitamin C': 90.0,
        'Vitamin D': 15.0,
        'Vitamin E': 15.0,
        'Vitamin K': 120.0,
        'Vitamin B1': 1.2,
        'Vitamin B2': 1.3,
        'Vitamin B3': 16.0,
        'Vitamin B5': 5.0,
        'Vitamin B6': 1.3,
        'Vitamin B7': 30.0,
        'Vitamin B9': 400.0,
        'Vitamin B12': 2.4,
      };
      
      // Load each vitamin target
      for (var entry in vitaminKeyMap.entries) {
        String uiKey = entry.key;
        String prefsKey = entry.key.toLowerCase().replaceAll(' ', '_');
        String unit = vitaminUnits[uiKey] ?? 'mg';
        
        // First try the exact key from calculation_screen.dart
        double target = prefs.getDouble(entry.value) ?? 
                        prefs.getDouble('vitamin_target_$prefsKey') ??
                        defaultValues[uiKey] ?? 0.0;
        
        if (vitamins.containsKey(uiKey)) {
          double currentValue = _parseCurrentValue(vitamins[uiKey]!.value);
          double progress = (currentValue / target); // Removed clamp
          int percentage = (progress * 100).round();
          
          // Get color based on progress
          Color progressColor = _getColorBasedOnProgress(progress);
          
          vitamins[uiKey] = NutrientInfo(
            name: uiKey,
            value: "$currentValue/${target.toStringAsFixed(1)} $unit",
            percent: "$percentage%",
            progress: progress,
            progressColor: progressColor,
            hasInfo: vitamins[uiKey]!.hasInfo
          );
        }
      }
    } catch (e) {
      print("Error loading vitamin targets: $e");
    }
  }
  
  // Helper method to load mineral targets
  Future<void> _loadMineralTargets(SharedPreferences prefs) async {
    try {
      // Map of mineral keys in the UI to their expected units
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
      
      // Default mineral values if not found in SharedPreferences
      Map<String, double> defaultValues = {
        'Calcium': 1000.0,
        'Chloride': 2300.0,
        'Chromium': 35.0,
        'Copper': 900.0,
        'Fluoride': 4.0,
        'Iodine': 150.0,
        'Iron': 8.0,
        'Magnesium': 400.0,
        'Manganese': 2.3,
        'Molybdenum': 45.0,
        'Phosphorus': 700.0,
        'Potassium': 3500.0,
        'Selenium': 55.0,
        'Sodium': 2300.0,
        'Zinc': 11.0,
      };
      
      // Load each mineral target
      for (var entry in mineralUnits.entries) {
        String uiKey = entry.key;
        String prefsKey = uiKey.toLowerCase().replaceAll(' ', '_');
        String unit = entry.value;
        
        // Get target from SharedPreferences, with fallback
        double target = prefs.getDouble('mineral_target_$prefsKey') ?? 
                        prefs.getDouble('nutrient_target_$prefsKey') ??
                        defaultValues[uiKey] ?? 0.0;
        
        if (minerals.containsKey(uiKey)) {
          double currentValue = _parseCurrentValue(minerals[uiKey]!.value);
          double progress = (currentValue / target); // Removed clamp
          int percentage = (progress * 100).round();
          
          // Get color based on progress
          Color progressColor = _getColorBasedOnProgress(progress);
          
          minerals[uiKey] = NutrientInfo(
            name: uiKey,
            value: "$currentValue/${target.toStringAsFixed(unit == 'mcg' ? 0 : 1)} $unit",
            percent: "$percentage%",
            progress: progress,
            progressColor: progressColor
          );
        }
      }
    } catch (e) {
      print("Error loading mineral targets: $e");
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

  // Save nutrition data to SharedPreferences for persistence
  Future<void> _saveNutritionData() async {
    try {
      print('Saving nutrition data for scan ID: $_scanId');
      // Get SharedPreferences instance
      final prefs = await SharedPreferences.getInstance();
      
      // Create a single large data object with all nutrition data
      Map<String, dynamic> allData = {
        'scanId': _scanId,
        'lastSaved': DateTime.now().millisecondsSinceEpoch,
        'vitamins': Map.fromEntries(vitamins.entries.map((e) => MapEntry(e.key, {
          'name': e.value.name,
          'value': e.value.value,
          'percent': e.value.percent,
          'progress': e.value.progress,
          'hasInfo': e.value.hasInfo,
        }))),
        'minerals': Map.fromEntries(minerals.entries.map((e) => MapEntry(e.key, {
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
      
      // Convert to JSON and save in a single operation
      String dataJson = jsonEncode(allData);
      
      // Save to both regular and backup keys to ensure data redundancy
      await prefs.setString('nutrition_data_$_scanId', dataJson);
      print('Primary nutrition data saved for $_scanId (${dataJson.length} bytes)');
      
      await prefs.setString('backup_nutrition_$_scanId', dataJson);
      print('Backup nutrition data saved for $_scanId');
      
      // Save to a final key as well for extra redundancy
      await prefs.setString('nutrition_${_scanId}_final', dataJson);
      print('Final nutrition data saved for $_scanId');
      
      // Also save as a simplified format for emergency recovery
      Map<String, dynamic> simpleData = {
        'scanId': _scanId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': {
          'vitamins': vitamins.map((k, v) => MapEntry(k, v.value)),
          'minerals': minerals.map((k, v) => MapEntry(k, v.value)),
          'other': other.map((k, v) => MapEntry(k, v.value)),
        }
      };
      String simpleJson = jsonEncode(simpleData);
      await prefs.setString('simple_nutrition_$_scanId', simpleJson);
      
      // Save the scan ID to the list of active scan IDs
      List<String> activeScanIds = prefs.getStringList('active_nutrition_scan_ids') ?? [];
      if (!activeScanIds.contains(_scanId)) {
        activeScanIds.add(_scanId);
        await prefs.setStringList('active_nutrition_scan_ids', activeScanIds);
        print('Added scanId $_scanId to active list');
      }
      
      // CRITICAL: Also store this as the last active scan ID for backup recovery
      await prefs.setString('current_nutrition_scan_id', _scanId);
      
      // Verify the save worked by reading back one key
      String? verifyData = prefs.getString('nutrition_data_$_scanId');
      if (verifyData != null && verifyData.isNotEmpty) {
        print('Verified data was saved successfully for $_scanId (${verifyData.length} bytes)');
      } else {
        print('WARNING: Primary data save failed! Using alternative keys.');
      }
    } catch (e) {
      print('Error saving nutrition data: $e');
      // Last resort emergency save
      try {
        final prefs = await SharedPreferences.getInstance();
        Map<String, dynamic> emergencyData = {
          'scanId': _scanId,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'emergency': true,
          'vitamins': vitamins.map((k, v) => MapEntry(k, {'value': v.value, 'progress': v.progress})).cast<String, dynamic>(),
          'minerals': minerals.map((k, v) => MapEntry(k, {'value': v.value, 'progress': v.progress})).cast<String, dynamic>(),
          'other': other.map((k, v) => MapEntry(k, {'value': v.value, 'progress': v.progress})).cast<String, dynamic>(),
        };
        
        String emergencyJson = jsonEncode(emergencyData);
        await prefs.setString('emergency_nutrition_$_scanId', emergencyJson);
        print('Emergency data saved for $_scanId');
      } catch (emergencyError) {
        print('All save attempts failed: $emergencyError');
      }
    }
  }

  // Load saved nutrition data from SharedPreferences
  Future<bool> _loadSavedNutritionData() async {
    print('Loading nutrition data for scan ID: $_scanId');
    try {
      final prefs = await SharedPreferences.getInstance();
      bool dataLoaded = false;
      String? savedData;
      
      // Log for debugging
      print('IMPORTANT: Attempting to load nutrition data for scan ID: $_scanId');
      
      // Try all possible keys in sequence
      List<String> possibleKeys = [
        'nutrition_data_$_scanId',
        'backup_nutrition_$_scanId',
        'nutrition_${_scanId}_final',
        'simple_nutrition_$_scanId',
        'emergency_nutrition_$_scanId',
        'quick_save_$_scanId'
      ];
      
      // Try each key in turn until we find data
      for (String key in possibleKeys) {
        savedData = prefs.getString(key);
        if (savedData != null && savedData.isNotEmpty) {
          print('Found saved data in key: $key (${savedData.length} bytes)');
          break;
        }
      }
      
      // Debug all scanIds available for diagnosis
      List<String> allKeys = prefs.getKeys().toList();
      List<String> nutritionKeys = allKeys.where((key) => key.contains('nutrition')).toList();
      print('All available nutrition keys: $nutritionKeys');
      
      // If not found in any of the direct keys, try the fallback using current_nutrition_scan_id
      if (savedData == null || savedData.isEmpty) {
        String? currentId = prefs.getString('current_nutrition_scan_id');
        if (currentId != null && currentId.isNotEmpty) {
          print('Trying fallback with current_nutrition_scan_id: $currentId');
          
          // Try keys with the current ID
          for (String baseKey in ['nutrition_data_', 'backup_nutrition_', 'nutrition_']) {
            savedData = prefs.getString('$baseKey$currentId');
            if (savedData != null && savedData.isNotEmpty) {
              print('Found saved data using current_nutrition_scan_id in key: $baseKey$currentId');
              break;
            }
          }
        }
      }
      
      // Process the data if found
      if (savedData != null && savedData.isNotEmpty) {
        print('Processing saved data (${savedData.length} bytes) for scanId $_scanId');
        
        Map<String, dynamic> loadedData;
        try {
          loadedData = jsonDecode(savedData);
        } catch (e) {
          print('Error decoding JSON: $e');
          return false;
        }
        
        // Process vitamins data
        if (loadedData.containsKey('vitamins')) {
          Map<String, dynamic> vitaminData = loadedData['vitamins'];
          vitaminData.forEach((key, value) {
            // Skip if the key isn't in our vitamins map
            if (!vitamins.containsKey(key)) return;
            
            double progress = 0.0;
            if (value is Map) {
              if (value.containsKey('progress')) {
                progress = value['progress'] is double ? value['progress'] : double.parse(value['progress'].toString());
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
          dataLoaded = true;
        }
        
        // Process minerals data
        if (loadedData.containsKey('minerals')) {
          Map<String, dynamic> mineralData = loadedData['minerals'];
          mineralData.forEach((key, value) {
            // Skip if the key isn't in our minerals map
            if (!minerals.containsKey(key)) return;
            
            double progress = 0.0;
            if (value is Map) {
              if (value.containsKey('progress')) {
                progress = value['progress'] is double ? value['progress'] : double.parse(value['progress'].toString());
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
          dataLoaded = true;
        }
        
        // Process other nutrients data
        if (loadedData.containsKey('other')) {
          Map<String, dynamic> otherData = loadedData['other'];
          otherData.forEach((key, value) {
            // Skip if the key isn't in our other map
            if (!other.containsKey(key)) return;
            
            double progress = 0.0;
            if (value is Map) {
              if (value.containsKey('progress')) {
                progress = value['progress'] is double ? value['progress'] : double.parse(value['progress'].toString());
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
          dataLoaded = true;
        }
        
        // Try the simplified data format if we didn't load anything yet
        if (!dataLoaded && loadedData.containsKey('data')) {
          print('Using simplified data format');
          Map<String, dynamic> simpleData = loadedData['data'];
          
          // Process simplified vitamins data
          if (simpleData.containsKey('vitamins')) {
            _processSimplifiedData(simpleData['vitamins'], vitamins);
            dataLoaded = true;
          }
          
          // Process simplified minerals data
          if (simpleData.containsKey('minerals')) {
            _processSimplifiedData(simpleData['minerals'], minerals);
            dataLoaded = true;
          }
          
          // Process simplified other nutrients data
          if (simpleData.containsKey('other')) {
            _processSimplifiedData(simpleData['other'], other);
            dataLoaded = true;
          }
        }
        
        // If we successfully loaded data, save it again to ensure it's properly stored
        if (dataLoaded) {
          print('Successfully loaded data, re-saving for consistency');
          _saveNutritionData();
          
          // Also save current scanId
          prefs.setString('current_nutrition_scan_id', _scanId);
        }
        
        // Update the UI if we loaded any data
        if (dataLoaded && mounted) {
          setState(() {
            print("UI updated with loaded nutrition data");
          });
        }
        
        return dataLoaded;
      } else {
        print('No saved data found for scan ID: $_scanId');
        
        // If widget provided data, use it and return true
        if (widget.nutritionData != null && widget.nutritionData!.isNotEmpty) {
          print('No saved data found, but widget provided nutrition data - using that');
          _updateNutrientValuesFromData(widget.nutritionData!);
          _saveNutritionData(); // Save this data for next time
          return true;
        }
        
        return false;
      }
    } catch (e) {
      print('Error loading saved nutrition data: $e');
      return false;
    }
  }
  
  // Helper method to process simplified data format
  void _processSimplifiedData(Map<String, dynamic> simplifiedData, Map<String, NutrientInfo> targetMap) {
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
        
        double progress = targetValue > 0 ? (currentValue / targetValue) : 0.0; // Removed clamp
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

  @override
  void dispose() {
    // Save nutrition data when leaving the screen
    print('Nutrition.dart dispose called - saving data for scan ID: $_scanId');
    
    // Force an immediate save before dispose completes
    // This is crucial for data persistence
    try {
      // Get a synchronous reference to SharedPreferences
      SharedPreferences.getInstance().then((prefs) {
        // Create essential data that needs to be saved
        Map<String, dynamic> essentialData = {
          'scanId': _scanId,
          'lastSaved': DateTime.now().millisecondsSinceEpoch,
          'vitamins': vitamins.map((k, v) => MapEntry(k, {'value': v.value, 'progress': v.progress})).cast<String, dynamic>(),
          'minerals': minerals.map((k, v) => MapEntry(k, {'value': v.value, 'progress': v.progress})).cast<String, dynamic>(),
          'other': other.map((k, v) => MapEntry(k, {'value': v.value, 'progress': v.progress})).cast<String, dynamic>(),
        };
        
        // Save data to multiple keys for redundancy
        String dataJson = jsonEncode(essentialData);
        prefs.setString('nutrition_data_$_scanId', dataJson);
        prefs.setString('backup_nutrition_$_scanId', dataJson);
        prefs.setString('nutrition_${_scanId}_final', dataJson);
        prefs.setString('quick_save_$_scanId', dataJson);
        
        // Always save the current scan ID for potential recovery
        prefs.setString('current_nutrition_scan_id', _scanId);
        
        print('Emergency save completed in dispose');
      });
    } catch (e) {
      print('Error in emergency save: $e');
    }
    
    // Continue with full save process in a fire-and-forget manner
    _saveNutritionData().then((_) {
      print('Full data save completed in dispose');
    }).catchError((error) {
      print('Error saving data in dispose: $error');
    });
    
    super.dispose();
  }

  // Add a helper method to determine color based on progress
  Color _getColorBasedOnProgress(double progress) {
    if (progress < 0.4) {
      return Colors.red;  // Red for 0-40%
    } else if (progress < 0.8) {
      return yellowColor; // Yellow for 40-80%
    } else {
      return greenColor;  // Green for 80-100%+ (anything above 0.8 is good)
    }
  }

  // Helper method to load personalized vitamin targets from SharedPreferences
  Future<void> _loadPersonalizedVitaminTargets(Map<String, Map<String, dynamic>> vitaminInfo) async {
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
          print('Loaded personalized vitamin target: $uiKey = $target ${info['unit']}');
        } else {
          print('No personalized target found for $uiKey, using default: ${info['target']} ${info['unit']}');
        }
      }
    } catch (e) {
      print('Error loading personalized vitamin targets: $e');
    }
  }

  // Helper method to load personalized mineral targets from SharedPreferences
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
          print('Loaded personalized mineral target: $uiKey = $target ${info['unit']}');
        } else {
          print('No personalized target found for $uiKey, using default: ${info['target']} ${info['unit']}');
        }
      }
    } catch (e) {
      print('Error loading personalized mineral targets: $e');
    }
  }

  Future<void> _refreshDisplaysWithPersonalizedTargets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Check if we have personalized targets
      String? calculationDate = prefs.getString('nutrient_targets_calculation_date');
      if (calculationDate != null) {
        print('Refreshing all displays with personalized targets calculated on: $calculationDate');
        
        // UPDATE OTHER NUTRIENTS
        // Fiber
        double fiberTarget = prefs.getDouble('nutrient_target_fiber') ?? 30.0;
        if (other.containsKey('Fiber')) {
          double currentValue = _parseCurrentValue(other['Fiber']!.value);
          _updateNutrientDisplay('Fiber', currentValue, fiberTarget, 'g', other);
        }
        
        // Cholesterol - FIXED to use the proper SharedPreferences key
        double cholesterolTarget = prefs.getDouble('nutrient_target_cholesterol') ?? 300.0;
        if (other.containsKey('Cholesterol')) {
          double currentValue = _parseCurrentValue(other['Cholesterol']!.value);
          _updateNutrientDisplay('Cholesterol', currentValue, cholesterolTarget, 'mg', other);
        }
        
        // Omega-3
        double omega3Target = prefs.getDouble('nutrient_target_omega3') ?? 1500.0;
        if (other.containsKey('Omega-3')) {
          double currentValue = _parseCurrentValue(other['Omega-3']!.value);
          _updateNutrientDisplay('Omega-3', currentValue, omega3Target, 'mg', other);
        }
        
        // Omega-6
        double omega6Target = prefs.getDouble('nutrient_target_omega6') ?? 14.0;
        if (other.containsKey('Omega-6')) {
          double currentValue = _parseCurrentValue(other['Omega-6']!.value);
          _updateNutrientDisplay('Omega-6', currentValue, omega6Target, 'g', other);
        }
        
        // Saturated Fats
        double saturatedFatTarget = prefs.getDouble('nutrient_target_saturated_fat') ?? 22.0;
        if (other.containsKey('Saturated Fats')) {
          double currentValue = _parseCurrentValue(other['Saturated Fats']!.value);
          _updateNutrientDisplay('Saturated Fats', currentValue, saturatedFatTarget, 'g', other);
        }
        
        // UPDATE VITAMINS
        // Process each vitamin using direct target lookup
        vitamins.forEach((key, info) {
          String prefsKey = key.toLowerCase().replaceAll(' ', '_');
          
          // IMPROVED: Use a direct lookup in SharedPreferences for each vitamin
          double? storedTarget = prefs.getDouble('vitamin_target_$prefsKey');
          
          if (storedTarget != null) {
            // Use the personalized target
            double currentValue = _parseCurrentValue(info.value);
            String unit = key.contains('A') || key.contains('D') || key.contains('B7') || 
                          key.contains('B9') || key.contains('B12') || key.contains('K') ? 'mcg' : 'mg';
            
            _updateNutrientDisplay(key, currentValue, storedTarget, unit, vitamins);
            print('Using personalized target for $key: $storedTarget $unit');
          } else {
            // No personalized target found - should never happen if calculation worked correctly
            print('WARNING: No personalized target found for $key, using existing value');
          }
        });
        
        // UPDATE MINERALS
        // Process each mineral using direct target lookup
        minerals.forEach((key, info) {
          String prefsKey = key.toLowerCase().replaceAll(' ', '_');
          
          // IMPROVED: Use a direct lookup in SharedPreferences for each mineral
          double? storedTarget = prefs.getDouble('mineral_target_$prefsKey');
          
          if (storedTarget != null) {
            // Use the personalized target
            double currentValue = _parseCurrentValue(info.value);
            String unit = key == 'Chromium' || key == 'Copper' || 
                         key == 'Iodine' || key == 'Molybdenum' || 
                         key == 'Selenium' ? 'mcg' : 'mg';
            
            _updateNutrientDisplay(key, currentValue, storedTarget, unit, minerals);
            print('Using personalized target for $key: $storedTarget $unit');
          } else {
            // No personalized target found - should never happen if calculation worked correctly
            print('WARNING: No personalized target found for $key, using existing value');
          }
        });
        
        print('Successfully refreshed all nutrient displays with personalized targets');
      } else {
        print('No personalized targets calculation date found - targets may not be fully personalized');
      }
    } catch (e) {
      print('Error refreshing displays with personalized targets: $e');
    }
  }
  
  // Helper method to update nutrient displays consistently
  void _updateNutrientDisplay(String key, double currentValue, double target, String unit, Map<String, NutrientInfo> nutrientMap) {
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
      hasInfo: nutrientMap[key]?.hasInfo ?? false
    );
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

