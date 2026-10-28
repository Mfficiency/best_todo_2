import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ui/alarm_ring_page.dart';
import 'ui/alarms_page.dart';
import 'ui/dice_timer_page.dart';
import 'ui/food_diary_page.dart';
import 'ui/home_scaffold_key.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';
import 'ui/app_logs_page.dart';
import 'ui/intro_page.dart';
import 'ui/mode_select_page.dart';
import 'ui/quick_add_share_page.dart';
import 'ui/startup_choice_page.dart';
import 'ui/web_approvals_site.dart';
import 'ui/web_data_choice_page.dart';
import 'config.dart';
import 'models/shared_payload.dart';
import 'services/alarm_ids.dart';
import 'services/alarm_service.dart';
import 'services/alarm_widget_service.dart';
import 'services/food_diary_widget_service.dart';
import 'services/app_updates.dart';
import 'services/item_history_seeder.dart';
import 'services/pre_update_backup.dart';
import 'services/share_intent_service.dart';
import 'services/startup_time_service.dart';
import 'services/sync_service.dart';
import 'services/todoist_sync_service.dart';
import 'services/task_widget_service.dart';
import 'services/notification_service.dart';
import 'services/f1_reminder_service.dart';
import 'services/sms_report_scheduler.dart';

const Color _seedColor = Color(0xFF005FDD);

/// Monochrome ink-on-paper theme used when minimalist mode is on: pure greys
/// only (no hue anywhere), flat surfaces, no ink splashes, and selection shown
/// with an underline instead of a filled highlight.
ThemeData buildMinimalistTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final paper = dark ? const Color(0xFF141414) : const Color(0xFFFAFAFA);
  final ink = dark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);
  final faintInk = dark ? const Color(0xFFA3A3A3) : const Color(0xFF616161);
  final mist = dark ? const Color(0xFF262626) : const Color(0xFFEEEEEE);
  final line = dark ? const Color(0xFF3A3A3A) : const Color(0xFFDBDBDB);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: ink,
    onPrimary: paper,
    primaryContainer: mist,
    onPrimaryContainer: ink,
    secondary: faintInk,
    onSecondary: paper,
    secondaryContainer: mist,
    onSecondaryContainer: ink,
    tertiary: faintInk,
    onTertiary: paper,
    error: ink,
    onError: paper,
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: faintInk,
    surfaceContainerHighest: mist,
    outline: faintInk,
    outlineVariant: line,
    inverseSurface: ink,
    onInverseSurface: paper,
    inversePrimary: paper,
    surfaceTint: Colors.transparent,
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: paper,
    splashFactory: NoSplash.splashFactory,
    dividerTheme: DividerThemeData(color: line),
    // Selected chips (e.g. the settings section chips) keep their quiet
    // outline and underline their label instead of filling with colour.
    chipTheme: ChipThemeData(
      selectedColor: Colors.transparent,
      showCheckmark: false,
      side: BorderSide(color: line),
      labelStyle: WidgetStateTextStyle.resolveWith(
        (states) => TextStyle(
          color: ink,
          decoration: states.contains(WidgetState.selected)
              ? TextDecoration.underline
              : TextDecoration.none,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.normal,
        ),
      ),
    ),
  );
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Background entry point invoked by a home-screen widget when a toggle is
/// tapped — an alarm's ON/OFF (`besttodoalarm://`) or a task's checkbox
/// (`besttodotask://`). Runs in its own isolate, so it works directly against
/// storage; the app itself may not be running at all.
@pragma('vm:entry-point')
Future<void> alarmWidgetBackgroundCallback(Uri? uri) async {
  // This isolate starts without the app's plugin registrations; without these
  // two calls path_provider / flutter_local_notifications method channels are
  // dead here and the toggle silently does nothing.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  if (uri == null) return;
  final id = uri.queryParameters['id'];
  if (id == null || id.isEmpty) return;
  if (uri.scheme == TaskWidgetService.scheme) {
    if (uri.host != TaskWidgetService.hostToggle &&
        uri.host != TaskWidgetService.hostComplete) {
      return;
    }
    // Settings decide what the widget redraws afterwards (progress line,
    // checkbox rows), and this isolate has not loaded them.
    await Config.load();
    if (uri.host == TaskWidgetService.hostComplete) {
      // The Wear OS companion's "done" while the app isn't running
      // (WearCommandService.kt): complete only, never un-complete.
      await TaskWidgetService.completeInStorage(id);
    } else {
      await TaskWidgetService.toggleInStorage(id);
    }
    return;
  }
  if (uri.host == AlarmWidgetService.hostToggle) {
    await AlarmService.toggleInStorage(id);
  }
}

/// Runs one launch-time initialisation step, keeping a failure inside it from
/// taking the whole launch down. Every step here is storage- or plugin-backed
/// and can fail on a platform that lacks the plugin (web has no path_provider,
/// so anything writing a JSON file throws `MissingPluginException`); an
/// uncaught throw means `runApp` is never reached and the app is a blank
/// screen instead of a degraded but usable one.
Future<void> _initStep(String label, Future<void> Function() step) async {
  try {
    await step();
  } catch (e) {
    debugPrint('Startup step "$label" failed: $e');
  }
}

Future<void> main() async {
  StartupTimeService.start();
  WidgetsFlutterBinding.ensureInitialized();
  // The approvals website (SPEC §4.2k) is its own small app: none of the
  // phone's startup (backups, alarms, widgets, updates) runs there.
  if (kIsWeb && Config.webApprovalsSite) {
    await _initStep('config', Config.load);
    runApp(const WebApprovalsSiteApp());
    return;
  }
  // The full backup (Download/BestToDo/Backups, before every update) first:
  // it tells a new install (nothing in SharedPreferences yet) to offer a
  // restore after the first frame.
  await _initStep('backup', AppUpdates.createBackup);
  await _initStep('config', Config.load);
  await _initStep('notifications', NotificationService.initialize);
  if (!kIsWeb) {
    await _initStep('sms report scheduler', SmsReportScheduler.applyFromConfig);
    await _initStep('f1 reminder', F1ReminderService.applyFromConfig);
  }
  await _initStep('alarms', AlarmService.instance.load);
  // Snapshot the device/permission state into the alarm log on every launch,
  // so a missed alarm can be diagnosed from the file after the fact. Fire and
  // forget: must not delay first frame.
  unawaited(NotificationService.runAlarmDiagnostics(trigger: 'app start'));
  try {
    await HomeWidget.setAppGroupId(AlarmWidgetService.appGroupId);
    await HomeWidget.registerInteractivityCallback(alarmWidgetBackgroundCallback);
  } catch (_) {}
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('Startup step "preferences" failed: $e');
  }
  // The mode question closes the intro, so someone who has never answered it
  // gets the whole welcome flow rather than the chooser on its own.
  final introAlreadyShown = prefs?.getBool('intro_shown') ?? false;
  final showIntro = Config.isDev ? false : !introAlreadyShown || !Config.modeChosen;
  // The fresh-start/import-from-Todoist question is a one-time step of its
  // own, decoupled from intro_shown so it survives being interrupted (app
  // closed mid-onboarding). An install that had already finished onboarding
  // before this question existed backfills to "already answered" here so
  // existing users are never asked it after an upgrade.
  var startupChoiceMade = prefs?.getBool('startup_choice_made');
  if (startupChoiceMade == null) {
    startupChoiceMade = introAlreadyShown;
    await prefs?.setBool('startup_choice_made', startupChoiceMade);
  }
  final showStartupChoice = Config.isDev ? false : !startupChoiceMade;
  // In-app updates (the shared mfficiency_updates package, see
  // AppUpdates): reads the version and the stored update state, no network.
  // The checks start after the first frame (_startUpdates).
  await _initStep('updates', () => AppUpdates.create(UpdatesApp.todo));
  runApp(MyApp(
    showIntro: showIntro,
    showModePicker: !showIntro && !Config.modeChosen,
    showStartupChoice: showStartupChoice,
    // `flutter run -d chrome`: ask demo seeds vs real Todoist data first.
    showWebDataChoice: kIsWeb && Config.isDev,
  ));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    StartupTimeService.record();
    // One-time backfill of the item-history journal from pre-journal data.
    // Deliberately a few seconds after the first frame so it never competes
    // with startup or the home page's initial load; once seeded it is a
    // single file-exists check.
    unawaited(Future<void>.delayed(const Duration(seconds: 3))
        .then((_) => ItemHistorySeeder.runOnce()));
    // Record which app version wrote the current data files, so future
    // migrations can take version-specific precautions. Same deferral.
    unawaited(Future<void>.delayed(const Duration(seconds: 3))
        .then((_) => PreUpdateBackup.recordCurrentVersion()));
  });
}

class MyApp extends StatefulWidget {
  final bool showIntro;

  /// Whether the simple/full mode picker is shown after the intro. Set from
  /// [Config.modeChosen] on launch; tests and screenshot runs pass false.
  final bool showModePicker;

  /// Whether the fresh-start/import-from-Todoist chooser is shown after the
  /// intro and mode picker, on a brand-new install only. Tests and
  /// screenshot runs pass false.
  final bool showStartupChoice;

  /// Whether the demo-vs-real-data chooser ([WebDataChoicePage]) opens
  /// first. Only for dev runs in a browser (`flutter run -d chrome`).
  final bool showWebDataChoice;
  const MyApp({
    Key? key,
    required this.showIntro,
    this.showModePicker = false,
    this.showStartupChoice = false,
    this.showWebDataChoice = false,
  }) : super(key: key);

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late bool _showIntro = widget.showIntro;
  late bool _showModePicker = widget.showModePicker;
  late bool _showStartupChoice = widget.showStartupChoice;
  late bool _showWebDataChoice = widget.showWebDataChoice;
  bool _alarmRingOpen = false;
  final List<SharedPayload> _pendingShares = [];
  bool _shareScreenOpen = false;

  /// Whether the automatic update checks were started ([AppUpdates.start]).
  bool _updatesStarted = false;

  /// The automatic update (checks, silent download, then Android's own
  /// install confirm) starts after the first frame; Android's dialog is
  /// held back ([AppUpdates.promptAllowed], the package's `promptAllowed`)
  /// while the intro or a first-start picker is open, and opens once they
  /// are closed.
  void _startUpdates() {
    final busy = _showWebDataChoice ||
        _showIntro ||
        _showModePicker ||
        _showStartupChoice;
    final start = !_updatesStarted;
    _updatesStarted = true;
    if (!start && AppUpdates.promptAllowed.value == !busy) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdates.promptAllowed.value = !busy;
      if (!start) return;
      final context = appNavigatorKey.currentContext;
      if (context == null) return;
      AppUpdates.start(context);
      // A new install asks once whether to restore a full backup.
      unawaited(AppUpdates.backup?.offerRestore(context));
    });
  }

  @override
  void initState() {
    super.initState();
    // Synced mode writes the task list to the chosen folder whenever the app
    // is left (backgrounded/quit). The observer only forwards lifecycle
    // states; SyncService does nothing at startup, keeping launch untouched.
    WidgetsBinding.instance.addObserver(this);
    // Full-screen alarm UI: when a ringing alarm opens the app (tap on the
    // notification, or its full-screen intent firing over the lock screen),
    // present the ring page. Covers both a warm app (callback) and a cold
    // start (launch details).
    NotificationService.setOnAlarmRing(_showAlarmRing);
    NotificationService.getAlarmLaunchPayload().then((payload) {
      if (payload != null) _showAlarmRing(payload);
    }).catchError((_) {});
    // A dice timer that runs out while the app is open but the timer page is
    // not shows the very same alarm screen, without going through the OS.
    DiceTimerController.presentFullScreenRing = _showAlarmRing;
    // Handle taps coming from the alarms home-screen widget. The widget is
    // Android-only; elsewhere the plugin's event channel has no implementation
    // and its activation failure is reported through FlutterError — bypassing
    // the stream's onError — which fails desktop/CI test runs.
    if (!kIsWeb && Platform.isAndroid) {
      try {
        HomeWidget.initiallyLaunchedFromHomeWidget()
            .then(_handleWidgetClick)
            .catchError((_) {});
        HomeWidget.widgetClicked.listen(
          _handleWidgetClick,
          onError: (_) {},
        );
      } catch (_) {}
      // Content shared into the app from other apps (Chrome, YouTube, Maps,
      // Gmail, Photos, ...) opens the small quick-add screen, prefilled from
      // whatever was shared. See _queueSharedPayload.
      ShareIntentService.instance.setOnSharedPayload(_queueSharedPayload);
      unawaited(ShareIntentService.instance.init().catchError((_) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.setOnAlarmRing(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    SyncService.instance.onLifecycleChanged(state);
    TodoistSyncService.instance.onLifecycleChanged(state);
    // Updates follow the lifecycle themselves (the package's controller).
  }

  /// Queues a shared payload and, if the quick-add screen isn't already open
  /// for an earlier one, presents it. Payloads are shown one at a time so a
  /// cold start with several queued shares doesn't stack screens.
  void _queueSharedPayload(SharedPayload payload) {
    _pendingShares.add(payload);
    if (!_shareScreenOpen) _presentNextSharedPayload();
  }

  void _presentNextSharedPayload() {
    if (_pendingShares.isEmpty) return;
    final payload = _pendingShares.removeAt(0);
    // Wait for the first frame so the navigator exists on a cold start, same
    // as the alarm-ring screen below.
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = appNavigatorKey.currentState;
      if (navigator == null) return;
      _shareScreenOpen = true;
      navigator
          .push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => QuickAddSharePage(payload: payload),
          ))
          .whenComplete(() {
        _shareScreenOpen = false;
        _presentNextSharedPayload();
      });
    });
  }

  void _showAlarmRing(Map<String, dynamic> payload) {
    // Wait for the first frame so the navigator exists on a cold start. The
    // explicit scheduleFrame makes sure the callback also runs when no frame
    // happens to be pending (warm launch from the background).
    WidgetsBinding.instance.scheduleFrame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = appNavigatorKey.currentState;
      if (navigator == null || _alarmRingOpen) return;
      _alarmRingOpen = true;
      navigator
          .push(MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => AlarmRingPage(payload: payload),
          ))
          .whenComplete(() {
        _alarmRingOpen = false;
        if (payload['uid'] == kDiceTimerUid) _afterDiceRingStopped();
      });
    });
  }

  /// A stopped dice-timer alarm hands the task back: silence whatever the ring
  /// was playing and open the timer page in its finished state, so Done /
  /// Postpone / +min are one tap away. After a cold start (app was killed) no
  /// timer is left in memory, and the hook simply does nothing.
  void _afterDiceRingStopped() {
    DiceTimerController.instance.stopAlert();
    openRunningDiceTimer?.call();
  }

  Future<void> _handleWidgetClick(Uri? uri) async {
    if (uri == null) return;
    if (uri.scheme == FoodDiaryWidgetService.scheme) {
      switch (uri.host) {
        case FoodDiaryWidgetService.hostAdd:
          _openFoodDiary(autoAdd: true);
          break;
        case FoodDiaryWidgetService.hostOpen:
          _openFoodDiary();
          break;
      }
      return;
    }
    final id = uri.queryParameters['id'];
    switch (uri.host) {
      case AlarmWidgetService.hostToggle:
        if (id != null && id.isNotEmpty) {
          await AlarmService.toggleInStorage(id);
          await AlarmService.instance.reload();
        }
        break;
      case AlarmWidgetService.hostEdit:
        _openAlarms(editUid: id);
        break;
      case AlarmWidgetService.hostOpen:
        _openAlarms();
        break;
    }
  }

  void _openAlarms({String? editUid}) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(builder: (_) => AlarmsPage(editUid: editUid)),
    );
  }

  void _openFoodDiary({bool autoAdd = false}) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(builder: (_) => FoodDiaryPage(autoAddEntry: autoAdd)),
    );
  }

  void updateTheme() => setState(() {});

  /// Called once the intro's closing page has stored a mode, so the picker
  /// never appears a second time straight after it.
  Future<void> _finishIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', true);
    if (!mounted) return;
    setState(() {
      _showIntro = false;
      _showModePicker = false;
    });
  }

  /// Replays the whole welcome flow — the slides *and* the mode question
  /// (About → "Replay introduction").
  Future<void> restartIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', false);
    Config.modeChosen = false;
    await Config.save();
    if (!mounted) return;
    setState(() {
      _showIntro = true;
      _showModePicker = false;
    });
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Called once the fresh-start/import-from-Todoist chooser has been
  /// answered (either choice), so it never appears again on this install.
  Future<void> _finishStartupChoice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('startup_choice_made', true);
    if (!mounted) return;
    setState(() => _showStartupChoice = false);
  }

  /// Shows the simple/full mode picker again (Settings → Mode & features).
  Future<void> restartModePicker() async {
    Config.modeChosen = false;
    await Config.save();
    if (!mounted) return;
    setState(() => _showModePicker = true);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget _initialPage() {
    switch (Config.startPage) {
      case 'settings':
        return const SettingsPage();
      case 'today':
        return HomePage(initialTabIndex: Config.startTabIndex);
      case 'app_logs':
      default:
        return const AppLogsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    _startUpdates();
    final updates = AppUpdates.controller;
    return MaterialApp(
      title: 'BestToDo',
      navigatorKey: appNavigatorKey,
      builder: (context, child) {
        final page = child ?? const SizedBox.shrink();
        return SafeArea(
          top: false,
          left: false,
          right: false,
          bottom: true,
          // The slim update banner ("Update ready · <version>" after
          // Android's confirm was cancelled, or a failed download's Try
          // again) sits below every screen; empty otherwise.
          child: updates == null
              ? page
              : Column(
                  children: [
                    Expanded(child: page),
                    UpdateBanner(controller: updates),
                  ],
                ),
        );
      },
      theme: Config.minimalistMode
          ? buildMinimalistTheme(Brightness.light)
          : ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: _seedColor)
                  .copyWith(primary: _seedColor),
              useMaterial3: true,
            ),
      darkTheme: Config.minimalistMode
          ? buildMinimalistTheme(Brightness.dark)
          : ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: _seedColor,
                brightness: Brightness.dark,
              ).copyWith(primary: _seedColor),
              useMaterial3: true,
            ),
      themeMode: Config.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: _showWebDataChoice
          ? WebDataChoicePage(
              onFinished: () => setState(() => _showWebDataChoice = false),
            )
          : _showIntro
              ? IntroPage(onFinished: _finishIntro)
              : _showModePicker
                  ? ModeSelectPage(
                      onModeSelected: () =>
                          setState(() => _showModePicker = false),
                    )
                  : _showStartupChoice
                      ? StartupChoicePage(onFinished: _finishStartupChoice)
                      : _initialPage(),
    );
  }
}
