import 'package:flutter/material.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';
import 'ui/app_logs_page.dart';
import 'config.dart';
import 'services/log_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.init();
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
      theme: ThemeData(primarySwatch: Colors.blue),
      darkTheme: ThemeData.dark(),
      themeMode: Config.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: _initialPage(),
    );
  }
}
