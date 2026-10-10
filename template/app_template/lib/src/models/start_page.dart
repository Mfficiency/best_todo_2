import 'package:flutter/material.dart';

import '../ui/app_logs_page.dart';
import '../ui/settings_page.dart';

/// A launch-screen option offered in Settings → Startup. The main menu is
/// always the navigation root; a start page (if any) is pushed on top of it at
/// launch, so backing out of it returns to the menu.
class StartPage {
  /// Stable identifier persisted in settings. Never rename an existing key.
  final String key;

  /// Human-readable label shown in the Settings dropdown.
  final String label;

  /// Page pushed at launch. `null` means "open on the main menu itself"
  /// (nothing is pushed).
  final Widget Function()? builder;

  const StartPage({required this.key, required this.label, this.builder});
}

/// Default start-page choices. The first entry is the out-of-the-box default.
/// Apps override this via [AppConfig.startPages].
const List<StartPage> defaultStartPages = [
  StartPage(key: 'menu', label: 'Main menu'),
  StartPage(key: 'settings', label: 'Settings', builder: SettingsPage.new),
  StartPage(key: 'app_logs', label: 'App Logs', builder: AppLogsPage.new),
];
