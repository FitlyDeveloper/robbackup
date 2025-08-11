import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkoutSessionProvider extends ChangeNotifier {
  bool _active = false;
  VoidCallback? _onResume;
  VoidCallback? _onDiscard;

  bool get isActive => _active;
  VoidCallback? get onResume => _onResume;
  VoidCallback? get onDiscard => _onDiscard;

  void startSession({VoidCallback? onResume, VoidCallback? onDiscard}) {
    _active = true;
    _onResume = onResume;
    _onDiscard = onDiscard;
    notifyListeners();
  }

  void endSession() async {
    _active = false;
    _onResume = null;
    _onDiscard = null;
    // Clear persistent session state if used
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('activeWorkout');
    notifyListeners();
  }
} 