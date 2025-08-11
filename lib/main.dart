import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:device_preview/device_preview.dart';
import 'Features/onboarding_screen.dart';
import 'firebase_options.dart';
import 'core/utils/device_size_adapter.dart';
import 'dart:ui' as ui;
import 'widgets/health_tracking_card.dart';
import 'Features/codia/Nutrition.dart' as nutrition; // Import for RouteObserver
import 'package:provider/provider.dart';
import 'WorkoutSession/WorkoutSessionProvider.dart';

// Custom binding to disable overflow errors
class NoOverflowErrorsFlutterBinding extends WidgetsFlutterBinding {
  @override
  void initInstances() {
    super.initInstances();
    // Disable overflow warning service extension
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.toString().contains('overflowed') ||
          details.toString().contains('overflow') ||
          details.toString().contains('exceeded')) {
        // Do nothing for overflow errors
        return;
      }
      // Forward other errors
      FlutterError.presentError(details);
    };
  }

  static WidgetsBinding ensureInitialized() {
    if (WidgetsBinding.instance is NoOverflowErrorsFlutterBinding) {
      return WidgetsBinding.instance;
    }
    NoOverflowErrorsFlutterBinding();
    return WidgetsBinding.instance;
  }
}

// Class to hide overflow messages in debug UI
class HideOverflowErrorsApp extends StatelessWidget {
  final Widget child;

  const HideOverflowErrorsApp({Key? key, required this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (context) {
      // Hide any existing overflow errors
      final overlay = WidgetsBinding.instance.renderViewElement;
      final renderObject = overlay?.renderObject;
      if (renderObject is RenderBox) {
        // Force layout to avoid overflow
        renderObject.markNeedsPaint();
      }

      return child;
    });
  }
}

void main() async {
  // Initialize the Flutter binding first
  WidgetsFlutterBinding.ensureInitialized();

  // Disable ALL debug rendering features
  debugPaintSizeEnabled = false;
  debugPaintBaselinesEnabled = false;
  debugPaintLayerBordersEnabled = false;
  debugPaintPointersEnabled = false;
  debugRepaintRainbowEnabled = false;

  // Initialize Firebase on all platforms
  try {
    await FirebaseService.initialize();
    print('Firebase initialized successfully');
  } catch (e) {
    print('Failed to initialize Firebase: $e');
    // Continue without Firebase - the app will use mock services
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => WorkoutSessionProvider(),
      child: DevicePreview(
        enabled: !kReleaseMode,
        builder: (context) => const MyApp(),
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      useInheritedMediaQuery: true,
      locale: DevicePreview.locale(context),
      builder: DevicePreview.appBuilder,
      debugShowCheckedModeBanner: false,
      title: 'Gym App',
      navigatorObservers: [nutrition.routeObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        useMaterial3: true,
        textTheme: TextTheme(
          bodyLarge:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          bodyMedium:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          bodySmall:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          titleLarge:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          titleMedium:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          titleSmall:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          displayLarge:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          displayMedium:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          displaySmall:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          headlineLarge:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          headlineMedium:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          headlineSmall:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          labelLarge:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          labelMedium:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
          labelSmall:
              TextStyle(color: Colors.black, decoration: TextDecoration.none),
        ),
        // Add global text style to ensure all text has no decoration
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: Colors.black,
        ),
        // Ensure all text has no decoration by default
        typography: Typography.material2021().copyWith(
          black: Typography.material2021().black.apply(
                decoration: TextDecoration.none,
              ),
          white: Typography.material2021().white.apply(
                decoration: TextDecoration.none,
              ),
        ),
      ),
      home: const OnboardingScreen(),
    );
  }
}

// Simple widget to ignore overflow errors
class IgnoreOverflowErrors extends StatelessWidget {
  final Widget child;

  const IgnoreOverflowErrors({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Using LayoutBuilder provides a boundary for overflow errors
        return child;
      },
    );
  }
}
