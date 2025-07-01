import 'package:flutter/material.dart';

class Config {
  static const int defaultDelaySeconds = 5;

  /// Whether the app is running in development mode.
  /// Uses the `dart.vm.product` flag to detect production builds.
  static const bool isDev = !bool.fromEnvironment('dart.vm.product');

  /// Current application version.
  static const String version = '0.1.3';

  static const List<String> initialTasks = [
    'Get milk',
    'Go to the car shop to get my carburator fixed',
    '@myself remember to do sports & drink water',
  ];

  static const List<String> tabs = [
    'Today',
    'Tomorrow',
    'Day After Tomorrow',
    'Next Week',
  ];

  /// Supported locales for the app.
  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('es'),
    Locale('fr'),
  ];

  /// Human readable names for the supported locales.
  static const Map<String, String> localeNames = {
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
  };

  /// If true, swipe left deletes a task and swipe right shows options.
  /// Otherwise the directions are reversed.
  static bool swipeLeftDelete = true;
}
