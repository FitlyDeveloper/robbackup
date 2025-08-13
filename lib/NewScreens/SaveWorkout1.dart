import 'package:flutter/material.dart';

import 'SaveWorkout.dart';
import '../models/intensity_level.dart';

class SaveWorkout1 extends StatefulWidget {
  final int duration;
  final int volume;
  final int prs;
  final String? workoutType;
  final double? distance;
  final String? exerciseName;
  final IntensityLevel? intensityLevel;
  final String? initialTitle;
  final String? runId;

  const SaveWorkout1({
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
  State<SaveWorkout1> createState() => _SaveWorkout1State();
}

class _SaveWorkout1State extends State<SaveWorkout1> {
  @override
  Widget build(BuildContext context) {
    return SaveWorkout(
      duration: widget.duration,
      volume: widget.volume,
      prs: widget.prs,
      workoutType: widget.workoutType,
      distance: widget.distance,
      exerciseName: widget.exerciseName,
      intensityLevel: widget.intensityLevel,
      initialTitle: widget.initialTitle,
      runId: widget.runId,
    );
  }
}


