import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'src/app.dart';
import 'src/app_settings.dart';
import 'src/services/startup_time_service.dart';
import 'src/util/app_version.dart';

/// App entry point. The order matters:
///  1. Start the startup-time stopwatch first thing.
///  2. Load persisted settings and the runtime version before the first frame.
///  3. Record the real startup duration after the first frame is rendered.
///
/// Register any [BackupService] sections here too (see TEMPLATE_GUIDE.md) so
/// your app's data participates in backups.
Future<void> main() async {
  StartupTimeService.start();
  WidgetsFlutterBinding.ensureInitialized();

  await AppSettings.instance.load();
  await AppVersion.ensureLoaded();

  final prefs = await SharedPreferences.getInstance();
  // Show the intro once, and never in dev builds (so hot-restart isn't noisy).
  final showIntro =
      AppVersion.isDev ? false : !(prefs.getBool('intro_shown') ?? false);

  runApp(TemplateApp(showIntro: showIntro));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    StartupTimeService.record();
  });
}
