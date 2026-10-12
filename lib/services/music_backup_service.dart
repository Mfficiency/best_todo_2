import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/task.dart';
import 'auto_backup_service.dart';
import 'log_service.dart';
import 'mp3_download_manager.dart';
import 'music_library_service.dart';
import 'music_metadata_enricher.dart';
import 'music_playlist_service.dart';
import 'music_resume_service.dart';
import 'storage_service.dart';
import 'youtube_feed_service.dart';

/// What [MusicBackupService.restore] did, for the snackbar.
class MusicRestoreResult {
  const MusicRestoreResult._(this.success, this.message);

  const MusicRestoreResult.ok(String message) : this._(true, message);
  const MusicRestoreResult.failed(String message) : this._(false, message);

  final bool success;
  final String message;
}

/// Best Music's backup & restore — the counterpart of BestToDo's "Export
/// Everything"/Import and [AutoBackupService] (Settings → Backup).
///
/// A backup is one JSON file (`best_music_backup_<stamp>.json`) holding the
/// settings ([Config.toMap]), the Wishlist items, and the decoded contents of
/// each of Best Music's own store files ([storeFiles]: library cache with
/// play counts and analyzed metadata such as BPM, playlists, Subscriptions
/// feed with watch progress, download history, metadata enrichment, the
/// playback resume point).
///
/// Local songs are keyed by their absolute path (`local:<path>`), so a
/// restore onto a phone whose music folder lives elsewhere rewrites those
/// paths to this phone's folder ([remapRoot]) — otherwise the next rescan
/// would orphan their metadata, favourites and playlist entries.
/// [relocateLibrary] does the same in place when the user picks a new
/// music folder because the old one no longer exists.
/// It is tagged `"app": "best_music"`, so restoring a BestToDo export here
/// (or this file into BestToDo) is refused instead of half-applied.
///
/// The automatic schedule reuses [Config.autoBackupFrequency]/
/// [Config.autoBackupDirectory] and [AutoBackupService.isDue] — Best Music
/// has its own sandboxed settings.json, so those keys are free here — with
/// its own last-run marker file. Errors are swallowed and logged like
/// [AutoBackupService]: a missing SD card must never break the app.
class MusicBackupService {
  MusicBackupService._();

  static const String app = 'best_music';
  static const int exportVersion = 1;
  static const String markerFileName = 'last_music_backup.txt';

  /// Written to the documents dir right before a restore overwrites
  /// anything, so a wrong pick can be undone by restoring this file.
  static const String preRestoreFileName = 'music_pre_restore_backup.json';

  /// The store files a backup carries, keyed by file name in the app
  /// documents dir.
  static const List<String> storeFiles = [
    'music_library.json',
    'music_playlists.json',
    'youtube_feed.json',
    'mp3_downloads.json',
    MusicMetadataEnricher.fileName,
    // Read once at startup, so a restored resume point applies on the next
    // launch.
    MusicResumeService.fileName,
  ];

  static Future<Directory> _documents() => getApplicationDocumentsDirectory();

  static Future<File> _markerFile() async =>
      File('${(await _documents()).path}/$markerFileName');

  /// When the last backup (automatic or "Back up now") was written.
  static Future<DateTime?> lastRun() async {
    try {
      final file = await _markerFile();
      if (!await file.exists()) return null;
      return DateTime.tryParse((await file.readAsString()).trim());
    } catch (_) {
      return null;
    }
  }

  /// The backup contents, read straight from disk so it is complete even
  /// when no page has loaded the stores yet.
  static Future<Map<String, dynamic>> buildPayload({DateTime? now}) async {
    final dir = await _documents();
    final stores = <String, dynamic>{};
    for (final name in storeFiles) {
      try {
        final file = File('${dir.path}/$name');
        if (!await file.exists()) continue;
        stores[name] = jsonDecode(await file.readAsString());
      } catch (e) {
        LogService.add('backup', 'Skipped unreadable $name: $e');
      }
    }
    var wishlist = const <Task>[];
    try {
      wishlist = (await StorageService().readTaskListRaw())
          .where((t) => t.isWish)
          .toList();
    } catch (_) {}
    return <String, dynamic>{
      'app': app,
      'export_version': exportVersion,
      'exported_at': (now ?? DateTime.now()).toIso8601String(),
      'settings': Config.toMap(),
      'wishlist': wishlist.map((t) => t.toJson()).toList(),
      'stores': stores,
    };
  }

  /// Writes a backup file into [directory] and records it as the last run.
  /// Returns the file, or null when the write failed.
  static Future<File?> exportTo(String directory, {DateTime? now}) async {
    try {
      final moment = now ?? DateTime.now();
      final sep = Platform.pathSeparator;
      final prefix = '$directory${directory.endsWith(sep) ? '' : sep}';
      final file =
          File('${prefix}best_music_backup_${_timestamp(moment)}.json');
      await file.writeAsString(jsonEncode(await buildPayload(now: moment)),
          flush: true);
      try {
        await (await _markerFile())
            .writeAsString(moment.toIso8601String(), flush: true);
      } catch (_) {}
      LogService.add('backup', 'Best Music backup written to ${file.path}');
      return file;
    } catch (e) {
      LogService.add('backup', 'Best Music backup failed: $e');
      return null;
    }
  }

  /// Backs up to [Config.autoBackupDirectory] regardless of the schedule.
  static Future<File?> runNow({DateTime? now}) async {
    final directory = Config.autoBackupDirectory;
    if (directory.isEmpty) return null;
    return exportTo(directory, now: now);
  }

  /// Backs up if the schedule says one is due; cheap when it's off.
  static Future<File?> maybeRun({DateTime? now}) async {
    if (Config.autoBackupFrequency == 'off') return null;
    if (Config.autoBackupDirectory.isEmpty) return null;
    final moment = now ?? DateTime.now();
    if (!AutoBackupService.isDue(await lastRun(), moment)) return null;
    return runNow(now: moment);
  }

  /// Restores the backup file at [path].
  static Future<MusicRestoreResult> restoreFile(String path) async {
    Object? decoded;
    try {
      decoded = jsonDecode(await File(path).readAsString());
    } catch (_) {
      return const MusicRestoreResult.failed('Not a Best Music backup file');
    }
    return restore(decoded);
  }

  /// Restores an already-decoded backup: settings, Wishlist and every store
  /// file it carries (stores it lacks are left alone), then reloads the
  /// in-memory services so the app shows the restored data right away.
  /// Settings-driven UI state (Best Music's dark mode notifier) is the
  /// caller's to refresh.
  static Future<MusicRestoreResult> restore(Object? decoded) async {
    if (decoded is! Map) {
      return const MusicRestoreResult.failed('Not a Best Music backup file');
    }
    final data = Map<String, dynamic>.from(decoded);
    if (data['app'] != app) {
      return MusicRestoreResult.failed(data['tasks_bundle'] != null
          ? 'That is a BestToDo backup — restore it in BestToDo'
          : 'Not a Best Music backup file');
    }
    final dir = await _documents();
    try {
      final safety = await buildPayload();
      await File('${dir.path}/$preRestoreFileName')
          .writeAsString(jsonEncode(safety), flush: true);
    } catch (e) {
      LogService.add('backup', 'Pre-restore backup failed: $e');
    }

    // This phone's music folder wins over the backup's: songs keep their
    // data when the folder lives at a different path here.
    final settingsRaw = data['settings'];
    final settings =
        settingsRaw is Map ? Map<String, dynamic>.from(settingsRaw) : null;
    final backupRoot = settings?['musicFolder'] as String? ?? '';
    final deviceRoot = Config.musicFolder;
    final remap = backupRoot.isNotEmpty &&
        deviceRoot.isNotEmpty &&
        _trimRoot(backupRoot) != _trimRoot(deviceRoot);
    if (remap) settings!['musicFolder'] = deviceRoot;

    final restored = <String>[];
    final stores = data['stores'];
    if (stores is Map) {
      for (final name in storeFiles) {
        if (!stores.containsKey(name)) continue;
        try {
          final content = remap
              ? remapRoot(stores[name], backupRoot, deviceRoot)
              : stores[name];
          await File('${dir.path}/$name')
              .writeAsString(jsonEncode(content), flush: true);
          restored.add(name);
        } catch (e) {
          LogService.add('backup', 'Could not restore $name: $e');
        }
      }
    }

    final wishlistRaw = data['wishlist'];
    if (wishlistRaw is List) {
      final wishes = [
        for (final w in wishlistRaw)
          if (w is Map) Task.fromJson(Map<String, dynamic>.from(w)),
      ];
      try {
        final storage = StorageService();
        // Best Music's task list only ever holds Wishlist items, but keep
        // anything else that may be there rather than dropping it.
        final others =
            (await storage.readTaskListRaw()).where((t) => !t.isWish);
        await storage.saveTaskList([...wishes, ...others]);
      } catch (e) {
        LogService.add('backup', 'Could not restore the Wishlist: $e');
      }
    }

    if (settings != null) {
      Config.applyMap(settings);
      await Config.save();
    }

    await _reloadStores(restored);
    LogService.add('backup', 'Best Music backup restored (${restored.length} '
        'stores${wishlistRaw is List ? ', wishlist' : ''}'
        '${settings != null ? ', settings' : ''}'
        '${remap ? ', songs moved from $backupRoot to $deviceRoot' : ''})');
    return const MusicRestoreResult.ok('Backup restored');
  }

  static Future<void> _reloadStores(List<String> restored) async {
    Future<void> guard(Future<void> Function() reload) async {
      try {
        await reload();
      } catch (_) {}
    }

    for (final name in restored) {
      switch (name) {
        case 'music_library.json':
          await guard(MusicLibraryService.instance.reload);
        case 'music_playlists.json':
          await guard(MusicPlaylistService.instance.reload);
        case 'youtube_feed.json':
          await guard(YoutubeFeedService.instance.reload);
        case 'mp3_downloads.json':
          await guard(Mp3DownloadManager.instance.reload);
        case MusicMetadataEnricher.fileName:
          await guard(MusicMetadataEnricher.instance.reload);
      }
    }
  }

  /// Moves every song's saved data (library, playlists, enrichment, resume
  /// point, download history) from [oldRoot] to [newRoot] on disk and
  /// reloads the services — for a music folder that moved, e.g. a restore
  /// onto a fresh install followed by picking this phone's folder. Returns
  /// whether anything changed.
  static Future<bool> relocateLibrary(String oldRoot, String newRoot) async {
    if (oldRoot.isEmpty || newRoot.isEmpty) return false;
    if (_trimRoot(oldRoot) == _trimRoot(newRoot)) return false;
    final dir = await _documents();
    final changed = <String>[];
    for (final name in storeFiles) {
      try {
        final file = File('${dir.path}/$name');
        if (!await file.exists()) continue;
        final before = await file.readAsString();
        final after =
            jsonEncode(remapRoot(jsonDecode(before), oldRoot, newRoot));
        if (after == before) continue;
        await file.writeAsString(after, flush: true);
        changed.add(name);
      } catch (e) {
        LogService.add('backup', 'Could not relocate $name: $e');
      }
    }
    await _reloadStores(changed);
    if (changed.isNotEmpty) {
      LogService.add('backup',
          'Moved song data from $oldRoot to $newRoot (${changed.join(', ')})');
    }
    return changed.isNotEmpty;
  }

  /// [json] with every path under [oldRoot] — as a plain string, a
  /// `local:` track id, or a map key — rewritten to the same path under
  /// [newRoot]. Anything else is returned unchanged.
  static Object? remapRoot(Object? json, String oldRoot, String newRoot) {
    final from = _trimRoot(oldRoot);
    final to = _trimRoot(newRoot);
    String move(String value) {
      for (final prefix in const ['', 'local:']) {
        final root = '$prefix$from';
        if (value == root) return '$prefix$to';
        if (value.startsWith(root) &&
            value.length > root.length &&
            (value[root.length] == '/' || value[root.length] == r'\')) {
          return '$prefix$to${value.substring(root.length)}';
        }
      }
      return value;
    }

    Object? walk(Object? node) {
      if (node is String) return move(node);
      if (node is List) return [for (final e in node) walk(e)];
      if (node is Map) {
        return {
          for (final e in node.entries) move('${e.key}'): walk(e.value),
        };
      }
      return node;
    }

    return walk(json);
  }

  static String _trimRoot(String root) {
    var r = root;
    while (r.length > 1 && (r.endsWith('/') || r.endsWith(r'\'))) {
      r = r.substring(0, r.length - 1);
    }
    return r;
  }

  static String _timestamp(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
