import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import '../Features/codia/codia_page.dart';
import 'dart:math';

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

class GymCardOpen extends StatefulWidget {
  final Map<String, dynamic> workoutData;
  
  const GymCardOpen({Key? key, required this.workoutData}) : super(key: key);

  @override
  State<GymCardOpen> createState() => _GymCardOpenState();
}

class _GymCardOpenState extends State<GymCardOpen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _isLiked = false;
  bool _isBookmarked = false;
  bool _isEditMode = false;
  int _counter = 1;
  String _privacyStatus = 'Private';
  bool _hasUnsavedChanges = false;
  
  // Original values to compare for changes
  String _originalWorkoutName = '';
  String _originalWorkoutType = '';
  String _originalCalories = '';
  int _originalCounter = 1;

  late AnimationController _bookmarkController;
  late Animation<double> _bookmarkScaleAnimation;
  late AnimationController _likeController;
  late Animation<double> _likeScaleAnimation;

  // Initialize with default values
  String _workoutName = 'Evening Workout 1';
  String _workoutType = 'Chest + tri + back';
  String _calories = '230';
  String _duration = '2h 32 min';
  String _volume = '10,384 kg';
  String _sets = '18';
  String _prs = '7';
  List<Map<String, dynamic>> _exercises = []; // Add exercises list
  double _intensity = 5.0; // Add intensity state variable

  @override
  void initState() {
    super.initState();
    print('GymCardOpen initState called');

    // Initialize with no unsaved changes
    _hasUnsavedChanges = false;

    // Initialize animation controllers
    _initAnimationControllers();

    // Set initial values from parameters if available
    if (widget.workoutData['name'] != null && widget.workoutData['name'].isNotEmpty) {
      _workoutName = widget.workoutData['name'];
    }

    if (widget.workoutData['calories'] != null) {
      _calories = widget.workoutData['calories'].toString();
    }

    if (widget.workoutData['duration'] != null) {
      int durationInMinutes = (widget.workoutData['duration'] / 60).floor();
      _duration = _formatDuration(durationInMinutes);
    }

    // Read actual session data
    if (widget.workoutData['volume'] != null) {
      _volume = '${widget.workoutData['volume']} kg';
    }

    if (widget.workoutData['prs'] != null) {
      _prs = widget.workoutData['prs'].toString();
    }

    // Read intensity data
    if (widget.workoutData['intensity'] != null) {
      _intensity = (widget.workoutData['intensity'] as num).toDouble();
    }

    // Read exercises data
    if (widget.workoutData['exercises'] != null) {
      _exercises = List<Map<String, dynamic>>.from(widget.workoutData['exercises']);
      // Calculate total completed sets only
      int totalCompletedSets = 0;
      for (final exercise in _exercises) {
        if (exercise['sets'] != null) {
          final sets = exercise['sets'] as List;
          for (final set in sets) {
            if (set is Map<String, dynamic> && set['isCompleted'] == true) {
              totalCompletedSets++;
            }
          }
        }
      }
      _sets = totalCompletedSets.toString();
    }

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

  // Format duration for display
  String _formatDuration(int durationInMinutes) {
    if (durationInMinutes < 1) {
      return '0 min';
    } else if (durationInMinutes < 60) {
      return '${durationInMinutes}min';
    } else {
      int hours = durationInMinutes ~/ 60;
      int minutes = durationInMinutes % 60;
      if (minutes == 0) {
        return '${hours}h';
      } else {
        return '${hours}h ${minutes}min';
      }
    }
  }

  // Add this method to reset the unsaved changes state after loading
  void _resetUnsavedChangesState() {
    // Update all original values to match current values
    _originalWorkoutName = _workoutName;
    _originalWorkoutType = _workoutType;
    _originalCalories = _calories;
    _originalCounter = _counter;

    // Reset the unsaved changes flag
    _hasUnsavedChanges = false;

    print('Reset unsaved changes state - screen is now in clean state');
  }

  // Load saved data from SharedPreferences
  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final workoutId = _workoutName.replaceAll(' ', '_').toLowerCase();

      print('Attempting to load saved data for workoutId: $workoutId');

      setState(() {
        // Load interaction data only (likes, bookmarks, counter)
        _isLiked = prefs.getBool('workout_liked_$workoutId') ?? false;
        _isBookmarked = prefs.getBool('workout_bookmarked_$workoutId') ?? false;
        _counter = prefs.getInt('workout_counter_$workoutId') ?? 1;
        // Load privacy status for this workout item
        _privacyStatus = prefs.getString('workout_privacy_$workoutId') ?? 'Private';

        // Only load nutrition values if they weren't passed as parameters
        if (widget.workoutData['calories'] == null) {
          _calories = prefs.getString('workout_calories_$workoutId') ?? _calories;
        }
      });

      print(
          'Loaded interaction data for $workoutId: liked=$_isLiked, bookmarked=$_isBookmarked, counter=$_counter');
      print(
          'Using workout data: calories=$_calories, duration=$_duration, volume=$_volume, sets=$_sets, prs=$_prs');

      // Important: Reset unsaved changes state after everything is loaded
      _resetUnsavedChangesState();
    } catch (e) {
      print('Error loading saved workout data: $e');
    }
  }

  // Save all data to SharedPreferences
  Future<void> _saveData() async {
    try {
      print('Saving all data to SharedPreferences...');
      final prefs = await SharedPreferences.getInstance();
      final String workoutId = _workoutName.replaceAll(' ', '_').toLowerCase();

      await prefs.setBool('workout_liked_$workoutId', _isLiked);
      await prefs.setBool('workout_bookmarked_$workoutId', _isBookmarked);
      await prefs.setInt('workout_counter_$workoutId', _counter);
      await prefs.setString('workout_privacy_$workoutId', _privacyStatus);

      // Save all workout values
      await prefs.setString('workout_calories_$workoutId', _calories);

      print(
          'Saved data for $workoutId: liked=$_isLiked, bookmarked=$_isBookmarked, counter=$_counter, calories=$_calories');
    } catch (e) {
      print('Error saving workout data: $e');
    }
  }

  @override
  void dispose() {
    _bookmarkController.dispose();
    _likeController.dispose();
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
    if (_workoutName != _originalWorkoutName) {
      print('Workout name changed: $_workoutName != $_originalWorkoutName');
      return true;
    }

    if (_calories != _originalCalories) {
      print('Calories changed: $_calories != $_originalCalories');
      return true;
    }

    if (_counter != _originalCounter) {
      print('Counter changed: $_counter != $_originalCounter');
      return true;
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
        if (mounted) {
          setState(() {
            // Reset all values to their original values
            _workoutName = _originalWorkoutName;
            _workoutType = _originalWorkoutType;
            _calories = _originalCalories;
            _counter = _originalCounter;
            _hasUnsavedChanges = false;

            // Always navigate to CodiaPage instead of using pop()
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => CodiaPage()),
            );
          });
        }
      }
      // If shouldDiscard is false, user clicked "Cancel", stay on GymCardOpen
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

  // Method to show privacy options in a bottom sheet
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
              _buildPrivacyOption(
                  'Private', 'assets/images/Lock.png', _selectedPrivacy,
                  (value) {
                setModalState(() => _selectedPrivacy = value);
                setState(() {
                  _privacyStatus = value;
                  _markAsUnsaved();
                });
                Navigator.pop(context);
              }),
              _buildPrivacyOption('Friends Only',
                  'assets/images/socialicon.png', _selectedPrivacy, (value) {
                setModalState(() => _selectedPrivacy = value);
                setState(() {
                  _privacyStatus = value;
                  _markAsUnsaved();
                });
                Navigator.pop(context);
              }),
              _buildPrivacyOption(
                  'Public', 'assets/images/globe.png', _selectedPrivacy,
                  (value) {
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

  // Mark as having unsaved changes
  void _markAsUnsaved() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
      print('Marked as having unsaved changes');
    }
  }

  // Show standard dialog
  void _showStandardDialog({
    required String title,
    required String message,
    required String positiveButtonText,
  }) {
    showDialog(
      context: context,
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
                  title,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SF Pro Display',
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Text(
                  message,
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
                      positiveButtonText,
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
                          // Dumbbell icon - centered like the meal image in FoodCardOpen
                          Center(
                            child: Image.asset(
                              'assets/images/dumbbell.png',
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
                                           'Apr 4, 12:32',
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
                                           _workoutName,
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
                                           _workoutType,
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

                                 // Calories and macros card - exactly like FoodCardOpen
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
                                                   _calories,
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

                                         // Workout Stats
                                         Row(
                                           mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                           children: [
                                             _buildMacro('Time', _duration, Color(0xFFD7C1FF)),
                                             _buildMacro('Volume', _volume, Color(0xFFFFD8B1)),
                                             _buildMacro('Sets', _sets, Color(0xFFB1EFD8)),
                                             _buildMacro('PRs', _prs, Color(0xFFFFB1B1)),
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
                                 ],

                                 SizedBox(height: 32),

                                 // Exercises Section - exactly like FoodCardOpen
                                 Padding(
                                   padding: const EdgeInsets.symmetric(horizontal: 29),
                                   child: Column(
                                     crossAxisAlignment: CrossAxisAlignment.start,
                                     children: [
                                       Text(
                                         'Exercises',
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
                                             // Display all exercises from session
                                             ..._exercises.asMap().entries.map((entry) {
                                               final exerciseIndex = entry.key;
                                               final exercise = entry.value;
                                               final exerciseName = exercise['name'] ?? 'Unknown Exercise';
                                               final sets = exercise['sets'] as List<dynamic>? ?? [];
                                               
                                               return Column(
                                                 crossAxisAlignment: CrossAxisAlignment.start,
                                                 children: [
                                                   // Exercise header
                                                   Row(
                                                     children: [
                                                       Container(
                                                         width: 40,
                                                         height: 40,
                                                         decoration: BoxDecoration(
                                                           color: Color(0xFFF2F2F2),
                                                           borderRadius: BorderRadius.circular(8),
                                                         ),
                                                         child: Center(
                                                           child: Image.asset(
                                                             'assets/images/dumbbell.png',
                                                             width: 24,
                                                             height: 24,
                                                             color: Colors.black,
                                                           ),
                                                         ),
                                                       ),
                                                       SizedBox(width: 12),
                                                       Expanded(
                                                         child: Text(
                                                           exerciseName,
                                                           style: TextStyle(
                                                             fontWeight: FontWeight.bold,
                                                             fontSize: 16,
                                                             fontFamily: 'SF Pro Display',
                                                           ),
                                                         ),
                                                       ),
                                                     ],
                                                   ),
                                                   SizedBox(height: 16),
                                                   // Table header
                                                   Container(
                                                     padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                                     decoration: BoxDecoration(
                                                       color: Color(0xFFF8F8F8),
                                                       borderRadius: BorderRadius.circular(8),
                                                     ),
                                                     child: Row(
                                                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                       children: [
                                                         Text(
                                                           "SET",
                                                           style: TextStyle(
                                                             fontWeight: FontWeight.w600,
                                                             fontSize: 12,
                                                             fontFamily: 'SF Pro Display',
                                                             color: Colors.black54,
                                                           ),
                                                         ),
                                                         Text(
                                                           "KG",
                                                           style: TextStyle(
                                                             fontWeight: FontWeight.w600,
                                                             fontSize: 12,
                                                             fontFamily: 'SF Pro Display',
                                                             color: Colors.black54,
                                                           ),
                                                         ),
                                                         Text(
                                                           "REPS",
                                                           style: TextStyle(
                                                             fontWeight: FontWeight.w600,
                                                             fontSize: 12,
                                                             fontFamily: 'SF Pro Display',
                                                             color: Colors.black54,
                                                           ),
                                                         ),
                                                       ],
                                                     ),
                                                   ),
                                                   SizedBox(height: 8),
                                                   // Table rows for this exercise
                                                   ...sets.asMap().entries.map((setEntry) {
                                                     final setIndex = setEntry.key;
                                                     final set = setEntry.value as Map<String, dynamic>;
                                                     final kg = set['kg']?.toString() ?? '0';
                                                     final reps = set['reps']?.toString() ?? '0';
                                                     
                                                     return Container(
                                                       padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                                       child: Row(
                                                         mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                         children: [
                                                           Text(
                                                             "${setIndex + 1}",
                                                             style: TextStyle(
                                                               fontSize: 14,
                                                               fontFamily: 'SF Pro Display',
                                                               fontWeight: FontWeight.w500,
                                                             ),
                                                           ),
                                                           Text(
                                                             kg,
                                                             style: TextStyle(
                                                               fontSize: 14,
                                                               fontFamily: 'SF Pro Display',
                                                               fontWeight: FontWeight.w500,
                                                             ),
                                                           ),
                                                           Text(
                                                             reps,
                                                             style: TextStyle(
                                                               fontSize: 14,
                                                               fontFamily: 'SF Pro Display',
                                                               fontWeight: FontWeight.w500,
                                                             ),
                                                           ),
                                                         ],
                                                       ),
                                                     );
                                                   }).toList(),
                                                   // Add spacing between exercises (except for the last one)
                                                   if (exerciseIndex < _exercises.length - 1) SizedBox(height: 24),
                                                 ],
                                               );
                                             }).toList(),
                                           ],
                                         ),
                                       ),
                                     ],
                                   ),
                                 ),

                                 SizedBox(height: 32),

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
                                       SizedBox(height: 20),
                                       _buildMoreOption('Add Intensity', 'intensity.png'),
                                       _buildMoreOption('Edit Workout', 'pencilicon.png'),
                                       _buildMoreOption('Fix with AI', 'bulb.png'),
                                       _buildMoreOptionWithDropdown(_privacyStatus, 'globe.png'),
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
                    // Exit edit mode if active
                    if (_isEditMode) {
                      setState(() {
                        _isEditMode = false;
                      });
                    }

                    // Save logic goes here
                    _saveData().then((_) {
                      setState(() {
                        _hasUnsavedChanges = false;

                        // Copy current values to original
                        _originalWorkoutName = _workoutName;
                        _originalWorkoutType = _workoutType;
                        _originalCalories = _calories;
                        _originalCounter = _counter;
                      });

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

  Widget _buildMetricItem(String label, String value, Color color) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontFamily: 'SF Pro Display',
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamily: 'SF Pro Display',
          ),
        ),
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
        if (title == 'Edit Workout') {
          // Show edit workout functionality
          print('Edit Workout functionality not implemented yet.');
        } else if (title == 'Fix with AI') {
          // Show the Fix with AI dialog
          print('Fix with AI functionality not implemented yet.');
        } else if (title == 'Add Intensity') {
          // Show intensity modal
          _showIntensityModal();
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

  Widget _buildMacro(String name, String amount, Color color) {
    return Container(
      width: 50, // Reduced width to prevent overflow
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            name, 
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Container(
            width: 45, // Slightly reduced pill width
            height: 10, // Fixed pill height
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(5),
            ),
            child: FractionallySizedBox(
              widthFactor: 1.0,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
          SizedBox(height: 4),
          Text(
            amount,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showIntensityModal() {
    double currentIntensity = _intensity;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withOpacity(0.5),
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.close,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
                
                // Title
                Text(
                  'Add Intensity',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'SF Pro Display',
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24),
                
                // Intensity icon
                Image.asset(
                  'assets/images/intensity.png',
                  width: 48,
                  height: 48,
                  color: Colors.black,
                ),
                SizedBox(height: 16),
                
                // Instruction label
                Text(
                  'Set Workout Intensity from 1-10',
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: 'SF Pro Display',
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24),
                
                // Slider
                SliderTheme(
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
                SizedBox(height: 8),
                
                // Selected value display
                Text(
                  currentIntensity.round().toString(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'SF Pro Display',
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: 32),
                
                // Add button
                Container(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      // Save the intensity value
                      setState(() {
                        _intensity = currentIntensity;
                      });
                      
                      // Close the modal
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
} 