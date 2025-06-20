class Config {
  static const int defaultDelaySeconds = 5;

  /// Whether the app is running in development mode.
  /// Uses the `dart.vm.product` flag to detect production builds.
  static const bool isDev = !bool.fromEnvironment('dart.vm.product');

  /// Current application version.
  static const String version = '0.1.0';

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
}
