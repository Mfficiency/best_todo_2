import 'dart:async' show unawaited;

import '../config.dart';
import 'log_service.dart';
import 'mp3_download_manager.dart';
import 'music_library_service.dart';

/// Best Music only (see `main_music.dart`): once the MP3 Downloader finishes
/// a song that landed inside the library's own folder ([Config.musicFolder]),
/// rescans the library so the song is right there in Songs/Artists/Recently
/// added — a song shared in from Spotify/Shazam/YouTube is playable without
/// a manual "Rescan".
///
/// Waits for the download queue to go idle first, so sharing (or a playlist
/// download of) several songs costs one rescan, not one per song. Only
/// completions seen *after* [attach] count — the persisted download history
/// loaded at startup never triggers one.
class MusicDownloadLibrarySync {
  MusicDownloadLibrarySync({
    Mp3DownloadManager? manager,
    Future<void> Function()? rescan,
    String Function()? musicFolder,
  })  : _manager = manager ?? Mp3DownloadManager.instance,
        _rescan = rescan ?? _defaultRescan,
        _musicFolder = musicFolder ?? _defaultMusicFolder;

  static final MusicDownloadLibrarySync instance = MusicDownloadLibrarySync();

  final Mp3DownloadManager _manager;
  final Future<void> Function() _rescan;
  final String Function() _musicFolder;

  final Set<String> _seenCompleted = <String>{};
  bool _pending = false;
  bool _attached = false;

  /// Same default as `MusicPlayerPage.initState`: with no library folder
  /// chosen yet, the MP3 Downloader's folder is it — so the very first song
  /// shared into a fresh install shows up in the library too.
  static String _defaultMusicFolder() {
    if (Config.musicFolder.isEmpty && Config.mp3DownloadFolder.isNotEmpty) {
      Config.musicFolder = Config.mp3DownloadFolder;
      unawaited(Config.save());
    }
    return Config.musicFolder;
  }

  static Future<void> _defaultRescan() async {
    final library = MusicLibraryService.instance;
    if (library.scanning) return;
    await library.rescan();
  }

  void attach() {
    if (_attached) return;
    _attached = true;
    _seenCompleted.addAll(_manager.jobs.value
        .where((j) => j.status == Mp3DownloadStatus.completed)
        .map((j) => j.id));
    _manager.jobs.addListener(_onJobsChanged);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    _manager.jobs.removeListener(_onJobsChanged);
    _seenCompleted.clear();
    _pending = false;
  }

  void _onJobsChanged() {
    final jobs = _manager.jobs.value;
    for (final job in jobs) {
      if (job.status != Mp3DownloadStatus.completed) continue;
      if (!_seenCompleted.add(job.id)) continue;
      if (_isInsideLibrary(job.filePath ?? job.destinationDir)) {
        _pending = true;
      }
    }
    if (_pending && !jobs.any((j) => j.isActive)) {
      _pending = false;
      LogService.add('Music', 'Download finished; rescanning the library');
      _rescan().catchError((Object e) {
        LogService.add('Music', 'Rescan after download failed: $e');
      });
    }
  }

  bool _isInsideLibrary(String path) {
    final root = _musicFolder().trim();
    if (root.isEmpty || path.isEmpty) return false;
    String normalize(String s) {
      var out = s.replaceAll('\\', '/');
      while (out.length > 1 && out.endsWith('/')) {
        out = out.substring(0, out.length - 1);
      }
      return out;
    }

    final normalizedRoot = normalize(root);
    final normalizedPath = normalize(path);
    return normalizedPath == normalizedRoot ||
        normalizedPath.startsWith('$normalizedRoot/');
  }
}
