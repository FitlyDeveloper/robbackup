import 'package:flutter/foundation.dart';

/// Centralized environment configuration for API base URLs and key scoping.
class AppEnv {
  /// Name of the environment. Override with
  /// --dart-define=APP_ENV=prod|staging|dev
  static const String envName = String.fromEnvironment(
    'APP_ENV',
    defaultValue: kReleaseMode ? 'prod' : 'staging',
  );

  /// API base URL per environment. Update as needed for your Render services.
  static String get baseUrl {
    switch (envName) {
      case 'prod':
        return 'https://snap-food.onrender.com';
      case 'staging':
      case 'dev':
      default:
        // Point staging/dev to a separate Render service if available.
        // Falls back to prod if not configured.
        return 'https://snap-food.onrender.com';
    }
  }

  /// Prefix SharedPreferences keys to avoid collisions across environments.
  static String key(String raw) => '${envName}_$raw';
}


