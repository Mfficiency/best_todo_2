import 'package:flutter/material.dart';

import '../config.dart';
import '../services/update_service.dart';
import 'about_page.dart';
import 'subpage_app_bar.dart';

/// Best Music's About page — the same [UpdateSection] as BestToDo's
/// [AboutPage], wired to its own [UpdateService.forApp] instance so the two
/// apps' update checks never see each other's builds (see
/// [UpdateService.checkReleases]'s doc comment).
class MusicAboutPage extends StatelessWidget {
  const MusicAboutPage({super.key});

  /// Public so tests can inject [UpdateService.fetchOverride]/
  /// [UpdateService.downloadChannelOverride] the same way
  /// `about_page_update_test.dart` does for [UpdateService.instance].
  static final UpdateService updateService = UpdateService.forApp(
    appDisplayName: 'Best Music',
    apkPrefix: 'best_music',
  );

  @override
  Widget build(BuildContext context) {
    final mode = Config.isDev ? 'Development' : 'Production';
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'About'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FutureBuilder<void>(
                future: Config.ensureVersionLoaded(),
                builder: (context, snapshot) {
                  return Text(
                    'Best Music v${Config.versionWithBuild}\nRunning in $mode mode',
                    textAlign: TextAlign.center,
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Best Music is the music player and MP3 downloader built out '
                'of BestToDo — no task list, just the Music Player (library, '
                'playlists, background playback) and the MP3 Downloader, in '
                'a standalone app.\n\n'
                'Best Music is a product of Mfficiency, created to make '
                'everyday productivity tools faster, leaner, and '
                'user-controlled.',
                textAlign: TextAlign.left,
              ),
              const SizedBox(height: 24),
              UpdateSection(service: updateService, appName: 'Best Music'),
            ],
          ),
        ),
      ),
    );
  }
}
