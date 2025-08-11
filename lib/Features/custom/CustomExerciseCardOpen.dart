import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../models/intensity_level.dart';

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

class CustomExerciseCardOpen extends StatefulWidget {
  final Map<String, dynamic> workoutData;
  
  const CustomExerciseCardOpen({Key? key, required this.workoutData}) : super(key: key);

  @override
  State<CustomExerciseCardOpen> createState() => _CustomExerciseCardOpenState();
}

class _CustomExerciseCardOpenState extends State<CustomExerciseCardOpen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _isLiked = false;
  bool _isBookmarked = false;
  bool _hasUnsavedChanges = false;
  
  // Original values to compare for changes
  String _originalExerciseName = '';
  String _originalCalories = '';
  String _originalNotes = '';

  late AnimationController _bookmarkController;
  late Animation<double> _bookmarkScaleAnimation;
  late AnimationController _likeController;
  late Animation<double> _likeScaleAnimation;

  // Initialize with default values
  String _exerciseName = 'Custom Exercise';
  String _notes = '';
  String _calories = '0';
  String _time = '0min';
  IntensityLevel? _intensity; // Changed to nullable to track if intensity exists
  String _privacyStatus = 'Private';

  @override
  void initState() {
    super.initState();
    print('CustomExerciseCardOpen initState called');

    // Initialize with no unsaved changes
    _hasUnsavedChanges = false;

    // Initialize animation controllers
    _initAnimationControllers();

    // Set initial values from parameters if available
    if (widget.workoutData['name'] != null && widget.workoutData['name'].isNotEmpty) {
      _exerciseName = widget.workoutData['name'];
    }

    if (widget.workoutData['notes'] != null && widget.workoutData['notes'].isNotEmpty) {
      _notes = widget.workoutData['notes'];
    }

    if (widget.workoutData['calories'] != null) {
      _calories = widget.workoutData['calories'].toString();
    }

    if (widget.workoutData['duration'] != null) {
      int durationInSeconds = widget.workoutData['duration'] is int 
          ? widget.workoutData['duration'] 
          : int.tryParse(widget.workoutData['duration'].toString()) ?? 0;
      _time = _formatDuration(durationInSeconds);
    }

    if (widget.workoutData['intensityLevel'] != null) {
      int intensityIndex = widget.workoutData['intensityLevel'] is int 
          ? widget.workoutData['intensityLevel'] 
          : int.tryParse(widget.workoutData['intensityLevel'].toString()) ?? 0;
      if (intensityIndex >= 0 && intensityIndex < IntensityLevel.values.length) {
        _intensity = IntensityLevel.values[intensityIndex];
      }
    }

    // Store original values
    _originalExerciseName = _exerciseName;
    _originalCalories = _calories;
    _originalNotes = _notes;
  }

  @override
  void dispose() {
    _bookmarkController.dispose();
    _likeController.dispose();
    super.dispose();
  }

  void _initAnimationControllers() {
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

    _likeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _likeScaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _likeController,
      curve: Curves.easeInOut,
    ));
  }

  void _toggleBookmark() {
    if (_isBookmarked) {
      _bookmarkController.reverse();
    } else {
      _bookmarkController.forward();
    }
    setState(() {
      _isBookmarked = !_isBookmarked;
      _markAsUnsaved();
    });
  }

  void _toggleLike() {
    if (_isLiked) {
      _likeController.reverse();
    } else {
      _likeController.forward();
    }
    setState(() {
      _isLiked = !_isLiked;
      _markAsUnsaved();
    });
  }

  void _markAsUnsaved() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }
  }

  void _handleBack() {
    if (_hasUnsavedChanges) {
      _showUnsavedChangesDialog();
    } else {
      Navigator.pop(context);
    }
  }

  void _showUnsavedChangesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Unsaved Changes'),
          content: Text('You have unsaved changes. Do you want to save them before leaving?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Go back without saving
              },
              child: Text('Discard'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                _saveData(); // Save and then go back
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    }
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    
    if (minutes < 60) {
      return '${minutes}min';
    }
    
    int hours = minutes ~/ 60;
    int remainingMinutes = minutes % 60;
    
    if (remainingMinutes > 0) {
      return '${hours}h ${remainingMinutes}min';
    } else {
      return '${hours}h';
    }
  }

  void _editIntensity() {
    IntensityLevel currentIntensity = _intensity ?? IntensityLevel.moderate; // Default to moderate if intensity is null
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
                                        'Set Exercise Intensity from 1-10',
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
                                          value: currentIntensity.rank.toDouble(),
                                          min: 1.0,
                                          max: 6.0,
                                          divisions: 5,
                                          onChanged: (value) {
                                            setModalState(() {
                                              currentIntensity = IntensityLevel.values[value.round() - 1];
                                            });
                                          },
                                        ),
                                      ),
                                    ),

                                    // Value display
                                    SizedBox(height: 8),
                                                                         Text(
                                       currentIntensity.rank.toString(),
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
                        top: 14,
                        right: 10,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              size: 20,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),

                      // Trash button for deleting intensity
                      if (_intensity != null)
                        Positioned(
                          top: 14,
                          left: 10,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _intensity = null;
                                _markAsUnsaved();
                              });
                              Navigator.pop(context);
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.red[100],
                                shape: BoxShape.circle,
                              ),
                              child: Image.asset(
                                'assets/images/trashcan.png',
                                width: 20,
                                height: 20,
                                color: Colors.red[600],
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
      },
    );
  }

  void _editExercise() {
    // Simple editor for exercise name and notes
    TextEditingController nameController = TextEditingController(text: _exerciseName);
    TextEditingController notesController = TextEditingController(text: _notes);
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit Exercise'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Exercise Name',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _exerciseName = nameController.text.trim();
                  _notes = notesController.text.trim();
                  _markAsUnsaved();
                });
                Navigator.pop(context);
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _fixWithAI() {
    // Reuse the exact same popup from FoodCardOpen
    TextEditingController descriptionController = TextEditingController();
    bool isFormValid = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void updateFormValidity() {
              bool descriptionValid = descriptionController.text.trim().isNotEmpty;
              setDialogState(() {
                isFormValid = descriptionValid;
              });
            }

            void handleSubmit() async {
              if (!isFormValid) return;
              String description = descriptionController.text.trim();
              Navigator.pop(context);
              
              // For now, just show a placeholder message
              // In the future, this would call an AI service
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('AI fix functionality coming soon!')),
              );
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 0,
              backgroundColor: Colors.white,
              insetPadding: EdgeInsets.symmetric(horizontal: 32),
              child: Container(
                width: 326,
                height: 360,
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(height: 14),
                          Text(
                            'Fix with AI',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SF Pro Display',
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset(
                                    'assets/images/bulb.png',
                                    width: 43.0,
                                    height: 43.0,
                                    color: Colors.black,
                                  ),
                                  SizedBox(height: 28),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 25),
                                    child: Text(
                                      'Describe what needs to be fixed',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontFamily: 'SF Pro Display',
                                        fontWeight: FontWeight.w400,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  SizedBox(height: 24),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: TextField(
                                      controller: descriptionController,
                                      onChanged: (value) => updateFormValidity(),
                                      decoration: InputDecoration(
                                        hintText: 'Enter description...',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        contentPadding: EdgeInsets.all(16),
                                      ),
                                      maxLines: 3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Container(
                              width: 280,
                              height: 48,
                              margin: EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: isFormValid ? Colors.black : Colors.grey[400],
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: TextButton(
                                onPressed: isFormValid ? handleSubmit : null,
                                style: ButtonStyle(
                                  overlayColor: MaterialStateProperty.all(Colors.transparent),
                                ),
                                child: Text(
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
                    Positioned(
                      top: 14,
                      right: 10,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: Colors.black,
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
      },
    );
  }

  void _showPrivacyOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.public),
                title: Text('Public'),
                onTap: () {
                  setState(() {
                    _privacyStatus = 'Public';
                    _markAsUnsaved();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.lock),
                title: Text('Private'),
                onTap: () {
                  setState(() {
                    _privacyStatus = 'Private';
                    _markAsUnsaved();
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing workout cards
      List<String> workoutCards = prefs.getStringList('workout_cards') ?? [];
      
      // Find and update the existing entry by ID
      bool found = false;
      for (int i = 0; i < workoutCards.length; i++) {
        try {
          Map<String, dynamic> workout = jsonDecode(workoutCards[i]);
          if (workout['id'] == widget.workoutData['id']) {
            // Update the existing entry
            workout['name'] = _exerciseName;
            workout['notes'] = _notes;
            workout['calories'] = int.tryParse(_calories) ?? 0;
            workout['intensityLevel'] = _intensity?.index;
            workout['privacyStatus'] = _privacyStatus;
            workout['isBookmarked'] = _isBookmarked;
            workout['isLiked'] = _isLiked;
            
            workoutCards[i] = jsonEncode(workout);
            found = true;
            break;
          }
        } catch (e) {
          print('Error parsing workout card: $e');
        }
      }
      
      if (found) {
        // Save updated workout cards
        await prefs.setStringList('workout_cards', workoutCards);
        
        setState(() {
          _hasUnsavedChanges = false;
        });
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exercise updated successfully!')),
        );
        
        // Go back to previous screen
        Navigator.pop(context);
      } else {
        throw Exception('Workout not found');
      }
    } catch (e) {
      print('Error saving exercise data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving exercise data')),
      );
    }
  }

  // New method to build the pill-shaped metrics matching RunCardOpen.dart exactly
  Widget _buildMetricPill(String label, String value, Color color, String iconAsset) {
    // Special handling for intensity to show the label
    if (label == 'Intensity' && _intensity != null) {
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
              // Small gap between label and value
              SizedBox(width: 6),
              Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          SizedBox(height: 4),
          Container(
            width: 80, // Match RunCardOpen.dart exactly
            height: 8, // Match RunCardOpen.dart exactly
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
          // Show intensity label below the pill
          Text(
            _intensity!.label,
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    
    // Regular pill for non-intensity metrics
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
          width: 80, // Match RunCardOpen.dart exactly
          height: 8, // Match RunCardOpen.dart exactly
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
        if (title == 'Edit Exercise') {
          _editExercise();
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
            Icon(Icons.keyboard_arrow_down, color: Colors.black),
          ],
        ),
      ),
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
                          // Plus icon - centered like the meal image in FoodCardOpen
                          Center(
                            child: Image.asset(
                              'assets/images/add.png',
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
                                           _exerciseName,
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

                                         // Exercise Stats - Two pill-shaped components
                                         Row(
                                           mainAxisAlignment: MainAxisAlignment.spaceAround,
                                           children: [
                                             _buildMetricPill('Time', _time, Color(0xFFD7C1FF), 'assets/images/Stopwatch.png'), // Purple
                                                                                           _buildMetricPill('Intensity', _intensity != null ? '${_intensity!.rank}/6' : '—/6', Color(0xFFFFD8B1), 'assets/images/intensity.png'), // Orange
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
                                       _buildMoreOption('Edit Exercise', 'pencilicon.png'),
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
                  onPressed: _hasUnsavedChanges ? _saveData : null,
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
}
