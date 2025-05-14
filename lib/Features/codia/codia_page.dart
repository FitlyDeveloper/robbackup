import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'Memories.dart';
import '../../NewScreens/ChooseWorkout.dart';
import '../../NewScreens/Coach.dart';
import '../../NewScreens/SnapFood.dart';
import 'flip_card.dart';
import 'home_card2.dart';
import '../../NewScreens/FoodCardOpen.dart';
import 'package:flutter/gestures.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:grouped_list/grouped_list.dart';
import './Nutrition.dart' as Nutrition;
// Temporarily commenting out table_calendar to fix build
// import 'package:table_calendar/table_calendar.dart';

// Stub implementation of TableCalendar to fix build
class TableCalendar extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime firstDay;
  final DateTime lastDay;
  final Function(DateTime, DateTime)? onDaySelected;
  final DateTime? selectedDay;
  final CalendarFormat calendarFormat;
  final Function(CalendarFormat)? onFormatChanged;

  const TableCalendar({
    Key? key,
    required this.focusedDay,
    required this.firstDay,
    required this.lastDay,
    this.onDaySelected,
    this.selectedDay,
    required this.calendarFormat,
    this.onFormatChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          "Calendar temporarily unavailable",
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

// Stub enum for CalendarFormat
enum CalendarFormat { month, twoWeeks, week }

// Custom painter for drawing the calorie gauge
class CalorieGaugePainter extends CustomPainter {
  final double consumedPercentage;

  CalorieGaugePainter({required this.consumedPercentage});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2,
        size.height / 2 + 11); // Moved down 11px total (1px up from before)
    final radius = size.width / 2 - 8;

    // Use exact degree calculations for precise control
    // Convert angles from degrees to radians for the drawArc method
    final double startAngleDegrees =
        47.0; // Moved -1 degree from previous position (48°)
    final double sweepAngleDegrees =
        -270.0; // Cover 3/4 of the circle clockwise

    // Convert to radians for Flutter's drawArc
    final double startAngleRadians = startAngleDegrees * math.pi / 180;
    final double sweepAngleRadians = sweepAngleDegrees * math.pi / 180;

    // Draw background arc (remaining calories) - gray
    final backgroundPaint = Paint()
      ..color = Color(0xFFE1E1E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14.0 // Increased from 12.0 to make it wider
      ..strokeCap = StrokeCap.round; // Rounded edges for the background gauge

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngleRadians,
      sweepAngleRadians,
      false,
      backgroundPaint,
    );

    // Draw consumed calories arc - black
    if (consumedPercentage > 0) {
      // To create a fill with one end rounded and one end straight,
      // we'll draw two arcs - one with rounded caps for the "back" and
      // one with butt cap for the "front"

      final double endAngle = startAngleRadians +
          sweepAngleRadians; // The end of the background arc

      // Create paint for the main fill (most of the arc) with rounded cap at the back
      final mainFillPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14.0
        ..strokeCap = StrokeCap.round; // Rounded edge for the back of the fill

      // If we're filling more than a tiny amount, draw the main portion with rounded back
      if (consumedPercentage > 0.02) {
        final adjustedSweepAngle = -sweepAngleRadians *
            (consumedPercentage - 0.01); // Slightly shorter

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          endAngle + 0.01, // Start slightly ahead to avoid overlap issues
          adjustedSweepAngle, // Go in opposite direction
          false,
          mainFillPaint,
        );
      }

      // Create paint for the front edge with butt cap
      final frontEdgePaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14.0
        ..strokeCap = StrokeCap.butt; // Straight edge for the front of the fill

      // Draw a very small arc at the front edge to create the straight cap
      final frontEdgeAngle = -sweepAngleRadians * consumedPercentage;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        endAngle + frontEdgeAngle - 0.02, // Just the very front part
        0.02, // Tiny arc
        false,
        frontEdgePaint,
      );
    }
  }

  @override
  bool shouldRepaint(CalorieGaugePainter oldDelegate) {
    return oldDelegate.consumedPercentage != consumedPercentage;
  }
}

// Observer class for app lifecycle events
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;

  _AppLifecycleObserver({required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _AppLifecycleObserver;
  }

  @override
  int get hashCode => onResume.hashCode;
}

// Class to track nutrition data from food logs
class NutritionTracker {
  // Singleton instance
  static final NutritionTracker _instance = NutritionTracker._internal();
  factory NutritionTracker() => _instance;
  NutritionTracker._internal();

  // Current nutrition values
  int _currentProtein = 0;
  int _currentFat = 0;
  int _currentCarb = 0;
  int _consumedCalories = 0;

  // Getters for nutrition values
  int get currentProtein => _currentProtein;
  int get currentFat => _currentFat;
  int get currentCarb => _currentCarb;
  int get consumedCalories => _consumedCalories;

  // Add a new food log entry
  Future<bool> logFood({
    required String name,
    required dynamic calories,
    required dynamic protein,
    required dynamic fat,
    required dynamic carbs,
    String? imageBase64,
    List<dynamic>? ingredients,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get today's date
      String today = DateTime.now().toString().split(' ')[0];
      String foodLogsKey = 'food_logs_$today';

      // Create the food log entry
      Map<String, dynamic> foodLog = {
        'name': name,
        'calories': calories,
        'protein': protein,
        'fat': fat,
        'carbs': carbs,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      if (imageBase64 != null) {
        foodLog['image'] = imageBase64;
      }

      if (ingredients != null) {
        foodLog['ingredients'] = ingredients;
      }

      // Load existing food logs for today
      List<dynamic> foodLogs = [];
      if (prefs.containsKey(foodLogsKey)) {
        String? existingLogs = prefs.getString(foodLogsKey);
        if (existingLogs != null && existingLogs.isNotEmpty) {
          try {
            foodLogs = jsonDecode(existingLogs);
          } catch (e) {
            print('Error parsing existing food logs: $e');
            foodLogs = [];
          }
        }
      }

      // Add the new food log
      foodLogs.add(foodLog);

      // Save the updated food logs
      await prefs.setString(foodLogsKey, jsonEncode(foodLogs));

      print(
          'Added food log: $name with calories=$calories, protein=$protein, fat=$fat, carbs=$carbs');

      // Update the current nutrition values
      _currentProtein += _parseNutritionValue(protein);
      _currentFat += _parseNutritionValue(fat);
      _currentCarb += _parseNutritionValue(carbs);
      _consumedCalories += _parseNutritionValue(calories);

      return true;
    } catch (e) {
      print('Error logging food: $e');
      return false;
    }
  }

  // Load nutrition data from SharedPreferences
  Future<void> loadNutritionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Reset values first
      _currentProtein = 0;
      _currentFat = 0;
      _currentCarb = 0;
      _consumedCalories = 0;

      // Try to load today's food logs
      String today = DateTime.now().toString().split(' ')[0]; // YYYY-MM-DD

      // First try to get data from any known food log formats
      bool dataFound = await _tryLoadFromFoodLogs(prefs, today) ||
          await _tryLoadFromFoodCards(prefs) ||
          await _tryLoadFromDailyNutrition(prefs, today);

      if (!dataFound) {
        print('No food log data found in any known format');

        // For testing ONLY - use hardcoded values, COMMENT THIS OUT IN PRODUCTION
        _setupTestData();
      }
    } catch (e) {
      print('Error loading nutrition data: $e');
    }
  }

  // Try to load from food_logs_DATE format
  Future<bool> _tryLoadFromFoodLogs(
      SharedPreferences prefs, String today) async {
    String foodLogsKey = 'food_logs_$today';
    print('Trying to load from $foodLogsKey');

    if (prefs.containsKey(foodLogsKey)) {
      String? foodLogsJson = prefs.getString(foodLogsKey);
      print('Food logs JSON: ${foodLogsJson?.length ?? 0} characters');

      if (foodLogsJson != null && foodLogsJson.isNotEmpty) {
        try {
          List<dynamic> foodLogs = jsonDecode(foodLogsJson);
          print('Decoded ${foodLogs.length} food logs from $foodLogsKey');

          // Sum up nutrition values from all food logs
          for (var foodLog in foodLogs) {
            try {
              _currentProtein += _parseNutritionValue(foodLog['protein']);
              _currentFat += _parseNutritionValue(foodLog['fat']);
              _currentCarb += _parseNutritionValue(foodLog['carbs']);
              _consumedCalories += _parseNutritionValue(foodLog['calories']);

              print('Processed food log: ${foodLog['name'] ?? 'Unknown'}, '
                  'calories: ${foodLog['calories']}, '
                  'protein: ${foodLog['protein']}, '
                  'fat: ${foodLog['fat']}, '
                  'carbs: ${foodLog['carbs']}');
            } catch (e) {
              print('Error processing food log entry: $e');
            }
          }

          print('Loaded nutrition data from $foodLogsKey: '
              'protein=$_currentProtein, fat=$_currentFat, '
              'carbs=$_currentCarb, calories=$_consumedCalories');
          return true;
        } catch (e) {
          print('Error parsing food logs JSON from $foodLogsKey: $e');
        }
      }
    }
    return false;
  }

  // Try to load from food_cards format (used by SnapFood)
  Future<bool> _tryLoadFromFoodCards(SharedPreferences prefs) async {
    print('Trying to load from food_cards');

    if (prefs.containsKey('food_cards')) {
      List<String>? cardStrings = prefs.getStringList('food_cards');

      if (cardStrings != null && cardStrings.isNotEmpty) {
        print('Found ${cardStrings.length} food cards');

        // Get today's date for filtering
        String today = DateTime.now().toString().split(' ')[0]; // YYYY-MM-DD

        for (String cardJson in cardStrings) {
          try {
            Map<String, dynamic> card = jsonDecode(cardJson);

            // Check if this card is from today
            int timestamp = card['timestamp'] ?? 0;
            DateTime cardDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
            String cardDateStr = cardDate.toString().split(' ')[0];

            if (cardDateStr == today) {
              // Get counter (portions) value with fallback to 1
              int counter = 1;
              if (card.containsKey('counter')) {
                counter = card['counter'] is int
                    ? card['counter']
                    : int.tryParse(card['counter'].toString()) ?? 1;

                // Ensure counter is between 1 and 3
                counter = counter.clamp(1, 3);
              }

              // This card is from today, add its nutrition values WITHOUT counter multiplier
              _currentProtein += _parseNutritionValue(card['protein']);
              _currentFat += _parseNutritionValue(card['fat']);
              _currentCarb += _parseNutritionValue(card['carbs']);
              _consumedCalories += _parseNutritionValue(card['calories']);

              print('Added food card from today: ${card['name']} (×$counter), '
                  'calories: ${_parseNutritionValue(card['calories'])} (base: ${card['calories']}), '
                  'protein: ${_parseNutritionValue(card['protein'])} (base: ${card['protein']}), '
                  'fat: ${_parseNutritionValue(card['fat'])} (base: ${card['fat']}), '
                  'carbs: ${_parseNutritionValue(card['carbs'])} (base: ${card['carbs']})');
            }
          } catch (e) {
            print('Error processing food card: $e');
          }
        }

        print('Loaded nutrition data from food_cards: '
            'protein=$_currentProtein, fat=$_currentFat, '
            'carbs=$_currentCarb, calories=$_consumedCalories');
        return true;
      }
    }
    return false;
  }

  // Try to load from daily nutrition format
  Future<bool> _tryLoadFromDailyNutrition(
      SharedPreferences prefs, String today) async {
    String dailyNutritionKey = 'daily_nutrition_$today';
    print('Trying to load from $dailyNutritionKey');

    if (prefs.containsKey(dailyNutritionKey)) {
      String? nutritionJson = prefs.getString(dailyNutritionKey);

      if (nutritionJson != null && nutritionJson.isNotEmpty) {
        try {
          Map<String, dynamic> nutrition = jsonDecode(nutritionJson);
          _currentProtein = _parseNutritionValue(nutrition['protein']);
          _currentFat = _parseNutritionValue(nutrition['fat']);
          _currentCarb = _parseNutritionValue(nutrition['carbs']);
          _consumedCalories = _parseNutritionValue(nutrition['calories']);

          print('Loaded nutrition data from $dailyNutritionKey: '
              'protein=$_currentProtein, fat=$_currentFat, '
              'carbs=$_currentCarb, calories=$_consumedCalories');
          return true;
        } catch (e) {
          print('Error parsing nutrition JSON from $dailyNutritionKey: $e');
        }
      }
    }
    return false;
  }

  // Helper method to parse nutrition values safely
  int _parseNutritionValue(dynamic value, [int multiplier = 1]) {
    if (value == null) return 0;

    if (value is int) {
      return value * multiplier;
    }

    if (value is double) {
      return (value * multiplier).round();
    }

    if (value is String) {
      // Remove any non-numeric characters except decimals
      String cleanedValue = value.replaceAll(RegExp(r'[^0-9.]'), '');
      if (cleanedValue.isEmpty) return 0;

      try {
        return (double.parse(cleanedValue) * multiplier).round();
      } catch (e) {
        print('Error parsing nutrition value "$value": $e');
        return 0;
      }
    }

    return 0;
  }

  // Setup test data for debugging
  void _setupTestData() {
    print('No food log data found - setting all nutrition values to zero');

    // Set all values to zero when no food logs are found
    _currentProtein = 0;
    _currentFat = 0;
    _currentCarb = 0;
    _consumedCalories = 0;

    print(
        'Set nutrition values to zero: protein=$_currentProtein, fat=$_currentFat, carbs=$_currentCarb, calories=$_consumedCalories');
  }
}

class CodiaPage extends StatefulWidget {
  CodiaPage({super.key});

  @override
  State<StatefulWidget> createState() => _CodiaPageState();
}

class _CodiaPageState extends State<CodiaPage> {
  int _selectedIndex = 0; // Track selected nav item
  bool _showFrontCard = true; // Track which card is showing
  bool isLoading = true; // Add this if it doesn't exist
  int targetCalories = 0; // Add this if it doesn't exist
  int remainingCalories = 0; // Add this to track remaining calories
  bool isImperial = false; // Track metric/imperial setting
  double originalGoalSpeed = 0.0; // Track original goal speed for logs
  int streakCount = 0; // Track user's streak count

  // Create instance of NutritionTracker
  final NutritionTracker _nutritionTracker = NutritionTracker();

  // User data variables - will be populated from saved answers
  String userGender = 'Female'; // Default values, will be overridden
  double userWeightKg = 70.0;
  double userHeightCm = 165.0;
  int userAge = 30;
  String userGoal = 'maintain'; // FIXED: Default to maintain instead of lose
  double goalSpeedKgPerWeek = 0.5;
  double dailyCalorieAdjustment = 0.0; // Add this line to track the adjustment
  String userGymGoal =
      "null"; // FIXED: Default to "null" for balanced macros, not "Build Muscle"

  // List to store food cards loaded from SharedPreferences
  List<Map<String, dynamic>> _foodCards = [];
  bool _isLoadingFoodCards = true;

  // Simple diagnostic method to show just the key user data without all the noise
  Future<void> _showBasicUserData() async {
    final prefs = await SharedPreferences.getInstance();

    print('\n========== BASIC USER DATA ==========');
    print('ALL KEYS: ${prefs.getKeys()}');

    // Print only the most important keys
    List<String> keysToPrint = [
      'gender',
      'user_gender',
      'weight',
      'user_weight_kg',
      'initialWeight',
      'height',
      'user_height_cm',
      'heightInCm',
      'birth_date',
      'birthDate',
      'goal',
      'isGaining',
      'goal_speed',
      'speedValue'
    ];

    for (String key in keysToPrint) {
      if (prefs.containsKey(key)) {
        var value;
        try {
          value = prefs.getString(key) ??
              prefs.getDouble(key) ??
              prefs.getInt(key) ??
              prefs.getBool(key);
          print('$key = $value');
        } catch (e) {
          print('$key = ERROR: $e');
        }
      } else {
        print('$key = NOT FOUND');
      }
    }

    print('=====================================\n');
  }

  @override
  void initState() {
    super.initState();

    // First show just basic diagnostic info
    _showBasicUserData();

    // DEBUGGING HELPER - Uncomment to clear all preferences for testing
    // resetOnboardingData();  // COMMENTING THIS OUT - IT WAS ERASING ALL REAL DATA!

    _loadUserData(); // Load the user's actual data from storage
    _loadFoodCards(); // Load food cards from SharedPreferences
    _loadNutritionData(); // Load nutrition data from food logs

    // Add listener to refresh data when app resumes
    WidgetsBinding.instance.addObserver(_AppLifecycleObserver(
      onResume: () {
        print('App resumed - refreshing nutrition data');
        _loadNutritionData();
      },
    ));
  }

  @override
  void dispose() {
    // Remove observers
    WidgetsBinding.instance.removeObserver(
      _AppLifecycleObserver(onResume: () {}),
    );
    super.dispose();
  }

  // Load user data from SharedPreferences
  Future<void> _loadUserData() async {
    debugPrint('Loading user data from SharedPreferences...');

    try {
      final prefs = await SharedPreferences.getInstance();

      // DEBUG: Print all SharedPreferences keys and values
      debugPrint('All SharedPreferences data:');
      final keys = prefs.getKeys();
      for (final key in keys) {
        try {
          var value = prefs.get(key);
          debugPrint('  $key: $value (${value.runtimeType})');
        } catch (e) {
          debugPrint('  $key: Error reading value - $e');
        }
      }

      // Load gender
      if (prefs.containsKey('user_gender')) {
        setState(() {
          userGender = prefs.getString('user_gender') ?? 'Male';
        });
        debugPrint('Loaded gender from user_gender key: $userGender');
      } else if (prefs.containsKey('gender')) {
        setState(() {
          userGender = prefs.getString('gender') ?? 'Male';
        });
        debugPrint('Loaded gender from gender key: $userGender');
      } else {
        debugPrint('No gender found, using default: Male');
      }

      // Load weight with fallbacks
      double weightInKg = 0.0;
      bool weightFound = false;

      // Try these keys in order for best chance of finding weight
      final weightKeys = [
        'user_weight_kg',
        'weightInKg',
        'weight_kg',
        'weight'
      ];

      // First try to load weight as double from any key
      for (final key in weightKeys) {
        try {
          if (prefs.containsKey(key) && !weightFound) {
            final value = prefs.getDouble(key);
            if (value != null && value > 0) {
              weightInKg = value;
              weightFound = true;
              debugPrint(
                  'Found weight as double in key: $key = $weightInKg kg');
              break;
            }
          }
        } catch (e) {
          debugPrint('Error reading weight from $key as double: $e');
        }
      }

      // If weight not found as double, try integers
      if (!weightFound) {
        for (final key in weightKeys) {
          try {
            if (prefs.containsKey(key)) {
              final value = prefs.getInt(key);
              if (value != null && value > 0) {
                weightInKg = value.toDouble();
                weightFound = true;
                debugPrint('Found weight as int in key: $key = $weightInKg kg');
                break;
              }
            }
          } catch (e) {
            debugPrint('Error reading weight from $key as int: $e');
          }
        }
      }

      // Set default weight if not found
      if (!weightFound || weightInKg <= 0) {
        weightInKg = 70.0;
        debugPrint('No valid weight found, using default: $weightInKg kg');
      }

      setState(() {
        userWeightKg = weightInKg;
      });
      debugPrint('Final weight set to: $userWeightKg kg');

      // FIXED HEIGHT LOADING LOGIC - similar to working weight logic
      double heightInCm = 0.0;
      bool heightFound = false;

      // Define height keys to check in order of preference
      final heightKeys = [
        'user_height_cm',
        'heightInCm',
        'height_cm',
        'height'
      ];

      // First try to retrieve height as an INT from specific keys (in priority order)
      for (final key in ['user_height_cm', 'height']) {
        try {
          if (prefs.containsKey(key) && !heightFound) {
            final value = prefs.getInt(key);
            if (value != null && value > 0) {
              heightInCm = value.toDouble();
              heightFound = true;
              debugPrint('Found height as INT in key: $key = $heightInCm cm');
              break;
            }
          }
        } catch (e) {
          debugPrint('Error reading height from $key as int: $e');
        }
      }

      // If height not found as int in priority keys, try as DOUBLE from any key
      if (!heightFound) {
        for (final key in heightKeys) {
          try {
            if (prefs.containsKey(key)) {
              final value = prefs.getDouble(key);
              if (value != null && value > 0) {
                heightInCm = value;
                heightFound = true;
                debugPrint(
                    'Found height as DOUBLE in key: $key = $heightInCm cm');
                break;
              }
            }
          } catch (e) {
            debugPrint('Error reading height from $key as double: $e');
          }
        }
      }

      // Last resort: check all remaining keys as INT if we still haven't found height
      if (!heightFound) {
        for (final key in heightKeys) {
          try {
            if (prefs.containsKey(key)) {
              final value = prefs.getInt(key);
              if (value != null && value > 0) {
                heightInCm = value.toDouble();
                heightFound = true;
                debugPrint(
                    'Found height as INT (last resort) in key: $key = $heightInCm cm');
                break;
              }
            }
          } catch (e) {
            debugPrint(
                'Error reading height from $key as int (last resort): $e');
          }
        }
      }

      // Set default height if not found
      if (!heightFound || heightInCm <= 0) {
        heightInCm = 170.0;
        debugPrint('No valid height found, using default: $heightInCm cm');
      }

      setState(() {
        userHeightCm = heightInCm;
      });
      debugPrint('Final height set to: $userHeightCm cm');

      // ----- AGE -----
      print('\nLOADING AGE:');
      int age = 25; // Default age

      // Try multiple keys for birth date
      List<String> birthDateKeys = [
        'birth_date',
        'birthDate',
        'user_birth_date',
        'dob'
      ];
      String? birthDateStr;

      for (String key in birthDateKeys) {
        if (prefs.containsKey(key)) {
          birthDateStr = prefs.getString(key);
          print('Found birth date in key "$key": $birthDateStr');
          break;
        }
      }

      if (birthDateStr != null) {
        try {
          DateTime birthDate = DateTime.parse(birthDateStr);
          DateTime today = DateTime.now();
          age = today.year - birthDate.year;
          if (today.month < birthDate.month ||
              (today.month == birthDate.month && today.day < birthDate.day)) {
            age--;
          }

          // Only check for maximum age (130)
          if (age > 130) {
            print('WARNING: Age over 130, capping at 130');
            age = 130;
          }

          print(
              'Successfully calculated age: $age from birth date: $birthDateStr');
        } catch (e) {
          print('Error parsing birth date: $e');
        }
      } else {
        // Try to get age directly if birth date not found
        if (prefs.containsKey('user_age')) {
          age = prefs.getInt('user_age') ?? 25;
          print('Found age directly: $age');
        } else {
          print('No birth date or age found, using default: $age');
        }
      }

      // ----- GOAL -----
      print('\nLOADING GOAL:');
      List<String> goalKeys = ['goal', 'userGoal', 'weight_goal'];
      String goal = 'maintain'; // Default

      for (String key in goalKeys) {
        if (prefs.containsKey(key)) {
          String? foundGoal = prefs.getString(key);
          if (foundGoal != null) {
            goal = foundGoal;
            print('Found goal in key "$key": $goal');
            break;
          }
        }
      }

      // Additional check for isGaining which might indicate goal
      if (prefs.containsKey('isGaining')) {
        bool? isGaining = prefs.getBool('isGaining');
        if (isGaining != null) {
          // Only use isGaining flag if isMaintaining isn't set to true
          bool isMaintaining = prefs.getBool('isMaintaining') ?? false;
          if (!isMaintaining) {
            goal = isGaining ? 'gain' : 'lose';
            print('Found isGaining flag: $isGaining, setting goal to: $goal');
          } else {
            print(
                'Found isMaintaining=true, maintaining "maintain" goal even with isGaining present');
          }
        }
      }
      print('Final goal value: $goal');

      // ----- GYM GOAL -----
      print('\nLOADING GYM GOAL:');
      List<String> gymGoalKeys = [
        'gymGoal',
        'gym_goal',
        'fitnessGoal',
        'fitness_goal'
      ];
      String? gymGoal;

      for (String key in gymGoalKeys) {
        if (prefs.containsKey(key)) {
          gymGoal = prefs.getString(key);
          if (gymGoal != null) {
            print('Found gym goal in key "$key": $gymGoal');
            break;
          }
        }
      }
      print('Final gym goal value: ${gymGoal ?? "null"}');

      // ----- GOAL SPEED -----
      print('\nLOADING GOAL SPEED:');
      List<String> goalSpeedKeys = [
        'goal_speed',
        'goalSpeed',
        'targetRate',
        'target_rate',
        'goal_speed_kg_per_week', // This key explicitly indicates kg units
      ];
      double goalSpeed = 0.0; // Default
      double originalGoalSpeed = 0.0; // Store original for display
      String speedUnit = 'kg/week'; // Default

      // First, try to find any goal_speed_kg_per_week which is guaranteed to be in kg
      try {
        if (prefs.containsKey('goal_speed_kg_per_week')) {
          double? speedKg = prefs.getDouble('goal_speed_kg_per_week');
          if (speedKg != null) {
            goalSpeed = speedKg;
            originalGoalSpeed = goalSpeed;
            speedUnit = 'kg/week';
            print('Found goal speed in kg: $goalSpeed kg/week');
          }
        }
      } catch (e) {
        print('Error reading goal_speed_kg_per_week: $e');
      }

      // If we didn't find the kg-specific key, check other keys
      if (goalSpeed == 0.0) {
        // Try other keys
        for (String key in goalSpeedKeys) {
          if (key == 'goal_speed_kg_per_week') continue; // Already checked

          try {
            if (prefs.containsKey(key)) {
              double? speed = prefs.getDouble(key);
              if (speed != null) {
                goalSpeed = speed;
                originalGoalSpeed = goalSpeed;
                print('Found goal speed in key "$key": $goalSpeed');
                break;
              }

              // Try as int if double fails
              int? speedInt = prefs.getInt(key);
              if (speedInt != null) {
                goalSpeed = speedInt.toDouble();
                originalGoalSpeed = goalSpeed;
                print('Found goal speed (as int) in key "$key": $goalSpeed');
                break;
              }
            }
          } catch (e) {
            print('Error reading goal speed from key "$key": $e');
          }
        }
        print('Original goal speed: $originalGoalSpeed');
      }

      // ----- METRIC SETTING -----
      print('\nLOADING METRIC SETTING:');
      List<String> metricKeys = ['is_metric', 'isMetric', 'useMetric'];
      bool isMetric = false; // Default to imperial

      for (String key in metricKeys) {
        if (prefs.containsKey(key)) {
          bool? metric = prefs.getBool(key);
          if (metric != null) {
            isMetric = metric;
            print('Found metric setting in key "$key": $isMetric');
            break;
          }
        }
      }

      // Calculate if we need to convert units
      bool isImperialUnits = !isMetric;

      // Auto-detect if values suggest imperial units
      if (weightInKg > 100) {
        print('Weight > 100kg suggests imperial units (pounds)');
        isImperialUnits = true;
      }

      // CRITICAL: Handle goal speed units correctly based on metric setting
      // If isMetric is true: goalSpeed is in kg/week
      // If isMetric is false (imperial): goalSpeed is in lb/week and needs conversion to kg for calculations

      double displayGoalSpeed = goalSpeed;
      bool speedWasInImperial = !isMetric; // Default based on unit system

      // If we're using imperial units, process accordingly
      if (isImperialUnits && goal != 'maintain') {
        // Convert weight if needed
        if (weightInKg > 100) {
          double oldWeight = weightInKg;
          weightInKg = weightInKg * 0.453592;
          print(
              'Converting weight from lbs to kg: $oldWeight lbs → $weightInKg kg');
        }

        // Handle goal speed for imperial systems - it's in lb/week and needs conversion
        // UNLESS we got it from goal_speed_kg_per_week which is already in kg
        speedWasInImperial = true;
        speedUnit = 'lb/week';
        displayGoalSpeed = goalSpeed; // Store original value for display

        // Check if we got the value from the kg-specific key
        if (prefs.containsKey('goal_speed_kg_per_week')) {
          print('Using goal speed already in kg: $goalSpeed kg/week');
          speedWasInImperial = false;
          speedUnit = 'kg/week';
        } else if (goalSpeed > 0) {
          // This is in lb/week and needs conversion to kg for calculations
          double oldSpeed = goalSpeed;
          goalSpeed = goalSpeed * 0.453592; // Convert to kg/week
          print(
              'Converting goal speed from lb/week to kg/week: $oldSpeed lb/week → $goalSpeed kg/week');
        }
      }

      // Set goal speed to 0 for maintain
      if (goal == 'maintain') {
        print('Goal is maintain, setting goal speed to 0');
        goalSpeed = 0.0;
        displayGoalSpeed = 0.0;
      }

      // NORMALIZE GOAL SPEED to exact increments - but only for display or for metric values
      if (goal != 'maintain' && goalSpeed > 0) {
        // For display value, round to exactly 1 decimal place
        displayGoalSpeed = (displayGoalSpeed * 10).round() / 10.0;

        if (speedWasInImperial) {
          print(
              'Normalized display goal speed to ${displayGoalSpeed.toStringAsFixed(1)} lb/week');
        } else {
          print(
              'Normalized display goal speed to ${displayGoalSpeed.toStringAsFixed(1)} kg/week');
        }

        // For the actual calculation value, also normalize to 1 decimal
        goalSpeed = (goalSpeed * 10).round() / 10.0;
        print(
            'Normalized calculation goal speed to ${goalSpeed.toStringAsFixed(1)} kg/week');
      }

      // Round weight to 1 decimal place
      weightInKg = (weightInKg * 10).round() / 10;

      // Ensure height is a whole number
      heightInCm = heightInCm.round().toDouble();

      // Update state with loaded values
      setState(() {
        userGender = prefs.getString('gender') ?? 'Male';
        userWeightKg = weightInKg;
        userHeightCm = heightInCm;
        userAge = age;
        userGoal = goal;
        goalSpeedKgPerWeek = goalSpeed;
        userGymGoal = gymGoal ?? "null"; // Handle null case
        isImperial = isImperialUnits;
        originalGoalSpeed = originalGoalSpeed;

        // Calculate calories now that all data is loaded
        _updateCalculatedValues();
      });

      print('\nFINAL VALUES USED:');
      print('- Age: $userAge');
      print('- Gender: "$userGender"');
      print('- Weight: ${(userWeightKg * 10).round() / 10.0} kg');

      // Display height in appropriate units
      if (isImperialUnits) {
        // Convert cm to inches
        double heightInches = userHeightCm / 2.54;
        int feet = (heightInches / 12).floor();
        int inches = (heightInches % 12).round();
        print('- Height: ${userHeightCm.round()} cm (${feet}\'${inches}")');
      } else {
        print('- Height: ${userHeightCm.round()} cm');
      }

      print('- Goal: "$userGoal"');
      print('- Gym Goal: $userGymGoal');
      // Display the goal speed in the appropriate units
      if (isImperialUnits && speedWasInImperial) {
        print(
            '- Goal Speed: ${displayGoalSpeed.toStringAsFixed(1)} $speedUnit');
      } else {
        print('- Goal Speed: ${goalSpeedKgPerWeek.toStringAsFixed(1)} kg/week');
      }
      print('- Target Calories: $targetCalories');
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  // Update UI state with calculated values
  void _updateCalculatedValues() {
    // Directly use the same calculation method as calculation_screen.dart
    double calculatedValue = _calculateTargetCalories();

    // Set exact same value to display in UI
    setState(() {
      targetCalories = calculatedValue.toInt();
      remainingCalories = targetCalories; // Set remaining to target initially
      isLoading = false;
    });

    print(
        "FINAL CALCULATED TARGET CALORIES (EXACTLY MATCHING CALCULATION_SCREEN): $targetCalories");
  }

  // Calculate target calories based on user data - EXACT COPY FROM CALCULATION_SCREEN.DART
  double _calculateTargetCalories() {
    // Print input values for debugging
    print('CALCULATION INPUTS (Codia Page):');
    print('- Gender: "$userGender"');
    print('- Weight: $userWeightKg kg');
    print('- Height: $userHeightCm cm');
    print('- Age: $userAge');
    print('- Goal: "$userGoal"');
    print('- Goal Speed: $goalSpeedKgPerWeek kg/week');
    print('- Gym Goal: "$userGymGoal"');
    print('- Is Imperial: $isImperial');

    // Convert measurements for consistency with calculation_screen.dart
    final weightInKg = userWeightKg;
    final heightInCm = userHeightCm;
    final gender = userGender;
    final birthDate = DateTime.now().subtract(Duration(days: 365 * userAge));
    final isGaining = userGoal == 'gain';
    double speedValue = goalSpeedKgPerWeek;
    final isMetric = !isImperial;
    final gymGoal = userGymGoal;

    print('Normalized values:');
    print('- Weight in kg: $weightInKg');
    print('- Height in cm: $heightInCm');
    print('- Speed: $speedValue ${isMetric ? 'kg' : 'lbs'}/week');
    print('- Units: ${isMetric ? 'Metric' : 'Imperial'}');

    // NORMALIZE GOAL SPEED to exact increments - EXACT COPY FROM CALCULATION_SCREEN
    double normalizedSpeed = speedValue;
    if (speedValue > 0) {
      if (isMetric) {
        // Round to exactly 1 decimal place
        normalizedSpeed = (speedValue * 10).round() / 10.0;
        print(
            'Normalized goal speed from $speedValue to ${normalizedSpeed.toStringAsFixed(1)} kg/week');
      } else {
        // For imperial units, speedValue is already in kg, so convert to lbs first for display
        double speedInLbs = speedValue / 0.453592;
        // Then round to exactly 1 decimal place
        double displaySpeed = (speedInLbs * 10).round() / 10.0;
        print(
            'Display speed in pounds: ${displaySpeed.toStringAsFixed(1)} lb/week');

        // But keep using the kg value for calculations
        normalizedSpeed = (speedValue * 10).round() / 10.0;
        print(
            'Normalized goal speed (kept in kg): ${normalizedSpeed.toStringAsFixed(1)} kg/week');
      }
    }

    // Round weightInKg to 1 decimal place - EXACT COPY FROM CALCULATION_SCREEN
    double roundedWeightKg = (weightInKg * 10).round() / 10.0;

    // Ensure height is a whole number - EXACT COPY FROM CALCULATION_SCREEN
    int roundedHeight = heightInCm.round();

    // Calculate TDEE first using rounded values - EXACT COPY FROM CALCULATION_SCREEN
    int tdee = calculateTDEE(
      gender: gender,
      weightKg: roundedWeightKg.round(), // Use rounded weight
      heightCm: roundedHeight, // Use rounded height
      userAge: userAge, // Use the calculated age
    );

    print('TDEE calculated: $tdee');

    // Calculate daily deficit/surplus - EXACT COPY FROM CALCULATION_SCREEN
    int dailyDeficit = 0;

    if (userGoal == 'maintain') {
      dailyDeficit = 0;
      print('Goal is maintain, deficit = 0');
    } else {
      if (isMetric) {
        // Metric: Use 7700 kcal per kg
        // Do NOT round the deficit calculation to maintain precision for small values
        double exactMetricDeficit = normalizedSpeed * 7700 / 7;
        dailyDeficit =
            exactMetricDeficit.floor(); // Weekly kg to daily calories
        print(
            'Metric calculation: ${normalizedSpeed.toStringAsFixed(3)} kg/week × 7700 ÷ 7 = ${exactMetricDeficit.toStringAsFixed(3)} → $dailyDeficit calories/day');
      } else {
        // Imperial: Use 3500 kcal per lb
        // However, we're still using kg value for normalizedSpeed, so convert to lb first
        double speedInLbs = normalizedSpeed / 0.453592;
        double displaySpeedLb = (speedInLbs * 10).round() / 10.0;

        // Calculate deficit using pounds formula
        double exactDeficit = speedInLbs * 3500 / 7;
        dailyDeficit = exactDeficit.floor(); // Weekly lbs to daily calories
        print(
            'Imperial calculation: ${displaySpeedLb.toStringAsFixed(1)} lb/week × 3500 ÷ 7 = ${exactDeficit.toStringAsFixed(3)} → $dailyDeficit calories/day');
      }
    }

    print('Daily deficit calculated: $dailyDeficit');

    // Calculate final target calories - EXACT COPY FROM CALCULATION_SCREEN
    double rawCalculatedCalories;
    if (userGoal == 'gain') {
      rawCalculatedCalories = tdee.toDouble() + dailyDeficit.toDouble();
    } else if (userGoal == 'lose') {
      rawCalculatedCalories = tdee.toDouble() - dailyDeficit.toDouble();
    } else {
      // maintain - use TDEE directly with no adjustment
      rawCalculatedCalories = tdee.toDouble();
    }

    print('Raw calculated calories before flooring: $rawCalculatedCalories');

    // Ensure the calories match exactly with calculation_screen.dart by using floor
    int calculatedCalories = rawCalculatedCalories.floorToDouble().toInt();

    print('Final target calories (floored): $calculatedCalories');

    return calculatedCalories.toDouble();
  }

  // TDEE calculation - EXACT COPY FROM CALCULATION_SCREEN
  int calculateTDEE({
    required String gender,
    required int weightKg,
    required int heightCm,
    required int userAge,
  }) {
    // BMR using Mifflin-St Jeor Equation
    double bmr;
    if (gender == 'Female') {
      bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * userAge) - 161;
    } else if (gender == 'Male') {
      bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * userAge) + 5;
    } else {
      // Default to female formula for "Other"
      bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * userAge) - 161;
    }

    // Apply activity multiplier (1.2 for sedentary - little/no exercise)
    final tdee = bmr * 1.2;
    print('BMR calculated: $bmr, TDEE with multiplier: $tdee');

    return tdee.round();
  }

  // Helper method to ensure consistent formatting of ingredient values
  dynamic normalizeIngredientValue(dynamic value) {
    if (value == null) return 0;

    // If it's a string that should be a number, convert it
    if (value is String && RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
      try {
        // Try to parse as integer first
        return int.tryParse(value) ?? double.tryParse(value) ?? 0;
      } catch (e) {
        return 0;
      }
    }

    return value;
  }

  // Helper method to preserve high quality image data
  String preserveImageQuality(String? base64Data) {
    if (base64Data == null || base64Data.isEmpty) return '';

    // Keep original high-quality data without any re-processing
    return base64Data;
  }

  // Load food cards from SharedPreferences
  Future<void> _loadFoodCards() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? storedCards = prefs.getStringList('food_cards');

      List<Map<String, dynamic>> cards = [];

      if (storedCards != null && storedCards.isNotEmpty) {
        final currentTime = DateTime.now().millisecondsSinceEpoch;
        final twelveHoursInMillis =
            12 * 60 * 60 * 1000; // 12 hours in milliseconds

        for (String cardJson in storedCards) {
          try {
            Map<String, dynamic> cardData = jsonDecode(cardJson);

            // Check if the card is less than 12 hours old
            int timestamp = cardData['timestamp'] ?? 0;
            if (currentTime - timestamp < twelveHoursInMillis) {
              // Ensure ingredients data structure is properly maintained
              if (cardData.containsKey('ingredients')) {
                List<dynamic> ingredients = cardData['ingredients'];

                // For each ingredient, ensure we have a properly structured map
                List<dynamic> validIngredients = [];
                Map<String, dynamic> ingredientAmounts = {};
                Map<String, dynamic> ingredientCalories = {};

                for (var ingredient in ingredients) {
                  if (ingredient is Map<String, dynamic>) {
                    // Normalize values to ensure proper data types
                    Map<String, dynamic> normalizedIngredient = {
                      'name': ingredient['name'] ?? 'Ingredient',
                      'amount': ingredient['amount'] ?? '1 serving',
                      'calories':
                          normalizeIngredientValue(ingredient['calories']),
                    };

                    // Use the normalized ingredient
                    validIngredients.add(normalizedIngredient);

                    // Store the name, amount and calories in separate maps for lookup
                    String name = normalizedIngredient['name'];
                    ingredientAmounts[name] = normalizedIngredient['amount'];
                    ingredientCalories[name] = normalizedIngredient['calories'];
                  } else if (ingredient is String) {
                    // If it's a string, we need to create a map and add it
                    validIngredients.add(ingredient);
                  }
                }

                // Replace the ingredients list with our validated list
                cardData['ingredients'] = validIngredients;

                // Add the lookup maps for amounts and calories
                cardData['ingredient_amounts'] = ingredientAmounts;
                cardData['ingredient_calories'] = ingredientCalories;
              }

              // Preserve the original high-quality image if it exists
              if (cardData.containsKey('image') &&
                  cardData['image'] is String) {
                cardData['image'] = preserveImageQuality(cardData['image']);
              }

              cards.add(cardData);
            }
          } catch (e) {
            print("Error parsing food card JSON: $e");
          }
        }

        // Save filtered cards back if any were removed due to expiration
        if (cards.length < storedCards.length) {
          final List<String> updatedCards =
              cards.map((card) => jsonEncode(card)).toList();
          await prefs.setStringList('food_cards', updatedCards);
        }

        // Sort by timestamp (most recent first)
        cards.sort(
            (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

        // Update streak count if we have food cards
        setState(() {
          _foodCards = cards;
          _isLoadingFoodCards = false;

          // Update streak count if we have food cards
          if (cards.isNotEmpty) {
            streakCount = 1; // Set streak to 1 if any food images are uploaded
          }
        });

        print("Loaded ${cards.length} food cards");
      }
    } catch (e) {
      print("Error loading food cards: $e");
      setState(() {
        _isLoadingFoodCards = false;
      });
    }
  }

  // Helper method to extract numeric value from a string and convert to int
  int _extractNumericValueAsInt(dynamic input, {int multiplier = 1}) {
    if (input is int) {
      return input * multiplier;
    } else if (input is double) {
      return (input * multiplier).round();
    } else if (input is String) {
      // Try to extract digits from the string, including possible decimal values
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(input);
      if (match != null && match.group(1) != null) {
        // Parse as double first to handle potential decimal values
        final value = double.tryParse(match.group(1)!) ?? 0.0;
        // Then round to nearest int, after applying multiplier
        return (value * multiplier).round();
      }
    }
    return 0;
  }

  // Helper method to extract numeric value as string without decimal precision
  String _extractNumericValue(dynamic input) {
    if (input is int) {
      // Return value as is - already an integer
      return input.toString();
    } else if (input is double) {
      // Convert to integer, removing decimals
      return input.toInt().toString();
    } else if (input is String) {
      // Try to extract digits from the string, including decimal values
      final match = RegExp(r'(\d+\.?\d*)').firstMatch(input);
      if (match != null && match.group(1) != null) {
        // Convert to double then integer to remove decimals
        double value = double.tryParse(match.group(1)!) ?? 0.0;
        return value.toInt().toString();
      }
    }
    return "0"; // Return string "0" as fallback (without decimal)
  }

  // Returns the exact integer value without rounding to nearest 5 or 10
  int _getRawCalorieValue(double calories) {
    // Just convert to int without rounding to multiples of 5 or 10
    return calories.toInt();
  }

  // Helper method to build default image container
  Widget _buildDefaultImageContainer() {
    return Container(
      width: 92,
      height: 92,
      color: Color(0xFFDADADA),
      child: Center(
        child: Image.asset(
          'assets/images/meal1.png',
          width: 28,
          height: 28,
        ),
      ),
    );
  }

  // Helper method to create a square food card image
  Widget _buildFoodCardImage(String? base64Image) {
    if (base64Image == null || base64Image.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildDefaultImageContainer(),
      );
    }

    try {
      Uint8List bytes = base64Decode(base64Image);
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          bytes,
          width: 92,
          height: 92,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          alignment: Alignment.center,
        ),
      );
    } catch (e) {
      print("Error decoding image: $e");
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildDefaultImageContainer(),
      );
    }
  }

  // Build a food card widget from food card data
  Widget _buildFoodCard(Map<String, dynamic> foodCard) {
    // Convert timestamp to time string (e.g., "12:07")
    String timeString = "Now";
    try {
      if (foodCard.containsKey('timestamp')) {
        DateTime timestamp =
            DateTime.fromMillisecondsSinceEpoch(foodCard['timestamp']);
        timeString =
            "${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}";
      }
    } catch (e) {
      print("Error formatting time: $e");
    }

    // Get values with fallbacks ensuring correct types
    String name = foodCard['name'] ?? 'Unknown Meal';

    // Get counter (portions) value with fallback to 1
    int counter = 1;
    if (foodCard.containsKey('counter')) {
      counter = foodCard['counter'] is int
          ? foodCard['counter']
          : _extractNumericValueAsInt(foodCard['counter']);

      // Ensure counter is between 1 and 3
      counter = counter.clamp(1, 3);
    }

    // Handle numeric values with proper parsing - DO NOT apply counter multiplier
    int calories = _extractNumericValueAsInt(foodCard['calories']);
    int protein = _extractNumericValueAsInt(foodCard['protein']);
    int fat = _extractNumericValueAsInt(foodCard['fat']);
    int carbs = _extractNumericValueAsInt(foodCard['carbs']);

    String? base64Image = foodCard['image'];
    List<dynamic> ingredients = foodCard['ingredients'] ?? [];

    // Properly convert ingredients to ensure they are all Map<String, dynamic>
    List<Map<String, dynamic>> processedIngredients = [];
    for (var ingredient in ingredients) {
      if (ingredient is Map<String, dynamic>) {
        // Already a Map<String, dynamic>, just add it
        processedIngredients.add(ingredient);
      } else if (ingredient is String) {
        // Convert String to Map<String, dynamic>
        // BUT preserve original calories and amount if found in the parent foodCard
        String ingredientName = ingredient.toString();

        // Try to find amount and calories by examining foodCard
        String amount = '1 serving';
        dynamic ingredientCalories = 0;

        // If the parent foodCard has calories data for this specific ingredient, use it
        if (foodCard.containsKey('ingredient_amounts') &&
            foodCard['ingredient_amounts'] is Map &&
            foodCard['ingredient_amounts'].containsKey(ingredientName)) {
          amount = foodCard['ingredient_amounts'][ingredientName] ?? amount;
        }

        if (foodCard.containsKey('ingredient_calories') &&
            foodCard['ingredient_calories'] is Map &&
            foodCard['ingredient_calories'].containsKey(ingredientName)) {
          ingredientCalories = foodCard['ingredient_calories']
                  [ingredientName] ??
              ingredientCalories;
        }

        processedIngredients.add({
          'name': ingredientName,
          'amount': amount,
          'calories': ingredientCalories,
        });
      } else {
        // Try to convert other types to String then to Map
        try {
          String ingredientStr = ingredient.toString();

          // Use the same logic as above to try to find amount and calories
          String amount = '1 serving';
          dynamic ingredientCalories = 0;

          if (foodCard.containsKey('ingredient_amounts') &&
              foodCard['ingredient_amounts'] is Map &&
              foodCard['ingredient_amounts'].containsKey(ingredientStr)) {
            amount = foodCard['ingredient_amounts'][ingredientStr] ?? amount;
          }

          if (foodCard.containsKey('ingredient_calories') &&
              foodCard['ingredient_calories'] is Map &&
              foodCard['ingredient_calories'].containsKey(ingredientStr)) {
            ingredientCalories = foodCard['ingredient_calories']
                    [ingredientStr] ??
                ingredientCalories;
          }

          processedIngredients.add({
            'name': ingredientStr,
            'amount': amount,
            'calories': ingredientCalories,
          });
        } catch (e) {
          print("Skipping invalid ingredient: $e");
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 29, vertical: 8),
      child: GestureDetector(
        onTap: () {
          // Pass the original base values to FoodCardOpen, not the multiplied ones
          // This ensures FoodCardOpen works with the base values and can multiply them as needed
          int baseCalories = _extractNumericValueAsInt(foodCard['calories']);
          int baseProtein = _extractNumericValueAsInt(foodCard['protein']);
          int baseFat = _extractNumericValueAsInt(foodCard['fat']);
          int baseCarbs = _extractNumericValueAsInt(foodCard['carbs']);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FoodCardOpen(
                foodName: name,
                calories: baseCalories.toString(),
                protein: baseProtein.toString(),
                fat: baseFat.toString(),
                carbs: baseCarbs.toString(),
                imageBase64: base64Image,
                ingredients: processedIngredients,
                healthScore: foodCard['health_score'] ?? '8/10',
              ),
            ),
          ).then((_) {
            // Refresh data when returning from FoodCardOpen
            _loadFoodCards();
            _loadNutritionData();
          });
        },
        child: Container(
          padding: EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Food image or placeholder - maintain perfect square shape
              SizedBox(
                width: 92,
                height: 92,
                child: _buildFoodCardImage(base64Image),
              ),
              SizedBox(width: 12),

              // Food details
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              counter > 1 ? '$name (×$counter)' : name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6.6, vertical: 2.2),
                            decoration: BoxDecoration(
                              color: Color(0xFFF2F2F2),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Text(
                              timeString,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.normal,
                                color: Colors.black,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 7),

                      // Calories
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/energy.png',
                            width: 18.83,
                            height: 18.83,
                          ),
                          SizedBox(width: 7.7),
                          Text(
                            '$calories calories',
                            style: TextStyle(
                              fontSize: 15.4,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 7),

                      // Macros
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/steak.png',
                            width: 14,
                            height: 14,
                          ),
                          SizedBox(width: 7.7),
                          Text(
                            '${protein}g',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          SizedBox(width: 24.2),
                          Image.asset(
                            'assets/images/avocado.png',
                            width: 14,
                            height: 14,
                          ),
                          SizedBox(width: 7.7),
                          Text(
                            '${fat}g',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          SizedBox(width: 24.2),
                          Image.asset(
                            'assets/images/carbicon.png',
                            width: 14,
                            height: 14,
                          ),
                          SizedBox(width: 7.7),
                          Text(
                            '${carbs}g',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.normal,
                              color: Colors.black,
                              decoration: TextDecoration.none,
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

  // Build a list of widgets for the Recent Activity section
  List<Widget> _buildDynamicFoodCards() {
    final List<Widget> widgets = [];

    // Only show loading indicator if we're still loading AND there are food cards to show
    if (_isLoadingFoodCards && _foodCards.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    // Display food cards loaded from SharedPreferences
    else if (_foodCards.isNotEmpty) {
      for (var foodCard in _foodCards) {
        widgets.add(_buildFoodCard(foodCard));
      }
    }
    // No loading animation when there are no food cards to show
    // Just return an empty list of widgets

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    // Update nutrition data when building to ensure consistent values
    if (!isLoading && targetCalories > 0) {
      remainingCalories = targetCalories - _nutritionTracker.consumedCalories;
      if (remainingCalories < 0) remainingCalories = 0;
    }

    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      // Ensure the entire screen is filled with the background color
      backgroundColor:
          Color(0xFFF5F5F5), // Light background color to match the app's theme
      body: Stack(
        children: [
          // Background and scrollable content
          Container(
            // Ensure the container fills the entire screen
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/images/background4.jpg'),
                fit: BoxFit.cover,
              ),
            ),
            child: SingleChildScrollView(
              // Ensure the scrollable content fills the available space
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Add padding for status bar
                  SizedBox(height: statusBarHeight),

                  // Header with Fitly title and icons
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 29, vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Calendar icon
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MemoriesScreen(),
                              ),
                            );
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 26, vertical: 8),
                            width: 70,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/calendar.png',
                              width: 19.4,
                              height: 19.4,
                            ),
                          ),
                        ),

                        // Fitly title
                        Text(
                          'Fitly',
                          style: TextStyle(
                            fontSize: 34.56,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SF Pro Display',
                            color: Colors.black,
                            decoration: TextDecoration.none,
                          ),
                        ),

                        // Streak icon with count
                        GestureDetector(
                          onTap: () async {
                            // Show streak popup
                            _showStreakPopup();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            width: 70, // Fixed width
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/images/streak0.png',
                                  width: 19.4,
                                  height: 19.4,
                                  color: streakCount > 0
                                      ? Color(0xFFFF9801)
                                      : null, // Orange for active streak
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  streakCount > 0 ? '1' : '0',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Today text
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 29, top: 8, bottom: 16),
                    child: Text(
                      'Today',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'SF Pro Display',
                        color: Colors.black,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),

                  // Flippable Calorie/Activity card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 29),
                    child: FlipCard(
                      frontSide: _buildCalorieCard(),
                      backSide: HomeCard2(),
                      onFlip: () {
                        setState(() {
                          _showFrontCard = !_showFrontCard;
                        });
                      },
                    ),
                  ),

                  // Pagination dots
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _showFrontCard
                                  ? Colors.black
                                  : Color(0xFFDADADA),
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _showFrontCard
                                  ? Color(0xFFDADADA)
                                  : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Snap Meal and Coach buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 29),
                    child: Row(
                      children: [
                        // Snap Meal button
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              // Navigate to SnapFood screen
                              _navigateToSnapFood();
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    'assets/images/camera.png',
                                    width: 24,
                                    height: 24,
                                  ),
                                  SizedBox(width: 14),
                                  Text(
                                    'Snap Meal',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        SizedBox(width: 22),

                        // Coach button
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _navigateToCoach();
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    'assets/images/coach.png',
                                    width: 24,
                                    height: 24,
                                  ),
                                  SizedBox(width: 14),
                                  Text(
                                    'Coach',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Recent Activity section
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 29, top: 24, bottom: 16),
                    child: Text(
                      'Recent Activity',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'SF Pro Display',
                        color: Colors.black,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),

                  // Dynamic food cards
                  ..._buildDynamicFoodCards(),

                  // Add padding at the bottom to ensure content doesn't get cut off by the nav bar
                  SizedBox(height: 90),
                ],
              ),
            ),
          ),

          // Fixed bottom navigation bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 90, // Increased from 60px to 90px
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 0),
                child: Transform.translate(
                  offset: Offset(0, -5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildNavItem('Home', 'assets/images/home.png',
                          _selectedIndex == 0, 0),
                      _buildNavItem('Social', 'assets/images/socialicon.png',
                          _selectedIndex == 1, 1),
                      _buildNavItem('Nutrition', 'assets/images/nutrition.png',
                          _selectedIndex == 2, 2),
                      _buildNavItem('Workout', 'assets/images/dumbbell.png',
                          _selectedIndex == 3, 3),
                      _buildNavItem('Profile', 'assets/images/profile.png',
                          _selectedIndex == 4, 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
      String label, String iconPath, bool isSelected, int index) {
    return GestureDetector(
      onTap: () {
        if (label == 'Workout') {
          Navigator.pushReplacement(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  ChooseWorkout(),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          );
        } else if (label == 'Nutrition') {
          // Call our custom navigation method for Nutrition
          _navigateToNutrition();
        }
        setState(() {
          _selectedIndex = index;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            iconPath,
            width: 27.6,
            height: 27.6,
            color: isSelected ? Colors.black : Colors.grey,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.grey,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalorieCard() {
    // Get the consumed calories directly from the NutritionTracker singleton
    int consumedCalories = _nutritionTracker.consumedCalories;

    // Calculate remaining calories directly - don't rely on class variables that might be stale
    int directRemaining = targetCalories - consumedCalories;

    // Get the macronutrient values from the NutritionTracker singleton
    int currentProtein = _nutritionTracker.currentProtein;
    int currentFat = _nutritionTracker.currentFat;
    int currentCarb = _nutritionTracker.currentCarb;

    // Define macro targets for UI
    int proteinTarget = 123; // Default values
    int fatTarget = 55;
    int carbTarget = 246;

    // Define macro distribution based on gym goal
    Map<String, Map<String, double>> macroTargets = {
      "Build Muscle": {
        "proteinPercent": 0.32,
        "carbPercent": 0.45,
        "fatPercent": 0.23,
      },
      "Gain Strength": {
        "proteinPercent": 0.28,
        "carbPercent": 0.42,
        "fatPercent": 0.30,
      },
      "Boost Endurance": {
        "proteinPercent": 0.18,
        "carbPercent": 0.60,
        "fatPercent": 0.22,
      },
      // Default balanced macros when no gym goal is selected
      "null": {
        "proteinPercent": 0.25,
        "carbPercent": 0.50,
        "fatPercent": 0.25,
      }
    };

    // Get the macro distribution for the selected gym goal
    Map<String, double> selectedMacros = macroTargets["null"]!; // Default
    String goalKey = userGymGoal ?? "null";
    if (macroTargets.containsKey(goalKey)) {
      selectedMacros = macroTargets[goalKey]!;
    }

    // Calculate macronutrient targets based on calorie goal
    if (targetCalories > 0) {
      double proteinPercent = selectedMacros["proteinPercent"]!;
      double carbPercent = selectedMacros["carbPercent"]!;
      double fatPercent = selectedMacros["fatPercent"]!;

      proteinTarget = ((targetCalories * proteinPercent) / 4).round();
      fatTarget = ((targetCalories * fatPercent) / 9).round();
      carbTarget = ((targetCalories * carbPercent) / 4).round();
    }

    // Determine deficit or surplus based on consumed vs target
    String deficitLabel = "Deficit";
    String deficitValue = "-${calculateTDEE(
      gender: userGender,
      weightKg: ((userWeightKg * 10).round() / 10.0).round(),
      heightCm: userHeightCm.round(),
      userAge: userAge,
    ).round()}";

    // If consumed calories exceed target, show as surplus
    if (consumedCalories >= targetCalories) {
      deficitLabel = "Surplus";
      int surplusAmount = consumedCalories - targetCalories;
      deficitValue = "${surplusAmount}";

      print(
          "SURPLUS DETECTED: Consumed=$consumedCalories, Target=$targetCalories, Surplus=$surplusAmount");
    }

    // Special handling for maintain goal
    if (userGoal == 'maintain') {
      if (directRemaining > 0) {
        deficitLabel = "Deficit";
        deficitValue = "-${directRemaining.abs().round()}";
      } else {
        deficitLabel = "Surplus";
        deficitValue = "${directRemaining.abs().round()}";
      }
    }

    // Format remaining calories text to show negative when below 0
    String remainingText = directRemaining < 0
        ? "-${directRemaining.abs().round()}"
        : "${directRemaining.round()}";

    // Debug print to verify our calculations
    print("DEBUG VALUES:");
    print("Target calories: $targetCalories");
    print("Consumed calories: $consumedCalories");
    print("Direct remaining: $directRemaining");
    print("Deficit/Surplus label: $deficitLabel");
    print("Deficit/Surplus value: $deficitValue");
    print("Remaining text: $remainingText");

    return Container(
      height: 220,
      padding: EdgeInsets.fromLTRB(20, 15, 20, 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          // Calorie stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Deficit/Surplus
              Column(
                children: [
                  Text(
                    deficitValue,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    deficitLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),

              // Circular progress
              Container(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Simple circle gauge using CustomPaint
                    Transform.translate(
                      offset: Offset(0, -3.9), // Move up by 3%
                      child: CustomPaint(
                        size: Size(132, 132),
                        painter: CalorieGaugePainter(
                          // Important: Always directly use consumed calories divided by target
                          // Without relying on a state variable that might not be updating
                          consumedPercentage: targetCalories > 0
                              ? (consumedCalories / targetCalories)
                                  .clamp(0.0, 1.0)
                              : 0.0,
                        ),
                      ),
                    ),

                    // Remaining calories text
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          remainingText,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        Text(
                          'Remaining',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                            color: Colors.black,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Burned
              Column(
                children: [
                  Text(
                    '0', // NOTE: Burned calculation is separate
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  Text(
                    'Burned',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: 5), // Reduced from 10

          // Macronutrient progress bars
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Protein
              Column(
                children: [
                  Text(
                    'Protein',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(height: 4),
                  Container(
                    width: 80,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: Color(0xFFEEEEEE),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: proteinTarget > 0
                          ? (currentProtein / proteinTarget).clamp(0.0, 1.0)
                          : 0.0,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Color(0xFFD7C1FF), // Light purple
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '$currentProtein / $proteinTarget g',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),

              // Fat
              Column(
                children: [
                  Text(
                    'Fat',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(width: 4),
                  Container(
                    width: 80,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: Color(0xFFEEEEEE),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: fatTarget > 0
                          ? (currentFat / fatTarget).clamp(0.0, 1.0)
                          : 0.0,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Color(0xFFFFD8B1), // Light orange
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '$currentFat / $fatTarget g',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),

              // Carbs
              Column(
                children: [
                  Text(
                    'Carbs',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  SizedBox(width: 4),
                  Container(
                    width: 80,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: Color(0xFFEEEEEE),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: carbTarget > 0
                          ? (currentCarb / carbTarget).clamp(0.0, 1.0)
                          : 0.0,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Color(0xFFB1EFD8), // Light green
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '$currentCarb / $carbTarget g',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // For testing/debugging only - clears preferences and forces defaults
  Future<void> resetOnboardingData() async {
    print('\n========== CLEARING ALL SHARED PREFERENCES ==========');
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    print('All SharedPreferences data cleared');

    // Set test data for verifying calculations
    await prefs.setString('gender', 'Male');
    await prefs.setDouble('user_weight_kg', 66.0);

    // CRITICAL FIX: For users who selected imperial units and entered height in feet/inches,
    // we need to store height in cm after converting. Assuming 6'1" = 73 inches = 185.42 cm
    // This simulates how onboarding screens should save height when using imperial units
    int heightInCm = 185; // 6'1" converted to cm
    await prefs.setInt('user_height_cm', heightInCm);
    await prefs.setDouble('heightInCm', heightInCm.toDouble());

    // Store indicator that we're using imperial units
    await prefs.setBool('is_metric', false);

    await prefs.setString('birth_date', '2009-01-01'); // 14 years old
    await prefs.setString('goal', 'lose');
    await prefs.setDouble('goal_speed', 0.5); // 0.5 kg/week
    print(
        'Test data set - Male, 66kg, 6\'1" (185cm), born 2009, lose weight at 0.5kg/week');

    print('====================================================\n');
  }

  void _showStreakPopup() {
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
            width: 326, // Exactly 326px as specified
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: 35), // Increased for more vertical space

                // Streak icon - 175x175 as specified
                Image.asset(
                  'assets/images/streak0.png',
                  width: 175,
                  height: 175,
                  color: streakCount > 0
                      ? Color(0xFFFF9801)
                      : null, // Orange color for active streak
                ),

                SizedBox(height: 20),

                // Streak count text - changes based on streak
                Text(
                  streakCount > 0 ? "1 Day Streak" : "0 Day Streak",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color:
                        streakCount > 0 ? Color(0xFFFF9801) : Color(0xFFD9D9D9),
                    fontFamily: 'SF Pro Display',
                  ),
                ),

                SizedBox(height: 20),

                // Level 1 text and progress bar for streaks > 0
                if (streakCount > 0) ...[
                  Text(
                    "Level 1",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.black.withOpacity(0.6),
                      fontFamily: 'SF Pro Display',
                    ),
                  ),

                  SizedBox(height: 10),

                  // Progress bar
                  Container(
                    width: 280, // Same width as Continue button
                    height: 10,
                    decoration: BoxDecoration(
                      color: Color(0xFFE0E0E0), // Gray background color
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: (280.0 / 7.0) *
                              streakCount
                                  .toDouble(), // Calculate exact width based on button width (280px / 7 days)
                          height: 10.0,
                          decoration: BoxDecoration(
                            color: Color(0xFFFF9801),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 20),
                ],

                // Motivational text - changes based on streak
                Container(
                  width: 280, // Match button width for alignment
                  child: Text(
                    streakCount > 0
                        ? "You're building a habit of success!" // 37 character limit
                        : "Every journey starts at zero - \nStart Now!",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.black.withOpacity(0.6),
                      fontFamily: 'SF Pro Display',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                SizedBox(height: 35),

                // Continue button - match sizing of Fix with AI button
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
                        Navigator.of(context).pop();
                      },
                      style: ButtonStyle(
                        overlayColor:
                            MaterialStateProperty.all(Colors.transparent),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'SF Pro Display',
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
      },
    );
  }

  // Load nutrition data from food logs
  Future<void> _loadNutritionData() async {
    await _nutritionTracker.loadNutritionData();
    setState(() {
      // Update remaining calories based on consumed calories
      if (targetCalories > 0) {
        remainingCalories = targetCalories - _nutritionTracker.consumedCalories;
        // Important: Print debug info to see what's happening with the values
        print(
            'LOAD DATA DEBUG: Target=$targetCalories, Consumed=${_nutritionTracker.consumedCalories}, Remaining=$remainingCalories');
        // No clamping - we need negative values to show overage
      }
    });
    print(
        'Updated remaining calories: $remainingCalories (target=$targetCalories, consumed=${_nutritionTracker.consumedCalories})');
  }

  // Navigation methods for Snap Meal and Coach buttons
  void _navigateToSnapFood() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SnapFood(),
      ),
    ).then((_) {
      // Refresh both food cards and nutrition data when returning from SnapFood
      print('Returned from SnapFood - refreshing data');
      _loadFoodCards();
      _loadNutritionData();
    });
  }

  // Navigation to Nutrition screen with better food-specific data handling
  void _navigateToNutrition() async {
    String finalScanId = 'nutrition_general_view';
    Map<String, dynamic>? existingNutritionData;

    try {
      // Get the current food scan ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();

      // First try to find food-specific nutrition data from recent food cards (highest priority)
      List<String>? foodCards = prefs.getStringList('food_cards');
      bool foundFoodCardData = false;

      if (foodCards != null && foodCards.isNotEmpty) {
        // Try to find the most recent food card with valid nutrition data
        for (String cardJson in foodCards.take(5)) {
          // Check only the 5 most recent cards
          try {
            Map<String, dynamic> foodCard = jsonDecode(cardJson);

            // Generate the proper scan ID using the same format as FoodCardOpen.dart
            if (foodCard.containsKey('name') &&
                foodCard.containsKey('calories')) {
              String foodName = foodCard['name']
                  .toString()
                  .toLowerCase()
                  .trim()
                  .replaceAll(' ', '_');
              String caloriesId =
                  foodCard['calories'].toString().replaceAll('.', '_');
              String foodSpecificScanId =
                  "food_nutrition_${foodName}_${caloriesId}";

              // Try to load nutrition data with this ID
              String? nutritionJson =
                  prefs.getString('food_nutrition_data_$foodSpecificScanId') ??
                      prefs.getString('nutrition_data_$foodSpecificScanId');

              if (nutritionJson != null && nutritionJson.isNotEmpty) {
                try {
                  existingNutritionData = jsonDecode(nutritionJson);
                  finalScanId = foodSpecificScanId;
                  print(
                      'Found nutrition data using food card ID: $foodSpecificScanId');
                  foundFoodCardData = true;
                  break;
                } catch (e) {
                  print('Error parsing nutrition data for card: $e');
                }
              }
            }
          } catch (e) {
            print('Error processing food card for nutrition data: $e');
          }
        }
      }

      // If we couldn't find any food-specific data, use the global data as fallback
      if (!foundFoodCardData) {
        // Check for global nutrition data
        if (prefs.containsKey('PERMANENT_GLOBAL_NUTRITION_DATA')) {
          try {
            String globalData =
                prefs.getString('PERMANENT_GLOBAL_NUTRITION_DATA')!;
            Map<String, dynamic> parsedData = jsonDecode(globalData);

            // Extract both scanId and the actual nutrition data
            if (parsedData.containsKey('scanId')) {
              finalScanId = parsedData['scanId'];
              print('Using scan ID from global nutrition data: $finalScanId');

              // Keep the existing nutrition data to pass to the next screen
              existingNutritionData = parsedData;
            }
          } catch (e) {
            print('Error parsing global nutrition data: $e');
          }
        }
      }

      print('Navigating to Nutrition with scan ID: $finalScanId');
    } catch (e) {
      print('Error preparing navigation to Nutrition: $e');
      // Keep using the default ID set above
    }

    // Always navigate, using either the found ID or the default
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Nutrition.CodiaPage(
          nutritionData: existingNutritionData != null
              ? (existingNutritionData['nutritionData'] ??
                  existingNutritionData)
              : null,
          scanId: finalScanId,
        ),
      ),
    );
  }

  void _navigateToCoach() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CoachScreen(),
      ),
    );
  }

  void _navigateToFoodCardOpen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const FoodCardOpen(),
      ),
    ).then((_) {
      // Refresh both food cards and nutrition data when returning
      print('Returned from FoodCardOpen - refreshing data');
      _loadFoodCards();
      _loadNutritionData();
    });
  }
}
