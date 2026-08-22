import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'models/streak_reminder.dart';

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

  /// If true the app runs in *simple mode*: the home page is the plain task
  /// list and every optional feature (tools, streak, dice, schedule view, …)
  /// is hidden regardless of [featureEnabled]. Switchable any time from
  /// Settings → Mode & features.
  static bool simpleMode = false;

  /// True once the user picked simple or full mode on the mode picker shown
  /// at first launch. While false the picker is shown before the home page.
  static bool modeChosen = false;

  /// Optional features that can be switched off individually in full mode.
  /// Keys are persisted, so keep them stable; the first eight match
  /// [startToolOptions] tool keys.
  static const List<String> featureKeys = [
    'alarms',
    'countdown',
    'wishlist',
    'projects',
    'chronize',
    'usage_data',
    'productivity_stats',
    'test_results',
    'streak',
    'dice_timer',
    'schedule_view',
    'search',
    'deleted_items',
    'changelog',
    'app_logs',
    'startup_times',
    'sms_report',
  ];

  /// Human-readable labels for [featureKeys], index-aligned.
  static const List<String> featureLabels = [
    'Alarms',
    'Countdown',
    'Wishlist',
    'Projects',
    'Chronize',
    'Usage Data',
    'Productivity Stats',
    'Test Results',
    'Streak',
    'Dice timer',
    'Schedule view',
    'Task search',
    'Deleted items',
    'Changelog',
    'App logs',
    'Startup times',
    'Daily SMS report',
  ];

  /// One-line explanations for [featureKeys], index-aligned.
  static const List<String> featureDescriptions = [
    'Alarm clock with escalating reminders',
    'Countdown timers with milestones',
    'Wishlist of someday items',
    'Project boards for grouping tasks',
    'Timeline planner for the day',
    'Charts about how you use the app',
    'Completion stats and trends',
    'Results of the latest CI test run',
    'Flame that grows for every day you finish a task',
    'Roll a random task and time it',
    'Calendar-style day-by-day view of the tasks',
    'Search field in the home app bar',
    'Restore or purge deleted tasks',
    "What changed in each version of the app",
    'Diagnostic log of what the app did',
    'How fast the app started, over time',
    'Daily SMS with your completion rate',
  ];

  /// Per-feature switches used in full mode. Missing keys count as enabled.
  static final Map<String, bool> featureEnabled = {
    for (final key in featureKeys) key: true,
  };

  /// Features that stay available in simple mode: the drawer entries that are
  /// not really "extra features" but the app's own service pages — the deleted
  /// items (the undo of a plain task list), the changelog, the app logs and the
  /// startup times. Simple mode is about the home surface, so these stay.
  static const Set<String> simpleModeFeatures = {
    'deleted_items',
    'changelog',
    'app_logs',
    'startup_times',
  };

  /// Whether [key] is currently available. Simple mode hides every optional
  /// feature except [simpleModeFeatures], so the per-feature switches only
  /// apply in full mode.
  static bool isFeatureEnabled(String key) {
    if (simpleMode) return simpleModeFeatures.contains(key);
    return featureEnabled[key] ?? true;
  }

  /// Turns a feature on or off (full mode only; no-op for unknown keys).
  static void setFeatureEnabled(String key, bool enabled) {
    if (!featureKeys.contains(key)) return;
    featureEnabled[key] = enabled;
  }

  /// If true, the experimental Chronize tool shows the hour scroll wheel on the
  /// right. Off by default so the timeline gets more room (the hour is set by
  /// scrolling the timeline itself).
  static bool chronizeShowHourWheel = false;

  /// If true, swipe left deletes a task and swipe right shows options.
  /// Otherwise the directions are reversed.
  static bool swipeLeftDelete = true;

  /// If true, the app uses a dark color scheme.
  static bool darkMode = false;

  /// If true, the hamburger menu icon on the home page carries a small red
  /// dot while the newest known test run has failures the user has not looked
  /// at yet. Off by default so the home screen stays calm; the Test Results
  /// entry in the drawer's Tools section always shows the dot until the
  /// results are opened.
  static bool showFailureDotOnMenu = false;

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

  /// The three daily streak challenges, keyed by `StreakKind.id` (kept as
  /// plain strings here so `Config` stays free of Flutter imports):
  ///  * `complete` — finish a task
  ///  * `create` — create a task
  ///  * `plan` — move a task to another day, or finish the whole day's list
  static const List<String> streakKindKeys = ['complete', 'create', 'plan'];

  /// Which streak challenges are active. All three by default; a challenge
  /// that is switched off keeps its history but drops out of the flame cycle,
  /// the streak page and the reminders.
  static final Map<String, bool> streakKindEnabled = {
    for (final key in streakKindKeys) key: true,
  };

  /// Whether streak challenge [key] is currently active.
  static bool isStreakKindEnabled(String key) => streakKindEnabled[key] ?? true;

  /// If true, the reminders in [streakReminders] are scheduled. The master
  /// switch for the whole list.
  static bool streakReminderEnabled = false;

  /// Time of day of the first reminder, in minutes since midnight. Only used
  /// as the default for a newly added reminder (and to migrate the single
  /// reminder of older versions into [streakReminders]).
  static int streakReminderMinutes = 22 * 60;

  /// Every "keep your streak alive" reminder the user configured: any number
  /// of times of day, each silent or with sound and vibration.
  static List<StreakReminder> streakReminders = [];

  /// If true, completing the first task of the day plays a short flame
  /// celebration animation.
  static bool streakCompletionAnimation = true;

  /// Length of the streak the dev/demo seed builds (ending today), so the
  /// flame is already warm in the Chrome demo, where nothing persists between
  /// runs. Only applied when [isDev] and no streak history exists yet.
  static const int devSeedStreakDays = 50;

  /// How the dice timer announces that the countdown hit zero. The keys are
  /// persisted, so keep them stable:
  ///  * `melody` — plays [diceTimerMelody] at [diceTimerVolume], like an alarm
  ///  * `vibrate` — vibration only, no sound
  ///  * `notification` — a notification only (the default); with notifications
  ///    switched off nothing happens beyond the dial reading 0:00
  ///  * `silent` — nothing at all, the dial just reads 0:00
  static const List<String> diceTimerAlertModes = [
    'melody',
    'vibrate',
    'notification',
    'silent',
  ];

  /// Human-readable labels for [diceTimerAlertModes], index-aligned.
  static const List<String> diceTimerAlertLabels = [
    'Melody',
    'Vibration',
    'Notification',
    'Silent',
  ];

  /// One-line explanations for [diceTimerAlertModes], index-aligned.
  static const List<String> diceTimerAlertDescriptions = [
    'Rings the chosen melody until you answer',
    'Buzzes until you answer, no sound',
    'Posts a notification (nothing when notifications are off)',
    'Stays completely quiet — the dial just shows 0:00',
  ];

  /// Which of [diceTimerAlertModes] the dice timer uses at zero.
  static String diceTimerAlertMode = 'notification';

  /// Melody played at zero in `melody` mode, see `kAlarmMelodies`.
  static String diceTimerMelody = 'Classic';

  /// Playback volume for the dice timer melody, 0.0 - 1.0 of the device max.
  static double diceTimerVolume = 0.8;

  /// If true the phone also vibrates in `melody` / `notification` mode
  /// (vibration is the alert itself in `vibrate` mode, and never happens in
  /// `silent` mode).
  static bool diceTimerAlsoVibrate = false;

  /// Minutes the dice timer dial is pre-wound to when a fresh timer opens.
  static int diceTimerDefaultMinutes = 20;

  /// Dial lengths offered as the pre-wound default (one dial turn = 60 min).
  static const List<int> diceTimerLengthOptions = [5, 10, 15, 20, 25, 30, 45, 60];

  /// If true, the tab bar shows icons for unselected tabs.
  /// When false, all tabs display text labels only.
  static bool useIconTabs = false;

  /// If true, the homescreen widget shows today's completion progress line.
  static bool showWidgetProgressLine = true;

  /// If true, the homescreen widget lists today's tasks as tappable rows with
  /// a checkbox, so tasks can be completed without opening the app. Off by
  /// default: the widget then stays the read-only text summary.
  static bool widgetCheckboxes = false;

  /// If true, new tasks are inserted at the top of the current list.
  /// Otherwise they are appended to the bottom.
  static bool addNewTasksToTop = true;

  /// If true, Enter saves the add-task field. When false, the add-task field
  /// accepts multiple lines and Ctrl+Enter saves it.
  static bool enterSavesNewTask = true;

  /// Value of [defaultAddTabIndex] meaning "whichever tab is open".
  static const int addToCurrentTab = -1;

  /// Which home tab a task typed into the add-task row lands in:
  /// [addToCurrentTab] (the default) files it under the tab you are looking
  /// at, an index into [tabs] pins every quick-added task to that bucket — so
  /// an idea typed while Today is open can still go straight to Future. The
  /// schedule view's active day beats this, because there the day is picked
  /// explicitly.
  static int defaultAddTabIndex = addToCurrentTab;

  /// If true, times are displayed and picked in 24-hour notation.
  static bool use24HourFormat = true;

  /// If true the app runs in *synced mode*: whenever it is left (backgrounded
  /// or quit) the task list is written to [syncFolderPath] in the background.
  /// Off (the default) keeps the app fully offline.
  static bool syncEnabled = false;

  /// Folder the background sync writes into; empty until the user picks one
  /// in Settings → Sync & export.
  static String syncFolderPath = '';

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

  /// How often the automatic backup writes a full export to
  /// [autoBackupDirectory]. The keys are persisted, so keep them stable:
  /// `off` (never, the default), `daily`, `weekly`.
  static const List<String> autoBackupFrequencies = ['off', 'daily', 'weekly'];

  /// Human-readable labels for [autoBackupFrequencies], index-aligned.
  static const List<String> autoBackupFrequencyLabels = [
    'Off',
    'Daily',
    'Weekly',
  ];

  /// Which of [autoBackupFrequencies] the automatic backup uses.
  static String autoBackupFrequency = 'off';

  /// Folder the automatic backup writes into; empty until the user picks one.
  static String autoBackupDirectory = '';

  /// If true, tasks are kept in sync both ways with a Todoist account (see
  /// `TodoistSyncService`). Off by default; enabling without a token set is a
  /// no-op until one is entered in Settings → Todoist sync.
  static bool todoistSyncEnabled = false;

  /// Todoist personal API token ("Integrations" tab of Todoist Settings).
  /// Stored in plain text alongside the rest of the app's settings, matching
  /// every other value in this file — the app has no secret-storage layer.
  static String todoistApiToken = '';

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
      'showFailureDotOnMenu': showFailureDotOnMenu,
      'minimalistMode': minimalistMode,
      'enableNotifications': enableNotifications,
      'defaultNotificationDelaySeconds': defaultNotificationDelaySeconds,
      'startTabIndex': startTabIndex,
      'quietHoursEnabled': quietHoursEnabled,
      'quietHoursStartMinutes': quietHoursStartMinutes,
      'quietHoursEndMinutes': quietHoursEndMinutes,
      'useIconTabs': useIconTabs,
      'showWidgetProgressLine': showWidgetProgressLine,
      'widgetCheckboxes': widgetCheckboxes,
      'addNewTasksToTop': addNewTasksToTop,
      'enterSavesNewTask': enterSavesNewTask,
      'defaultAddTabIndex': defaultAddTabIndex,
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
      'streakReminders': [
        for (final reminder in streakReminders) reminder.toJson(),
      ],
      'streakKindEnabled': Map<String, bool>.from(streakKindEnabled),
      'streakCompletionAnimation': streakCompletionAnimation,
      'simpleMode': simpleMode,
      'modeChosen': modeChosen,
      'diceTimerAlertMode': diceTimerAlertMode,
      'diceTimerMelody': diceTimerMelody,
      'diceTimerVolume': diceTimerVolume,
      'diceTimerAlsoVibrate': diceTimerAlsoVibrate,
      'diceTimerDefaultMinutes': diceTimerDefaultMinutes,
      'autoBackupFrequency': autoBackupFrequency,
      'autoBackupDirectory': autoBackupDirectory,
      'syncEnabled': syncEnabled,
      'syncFolderPath': syncFolderPath,
      'todoistSyncEnabled': todoistSyncEnabled,
      'todoistApiToken': todoistApiToken,
      'features': Map<String, bool>.from(featureEnabled),
    };
  }

  static void applyMap(Map<String, dynamic> data) {
    swipeLeftDelete = data['swipeLeftDelete'] ?? swipeLeftDelete;
    darkMode = data['darkMode'] ?? darkMode;
    showFailureDotOnMenu =
        data['showFailureDotOnMenu'] ?? showFailureDotOnMenu;
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
    widgetCheckboxes = data['widgetCheckboxes'] ?? widgetCheckboxes;
    addNewTasksToTop = data['addNewTasksToTop'] ?? addNewTasksToTop;
    enterSavesNewTask = data['enterSavesNewTask'] ?? enterSavesNewTask;
    defaultAddTabIndex = (data['defaultAddTabIndex'] as num?)
            ?.round()
            .clamp(addToCurrentTab, tabs.length - 1) ??
        defaultAddTabIndex;
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
    final savedReminders = data['streakReminders'];
    if (savedReminders is List) {
      streakReminders = [
        for (final entry in savedReminders)
          if (entry is Map)
            StreakReminder.fromJson(Map<String, dynamic>.from(entry)),
      ].take(maxStreakReminders).toList();
    } else if (streakReminderEnabled && streakReminders.isEmpty) {
      // Settings written before the reminder list existed: carry the single
      // reminder over so its time is not silently lost.
      streakReminders = [StreakReminder(minutes: streakReminderMinutes)];
    }
    final savedStreakKinds = data['streakKindEnabled'];
    if (savedStreakKinds is Map) {
      for (final key in streakKindKeys) {
        final value = savedStreakKinds[key];
        if (value is bool) streakKindEnabled[key] = value;
      }
    }
    streakCompletionAnimation =
        data['streakCompletionAnimation'] ?? streakCompletionAnimation;
    simpleMode = data['simpleMode'] ?? simpleMode;
    modeChosen = data['modeChosen'] ?? modeChosen;
    final savedAlertMode = data['diceTimerAlertMode'] as String?;
    if (savedAlertMode != null && diceTimerAlertModes.contains(savedAlertMode)) {
      diceTimerAlertMode = savedAlertMode;
    }
    diceTimerMelody = data['diceTimerMelody'] as String? ?? diceTimerMelody;
    diceTimerVolume =
        (data['diceTimerVolume'] as num?)?.toDouble().clamp(0.0, 1.0) ??
            diceTimerVolume;
    diceTimerAlsoVibrate =
        data['diceTimerAlsoVibrate'] ?? diceTimerAlsoVibrate;
    diceTimerDefaultMinutes =
        (data['diceTimerDefaultMinutes'] as num?)?.round().clamp(1, 60) ??
            diceTimerDefaultMinutes;
    final savedBackupFrequency = data['autoBackupFrequency'] as String?;
    if (savedBackupFrequency != null &&
        autoBackupFrequencies.contains(savedBackupFrequency)) {
      autoBackupFrequency = savedBackupFrequency;
    }
    autoBackupDirectory =
        data['autoBackupDirectory'] as String? ?? autoBackupDirectory;
    syncEnabled = data['syncEnabled'] ?? syncEnabled;
    syncFolderPath = data['syncFolderPath'] as String? ?? syncFolderPath;
    todoistSyncEnabled = data['todoistSyncEnabled'] ?? todoistSyncEnabled;
    todoistApiToken = data['todoistApiToken'] as String? ?? todoistApiToken;
    final savedFeatures = data['features'];
    if (savedFeatures is Map) {
      for (final key in featureKeys) {
        final value = savedFeatures[key];
        if (value is bool) featureEnabled[key] = value;
      }
    }
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
