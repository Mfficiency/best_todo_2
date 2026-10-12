import 'package:flutter/material.dart';

import '../config.dart';
import 'about_page.dart';
import 'best_music_logo.dart';
import 'subpage_app_bar.dart';

/// Best Music's About page — the same [UpdateSection] as BestToDo's
/// [AboutPage]. In Best Music the running app's controller
/// ([AppUpdates.controller], made by `main_music.dart`) only knows Best
/// Music's own release tags (`music-v…`), so it never offers BestToDo's
/// builds.
class MusicAboutPage extends StatelessWidget {
  const MusicAboutPage({super.key});

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
              const BestMusicLogo(size: 96),
              const SizedBox(height: 16),
              FutureBuilder<void>(
                future: Config.ensureVersionLoaded(),
                builder: (context, snapshot) {
                  return Text(
                    'Best Music v${Config.versionWithChannel}\nRunning in $mode mode',
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
              const UpdateSection(),
            ],
          ),
        ),
      ),
    );
  }
}
