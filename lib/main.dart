import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';
import 'ui/app_logs_page.dart';
import 'config.dart';
import 'widget_update_worker.dart';

const Color _seedColor = Color(0xFF005FDD);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Config.load();
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  if (Config.enableWidgetUpdates) {
    registerWidgetUpdate();
  } else {
    cancelWidgetUpdate();
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  void updateTheme() => setState(() {});

  Widget _initialPage() {
    switch (Config.startPage) {
      case 'settings':
        return const SettingsPage();
      case 'today':
        return const HomePage();
      case 'app_logs':
      default:
        return const AppLogsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Best Todo 2',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: Config.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: _initialPage(),
    );
  }
}
