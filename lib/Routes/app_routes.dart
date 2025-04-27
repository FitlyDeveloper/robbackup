import 'package:flutter/material.dart';
import 'package:fitness_app/Screens/main_screen.dart';
import 'package:fitness_app/Features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:fitness_app/Features/onboarding/presentation/screens/registration_screen.dart';
import 'package:fitness_app/Features/onboarding/presentation/screens/calculation_screen.dart';
import 'package:fitness_app/Features/onboarding/presentation/screens/nutrition_plan_screen.dart';
import 'package:fitness_app/Features/onboarding/presentation/screens/goal_selection_screen.dart';
import 'package:fitness_app/Features/onboarding/presentation/screens/physique_screen.dart';
import 'package:fitness_app/Screens/WorkoutHistoryScreen.dart';

class AppRouter {
  static const String mainRoute = '/';
  static const String onboardingRoute = '/onboarding';
  static const String registrationRoute = '/registration';
  static const String calculationRoute = '/calculation';
  static const String nutritionPlanRoute = '/nutrition_plan';
  static const String goalSelectionRoute = '/goal_selection';
  static const String physiqueRoute = '/physique';
  static const String workoutHistoryRoute = '/workout_history';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case mainRoute:
        return MaterialPageRoute(builder: (_) => MainScreen());
      case onboardingRoute:
        return MaterialPageRoute(builder: (_) => OnboardingScreen());
      case registrationRoute:
        return MaterialPageRoute(builder: (_) => RegistrationScreen());
      case calculationRoute:
        return MaterialPageRoute(builder: (_) => CalculationScreen());
      case nutritionPlanRoute:
        return MaterialPageRoute(builder: (_) => NutritionPlanScreen());
      case goalSelectionRoute:
        return MaterialPageRoute(builder: (_) => GoalSelectionScreen());
      case physiqueRoute:
        return MaterialPageRoute(builder: (_) => PhysiqueScreen());
      case workoutHistoryRoute:
        return MaterialPageRoute(builder: (_) => WorkoutHistoryScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}
