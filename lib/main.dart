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
import 'ui/home_scaffold_key.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';
import 'ui/app_logs_page.dart';
import 'ui/intro_page.dart';
import 'ui/mode_select_page.dart';
import 'config.dart';
import 'services/alarm_ids.dart';
import 'services/alarm_service.dart';
import 'services/alarm_widget_service.dart';
import 'services/item_history_seeder.dart';
import 'services/pre_update_backup.dart';
import 'services/share_intent_service.dart';
import 'services/startup_time_service.dart';
import 'services/sync_service.dart';
import 'services/task_widget_service.dart';
import 'services/notification_service.dart';
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
    if (uri.host != TaskWidgetService.hostToggle) return;
    // Settings decide what the widget redraws afterwards (progress line,
    // checkbox rows), and this isolate has not loaded them.
    await Config.load();
    await TaskWidgetService.toggleInStorage(id);
    return;
  }
  if (uri.host == AlarmWidgetService.hostToggle) {
    await AlarmService.toggleInStorage(id);
  }
}

Future<void> main() async {
  StartupTimeService.start();
  WidgetsFlutterBinding.ensureInitialized();
  await Config.load();
  await NotificationService.initialize();
  if (!kIsWeb) {
    await SmsReportScheduler.applyFromConfig();
  }
  await AlarmService.instance.load();
  // Snapshot the device/permission state into the alarm log on every launch,
  // so a missed alarm can be diagnosed from the file after the fact. Fire and
  // forget: must not delay first frame.
  unawaited(NotificationService.runAlarmDiagnostics(trigger: 'app start'));
  try {
    await HomeWidget.setAppGroupId(AlarmWidgetService.appGroupId);
    await HomeWidget.registerInteractivityCallback(alarmWidgetBackgroundCallback);
  } catch (_) {}
  final prefs = await SharedPreferences.getInstance();
  // The mode question closes the intro, so someone who has never answered it
  // gets the whole welcome flow rather than the chooser on its own.
  final showIntro = Config.isDev
      ? false
      : !(prefs.getBool('intro_shown') ?? false) || !Config.modeChosen;
  runApp(MyApp(
    showIntro: showIntro,
    showModePicker: !showIntro && !Config.modeChosen,
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
  const MyApp({
    Key? key,
    required this.showIntro,
    this.showModePicker = false,
  }) : super(key: key);

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late bool _showIntro = widget.showIntro;
  late bool _showModePicker = widget.showModePicker;
  bool _alarmRingOpen = false;

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
      // Text shared into the app from other apps becomes a task on Today.
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
    return MaterialApp(
      title: 'BestToDo',
      navigatorKey: appNavigatorKey,
      builder: (context, child) {
        return SafeArea(
          top: false,
          left: false,
          right: false,
          bottom: true,
          child: child ?? const SizedBox.shrink(),
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
      home: _showIntro
          ? IntroPage(onFinished: _finishIntro)
          : _showModePicker
              ? ModeSelectPage(
                  onModeSelected: () =>
                      setState(() => _showModePicker = false),
                )
              : _initialPage(),
    );
  }
}
