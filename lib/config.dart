class Config {
  static const int defaultDelaySeconds = 5;

  /// Whether the app is running in development mode.
  /// Uses the `dart.vm.product` flag to detect production builds.
  static const bool isDev = !bool.fromEnvironment('dart.vm.product');

  /// Current application version.
  static const String version = '0.1.9';

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

  /// If true, swipe left deletes a task and swipe right shows options.
  /// Otherwise the directions are reversed.
  static bool swipeLeftDelete = true;

  /// If true, the app uses a dark color scheme.
  static bool darkMode = false;
}
