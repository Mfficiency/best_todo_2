import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../models/track.dart';
import 'log_service.dart';
import 'mp3_downloader_service.dart';

/// Keeps a full local copy of every Subscriptions video you start
/// listening to, for [keepFor] after you last played it — so going back
/// into a video you stopped halfway plays instantly from disk (no
/// resolving, no buffering, works offline) instead of streaming again.
///
/// Files live in `<app support>/video_cache/<videoId>/` (one audio file
/// each, saved by [Mp3DownloaderService.downloadMp3]); a file's
/// modification time is when it was last played ([touch]), and
/// [purgeExpired] deletes anything older than [keepFor]. Separate from the
/// MP3 Downloader: nothing lands in the music library or its downloads
/// list.
class VideoAudioCache {
  VideoAudioCache({
    Future<Directory?> Function()? root,
    Future<String> Function(Mp3SearchResult result, String dir)? download,
    DateTime Function()? now,
  })  : _rootOverride = root,
        _downloadOverride = download,
        _now = now ?? DateTime.now;

  static VideoAudioCache instance = VideoAudioCache();

  static const Duration keepFor = Duration(days: 7);

  final Future<Directory?> Function()? _rootOverride;
  final Future<String> Function(Mp3SearchResult, String)? _downloadOverride;
  final DateTime Function() _now;

  final Set<String> _inFlight = <String>{};
  final List<Mp3SearchResult> _queue = [];
  bool _draining = false;

  void _log(String m) => LogService.add('Feed', m);

  Future<Directory?> _root() async {
    final override = _rootOverride;
    if (override != null) return override();
    try {
      final base = await getApplicationSupportDirectory();
      return Directory('${base.path}${Platform.pathSeparator}video_cache');
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _dirFor(String videoId) async {
    final root = await _root();
    return root == null
        ? null
        : Directory('${root.path}${Platform.pathSeparator}$videoId');
  }

  /// The cached audio file for [videoId], if one is complete and not
  /// expired.
  Future<File?> cachedFile(String videoId) async {
    try {
      final dir = await _dirFor(videoId);
      if (dir == null || !await dir.exists()) return null;
      await for (final entity in dir.list()) {
        if (entity is! File || entity.path.endsWith('.part')) continue;
        final modified = await entity.lastModified();
        if (_now().difference(modified) > keepFor) return null;
        return entity;
      }
    } catch (_) {}
    return null;
  }

  /// Marks [file] as just played, restarting its [keepFor] countdown.
  Future<void> touch(File file) async {
    try {
      await file.setLastModified(_now());
    } catch (_) {}
  }

  /// Whether [videoId] is downloading (or waiting to) right now.
  bool isCaching(String videoId) => _inFlight.contains(videoId);

  /// Starts downloading [track] (a feed video) in the background unless
  /// it's already cached or on its way. Downloads run one at a time.
  Future<void> cacheInBackground(Track track) async {
    final id = track.remoteId;
    if (!track.isFeedVideo || id == null || _inFlight.contains(id)) return;
    final existing = await cachedFile(id);
    if (existing != null) {
      await touch(existing);
      return;
    }
    _inFlight.add(id);
    _queue.add(Mp3SearchResult(
      videoId: id,
      title: track.title,
      channel: track.artist,
      duration: track.durationMs == null
          ? null
          : Duration(milliseconds: track.durationMs!),
    ));
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        try {
          final dir = await _dirFor(next.videoId);
          if (dir == null) continue;
          await dir.create(recursive: true);
          final download = _downloadOverride;
          final path = download != null
              ? await download(next, dir.path)
              : await Mp3DownloaderService.instance
                  .downloadMp3(next, dir.path);
          _log('Cached "${next.title}" for ${keepFor.inDays} days -> $path');
        } catch (e) {
          _log('Caching "${next.title}" failed: $e');
          try {
            final dir = await _dirFor(next.videoId);
            if (dir != null && await dir.exists()) {
              await dir.delete(recursive: true);
            }
          } catch (_) {}
        } finally {
          _inFlight.remove(next.videoId);
        }
      }
      await purgeExpired();
    } finally {
      _draining = false;
    }
  }

  /// Deletes every cached video not played within [keepFor].
  Future<void> purgeExpired() async {
    try {
      final root = await _root();
      if (root == null || !await root.exists()) return;
      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        final id = entity.path.split(Platform.pathSeparator).last;
        if (_inFlight.contains(id)) continue;
        DateTime? newest;
        await for (final file in entity.list()) {
          if (file is! File) continue;
          final modified = await file.lastModified();
          if (newest == null || modified.isAfter(newest)) newest = modified;
        }
        if (newest == null || _now().difference(newest) > keepFor) {
          await entity.delete(recursive: true);
          _log('Removed cached video $id (not played for '
              '${keepFor.inDays} days)');
        }
      }
    } catch (_) {}
  }

  @visibleForTesting
  Future<void> get idle async {
    while (_draining || _queue.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}
