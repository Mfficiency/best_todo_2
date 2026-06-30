import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  @override
  void initState() {
    super.initState();
    // Handle taps coming from the alarms home-screen widget. Guarded so that
    // environments without the platform channel (e.g. widget tests) stay quiet.
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
