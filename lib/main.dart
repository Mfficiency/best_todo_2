import 'dart:async' show unawaited;
import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ui/alarm_ring_page.dart';
import 'ui/alarms_page.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';
import 'ui/app_logs_page.dart';
import 'ui/intro_page.dart';
import 'config.dart';
import 'services/alarm_service.dart';
import 'services/alarm_widget_service.dart';
import 'services/startup_time_service.dart';
import 'services/notification_service.dart';
import 'services/sms_report_scheduler.dart';

const Color _seedColor = Color(0xFF005FDD);

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Background entry point invoked by the home-screen widget when a toggle is
/// tapped. Runs in its own isolate, so it works directly against storage.
@pragma('vm:entry-point')
Future<void> alarmWidgetBackgroundCallback(Uri? uri) async {
  // This isolate starts without the app's plugin registrations; without these
  // two calls path_provider / flutter_local_notifications method channels are
  // dead here and the toggle silently does nothing.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  if (uri == null) return;
  if (uri.host == AlarmWidgetService.hostToggle) {
    final id = uri.queryParameters['id'];
    if (id != null && id.isNotEmpty) {
      await AlarmService.toggleInStorage(id);
    }
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
  final showIntro =
      Config.isDev ? false : !(prefs.getBool('intro_shown') ?? false);
  runApp(MyApp(showIntro: showIntro));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    StartupTimeService.record();
  });
}

class MyApp extends StatefulWidget {
  final bool showIntro;
  const MyApp({Key? key, required this.showIntro}) : super(key: key);

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late bool _showIntro = widget.showIntro;
  bool _alarmRingOpen = false;

  @override
  void initState() {
    super.initState();
    // Full-screen alarm UI: when a ringing alarm opens the app (tap on the
    // notification, or its full-screen intent firing over the lock screen),
    // present the ring page. Covers both a warm app (callback) and a cold
    // start (launch details).
    NotificationService.setOnAlarmRing(_showAlarmRing);
    NotificationService.getAlarmLaunchPayload().then((payload) {
      if (payload != null) _showAlarmRing(payload);
    }).catchError((_) {});
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
    }
  }

  @override
  void dispose() {
    NotificationService.setOnAlarmRing(null);
    super.dispose();
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
          .whenComplete(() => _alarmRingOpen = false);
    });
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

  Future<void> _finishIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', true);
    setState(() => _showIntro = false);
  }

  Future<void> restartIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', false);
    setState(() => _showIntro = true);
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor)
            .copyWith(primary: _seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ).copyWith(primary: _seedColor),
        useMaterial3: true,
      ),
      themeMode: Config.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: _showIntro ? IntroPage(onFinished: _finishIntro) : _initialPage(),
    );
  }
}
