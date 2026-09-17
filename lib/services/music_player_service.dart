import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../models/track.dart';
import 'music_audio_handler.dart';
import 'music_library_service.dart';
import 'music_playlist_service.dart';
import 'music_widget_service.dart';

/// Facade over [MusicAudioHandler]: owns startup (registering it with
/// `audio_service` so the system notification/lock screen work, where that
/// platform support exists) and the convenience "play this" entry points
/// the UI calls, so pages never talk to [BaseAudioHandler]/`just_audio`
/// directly.
class MusicPlayerService {
  MusicPlayerService._();

  static MusicAudioHandler? _handler;
  static bool _initStarted = false;

  /// The active audio handler. Only valid after [init] has completed —
  /// callers that run after app startup (all UI code) can rely on it.
  static MusicAudioHandler get handler {
    final h = _handler;
    if (h == null) {
      throw StateError('MusicPlayerService.init() has not completed yet');
    }
    return h;
  }

  static bool get isReady => _handler != null;

  /// `audio_service`'s Android/iOS/macOS notification+lock-screen wrapper
  /// isn't available on every platform this app runs on (Windows desktop is
  /// used for tests/screenshots); on those, playback still works through
  /// the handler directly, just without the system media integration.
  static bool get _platformSupportsAudioService =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  static Future<void> init() async {
    if (_initStarted) return;
    _initStarted = true;
    if (_platformSupportsAudioService) {
      _handler = await AudioService.init(
        builder: () => MusicAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.mfficiency.best_todo_2.music_channel',
          androidNotificationChannelName: 'Music playback',
          androidNotificationIcon: 'drawable/ic_stat_music_note',
          androidShowNotificationBadge: true,
          androidStopForegroundOnPause: false,
        ),
      );
    } else {
      _handler = MusicAudioHandler();
    }
    MusicWidgetService.attach(_handler!);
  }

  /// Plays the whole local+configured library in a fresh weighted shuffle
  /// (favorites more often, disliked far less).
  static Future<void> playLibraryShuffled() async {
    final tracks = MusicLibraryService.instance.tracks.value;
    if (tracks.isEmpty) return;
    final shuffled = MusicPlaylistService.instance.weightedShuffle(tracks);
    await handler.setQueueAndPlay(shuffled);
  }

  /// Plays [tracks] in order starting at [startIndex] — used for "play this
  /// playlist" / "play from this song" (no shuffle).
  static Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    await handler.setQueueAndPlay(tracks, startIndex: startIndex);
  }

  /// Requests the runtime permissions the Music Player needs, Android only
  /// (nothing here applies on iOS/desktop/web). Call once per app start —
  /// there's no "already asked" flag, so a still-missing permission gets
  /// asked again on the next launch instead of staying silently broken.
  ///
  /// [eager]: request storage access ("All files access") even before any
  /// music folder is chosen — Best Music, where local playback is the whole
  /// app, so it's worth asking upfront like other music apps do. Off
  /// (BestToDo's default): only once a folder is already configured, so the
  /// far larger group of BestToDo users who never open Music Player aren't
  /// interrupted at launch for a permission a tool they don't use needs.
  static Future<void> ensurePermissions({bool eager = false}) async {
    if (!Platform.isAndroid) return;
    try {
      if (eager || Config.musicFolder.trim().isNotEmpty) {
        final wasGranted = await Permission.manageExternalStorage.isGranted;
        final granted = await MusicLibraryService.instance.ensureFolderPermission();
        // Granted just now on a folder that was already configured but
        // scanned empty (the whole point of asking here) — pick that scan
        // back up immediately instead of waiting for the user to notice.
        if (!wasGranted && granted && Config.musicFolder.trim().isNotEmpty) {
          await MusicLibraryService.instance.rescan();
        }
      }
      if (!await Permission.notification.isGranted) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('MusicPlayerService.ensurePermissions failed: $e');
    }
  }
}
