import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:provider/provider.dart';
import '../WorkoutSession/WorkoutSessionProvider.dart';
import '../Screens/WeightLifting.dart';
import '../NewScreens/GoodJob.dart';
import '../models/intensity_level.dart';

class SaveWorkout extends StatefulWidget {
  final int duration;
  final int volume;
  final int prs;
  final String? workoutType; // 'weightlifting', 'running', 'custom', or custom name
  final double? distance; // Distance for running/custom workouts
  final String? exerciseName; // Exercise name for custom workouts
  final IntensityLevel? intensityLevel; // Intensity level for custom workouts
  final String? initialTitle; // Initial title for editing existing workouts
  final String? runId; // ID of the run being edited (null for new runs)
  const SaveWorkout({
    Key? key, 
    required this.duration, 
    required this.volume, 
    required this.prs, 
    this.workoutType, 
    this.distance, 
    this.exerciseName, 
    this.intensityLevel,
    this.initialTitle,
    this.runId,
  }) : super(key: key);

  @override
  State<SaveWorkout> createState() => _SaveWorkoutState();
}

class _SaveWorkoutState extends State<SaveWorkout> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedPrivacy = 'Public';

  @override
  void initState() {
    super.initState();
    
    // Use initial title if provided (for editing), otherwise generate a new title
    if (widget.initialTitle != null && widget.initialTitle!.isNotEmpty) {
      _titleController.text = widget.initialTitle!;
    } else {
      _generateTitle();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _generateTitle() {
    if (_titleController.text.isNotEmpty || widget.initialTitle != null) return; // Don't override if user already entered a title or if initial title is provided
    
    final now = DateTime.now();
    final hour = now.hour;
    
    String timeOfDay;
    if (hour >= 5 && hour < 12) {
      timeOfDay = 'Morning';
    } else if (hour >= 12 && hour < 17) {
      timeOfDay = 'Afternoon';
    } else if (hour >= 17 && hour < 21) {
      timeOfDay = 'Evening';
    } else {
      timeOfDay = 'Night';
    }
    
    String workoutName;
    if (widget.workoutType == null) {
      // Default to weightlifting if no type specified
      workoutName = 'Workout';
    } else if (widget.workoutType == 'running') {
      workoutName = 'Run';
    } else if (widget.workoutType == 'weightlifting') {
      workoutName = 'Workout';
    } else if (widget.workoutType == 'custom') {
      // Custom workout name
      workoutName = 'Exercise';
    } else {
      // Custom workout name from "More" field
      workoutName = widget.workoutType!;
    }
    
    _titleController.text = '$timeOfDay $workoutName';
  }

  void _showPrivacyOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPrivacyOption('Public', 'assets/images/globe.png'),
            _buildPrivacyOption('Private', 'assets/images/Lock.png'),
            _buildPrivacyOption('Friends Only', 'assets/images/socialicon.png'),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyOption(String title, String iconPath) {
    bool isSelected = _selectedPrivacy == title;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPrivacy = title;
        });
        Navigator.pop(context);
      },
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
            if (isSelected)
              Icon(Icons.check, color: Colors.black),
          ],
        ),
      ),
    );
  }

  void _showImageSelectionModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grabber/handle
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Take Photo option
            InkWell(
              onTap: () async {
                Navigator.pop(context);
                await _takePhoto();
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                                         Image.asset(
                       'assets/images/camera.png',
                       width: 24,
                       height: 24,
                       color: Colors.black,
                     ),
                    SizedBox(width: 12),
                    Text(
                      'Take Photo',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Divider
            Container(
              height: 0.5,
              color: Colors.grey[300],
              margin: EdgeInsets.symmetric(horizontal: 20),
            ),
            // Upload From Library option
            InkWell(
              onTap: () async {
                Navigator.pop(context);
                await _uploadFromLibrary();
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                                         Image.asset(
                       'assets/images/addphoto.png',
                       width: 24,
                       height: 24,
                       color: Colors.black,
                     ),
                    SizedBox(width: 12),
                    Text(
                      'Upload From Library',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.black,
                        fontFamily: 'SF Pro Display',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _takePhoto() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      if (photo != null) {
        // Handle the captured photo
        print('Photo taken: ${photo.path}');
        // TODO: Add logic to handle the captured photo
      }
    } catch (e) {
      print('Error taking photo: $e');
    }
  }

  Future<void> _uploadFromLibrary() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        // Handle the selected image
        print('Image selected: ${image.path}');
        // TODO: Add logic to handle the selected image
      }
    } catch (e) {
      print('Error selecting image: $e');
    }
  }



  Future<void> _showDiscardDialog() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: Container(
            width: 338,
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Discard Workout?',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'SF Pro Display',
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24),
                // Discard button
                Container(
                  width: 267,
                  height: 40,
                  margin: EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        offset: Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      splashColor: Colors.grey[200],
                      highlightColor: Colors.grey[100],
                      onTap: () => Navigator.of(context).pop(true),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/trashcan.png',
                            width: 15,
                            height: 15,
                            color: Color(0xFFFF3B30),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Discard',
                            style: TextStyle(
                              color: Color(0xFFFF3B30),
                              fontSize: 17,
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Cancel button
                Container(
                  width: 267,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        offset: Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      splashColor: Colors.grey[200],
                      highlightColor: Colors.grey[100],
                      onTap: () => Navigator.of(context).pop(false),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/CLOSEicon.png',
                            width: 15,
                            height: 15,
                            color: Color(0xFFBDBDBD),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Cancel',
                            style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 17,
                              fontFamily: 'SF Pro Display',
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
          ),
        ),
      ),
    );
    if (shouldDiscard == true && mounted) {
      final provider = Provider.of<WorkoutSessionProvider>(context, listen: false);
      provider.endSession();
      _titleController.clear();
      _descriptionController.clear();
      await Future.delayed(Duration.zero);
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            opaque: false,
            pageBuilder: (context, animation, secondaryAnimation) => WeightLifting(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return Stack(
                children: [
                  child,
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset.zero,
                      end: const Offset(1.0, 0.0),
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeInOut,
                    )),
                    child: Container(
                      color: Colors.transparent,
                      child: this.widget,
                    ),
                  ),
                ],
              );
            },
            transitionDuration: const Duration(milliseconds: 500),
            reverseTransitionDuration: const Duration(milliseconds: 500),
          ),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background4.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                children: [
                  // AppBar
                  PreferredSize(
                    preferredSize: Size.fromHeight(kToolbarHeight),
                    child: AppBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      automaticallyImplyLeading: false,
                      flexibleSpace: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 29).copyWith(top: 16, bottom: 8.5),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: Colors.black, size: 24),
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: BoxConstraints(),
                                ),
                                Text(
                                  'Save Workout',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'SF Pro Display',
                                    color: Colors.black,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                SizedBox(width: 24),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Divider line
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 29),
                    height: 0.5,
                    color: Color(0xFFBDBDBD),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 29),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            SizedBox(height: 20),
                            // Workout title field
                            Container(
                              width: double.infinity,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Color(0xFFE8E8E8)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    textSelectionTheme: TextSelectionThemeData(
                                      selectionColor: Colors.grey[300]!.withOpacity(0.5),
                                      selectionHandleColor: Colors.grey[300]!,
                                      cursorColor: Colors.black,
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _titleController,
                                    cursorColor: Colors.black,
                                    cursorWidth: 1.2,
                                    style: TextStyle(
                                      fontSize: 13.6,
                                      fontFamily: '.SF Pro Display',
                                      color: Colors.black,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Workout title',
                                      hintStyle: TextStyle(
                                        color: Colors.grey[600]!.withOpacity(0.7),
                                        fontSize: 13.6,
                                        fontFamily: '.SF Pro Display',
                                      ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(vertical: 15),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                            
                            // Describe workout field
                            Container(
                              width: double.infinity,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Color(0xFFE8E8E8)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    offset: Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    textSelectionTheme: TextSelectionThemeData(
                                      selectionColor: Colors.grey[300]!.withOpacity(0.5),
                                      selectionHandleColor: Colors.grey[300]!,
                                      cursorColor: Colors.black,
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _descriptionController,
                                    cursorColor: Colors.black,
                                    cursorWidth: 1.2,
                                    style: TextStyle(
                                      fontSize: 13.6,
                                      fontFamily: '.SF Pro Display',
                                      color: Colors.black,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Describe your workout',
                                      hintStyle: TextStyle(
                                        color: Colors.grey[600]!.withOpacity(0.7),
                                        fontSize: 13.6,
                                        fontFamily: '.SF Pro Display',
                                      ),
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(vertical: 15),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                            
                            // Privacy selector
                            GestureDetector(
                              onTap: _showPrivacyOptions,
                              child: Container(
                                width: double.infinity,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Color(0xFFE8E8E8)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      offset: Offset(0, 2),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Image.asset(
                                            _selectedPrivacy.toLowerCase() == 'public' 
                                              ? 'assets/images/globe.png'
                                              : _selectedPrivacy.toLowerCase() == 'private' 
                                                ? 'assets/images/Lock.png'
                                                : 'assets/images/socialicon.png',
                                            width: 20,
                                            height: 20,
                                            color: Colors.black,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            _selectedPrivacy,
                                            style: TextStyle(
                                              color: Colors.black,
                                              fontSize: 15,
                                              fontFamily: 'SF Pro Display',
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Icon(Icons.keyboard_arrow_down, color: Colors.black, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 25),
                            
                            // Bottom row with Add Photos and buttons
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Add Photos/Videos button
                                GestureDetector(
                                  onTap: _showImageSelectionModal,
                                  child: Container(
                                    width: 118,
                                    height: 94,
                                    child: CustomPaint(
                                      painter: DottedBorderPainter(
                                        color: Colors.black,
                                        strokeWidth: 1.5,
                                        dashPattern: [6, 4],
                                        borderRadius: 15,
                                      ),
                                      child: Container(
                                        color: Colors.transparent,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'assets/images/AddPhoto.png',
                                            width: 50,
                                            height: 50,
                                            color: Color(0xFF333333),
                                          ),
                                          SizedBox(height: 4),
                                          Container(
                                            width: double.infinity,
                                            child: Text(
                                              'Add Photos/Videos',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Color(0xFF333333),
                                                fontSize: 12,
                                                fontFamily: 'SF Pro Display',
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ),
                                ),
                                SizedBox(width: 16),
                                // Buttons column
                                Expanded(
                                  child: SizedBox(
                                    width: 267,
                                    height: 94,
                                    child: Stack(
                                      children: [
                                        // Discard button (top-aligned)
                                        Positioned(
                                          top: 0,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            width: 267,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(15),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.05),
                                                  offset: Offset(0, 2),
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(15),
                                                splashColor: Colors.grey[200],
                                                highlightColor: Colors.grey[100],
                                                onTap: _showDiscardDialog,
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Image.asset(
                                                      'assets/images/trashcan.png',
                                                      width: 20,
                                                      height: 20,
                                                      color: Color(0xFFFF4D4F),
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Discard',
                                                      style: TextStyle(
                                                        color: Color(0xFFFF4D4F),
                                                        fontSize: 17,
                                                        fontFamily: 'SF Pro Display',
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Save Workout button (bottom-aligned)
                                        Positioned(
                                          bottom: 0,
                                          left: 0,
                                          right: 0,
                                          child: Container(
                                            width: 267,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: Colors.black,
                                              borderRadius: BorderRadius.circular(15),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.05),
                                                  offset: Offset(0, 2),
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(15),
                                                splashColor: Colors.grey[800],
                                                highlightColor: Colors.grey[900],
                                                onTap: () async {
                                                  // End the workout session before saving
                                                  final provider = Provider.of<WorkoutSessionProvider>(context, listen: false);
                                                  provider.endSession();
                                                  
                                                  // Navigate to GoodJob.dart with standard forward animation
                                                  if (mounted) {
                                                    Navigator.of(context).push(
                                                      PageRouteBuilder(
                                                        pageBuilder: (context, animation, secondaryAnimation) => GoodJob(
                                                          workoutTitle: _titleController.text.isNotEmpty ? _titleController.text : null,
                                                          workoutType: widget.workoutType,
                                                          duration: widget.duration,
                                                          volume: widget.volume,
                                                          prs: widget.prs,
                                                          distance: widget.distance,
                                                          exerciseName: widget.exerciseName,
                                                          intensityLevel: widget.intensityLevel,
                                                          runId: widget.runId, // Pass the run ID for editing existing runs
                                                        ),
                                                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                                          const begin = Offset(1.0, 0.0);
                                                          const end = Offset.zero;
                                                          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: Curves.easeInOut));
                                                          return SlideTransition(
                                                            position: animation.drive(tween),
                                                            child: child,
                                                          );
                                                        },
                                                        transitionDuration: const Duration(milliseconds: 400),
                                                        reverseTransitionDuration: const Duration(milliseconds: 400),
                                                      ),
                                                    );
                                                  }
                                                },
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Image.asset(
                                                      'assets/images/finish.png',
                                                      width: 20,
                                                      height: 20,
                                                      color: Colors.white,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Save Workout',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 17,
                                                        fontWeight: FontWeight.w500,
                                                        fontFamily: 'SF Pro Display',
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
                                ),
                              ],
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
      ),
    );
  }
}

class DottedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final List<double> dashPattern;
  final double borderRadius;

  DottedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashPattern,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );
    path.addRRect(rect);

    final dashLength = dashPattern[0];
    final gapLength = dashPattern[1];
    final totalLength = dashLength + gapLength;

    final pathMetrics = path.computeMetrics().first;
    final pathLength = pathMetrics.length;
    final dashCount = (pathLength / totalLength).floor();

    for (int i = 0; i < dashCount; i++) {
      final start = i * totalLength;
      final end = start + dashLength;
      if (end <= pathLength) {
        final extractPath = pathMetrics.extractPath(start, end);
        canvas.drawPath(extractPath, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}