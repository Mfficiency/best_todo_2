// Entry point for the `music` build flavor: Best Music, a standalone app
// built from this same codebase (`flutter build apk --flavor music -t
// lib/main_music.dart`, or `sh tool/build.sh music-apk --release`). Unlike
// `main.dart` it boots none of BestToDo's task/alarm/sync machinery — only
// what the Music Player and MP3 Downloader tools need.
import 'package:flutter/material.dart';

import 'config.dart';
import 'services/music_library_service.dart';
import 'services/music_player_service.dart';
import 'services/music_playlist_service.dart';
import 'services/startup_time_service.dart';
import 'ui/music_player_page.dart';

Future<void> _initStep(String label, Future<void> Function() step) async {
  try {
    await step();
  } catch (e) {
    debugPrint('Startup step "$label" failed: $e');
  }
}

Future<void> main() async {
  StartupTimeService.start();
  WidgetsFlutterBinding.ensureInitialized();
  await _initStep('config', Config.load);
  await _initStep('music library', MusicLibraryService.instance.load);
  await _initStep('music playlists', MusicPlaylistService.instance.load);
  await _initStep('music player', MusicPlayerService.init);
  runApp(const BestMusicApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    StartupTimeService.record();
  });
}

class BestMusicApp extends StatelessWidget {
  const BestMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Best Music',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.white,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: Config.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const MusicPlayerPage(standalone: true),
    );
  }
}
