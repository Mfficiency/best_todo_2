// Entry point for the `music` build flavor: Best Music, a standalone app
// built from this same codebase (`flutter build apk --flavor music -t
// lib/main_music.dart`, or `sh tool/build.sh music-apk --release`). Unlike
// `main.dart` it boots none of BestToDo's task/alarm/sync machinery — only
// what the Music Player and MP3 Downloader tools need.
import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'config.dart';
import 'services/auto_update_checker.dart';
import 'services/music_library_service.dart';
import 'services/music_player_service.dart';
import 'services/music_playlist_service.dart';
import 'services/startup_time_service.dart';
import 'services/update_service.dart';
import 'ui/auto_update_dialog.dart';
import 'ui/music_about_page.dart';
import 'ui/music_player_page.dart';

/// Best Music's own navigator, so the background update poll can show its
/// "New version available" dialog without a [BuildContext] on hand — same
/// pattern as BestToDo's `appNavigatorKey` in `main.dart`.
final GlobalKey<NavigatorState> musicNavigatorKey = GlobalKey<NavigatorState>();

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
    // Local playback is this app's whole purpose, so ask for "All files
    // access" up front like other music apps do, rather than waiting for
    // the user to pick a folder and discover it silently finds nothing —
    // see MusicPlayerService.ensurePermissions.
    unawaited(MusicPlayerService.ensurePermissions(eager: true));
  });
}

class BestMusicApp extends StatefulWidget {
  const BestMusicApp({super.key});

  @override
  State<BestMusicApp> createState() => _BestMusicAppState();
}

class _BestMusicAppState extends State<BestMusicApp> {
  /// Version currently prompted/downloading, so a poll tick that lands
  /// mid-dialog or mid-download doesn't pop a second prompt for the same
  /// build. Mirrors `_MyAppState._pendingUpdateVersion` in `main.dart`,
  /// without that file's task/alarm/sync-specific resume logic Best Music
  /// doesn't need.
  String? _pendingUpdateVersion;

  @override
  void initState() {
    super.initState();
    // Settings → Updates → "Automatically check for updates" applies to
    // BestToDo's own build; Best Music has no such toggle yet, so this
    // background poll (mirroring main.dart's) always runs. Points at
    // MusicAboutPage's own UpdateService.forApp instance so it only ever
    // offers Best Music's builds, never BestToDo's.
    if (!kIsWeb && Platform.isAndroid) {
      AutoUpdateChecker.instance
          .start(_onUpdateFound, service: MusicAboutPage.updateService);
    }
  }

  @override
  void dispose() {
    AutoUpdateChecker.instance.stop();
    super.dispose();
  }

  void _onUpdateFound(UpdateInfo info) {
    if (_pendingUpdateVersion == info.version) return;
    _pendingUpdateVersion = info.version;
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptUpdate(info));
  }

  Future<void> _promptUpdate(UpdateInfo info) async {
    final navigator = musicNavigatorKey.currentState;
    if (navigator == null) {
      _pendingUpdateVersion = null;
      return;
    }
    final accepted = await showUpdateAvailableDialog(navigator.context, info);
    if (accepted != true) {
      AutoUpdateChecker.instance.dismiss(info.version);
      _pendingUpdateVersion = null;
      return;
    }
    // The download runs in the background (Android's DownloadManager), so
    // don't await it here — but keep _pendingUpdateVersion set for its
    // whole duration so a poll tick mid-download doesn't re-prompt.
    unawaited(downloadUpdateInBackground(
      navigator.context,
      info,
      service: MusicAboutPage.updateService,
    ).whenComplete(() {
      if (_pendingUpdateVersion == info.version) {
        _pendingUpdateVersion = null;
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: musicNavigatorKey,
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
