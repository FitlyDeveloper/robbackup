import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../Features/codia/codia_page.dart';
import '../models/intensity_level.dart';

final List<Map<String, dynamic>> weightComparisons = [
  {"min": 0, "max": 200, "label": "a bear", "image": "assets/images/bear.png"},
  {"min": 200, "max": 500, "label": "a lion", "image": "assets/images/lion.png"},
  {"min": 500, "max": 800, "label": "a horse", "image": "assets/images/horse.png"},
  {"min": 800, "max": 1000, "label": "a school bus", "image": "assets/images/school-bus.png"},
  {"min": 1000, "max": 1500, "label": "a rhino", "image": "assets/images/rhino.png"},
  {"min": 1500, "max": 2000, "label": "a whale", "image": "assets/images/whale.png"},
  {"min": 2000, "max": 5000, "label": "an elephant", "image": "assets/images/elephant.png"},
  {"min": 5000, "max": 8000, "label": "a Porsche 911", "image": "assets/images/porsche-911.png"},
  {"min": 8000, "max": 20000, "label": "a grand piano", "image": "assets/images/grand-piano.png"},
  {"min": 20000, "max": 999999, "label": "a tank", "image": "assets/images/tank.png"},
];

class GoodJob extends StatefulWidget {
  final int? duration;
  final int? volume;
  final int? prs;
  final String? workoutType;
  final double? distance;
  final String? exerciseName;
  final IntensityLevel? intensityLevel;
  final String? workoutTitle;
  final List<Map<String, dynamic>>? exercises;
  final String? runId;
  final double? totalKg;
  
  const GoodJob({
    Key? key,
    this.duration,
    this.volume,
    this.prs,
    this.workoutType,
    this.distance,
    this.exerciseName,
    this.intensityLevel,
    this.workoutTitle,
    this.exercises,
    this.runId,
    this.totalKg,
  }) : super(key: key);

  @override
  State<GoodJob> createState() => _GoodJobState();
}

class _GoodJobState extends State<GoodJob> {
  Map<String, String> getWeightComparison(int kg) {
    for (final comp in weightComparisons) {
      if (kg >= comp["min"] && kg < comp["max"]) {
        return {"label": comp["label"], "image": comp["image"]};
      }
    }
    return {"label": "something heavy!", "image": "assets/images/bear.png"};
  }

  @override
  Widget build(BuildContext context) {
    final comparison = getWeightComparison(widget.volume ?? 0);
    final double screenHeight = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'assets/images/background4.jpg',
              fit: BoxFit.cover,
            ),
          ),
          // Main vertical layout
          Column(
            children: [
              SizedBox(height: screenHeight * 0.07), // Move header higher
              // Good Job! header with close icon
              Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    'Good Job!',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'SF Pro Display',
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Subtitle
              Text(
                'Your goal just got closer.',
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'SF Pro Display',
                  color: Colors.black.withOpacity(0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18), // 18px gap to white card
              // White card
              Center(
                child: Container(
                  width: 338,
                  height: 411,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.07),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 26, right: 26, top: 13, bottom: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Profile row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 0), // Already 26px from left
                              child: Text(
                                'Fitly',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SF Pro Display',
                                  color: Colors.black,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 0), // Already 26px from right
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF2F2F2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Image.asset(
                                        'assets/images/profile.png',
                                        width: 26,
                                        height: 26,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Username',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.normal,
                                      fontFamily: 'SF Pro Display',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24), // Figma: more space below row
                        // Centered image
                        Expanded(
                          child: Center(
                            child: Image.asset(
                              comparison["image"]!,
                              width: 220,
                              height: 180,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        // Weight and comparison text
                        Column(
                          children: [
                            Text(
                              'You lifted a total of ${widget.volume ?? 0} kg',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'SF Pro Display',
                                color: Colors.black,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "That's like lifting ${comparison["label"]}!",
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.normal,
                                fontFamily: 'SF Pro Display',
                              ),
                              textAlign: TextAlign.center,
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
          // Continue button in white box with shadow at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.of(context).size.height * 0.148887,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.zero,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
            ),
          ),
          // Continue button
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
                onPressed: () async {
                  // Save workout log to workout_cards (separate from food)
                  final prefs = await SharedPreferences.getInstance();
                  List<String> workoutCards = prefs.getStringList('workout_cards') ?? [];
                  final now = DateTime.now();
                  final double? rawDistance = widget.distance;
                  

                  
                  final workoutLog = {
                    'type': 'workout',
                    'workoutType': widget.workoutType ?? 'weightlifting', // Default to weightlifting if not specified
                    'name': widget.workoutTitle ?? 'Evening Workout 1', // Use passed title or fallback
                    'calories': 200, // Replace with actual calories
                    'duration': widget.duration ?? 51, // Use actual duration or fallback
                    'volume': widget.volume ?? 0, // Use volume from widget
                    'prs': widget.prs ?? 0, // Use prs from widget
                    'timestamp': now.millisecondsSinceEpoch,
                    'id': 'workout_${now.millisecondsSinceEpoch}', // Generate unique ID
                    'exercises': widget.exercises, // Add exercises data
                  };
                  
                  // Add running-specific fields if this is a running workout
                  if (widget.workoutType == 'running' && rawDistance != null && rawDistance > 0) {
                    workoutLog['distance'] = rawDistance; // Store distance in meters
                    
                    // Calculate pace: minutes per kilometer
                    int durationInMinutes = (widget.duration ?? 0) ~/ 60; // Convert seconds to minutes
                    double distanceInKm = rawDistance / 1000; // Convert meters to kilometers
                    double paceMinutesPerKm = distanceInKm > 0 ? durationInMinutes / distanceInKm : 0.0; // Avoid division by zero
                    workoutLog['pace'] = double.parse(paceMinutesPerKm.toStringAsFixed(1)); // Round to 1 decimal place
                  }
                  
                  // Add custom exercise-specific fields if this is a custom workout
                  if (widget.workoutType == 'custom') {
                    // Use custom exercise name if provided
                    if (widget.exerciseName != null && widget.exerciseName!.isNotEmpty) {
                      workoutLog['name'] = widget.exerciseName!;
                    }
                    
                    // Handle distance vs intensity toggle
                    if (rawDistance != null && rawDistance > 0) {
                      // User entered distance
                      workoutLog['distance'] = rawDistance; // Store distance in meters
                      
                      // Calculate pace: minutes per kilometer
                      int durationInMinutes = (widget.duration ?? 0) ~/ 60; // Convert seconds to minutes
                      double distanceInKm = rawDistance / 1000; // Convert meters to kilometers
                      double paceMinutesPerKm = distanceInKm > 0 ? durationInMinutes / distanceInKm : 0.0; // Avoid division by zero
                      workoutLog['pace'] = double.parse(paceMinutesPerKm.toStringAsFixed(1)); // Round to 1 decimal place
                    } else if (widget.intensityLevel != null) {
                      // User used intensity slider
                      workoutLog['intensityLevel'] = widget.intensityLevel!.index; // Store intensity level index
                    }
                  }
                  
                  // If editing an existing run, update it instead of creating new
                  if (widget.runId != null) {
                    // Find and update the existing run
                    bool foundAndUpdated = false;
                    for (int i = 0; i < workoutCards.length; i++) {
                      try {
                        final cardData = jsonDecode(workoutCards[i]);
                        
                        // Check if this is the run we want to update
                        bool isTargetRun = false;
                        
                        // First, try to match by ID
                        if (cardData['id'] == widget.runId) {
                          isTargetRun = true;
                        }
                        // If no ID match, try to match by timestamp (for older workouts without IDs)
                        else if (cardData['timestamp'] != null && widget.runId!.startsWith('workout_')) {
                          String timestampFromId = widget.runId!.replaceFirst('workout_', '');
                          if (cardData['timestamp'].toString() == timestampFromId) {
                            isTargetRun = true;
                          }
                        }
                        
                        if (isTargetRun) {
                          // Update the existing run with new data
                          workoutLog['id'] = widget.runId; // Preserve the original ID
                          workoutLog['timestamp'] = cardData['timestamp']; // Preserve original timestamp
                          workoutCards[i] = jsonEncode(workoutLog);
                          foundAndUpdated = true;
                          print('Updated existing run with ID: ${widget.runId}');
                          break;
                        }
                      } catch (e) {
                        // Skip invalid JSON entries
                        continue;
                      }
                    }
                    
                    // If we didn't find the run to update, create a new one with the provided ID
                    if (!foundAndUpdated) {
                      workoutLog['id'] = widget.runId;
                      workoutCards.insert(0, jsonEncode(workoutLog));
                      print('Created new run with provided ID: ${widget.runId}');
                    }
                  } else {
                    // Create new run - generate a unique ID using timestamp
                    String newId = 'workout_${now.millisecondsSinceEpoch}';
                    workoutLog['id'] = newId;
                    workoutCards.insert(0, jsonEncode(workoutLog));
                    print('Created new run with generated ID: $newId');
                  }
                  

                  
                  await prefs.setStringList('workout_cards', workoutCards);
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => CodiaPage()),
                    (route) => false,
                  );
                },
                child: const Text(
                  'Continue',
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
    );
  }
} 