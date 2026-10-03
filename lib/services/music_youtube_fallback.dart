import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../config.dart';
import '../models/track.dart';
import 'log_service.dart';
import 'mp3_download_manager.dart';
import 'mp3_downloader_service.dart';
import 'music_player_service.dart';
import 'track_title.dart';

/// The Music Player search's "nothing in your library — try YouTube?"
/// fallback: picking a YouTube result starts streaming it right away
/// ([Track.youtube], played through `YoutubeAudioSource` like a
/// Subscriptions-feed video) and, at the same time,
/// quietly queues it on [Mp3DownloadManager] so it ends up in the library
/// (via `MusicDownloadLibrarySync`'s rescan) without any prompt.
class MusicYoutubeFallback {
  MusicYoutubeFallback._();

  /// Lets tests skip the real folder probing.
  @visibleForTesting
  static Future<String?> Function()? downloadFolderOverride;

  /// Lets tests observe playback without an audio handler.
  @visibleForTesting
  static Future<void> Function(Track track)? playOverride;

  /// The [Track] that streams [result], titled the way the downloaded file
  /// will be (`Artist - Title` split out of the video title).
  static Track trackFor(Mp3SearchResult result) {
    final parts = parseTrackTitle(result.title, result.channel);
    return Track.youtube(
      videoId: result.videoId,
      title: parts.title,
      artist: parts.artist,
      durationMs: result.duration?.inMilliseconds,
      artUrl: 'https://i.ytimg.com/vi/${result.videoId}/hqdefault.jpg',
    );
  }

  /// Where a background download goes, without ever asking: the MP3
  /// Downloader's folder if one was chosen, else the library folder (so the
  /// song shows up in the library once it lands), else the app's default
  /// download folder. Null when nothing writable is available.
  static Future<String?> downloadFolder() async {
    if (downloadFolderOverride != null) return downloadFolderOverride!();
    final saved = Config.mp3DownloadFolder.trim();
    if (saved.isNotEmpty) return saved;
    final library = Config.musicFolder.trim();
    if (library.isNotEmpty && await canWriteToFolder(library)) return library;
    return defaultDownloadFolder();
  }

  /// Starts playing [result] and silently downloads it in the background.
  /// Returns once the download is queued and playback has been started —
  /// not when the stream actually begins, which takes a few seconds while
  /// YouTube's stream URL is resolved.
  static Future<void> playAndDownload(Mp3SearchResult result) async {
    await _downloadInBackground(result);
    final track = trackFor(result);
    final play = playOverride;
    if (play != null) {
      await play(track);
    } else {
      unawaited(MusicPlayerService.playQueue([track]));
    }
  }

  static Future<void> _downloadInBackground(Mp3SearchResult result) async {
    final manager = Mp3DownloadManager.instance;
    for (final job in manager.jobs.value) {
      if (job.videoId != result.videoId) continue;
      if (job.isActive) return;
      final path = job.filePath;
      if (job.status == Mp3DownloadStatus.completed &&
          path != null &&
          await File(path).exists()) {
        return;
      }
    }
    final folder = await downloadFolder();
    if (folder == null || folder.isEmpty) {
      LogService.add('MP3',
          'No download folder for "${result.title}" — streaming only');
      return;
    }
    manager.enqueue(result, folder);
  }
}
