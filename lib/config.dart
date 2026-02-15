import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

class Config {
  static double defaultDelaySeconds = 5.0;

  static Duration get delayDuration =>
      Duration(milliseconds: (defaultDelaySeconds * 1000).round());

  /// Whether the app is running in development mode.
  /// Uses the `dart.vm.product` flag to detect production builds.
  static const bool isDev = !bool.fromEnvironment('dart.vm.product');

  static String _appVersion = 'unknown';
  static String _buildNumber = '';
  static Future<void>? _versionLoadFuture;

  /// Current application version, read from pubspec at runtime.
  static String get version => _appVersion;

  /// Current application version including build number when available.
  static String get versionWithBuild =>
      _buildNumber.isEmpty ? _appVersion : '$_appVersion+$_buildNumber';

  /// Ensures app version metadata has been loaded from the platform.
  static Future<void> ensureVersionLoaded() {
    _versionLoadFuture ??= _loadVersion();
    return _versionLoadFuture!;
  }

  static Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
      _buildNumber = info.buildNumber;
    } catch (_) {}
  }

  static const List<String> initialTasks = [
    'Get milk',
    'Go to the car shop to get my carburator fixed',
    '@myself remember to do sports & drink water',
  ];

  static const List<String> tabs = [
    'Today',
    'Tomorrow',
    ' Day After\nTomorrow',
    ' Next\nWeek',
    ' Next\nMonth',
  ];

  /// Page shown when the app starts.
  /// Default is the Today list.
  static const String startPage = 'today';
  // static const String startPage = 'app_logs'; // App logs page
  // static const String startPage = 'settings'; // Settings page

  /// If true, swipe left deletes a task and swipe right shows options.
  /// Otherwise the directions are reversed.
  static bool swipeLeftDelete = true;

  /// If true, the app uses a dark color scheme.
  static bool darkMode = false;

  /// If true, notifications are enabled.
  static bool enableNotifications = false;

  /// If true, the tab bar shows icons for unselected tabs.
  /// When false, all tabs display text labels only.
  static bool useIconTabs = false;

  static const _settingsFileName = 'settings.json';

  static Future<File> _getSettingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_settingsFileName');
  }

  /// Loads persisted settings from disk.
  static Future<void> load() async {
    try {
      final file = await _getSettingsFile();
      if (await file.exists()) {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        swipeLeftDelete = data['swipeLeftDelete'] ?? swipeLeftDelete;
        darkMode = data['darkMode'] ?? darkMode;
        enableNotifications =
            data['enableNotifications'] ?? enableNotifications;
        useIconTabs = data['useIconTabs'] ?? useIconTabs;
        defaultDelaySeconds =
            (data['defaultDelaySeconds'] as num?)?.toDouble() ??
                defaultDelaySeconds;
      }
    } catch (_) {}
  }

  /// Persists the current settings to disk.
  static Future<void> save() async {
    try {
      final file = await _getSettingsFile();
      final data = {
        'swipeLeftDelete': swipeLeftDelete,
        'darkMode': darkMode,
        'enableNotifications': enableNotifications,
        'useIconTabs': useIconTabs,
        'defaultDelaySeconds': defaultDelaySeconds,
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {}
  }
}
