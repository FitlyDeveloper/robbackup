import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import '../Features/codia/codia_page.dart';
import 'LogRunning.dart';
import 'dart:math';
// Local import adjusted: use relative path to avoid missing package mapping
import '../core/run_calories.dart';


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

class RunCardOpen extends StatefulWidget {
  final Map<String, dynamic> workoutData;
  
  const RunCardOpen({Key? key, required this.workoutData}) : super(key: key);

  @override
  State<RunCardOpen> createState() => _RunCardOpenState();
}

class _RunCardOpenState extends State<RunCardOpen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _isLiked = false;
  bool _isBookmarked = false;
  bool _hasUnsavedChanges = false;
  
  // Original values to compare for changes
  String _originalRunName = '';
  String _originalCalories = '';
  String _originalNotes = '';

  late AnimationController _bookmarkController;
  late Animation<double> _bookmarkScaleAnimation;
  late AnimationController _likeController;
  late Animation<double> _likeScaleAnimation;

  // Initialize with default values
  String _runName = 'Evening run 1';
  String _notes = 'It was cold asf';
  String _calories = '230';
  String _time = '18h 11min';
  String _distance = '0km';
  String _pace = '0m 00s/km';
  double? _intensity; // Changed to nullable to track if intensity exists
  String _privacyStatus = 'Private';

  // Computed calories state
  double? _caloriesKcal; // computed kcal for display and potential ring value
  double? _weightKg;     // loaded from SharedPreferences
  double? _heightCm;     // loaded from SharedPreferences
  int? _ageYears;        // loaded from SharedPreferences
  double? _distanceKm;   // extracted from current model/string
  double? _timeMinutes;  // extracted from current model/string

  // Short debug logger for calories
  void _debugCalLog(String where) {
    print('[RunCal] $where -> weightKg=$_weightKg, heightCm=$_heightCm, ageYears=$_ageYears, distKm=$_distanceKm, timeMin=$_timeMinutes, kcal=$_caloriesKcal');
  }
  void _log(String msg) => print('[RunCal] $msg');

  @override
  void initState() {
    super.initState();
    print('RunCardOpen initState called');
    _log('initState');

    // Initialize with no unsaved changes
    _hasUnsavedChanges = false;

    // Initialize animation controllers
    _initAnimationControllers();

    // Set initial values from parameters if available
    if (widget.workoutData['name'] != null && widget.workoutData['name'].isNotEmpty) {
      _runName = widget.workoutData['name'];
    }

    if (widget.workoutData['calories'] != null) {
      _calories = widget.workoutData['calories'].toString();
    }

    if (widget.workoutData['duration'] != null) {
      int durationInMinutes = (widget.workoutData['duration'] / 60).floor();
      _time = _formatDuration(durationInMinutes);
    }

    if (widget.workoutData['distance'] != null) {
      double distance = _extractNumericValueAsDouble(widget.workoutData['distance']) ?? 0.0;
      if (distance > 0) {
        _distance = '${_formatDistance(distance / 1000)}km';
      } else {
        _distance = '0km';
      }
    }

    // Calculate pace from distance and duration
    double distanceInMeters = _extractNumericValueAsDouble(widget.workoutData['distance']) ?? 0.0;
    int durationInSeconds = widget.workoutData['duration'] ?? 0;
    
    if (distanceInMeters > 0 && durationInSeconds > 0) {
      _pace = _formatPace(distanceInMeters, durationInSeconds);
    } else {
      _pace = '0m 00s/km';
    }

    if (widget.workoutData['intensity'] != null) {
      _intensity = (widget.workoutData['intensity'] as num).toDouble();
    }

    if (widget.workoutData['notes'] != null) {
      _notes = widget.workoutData['notes'];
    }

    // Sync numeric metrics and compute calories using user stats
    _syncMetricsFromStrings();
    _loadUserStatsAndCompute();

    // In case some label strings finalize after first build, resync and compute
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _log('postFrame -> re-sync + compute');
      _syncMetricsFromStrings();
      _computeCaloriesOrFallback();
    });

    // Load saved data from SharedPreferences
    _loadSavedData().then((_) {
      if (mounted) {
        // Reset unsaved changes state after loading
        _resetUnsavedChangesState();
      }
    });
  }

  void _initAnimationControllers() {
    // Bookmark animations
    _bookmarkController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _bookmarkScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _bookmarkController,
      curve: Curves.easeInOut,
    ));

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

  @override
  void dispose() {
    _bookmarkController.dispose();
    _likeController.dispose();
    super.dispose();
  }

  String _formatDuration(int minutes) {
    if (minutes < 1) {
      return '0 min';
    }
    int hours = minutes ~/ 60;
    int remainingMinutes = minutes % 60;
    
    if (hours > 0) {
      return '${hours}h ${remainingMinutes}min';
    } else {
      return '${remainingMinutes}min';
    }
  }

  String _formatDistance(double distance) {
    if (distance % 1 == 0) {
      return distance.toInt().toString();
    } else if ((distance * 10) % 1 == 0) {
      return distance.toStringAsFixed(1);
    } else {
      return distance.toStringAsFixed(2);
    }
  }

  String _formatPace(double distanceInMeters, int durationInSeconds) {
    if (distanceInMeters <= 0 || durationInSeconds <= 0) {
      return '0m 00s/km';
    }
    
    // Convert distance to kilometers
    double distanceInKm = distanceInMeters / 1000;
    
    // Convert duration to minutes
    double durationInMinutes = durationInSeconds / 60;
    
    // Calculate pace: total time in minutes ÷ distance in kilometers
    double paceInMinutes = durationInMinutes / distanceInKm;
    
    // Extract minutes and seconds
    int paceMinutes = paceInMinutes.floor();
    int paceSeconds = ((paceInMinutes - paceMinutes) * 60).round();
    
    // Handle edge case where seconds round up to 60
    if (paceSeconds >= 60) {
      paceMinutes += 1;
      paceSeconds = 0;
    }
    
    return '${paceMinutes}m ${paceSeconds.toString().padLeft(2, '0')}s/km';
  }

  double? _extractNumericValueAsDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) {
      // Remove non-numeric characters except decimal point
      String cleaned = value.replaceAll(RegExp(r'[^\d.]'), '');
      if (cleaned.isNotEmpty) {
        return double.tryParse(cleaned);
      }
    }
    return null;
  }

  int _extractTimeInMinutes(String timeString) {
    if (timeString.isEmpty) return 0;
    
    // Handle formats like "1h 30min", "60min", "1h"
    if (timeString.contains('h')) {
      int hours = 0;
      int minutes = 0;
      
      // Extract hours
      RegExp hourRegex = RegExp(r'(\d+)h');
      Match? hourMatch = hourRegex.firstMatch(timeString);
      if (hourMatch != null) {
        hours = int.tryParse(hourMatch.group(1) ?? '0') ?? 0;
      }
      
      // Extract minutes
      RegExp minuteRegex = RegExp(r'(\d+)min');
      Match? minuteMatch = minuteRegex.firstMatch(timeString);
      if (minuteMatch != null) {
        minutes = int.tryParse(minuteMatch.group(1) ?? '0') ?? 0;
      }
      
      return (hours * 60) + minutes;
    } else {
      // Handle "60min" format
      RegExp minuteRegex = RegExp(r'(\d+)min');
      Match? minuteMatch = minuteRegex.firstMatch(timeString);
      if (minuteMatch != null) {
        return int.tryParse(minuteMatch.group(1) ?? '0') ?? 0;
      }
    }
    
    return 0;
  }

  // Keep distance/time in numeric form from current strings
  void _syncMetricsFromStrings() {
    _log('raw labels -> time="$_time", distance="$_distance"');
    // 1) Prefer raw model values if present
    double? rawDistanceMeters = _extractNumericValueAsDouble(widget.workoutData['distance']);
    double? rawDurationSeconds;
    final rawDuration = widget.workoutData['duration'];
    if (rawDuration is num) {
      rawDurationSeconds = rawDuration.toDouble();
    } else if (rawDuration != null) {
      rawDurationSeconds = _extractNumericValueAsDouble(rawDuration);
    }

    // Convert to desired units
    double? rawDistanceKm = rawDistanceMeters != null ? (rawDistanceMeters / 1000.0) : null;
    double? rawTimeMinutes = rawDurationSeconds != null ? (rawDurationSeconds / 60.0) : null;

    // 2) Fallback to parsing the label strings if raw are missing
    final parsedLabelDistanceKm = _extractNumericValueAsDouble(_distance);
    final parsedLabelTimeMinutes = _extractTimeInMinutes(_time).toDouble();

    _distanceKm = rawDistanceKm ?? parsedLabelDistanceKm;
    _timeMinutes = rawTimeMinutes ?? parsedLabelTimeMinutes;

    _log('parsed -> timeMinutes=${_timeMinutes}, distanceKm=${_distanceKm}');
    _debugCalLog('after _syncMetricsFromStrings');
  }

  Future<void> _loadUserStatsAndCompute() async {
    _log('loadUserStatsAndCompute: start');
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // DIAGNOSTIC: Dump all available keys and their values
      final allKeys = prefs.getKeys().toList();
      _log('[RCO][PREFS] Available keys: ${allKeys.join(', ')}');
      
      // Check specific metric keys and their values
      final metricKeys = ['user_weight_kg', 'weightKg', 'user_height_cm', 'heightCm', 'birth_date', 'age', 'user_age', 'gender', 'user_gender'];
      for (final key in metricKeys) {
        if (prefs.containsKey(key)) {
          final value = prefs.get(key);
          final type = value.runtimeType.toString();
          _log('[RCO][PREFS] key=$key, exists=true, type=$type, value=$value');
        } else {
          _log('[RCO][PREFS] key=$key, exists=false');
        }
      }
      
      // Load metrics from persistent keys set by codia_page.dart
      final weightKg = prefs.getDouble('user_weight_kg');
      final heightCm = prefs.getDouble('user_height_cm');
      final ageYears = prefs.getInt('age');
      final gender = prefs.getString('gender') ?? 'Male';
      final birthIso = prefs.getString('birth_date');

      // If birth_date exists but age missing, derive it
      int? derivedAge = ageYears;
      if (derivedAge == null && birthIso != null && birthIso.isNotEmpty) {
        derivedAge = _computeAgeFromIso(birthIso);
      }

      _log('[RunCardOpen][PREFS] w=$weightKg, h=$heightCm, age=$derivedAge, gender=$gender');
      
      setState(() {
        _weightKg = weightKg;
        _heightCm = heightCm;
        _ageYears = derivedAge;
      });
      
      _log('metrics loaded -> weightKg=$weightKg, heightCm=$heightCm, ageYears=$derivedAge');
      
      // Debug: check if any metrics are null
      if (weightKg == null) _log('WARNING: weightKg is null');
      if (heightCm == null) _log('WARNING: heightCm is null');
      if (derivedAge == null) _log('WARNING: ageYears is null');
      
      _log('state set -> weightKg=$_weightKg, heightCm=$_heightCm, ageYears=$_ageYears');
    } catch (e) {
      _log('prefs error: $e');
      _weightKg = null;
      _heightCm = null;
      _ageYears = null;
    }
    
    // Debug: check state after setState
    _log('after setState -> weightKg=$_weightKg, heightCm=$_heightCm, ageYears=$_ageYears');
    
    await _computeCaloriesOrFallback();
  }

  // Helper method to compute age from birth date ISO string
  int? _computeAgeFromIso(String iso) {
    try {
      final dob = DateTime.parse(iso); // yyyy-MM-dd
      final now = DateTime.now();
      var age = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
      return age;
    } catch (_) { 
      return null; 
    }
  }

  Future<void> _computeCaloriesOrFallback() async {
    _log('compute inputs -> weightKg=$_weightKg, distanceKm=$_distanceKm, timeMinutes=$_timeMinutes');
    _debugCalLog('compute start');
    
    // Check if we have the minimum required metrics for computation
    final hasRequiredMetrics = _weightKg != null; // Only weight is needed for the formula
    final hasValues = _distanceKm != null && _timeMinutes != null;
    
    _log('compute check -> hasRequiredMetrics=$hasRequiredMetrics (w=$_weightKg), hasValues=$hasValues (d=$_distanceKm, t=$_timeMinutes)');
    
    if (hasRequiredMetrics && hasValues) {
      // We have weight and distance/time, compute calories
      final w = _weightKg!;
      final d = _distanceKm!;
      final t = _timeMinutes!;
      
      // Use shared helper for consistent computation
      final int computedKcal = RunCalories.compute(
        weightKg: w,
        distanceMeters: d * 1000, // convert km to meters
        durationSeconds: t * 60,   // convert minutes to seconds
        gender: null, // not used in current MET calc
      );
      
      setState(() => _caloriesKcal = computedKcal.toDouble());
      _log('compute result -> kcal=$_caloriesKcal (computed)');
      _log('[RCO] PATH = COMPUTE (w=$w,d=$d,t=$t) -> kcal=$_caloriesKcal');
      _log('[RunCal] COMPUTE -> ${computedKcal} kcal (km=${d}, min=${t})');
      _log('[RunCal][DEBUG] weight=${w}, dist=${(d * 1000).round()}m, dur=${(t * 60).round()}s -> kcal=${computedKcal}');
      _debugCalLog('compute end');
    } else {
      // Missing required metrics or values, try fallback
      final storedCalories = widget.workoutData['calories'] as double?;
      if (storedCalories != null && storedCalories > 0) {
        setState(() => _caloriesKcal = storedCalories);
        _log('using stored calories fallback: $_caloriesKcal');
        _log('[RCO] PATH = FALLBACK (stored calories=$_caloriesKcal)');
        _debugCalLog('fallback stored');
      } else {
        setState(() => _caloriesKcal = null);
        _log('no stored calories, showing --');
        _log('[RCO] PATH = FALLBACK (no stored calories)');
        _debugCalLog('fallback none');
      }
    }
  }



  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('run_${widget.workoutData['id'] ?? 'default'}');
      
      if (savedData != null) {
        final data = json.decode(savedData);
        setState(() {
          _runName = data['runName'] ?? _runName;
          _notes = data['notes'] ?? _notes;
          _calories = data['calories'] ?? _calories;
          _intensity = data['intensity'];
          _isLiked = data['isLiked'] ?? false;
          _isBookmarked = data['isBookmarked'] ?? false;
          _privacyStatus = data['privacyStatus'] ?? 'Private';
        });
      }
    } catch (e) {
      print('Error loading saved data: $e');
    }
  }

  Future<void> _saveData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'runName': _runName,
        'notes': _notes,
        'calories': _calories,
        'intensity': _intensity,
        'isLiked': _isLiked,
        'isBookmarked': _isBookmarked,
        'privacyStatus': _privacyStatus,
      };
      
      await prefs.setString('run_${widget.workoutData['id'] ?? 'default'}', json.encode(data));
      setState(() {
        _hasUnsavedChanges = false;
      });
    } catch (e) {
      print('Error saving data: $e');
    }
  }

  void _resetUnsavedChangesState() {
    _originalRunName = _runName;
    _originalCalories = _calories;
    _originalNotes = _notes;
    _hasUnsavedChanges = false;
  }

  // Check for unsaved changes
  bool _checkForUnsavedChanges() {
    return _hasUnsavedChanges;
  }

  // Mark as having unsaved changes
  void _markAsUnsaved() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
      print('Marked as having unsaved changes');
    }
  }

  // Method to toggle bookmark state with animation
  void _toggleBookmark() {
    setState(() {
      _isBookmarked = !_isBookmarked;
      _bookmarkController.reset();
      _bookmarkController.forward();
      _markAsUnsaved(); // Mark as having unsaved changes
    });
  }

  // Method to toggle like state with animation
  void _toggleLike() {
    setState(() {
      _isLiked = !_isLiked;
      _likeController.reset();
      _likeController.forward();
      _markAsUnsaved(); // Mark as having unsaved changes
    });
  }

  // Handle back button press
  void _handleBack() async {
    if (_checkForUnsavedChanges()) {
      bool shouldDiscard = await _showUnsavedChangesDialog();
      if (shouldDiscard) {
        if (mounted) {
          setState(() {
            _runName = _originalRunName;
            _notes = _originalNotes;
            _calories = _originalCalories;
            _hasUnsavedChanges = false;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => CodiaPage()),
            );
          });
        }
      }
    } else {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => CodiaPage()),
        );
      }
    }
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

  void _showPrivacyOptions() {
    String _selectedPrivacy = _privacyStatus;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withOpacity(0.5),
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          width: MediaQuery.of(context).size.width,
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPrivacyOption('Private', 'assets/images/Lock.png', _selectedPrivacy, (value) {
                setModalState(() => _selectedPrivacy = value);
                setState(() {
                  _privacyStatus = value;
                  _markAsUnsaved();
                });
                Navigator.pop(context);
              }),
              _buildPrivacyOption('Friends Only', 'assets/images/socialicon.png', _selectedPrivacy, (value) {
                setModalState(() => _selectedPrivacy = value);
                setState(() {
                  _privacyStatus = value;
                  _markAsUnsaved();
                });
                Navigator.pop(context);
              }),
              _buildPrivacyOption('Public', 'assets/images/globe.png', _selectedPrivacy, (value) {
                setModalState(() => _selectedPrivacy = value);
                setState(() {
                  _privacyStatus = value;
                  _markAsUnsaved();
                });
                Navigator.pop(context);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyOption(String title, String iconPath, String selectedPrivacy, Function(String) onSelect) {
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

  void _editIntensity() {
    double currentIntensity = _intensity ?? 5.0; // Default to 5 if intensity is null
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                              _intensity != null ? 'Edit Intensity' : 'Add Intensity',
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
                                    // Intensity icon - exactly 43x43
                                    Image.asset(
                                      'assets/images/intensity.png',
                                      width: 43.0,
                                      height: 43.0,
                                      color: Colors.black,
                                    ),

                                    // 28px gap between image and text
                                    SizedBox(height: 28),

                                    // Instructions text - match font size and style
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 25),
                                      child: Text(
                                        'Set Run Intensity from 1-10',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontFamily: 'SF Pro Display',
                                          fontWeight: FontWeight.w400,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),

                                    // 24px gap before slider
                                    SizedBox(height: 24),

                                    // Slider
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          activeTrackColor: Colors.black,
                                          inactiveTrackColor: Colors.grey[300],
                                          thumbColor: Colors.white,
                                          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
                                          overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
                                          trackHeight: 4,
                                        ),
                                        child: Slider(
                                          value: currentIntensity,
                                          min: 1.0,
                                          max: 10.0,
                                          divisions: 9,
                                          onChanged: (value) {
                                            setModalState(() {
                                              currentIntensity = value;
                                            });
                                          },
                                        ),
                                      ),
                                    ),

                                    // Value display
                                    SizedBox(height: 8),
                                    Text(
                                      currentIntensity.round().toString(),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'SF Pro Display',
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Add/Save button - match "Fix Now" popup spacing
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Container(
                                width: 280,
                                height: 48,
                                margin: EdgeInsets.only(bottom: 24), // Same margin as Fix Now popup
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _intensity = currentIntensity;
                                      _markAsUnsaved();
                                    });
                                    Navigator.pop(context);
                                  },
                                  style: ButtonStyle(
                                    overlayColor: MaterialStateProperty.all(Colors.transparent),
                                  ),
                                  child: Text(
                                    _intensity != null ? 'Save' : 'Add',
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

                      // Close button - match Fix Manually popup positioning
                      Positioned(
                        top: 23, // Adjusted to align with the title
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

                      // Delete button - only show when editing intensity
                      if (_intensity != null) ...[
                        Positioned(
                          top: 23, // Aligned with the title and close button
                          left: 20,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _intensity = null; // Reset intensity to null
                                _markAsUnsaved();
                              });
                              Navigator.pop(context);
                            },
                            child: Image.asset(
                              'assets/images/trashcan.png',
                              width: 20,
                              height: 20,
                              color: Color(0xFFE97372),
                            ),
                          ),
                        ),
                      ],
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

  void _editRun() {
    // Extract distance and time from current values
    double distanceInKm = _extractNumericValueAsDouble(_distance) ?? 0.0;
    int timeInMinutes = _extractTimeInMinutes(_time);
    
    // Generate or get the run ID for editing
    String? runId;
    if (widget.workoutData['id'] != null) {
      // Use existing ID if available
      runId = widget.workoutData['id'];
    } else if (widget.workoutData['timestamp'] != null) {
      // Generate ID from timestamp for older workouts that don't have an ID
      runId = 'workout_${widget.workoutData['timestamp']}';
    }
    
    // Navigate to LogRunning with current values and run ID for editing
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LogRunning(
          initialDistance: distanceInKm,
          initialTime: timeInMinutes,
          initialTitle: _runName,
          runId: runId, // Pass the run ID for editing
        ),
      ),
    );
  }

  void _fixWithAI() {
    _showFixWithAIDialog();
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

              // Call the AI to fix the run with a callback to handle the response
              _fixRunWithAI(description, (result) {
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

                // Process the AI's response to update the run
                print('AI RESPONSE DATA: ${result.toString()}');

                // Handle any potentially capitalized keys
                Map<String, dynamic> normalizedData = Map.from(result);

                // Check for capitalized field names and normalize them
                if (normalizedData.containsKey('Name') &&
                    !normalizedData.containsKey('name')) {
                  normalizedData['name'] = normalizedData.remove('Name');
                }

                if (normalizedData.containsKey('Distance') &&
                    !normalizedData.containsKey('distance')) {
                  normalizedData['distance'] = normalizedData.remove('Distance');
                }

                if (normalizedData.containsKey('Duration') &&
                    !normalizedData.containsKey('duration')) {
                  normalizedData['duration'] = normalizedData.remove('Duration');
                }

                if (normalizedData.containsKey('Calories') &&
                    !normalizedData.containsKey('calories')) {
                  normalizedData['calories'] = normalizedData.remove('Calories');
                }

                if (normalizedData.containsKey('Notes') &&
                    !normalizedData.containsKey('notes')) {
                  normalizedData['notes'] = normalizedData.remove('Notes');
                }

                // Update the state with the new values
                setState(() {
                  // Update run name if provided
                  if (normalizedData.containsKey('name')) {
                    _runName = normalizedData['name'];
                    print('Updated run name to: $_runName');
                  }

                  // Update distance if provided
                  if (normalizedData.containsKey('distance')) {
                    double distance = normalizedData['distance'];
                    _distance = '${_formatDistance(distance)}km';
                    print('Updated distance to: $_distance');
                  }

                  // Update duration if provided
                  if (normalizedData.containsKey('duration')) {
                    int durationInMinutes = normalizedData['duration'];
                    _time = _formatDuration(durationInMinutes);
                    print('Updated time to: $_time');
                  }

                  // Update calories if provided
                  if (normalizedData.containsKey('calories')) {
                    _calories = normalizedData['calories'].toString();
                    print('Updated calories to: $_calories');
                  }

                  // Update notes if provided
                  if (normalizedData.containsKey('notes')) {
                    _notes = normalizedData['notes'];
                    print('Updated notes to: $_notes');
                  }

                  // Mark as having unsaved changes
                  _markAsUnsaved();

                  print("Run successfully modified with AI: $_runName");
                });
                // Re-sync metrics and recompute calories after updates
                _syncMetricsFromStrings();
                _computeCaloriesOrFallback();
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

  // Helper method to show standard dialogs
  void _showStandardDialog({
    required String title,
    required String message,
    required String positiveButtonText,
  }) {
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
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SF Pro Display',
                    ),
                  ),
                  SizedBox(height: 20),

                  // Message
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'SF Pro Display',
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20),

                  // OK button
                  Container(
                    width: 267,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.black,
                    ),
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: ButtonStyle(
                        overlayColor: MaterialStateProperty.all(Colors.transparent),
                      ),
                      child: Text(
                        positiveButtonText,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'SF Pro Display',
                          fontWeight: FontWeight.w500,
                        ),
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

  // Function to fix run with AI and recalculate data
  Future<void> _fixRunWithAI(
      String instructions, Function(Map<String, dynamic>) callback) async {
    
    BuildContext? localContext = context;
    BuildContext? dialogContext;
    bool isDialogShowing = false;

    try {
      print('STARTING AI fix for: $_runName with instructions: $instructions');

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
      } else if (instructions.toLowerCase().contains('faster') ||
          instructions.toLowerCase().contains('quicker')) {
        operationType = 'REDUCE_DURATION';
      } else if (instructions.toLowerCase().contains('slower') ||
          instructions.toLowerCase().contains('longer')) {
        operationType = 'INCREASE_DURATION';
      } else if (instructions.toLowerCase().contains('longer distance') ||
          instructions.toLowerCase().contains('more distance')) {
        operationType = 'INCREASE_DISTANCE';
      } else if (instructions.toLowerCase().contains('shorter distance') ||
          instructions.toLowerCase().contains('less distance')) {
        operationType = 'REDUCE_DISTANCE';
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

      // Create a description of the current run
      String currentRunDescription = "Run: $_runName\n";
      currentRunDescription += "Distance: $_distance\n";
      currentRunDescription += "Duration: $_time\n";
      currentRunDescription += "Calories: $_calories\n";
      currentRunDescription += "Notes: $_notes\n";
      if (_intensity != null) {
        currentRunDescription += "Intensity: $_intensity/10\n";
      }

      // Add the specific instruction about what to fix
      currentRunDescription +=
          "\nPlease analyze and update the run according to the following instruction: '$preprocessedInstructions' (Operation type: $operationType)";
      print("Full content for AI: $currentRunDescription");

      // Print request data for debugging
      final requestData = {
        'run_name': _runName,
        'current_data': {
          'distance': _distance,
          'time': _time,
          'calories': _calories,
          'notes': _notes,
          'intensity': _intensity,
        },
        'instructions': preprocessedInstructions,
        'operation_type': operationType
      };
      print('RUN FIXER: Request data: ${jsonEncode(requestData)}');

      try {
        // Attempt to call the Render.com DeepSeek service
        print(
            'RUN FIXER: Creating request to Render.com DeepSeek service for fixing run');

        // Store a local copy of the context to avoid issues
        final BuildContext localContext = context;

        final response = await http
            .post(
          Uri.parse('https://deepseek-uhrc.onrender.com/api/running'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode(requestData),
        )
            .timeout(const Duration(minutes: 1), onTimeout: () {
          print('RUN FIXER: Request timed out');
          // Safely show error dialog on timeout without navigating away
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && localContext != null) {
              _showStandardDialog(
                title: "Error",
                message: "Request timed out. Please try again.",
                positiveButtonText: "OK",
              );
            }
          });
          throw Exception('Request timed out');
        });

        // Close loading dialog safely
        if (isDialogShowing && dialogContext != null) {
          try {
            Navigator.of(dialogContext!).pop();
          } catch (e) {
            print('Error dismissing loading dialog: $e');
          }
          isDialogShowing = false;
          dialogContext = null;
        }

        if (response.statusCode == 200) {
          try {
            final responseData = json.decode(response.body);
            print('RUN FIXER: Success response: ${response.body}');

            // Call the callback with the response data
            callback(responseData);
          } catch (parseError) {
            print('RUN FIXER: Error parsing response: $parseError');
            callback({
              'error': true,
              'message': 'Failed to parse AI response: $parseError'
            });
          }
        } else {
          print('RUN FIXER: Error response: ${response.statusCode} - ${response.body}');
          callback({
            'error': true,
            'message': 'Server error: ${response.statusCode}'
          });
        }
      } catch (e) {
        print('RUN FIXER: Exception during API call: $e');
        
        // Close loading dialog safely
        if (isDialogShowing && dialogContext != null) {
          try {
            Navigator.of(dialogContext!).pop();
          } catch (dialogError) {
            print('Error dismissing loading dialog: $dialogError');
          }
          isDialogShowing = false;
          dialogContext = null;
        }

        callback({
          'error': true,
          'message': 'Network error: $e'
        });
      }
    } catch (e) {
      print('RUN FIXER: General error: $e');
      
      // Close loading dialog safely
      if (isDialogShowing && dialogContext != null) {
        try {
          Navigator.of(dialogContext!).pop();
        } catch (dialogError) {
          print('Error dismissing loading dialog: $dialogError');
        }
        isDialogShowing = false;
        dialogContext = null;
      }

      callback({
        'error': true,
        'message': 'An unexpected error occurred: $e'
      });
    }
  }

    @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.of(context).viewPadding.top;

    return Scaffold(
      backgroundColor: Color(0xFFDADADA),
      body: WillPopScope(
        onWillPop: () async {
          _handleBack();
          return false;
        },
        child: Stack(
          children: [
            // Background image
            Positioned.fill(
              child: Image.asset(
                'assets/images/background4.jpg',
                fit: BoxFit.cover,
              ),
            ),
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
                          // Running shoe icon - centered like the meal image in FoodCardOpen
                          Center(
                            child: Image.asset(
                              'assets/images/Shoe.png',
                              width: 120,
                              height: 120,
                              color: Colors.black,
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
                                        width: 21.6,
                                        height: 21.6,
                                        color: Colors.black,
                                      ),
                                      onPressed: () {},
                                      padding: EdgeInsets.zero,
                                      constraints: BoxConstraints(),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
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
                                        'assets/images/more.png',
                                        width: 21.6,
                                        height: 21.6,
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

                     // White rounded container with gradient - exactly like FoodCardOpen
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

                             // Time and interaction buttons - exactly like FoodCardOpen
                             Padding(
                               padding: const EdgeInsets.fromLTRB(29, 0, 29, 0),
                               child: Row(
                                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                               scale: _bookmarkScaleAnimation.value,
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
                                           borderRadius: BorderRadius.circular(12),
                                         ),
                                         child: Text(
                                           '12:07',
                                           style: TextStyle(fontSize: 12),
                                         ),
                                       ),
                                     ],
                                   ),
                                 ],
                               ),
                             ),

                             // Title and description with adjusted padding - exactly like FoodCardOpen
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
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       mainAxisSize: MainAxisSize.min,
                                       children: [
                                                                                   Text(
                                          _runName,
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'SF Pro Display',
                                          ),
                                          // Allow wrapping to multiple lines
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        // Only show description if it's not empty, null, or just whitespace
                                        if (_notes != null && _notes.trim().isNotEmpty) ...[
                                          SizedBox(height: 4),
                                          Text(
                                            _notes,
                                            style: TextStyle(
                                              fontSize: 18,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                       ],
                                     ),
                                   ),
                                 ),

                                 // Add 20px gap between subtitle and divider
                                 SizedBox(height: 20),

                                 // Calories and metrics card - exactly like FoodCardOpen
                                 Padding(
                                   padding: const EdgeInsets.symmetric(horizontal: 29),
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
                                                    (_caloriesKcal == null
                                                            ? '--'
                                                            : _caloriesKcal!.round().toString()),
                                                   style: TextStyle(
                                                     fontSize: 20,
                                                     fontWeight: FontWeight.bold,
                                                     color: Colors.black,
                                                     decoration: TextDecoration.none,
                                                   ),
                                                 ),
                                                 Text(
                                                   'Calories',
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
                                         SizedBox(height: 5),

                                                                                   // Run Stats - Three pill-shaped components as shown in the image
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                                            children: [
                                              _buildRunMetricPill('Time', _time, Color(0xFFD7C1FF), 'assets/images/Stopwatch.png'),
                                              _buildRunMetricPill('Distance', _distance, Color(0xFFFFD8B1), 'assets/images/distance.png'),
                                              _buildRunMetricPill('Pace', _pace, Color(0xFFB1EFD8), 'assets/images/speedicon.png'),
                                            ],
                                          ),
                                       ],
                                     ),
                                   ),
                                 ),

                                 SizedBox(height: 32),

                                 // Only show social interaction area if not Private
                                 if (_privacyStatus != 'Private') ...[
                                   // Social Section - exactly like FoodCardOpen
                                   Padding(
                                     padding: const EdgeInsets.symmetric(horizontal: 29),
                                     child: Column(
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       children: [
                                         Text(
                                           'Social',
                                           style: TextStyle(
                                             color: Colors.black,
                                             fontSize: 20,
                                             fontWeight: FontWeight.bold,
                                             fontFamily: 'SF Pro Display',
                                           ),
                                         ),
                                         SizedBox(height: 16),
                                         // Social sharing buttons - matching Figma design exactly
                                         Row(
                                           children: [
                                             // Like button area (left section)
                                             Expanded(
                                               child: Container(
                                                 height: 48,
                                                 decoration: BoxDecoration(
                                                   color: Colors.white,
                                                   borderRadius: BorderRadius.circular(24),
                                                   boxShadow: [
                                                     BoxShadow(
                                                       color: Colors.black.withOpacity(0.05),
                                                       blurRadius: 4,
                                                       offset: Offset(0, 2),
                                                     ),
                                                   ],
                                                 ),
                                                 child: Center(
                                                   child: Row(
                                                     mainAxisAlignment: MainAxisAlignment.center,
                                                     children: [
                                                       GestureDetector(
                                                         onTap: _toggleLike,
                                                         child: AnimatedBuilder(
                                                           animation: _likeController,
                                                           builder: (context, child) {
                                                             return Transform.scale(
                                                               scale: _likeScaleAnimation.value,
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
                                                         '0 Likes',
                                                         style: TextStyle(
                                                           fontSize: 16,
                                                           fontWeight: FontWeight.w500,
                                                         ),
                                                       ),
                                                     ],
                                                   ),
                                                 ),
                                               ),
                                             ),
                                             
                                             SizedBox(width: 16),
                                             
                                             // Comment button (right section)
                                             Expanded(
                                               child: Container(
                                                 height: 48,
                                                 decoration: BoxDecoration(
                                                   color: Colors.white,
                                                   borderRadius: BorderRadius.circular(24),
                                                   boxShadow: [
                                                     BoxShadow(
                                                       color: Colors.black.withOpacity(0.05),
                                                       blurRadius: 4,
                                                       offset: Offset(0, 2),
                                                     ),
                                                   ],
                                                 ),
                                                 child: Center(
                                                   child: Row(
                                                     mainAxisAlignment: MainAxisAlignment.center,
                                                     children: [
                                                       Image.asset(
                                                         'assets/images/comment.png',
                                                         width: 24,
                                                         height: 24,
                                                         color: Colors.black,
                                                       ),
                                                       SizedBox(width: 8),
                                                       Text(
                                                         '0 Comments',
                                                         style: TextStyle(
                                                           fontSize: 16,
                                                           fontWeight: FontWeight.w500,
                                                         ),
                                                       ),
                                                     ],
                                                   ),
                                                 ),
                                               ),
                                             ),
                                           ],
                                         ),
                                       ],
                                     ),
                                   ),
                                   
                                   SizedBox(height: 32),
                                 ],

                                 // Intensity Section - Only show if intensity exists
                                 if (_intensity != null) ...[
                                   Padding(
                                     padding: const EdgeInsets.symmetric(horizontal: 29),
                                     child: Column(
                                       crossAxisAlignment: CrossAxisAlignment.start,
                                       children: [
                                         Text(
                                           'Intensity',
                                           style: TextStyle(
                                             color: Colors.black,
                                             fontSize: 20,
                                             fontWeight: FontWeight.bold,
                                             fontFamily: 'SF Pro Display',
                                           ),
                                         ),
                                         SizedBox(height: 16),
                                         Container(
                                           padding: EdgeInsets.all(20),
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
                                             crossAxisAlignment: CrossAxisAlignment.start,
                                             children: [
                                               // Top row with icon, label, and value
                                               Row(
                                                 children: [
                                                   Image.asset(
                                                     'assets/images/intensity.png',
                                                     width: 24,
                                                     height: 24,
                                                     color: Colors.black,
                                                   ),
                                                   SizedBox(width: 12),
                                                   Text(
                                                     'Intensity',
                                                     style: TextStyle(
                                                       fontSize: 16,
                                                       fontWeight: FontWeight.w500,
                                                       color: Colors.black,
                                                     ),
                                                   ),
                                                   Spacer(),
                                                   Text(
                                                     '${_intensity!.toInt()}/10',
                                                     style: TextStyle(
                                                       fontSize: 14,
                                                       color: Colors.black,
                                                       fontWeight: FontWeight.w500,
                                                     ),
                                                   ),
                                                 ],
                                               ),
                                               SizedBox(height: 12),
                                               // Progress bar
                                               Container(
                                                 width: double.infinity,
                                                 height: 4,
                                                 decoration: BoxDecoration(
                                                   color: Color(0xFFE0E0E0), // Light grey background
                                                   borderRadius: BorderRadius.circular(2),
                                                 ),
                                                 child: FractionallySizedBox(
                                                   alignment: Alignment.centerLeft,
                                                   widthFactor: _intensity! / 10.0,
                                                   child: Container(
                                                     decoration: BoxDecoration(
                                                       color: Colors.black,
                                                       borderRadius: BorderRadius.circular(2),
                                                     ),
                                                   ),
                                                 ),
                                               ),
                                             ],
                                           ),
                                         ),
                                       ],
                                     ),
                                   ),
                                   SizedBox(height: 32),
                                 ],

                                 // More Section - exactly like FoodCardOpen
                                 Padding(
                                   padding: const EdgeInsets.symmetric(horizontal: 29),
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       Text(
                                         'More',
                                         style: TextStyle(
                                           color: Colors.black,
                                           fontSize: 20,
                                           fontWeight: FontWeight.bold,
                                           fontFamily: 'SF Pro Display',
                                         ),
                                       ),
                                       SizedBox(height: 16),
                                       // More options buttons - matching Figma design exactly
                                       _buildMoreOption(_intensity != null ? 'Edit Intensity' : 'Add Intensity', 'intensity.png'),
                                       _buildMoreOption('Edit Run', 'pencilicon.png'),
                                       _buildMoreOption('Fix with AI', 'bulb.png'),
                                       _buildMoreOptionWithDropdown('Public', 'globe.png'),
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

            // White box at bottom - EXACTLY as in FoodCardOpen.dart
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

            // Save button - EXACTLY as in FoodCardOpen.dart
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
                    // Save data and navigate to CodiaPage
                    _saveData().then((_) {
                      setState(() {
                        _hasUnsavedChanges = false; // Clear unsaved changes flag

                        // Update original values to match current values
                        // so subsequent changes are tracked properly
                        _originalRunName = _runName;
                        _originalCalories = _calories;
                        _originalNotes = _notes;
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

  // New method to build the pill-shaped run metrics matching FoodCardOpen.dart exactly
  Widget _buildRunMetricPill(String label, String value, Color color, String iconAsset) {
    return Column(
      children: [
        // Label row with icon and text
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon - increased size for better visual balance with text
            Image.asset(
              iconAsset,
              width: 22,
              height: 22,
              color: Colors.black,
            ),
            // Small gap between icon and text
            SizedBox(width: 4),
            // Label text
            Text(label, style: TextStyle(fontSize: 12)),
          ],
        ),
        SizedBox(height: 4),
        Container(
          width: 80, // Match FoodCardOpen.dart exactly
          height: 8, // Match FoodCardOpen.dart exactly
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(4),
          ),
          child: FractionallySizedBox(
            widthFactor: 1.0,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMoreOption(String title, String iconAsset) {
    // Base icon size for pencilicon.png
    double baseIconSize = 25.0;
    // Calculate 10% larger size for the other two icons
    double largerIconSize = baseIconSize * 1.1; // 27.5px

    // Determine the size for the current icon
    double iconSize = (iconAsset == 'intensity.png' || iconAsset == 'bulb.png')
        ? largerIconSize
        : (iconAsset == 'globe.png' ? baseIconSize * 0.9 : baseIconSize);

    return GestureDetector(
      onTap: () {
        // Handle the click based on which option was selected
        if (title == 'Edit Run') {
          _editRun();
        } else if (title == 'Fix with AI') {
          _fixWithAI();
        } else if (title == 'Edit Intensity' || title == 'Add Intensity') {
          _editIntensity();
        }
        // Add other handlers for different options if needed
      },
      child: Container(
        margin: EdgeInsets.only(bottom: 15), // Set gap between boxes to 15px
        padding: EdgeInsets.symmetric(vertical: 0, horizontal: 20),
        width: double.infinity,
        height: 45,
        decoration: BoxDecoration(
          color: Colors.white,
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
                      color: Colors.black,
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
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                  softWrap: false, // Prevent text from wrapping to the next line
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreOptionWithDropdown(String title, String iconAsset) {
    // Base icon size for pencilicon.png
    double baseIconSize = 25.0;
    // Calculate 10% larger size for the other two icons
    double largerIconSize = baseIconSize * 1.1; // 27.5px

    // Determine the size for the current icon
    double iconSize = (iconAsset == 'intensity.png' || iconAsset == 'bulb.png')
        ? largerIconSize
        : (iconAsset == 'globe.png' ? baseIconSize * 0.9 : baseIconSize);

    return GestureDetector(
      onTap: _showPrivacyOptions,
      child: Container(
        margin: EdgeInsets.only(bottom: 15), // Set gap between boxes to 15px
        padding: EdgeInsets.symmetric(vertical: 0, horizontal: 20),
        width: double.infinity,
        height: 45,
        decoration: BoxDecoration(
          color: Colors.white,
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
                      color: Colors.black,
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
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                  softWrap: false, // Prevent text from wrapping to the next line
                ),
              ),
            ),
            // Dropdown arrow
            Icon(Icons.keyboard_arrow_down, color: Colors.black, size: 20),
          ],
        ),
      ),
    );
  }
} 