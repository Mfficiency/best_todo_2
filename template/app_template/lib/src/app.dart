import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';
import 'app_settings.dart';
import 'theme/app_theme.dart';
import 'ui/intro_page.dart';
import 'ui/main_menu_page.dart';

/// Root widget. Rebuilds the [MaterialApp] theme whenever [AppSettings] changes
/// (it listens to the singleton [ChangeNotifier]), shows the first-run intro,
/// and exposes [replayIntro] so the About page can restart it.
///
/// Reach it from anywhere with `TemplateApp.of(context)?.replayIntro()`.
class TemplateApp extends StatefulWidget {
  /// Whether to show the intro carousel on launch (usually: not shown before,
  /// and not a dev build).
  final bool showIntro;

  const TemplateApp({super.key, required this.showIntro});

  static TemplateAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<TemplateAppState>();

  @override
  State<TemplateApp> createState() => TemplateAppState();
}

class TemplateAppState extends State<TemplateApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late bool _showIntro = widget.showIntro;

  final AppSettings _settings = AppSettings.instance;

  @override
  void initState() {
    super.initState();
    // Rebuild (and re-theme) whenever any setting changes.
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _finishIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', true);
    if (mounted) setState(() => _showIntro = false);
  }

  /// Restarts the first-run introduction (About page action).
  Future<void> replayIntro() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('intro_shown', false);
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (mounted) setState(() => _showIntro = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: AppTheme.light(_settings),
      darkTheme: AppTheme.dark(_settings),
      themeMode: _settings.materialThemeMode,
      home: _showIntro
          ? IntroPage(onFinished: _finishIntro)
          : const MainMenuPage(),
    );
  }
}
