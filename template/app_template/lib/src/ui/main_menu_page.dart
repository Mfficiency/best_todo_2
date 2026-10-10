import 'package:flutter/material.dart';

import '../app_config.dart';
import '../app_settings.dart';
import '../models/menu_entry.dart';
import 'about_page.dart';
import 'app_logs_page.dart';
import 'changelog_page.dart';
import 'settings_page.dart';
import 'startup_times_page.dart';
import 'test_results_page.dart';
import 'widgets/spacing.dart';
import 'widgets/version_banner.dart';

/// The app's home screen and navigation root: the app title and current
/// version at the top, then app-specific entries ([AppConfig.customMenuEntries])
/// followed by the built-in technical pages.
///
/// On first build it opens the user's chosen start page (Settings → Startup)
/// on top of itself, so backing out always lands here.
class MainMenuPage extends StatefulWidget {
  const MainMenuPage({super.key});

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openStartPage());
  }

  void _openStartPage() {
    if (!mounted) return;
    final key = AppSettings.instance.startPageKey;
    final page = AppConfig.startPages
        .where((p) => p.key == key && p.builder != null)
        .firstOrNull;
    final builder = page?.builder;
    if (builder != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => builder()),
      );
    }
  }

  /// Built-in technical pages, appended after the app's own entries.
  static const List<MenuEntry> _builtInEntries = [
    MenuEntry(
        icon: Icons.settings,
        label: 'Settings',
        routeBuilder: SettingsPage.new),
    MenuEntry(
        icon: Icons.info_outline, label: 'About', routeBuilder: AboutPage.new),
    MenuEntry(
        icon: Icons.receipt_long,
        label: 'Changelog',
        routeBuilder: ChangelogPage.new),
    MenuEntry(
        icon: Icons.article_outlined,
        label: 'App Logs',
        routeBuilder: AppLogsPage.new),
    MenuEntry(
        icon: Icons.timer_outlined,
        label: 'Startup Times',
        routeBuilder: StartupTimesPage.new),
    MenuEntry(
        icon: Icons.checklist,
        label: 'Test Results',
        routeBuilder: TestResultsPage.new),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = [...AppConfig.customMenuEntries, ..._builtInEntries];
    return Scaffold(
      appBar: AppBar(title: const Text(AppConfig.appName)),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
            child: VersionBanner(detailed: true),
          ),
          const Divider(height: 1),
          for (final entry in entries)
            ListTile(
              leading: Icon(entry.icon),
              title: Text(entry.label),
              subtitle: entry.subtitle == null ? null : Text(entry.subtitle!),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => entry.routeBuilder()),
              ),
            ),
        ],
      ),
    );
  }
}
