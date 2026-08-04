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

  /// Clears the memoized version future so each widget test loads it fresh in
  /// its own async zone (a future completed in a prior test's zone never fires
  /// its continuation when awaited in the next test).
  static void resetVersionForTest() {
    _versionLoadFuture = null;
    _appVersion = 'unknown';
    _buildNumber = '';
  }

  static const List<String> initialTasks = [
    'Get milk',
    'Go to the car shop to get my carburator fixed',
    '@myself remember to do sports & drink water',
  ];
  static const List<String> initialFutureTasks = [
    'Here you put all your hopes and dreams.',
  ];

  static const List<String> tabs = [
    'Today',
    'Tomorrow',
    ' Day After\nTomorrow',
    ' Next\nWeek',
    ' Next\nMonth',
    'Future',
  ];

  /// Page shown when the app starts.
  /// Default is the Today list.
  static const String startPage = 'today';
  // static const String startPage = 'app_logs'; // App logs page
  // static const String startPage = 'settings'; // Settings page

  /// Home tab index shown when the app starts.
  static int startTabIndex = 0;

  /// Pages selectable as the app's default start page: the task list plus
  /// every tool. The keys are stored in settings, so keep them stable.
  static const List<String> startToolOptions = [
    'tasks',
    'alarms',
    'countdown',
    'wishlist',
    'projects',
    'chronize',
    'usage_data',
    'productivity_stats',
    'test_results',
  ];

  /// Human-readable labels for [startToolOptions], index-aligned.
  static const List<String> startToolLabels = [
    'Task list',
    'Alarms',
    'Countdown',
    'Wishlist',
    'Projects',
    'Chronize',
    'Usage Data',
    'Productivity Stats',
    'Test Results',
  ];

  /// Which page opens when the app starts: 'tasks' (the regular task list,
  /// default) or one of the tools in [startToolOptions]. Tools open on top of
  /// the task list, so backing out always lands on the tasks.
  static String startTool = 'tasks';

  /// If true, the home page opens directly in the day-grouped schedule view
  /// instead of the per-tab list view.
  static bool startInScheduleView = false;

  /// If true, the experimental Chronize tool shows the hour scroll wheel on the
  /// right. Off by default so the timeline gets more room (the hour is set by
  /// scrolling the timeline itself).
  static bool chronizeShowHourWheel = false;

  /// If true, swipe left deletes a task and swipe right shows options.
  /// Otherwise the directions are reversed.
  static bool swipeLeftDelete = true;

  /// If true, the app uses a dark color scheme.
  static bool darkMode = false;

  /// If true, the app uses the minimalist look: a monochrome ink-on-paper
  /// theme with no accent colours, flat surfaces and underlines instead of
  /// filled highlights. Combines with [darkMode] for a dark monochrome look.
  static bool minimalistMode = false;

  /// If true, notifications are enabled.
  static bool enableNotifications = false;

  /// Default delay before sending a manual notification from a task bell.
  /// Dev builds use 00:03 for faster testing, production defaults to 05:00.
  static int defaultNotificationDelaySeconds = isDev ? 3 : 300;

  /// If true, manual notifications are delayed until quiet hours end.
  static bool quietHoursEnabled = false;

  /// Start time for quiet hours in minutes since midnight.
  static int quietHoursStartMinutes = 22 * 60;

  /// End time for quiet hours in minutes since midnight.
  static int quietHoursEndMinutes = 7 * 60;

  /// If true, the home page shows the streak flame next to the dice and the
  /// streak feature is active. Off hides the flame and its reminder.
  static bool showStreak = true;

  /// How long the user has to keep the streak alive: 24 means a task must be
  /// completed every calendar day, 48 tolerates one missed day in between.
  static int streakGraceHours = 24;

  /// If true, a daily reminder fires at [streakReminderMinutes] when no task
  /// has been completed yet that day.
  static bool streakReminderEnabled = false;

  /// Time of day for the streak reminder in minutes since midnight.
  static int streakReminderMinutes = 22 * 60;

  /// If true, completing the first task of the day plays a short flame
  /// celebration animation.
  static bool streakCompletionAnimation = true;

  /// If true, the tab bar shows icons for unselected tabs.
  /// When false, all tabs display text labels only.
  static bool useIconTabs = false;

  /// If true, the homescreen widget shows today's completion progress line.
  static bool showWidgetProgressLine = true;

  /// If true, new tasks are inserted at the top of the current list.
  /// Otherwise they are appended to the bottom.
  static bool addNewTasksToTop = true;

  /// If true, times are displayed and picked in 24-hour notation.
  static bool use24HourFormat = true;

  /// Available date display formats; the first entry is the default.
  static const List<String> dateFormats = [
    'dd.MM.yy',
    'dd.MM.yyyy',
    'dd/MM/yyyy',
    'MM/dd/yyyy',
    'yyyy-MM-dd',
    'd MMM yyyy',
  ];

  /// Date display format, one of [dateFormats]. Defaults to dd.mm.yy.
  static String dateFormat = dateFormats.first;

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
        applyMap(data);
      }
    } catch (_) {}
  }

  static Map<String, dynamic> toMap() {
    return {
      'swipeLeftDelete': swipeLeftDelete,
      'darkMode': darkMode,
      'minimalistMode': minimalistMode,
      'enableNotifications': enableNotifications,
      'defaultNotificationDelaySeconds': defaultNotificationDelaySeconds,
      'startTabIndex': startTabIndex,
      'quietHoursEnabled': quietHoursEnabled,
      'quietHoursStartMinutes': quietHoursStartMinutes,
      'quietHoursEndMinutes': quietHoursEndMinutes,
      'useIconTabs': useIconTabs,
      'showWidgetProgressLine': showWidgetProgressLine,
      'addNewTasksToTop': addNewTasksToTop,
      'use24HourFormat': use24HourFormat,
      'dateFormat': dateFormat,
      'defaultDelaySeconds': defaultDelaySeconds,
      'startInScheduleView': startInScheduleView,
      'chronizeShowHourWheel': chronizeShowHourWheel,
      'startTool': startTool,
      'showStreak': showStreak,
      'streakGraceHours': streakGraceHours,
      'streakReminderEnabled': streakReminderEnabled,
      'streakReminderMinutes': streakReminderMinutes,
      'streakCompletionAnimation': streakCompletionAnimation,
    };
  }

  static void applyMap(Map<String, dynamic> data) {
    swipeLeftDelete = data['swipeLeftDelete'] ?? swipeLeftDelete;
    darkMode = data['darkMode'] ?? darkMode;
    minimalistMode = data['minimalistMode'] ?? minimalistMode;
    enableNotifications = data['enableNotifications'] ?? enableNotifications;
    defaultNotificationDelaySeconds =
        (data['defaultNotificationDelaySeconds'] as num?)?.round() ??
            defaultNotificationDelaySeconds;
    startTabIndex =
        (data['startTabIndex'] as num?)?.round().clamp(0, tabs.length - 1) ??
            startTabIndex;
    quietHoursEnabled = data['quietHoursEnabled'] ?? quietHoursEnabled;
    quietHoursStartMinutes =
        (data['quietHoursStartMinutes'] as num?)?.round().clamp(0, 1439) ??
            quietHoursStartMinutes;
    quietHoursEndMinutes =
        (data['quietHoursEndMinutes'] as num?)?.round().clamp(0, 1439) ??
            quietHoursEndMinutes;
    useIconTabs = data['useIconTabs'] ?? useIconTabs;
    showWidgetProgressLine =
        data['showWidgetProgressLine'] ?? showWidgetProgressLine;
    addNewTasksToTop = data['addNewTasksToTop'] ?? addNewTasksToTop;
    use24HourFormat = data['use24HourFormat'] ?? use24HourFormat;
    final savedDateFormat = data['dateFormat'] as String?;
    if (savedDateFormat != null && dateFormats.contains(savedDateFormat)) {
      dateFormat = savedDateFormat;
    }
    defaultDelaySeconds =
        (data['defaultDelaySeconds'] as num?)?.toDouble() ?? defaultDelaySeconds;
    startInScheduleView = data['startInScheduleView'] ?? startInScheduleView;
    chronizeShowHourWheel =
        data['chronizeShowHourWheel'] ?? chronizeShowHourWheel;
    final savedStartTool = data['startTool'] as String?;
    if (savedStartTool != null && startToolOptions.contains(savedStartTool)) {
      startTool = savedStartTool;
    }
    showStreak = data['showStreak'] ?? showStreak;
    final savedGrace = (data['streakGraceHours'] as num?)?.round();
    if (savedGrace == 24 || savedGrace == 48) {
      streakGraceHours = savedGrace!;
    }
    streakReminderEnabled =
        data['streakReminderEnabled'] ?? streakReminderEnabled;
    streakReminderMinutes =
        (data['streakReminderMinutes'] as num?)?.round().clamp(0, 1439) ??
            streakReminderMinutes;
    streakCompletionAnimation =
        data['streakCompletionAnimation'] ?? streakCompletionAnimation;
  }

  /// Persists the current settings to disk.
  static Future<void> save() async {
    try {
      final file = await _getSettingsFile();
      final data = toMap();
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {}
  }
}
