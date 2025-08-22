import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';
import 'ui/app_logs_page.dart';
import 'ui/intro_page.dart';
import 'config.dart';

const Color _seedColor = Color(0xFF005FDD);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final showIntro = !(prefs.getBool('intro_shown') ?? false);
  runApp(MyApp(showIntro: showIntro));
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

  void updateTheme() => setState(() {});

  Future<void> _finishIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', true);
    setState(() => _showIntro = false);
  }

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
      home: _showIntro
          ? IntroPage(onFinished: _finishIntro)
          : _initialPage(),
    );
  }
}
