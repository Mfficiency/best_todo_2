import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import '../models/track.dart';
import 'log_service.dart';
import 'music_metadata_csv.dart';
import 'music_metadata_extractor.dart';

/// Scans [Config.musicFolder] and every subfolder for playable audio files,
/// skipping anything under [Config.musicExcludedSubfolders]. Reads ID3 tags
/// (best-effort, mp3 only) for a readable title/artist/album, falling back
/// to the filename when tags are missing or unreadable. Results are cached
/// to `music_library.json` so the library shows up instantly on next launch
/// without waiting for a fresh scan; call [rescan] to refresh it (e.g. after
/// the user changes the music folder or adds files).
class MusicLibraryService {
  MusicLibraryService._();

  static final MusicLibraryService instance = MusicLibraryService._();

  static const _fileName = 'music_library.json';

  /// Extensions treated as playable audio.
  static const Set<String> supportedExtensions = {
    'mp3',
    'm4a',
    'flac',
    'wav',
    'ogg',
    'aac',
    'wma',
  };

  final ValueNotifier<List<Track>> tracks = ValueNotifier<List<Track>>([]);
  bool _loaded = false;
  bool scanning = false;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Loads the cached library from disk (only once). Does not scan the
  /// filesystem — call [rescan] for that.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final List<dynamic> data = jsonDecode(await file.readAsString());
        tracks.value = data
            .whereType<Map>()
            .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
            .where((t) => t.id.isNotEmpty)
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      final jsonString =
          jsonEncode(tracks.value.map((t) => t.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {}
  }

  static String normalizePath(String p) => p.replaceAll('\\', '/');

  /// True if [relativeDir] (forward-slash separated, no leading/trailing
  /// slash — empty means the root folder itself) is excluded, either
  /// directly or because it is nested under an excluded folder.
  static bool isExcludedRelativeDir(
      String relativeDir, List<String> excluded) {
    if (relativeDir.isEmpty) return false;
    final normalizedDir = normalizePath(relativeDir);
    for (final raw in excluded) {
      final ex = normalizePath(raw).trim();
      if (ex.isEmpty) continue;
      if (normalizedDir == ex || normalizedDir.startsWith('$ex/')) {
        return true;
      }
    }
    return false;
  }

  /// On Android, the folder scan needs the "All files access"
  /// (`MANAGE_EXTERNAL_STORAGE`) permission — nothing else in the music
  /// folder pick flow asks for it, so without this a freshly chosen folder
  /// scans as empty with no visible error (`rescan` logs the denial, but by
  /// then the user has already picked a folder that "has no songs"). Call
  /// this right after the user picks a folder, before the first scan. No-op
  /// (always true) off Android.
  Future<bool> ensureFolderPermission() async {
    if (!Platform.isAndroid) return true;
    var status = await Permission.manageExternalStorage.status;
    LogService.add('Music', 'ensureFolderPermission: status=$status');
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
      LogService.add('Music', 'ensureFolderPermission: requested -> $status');
    }
    return status.isGranted;
  }

  static String extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  static String baseNameOf(String path) {
    final normalized = normalizePath(path);
    final slash = normalized.lastIndexOf('/');
    final name = slash >= 0 ? normalized.substring(slash + 1) : normalized;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// Every subfolder under [Config.musicFolder] (recursively, as
  /// forward-slash relative paths with no leading slash), for the exclusion
  /// checkboxes in Settings. Empty if the folder isn't set or doesn't exist.
  Future<List<String>> listSubfolders() async {
    final root = Config.musicFolder.trim();
    if (root.isEmpty) return [];
    final rootDir = Directory(root);
    if (!await rootDir.exists()) return [];
    final normalizedRoot = normalizePath(root);
    final result = <String>[];
    try {
      await for (final entity
          in rootDir.list(recursive: true, followLinks: false)) {
        if (entity is! Directory) continue;
        final rel = _relativePath(normalizePath(entity.path), normalizedRoot);
        if (rel.isNotEmpty) result.add(rel);
      }
    } catch (e) {
      LogService.add('Music', 'listSubfolders: "$root" failed: $e');
    }
    result.sort();
    return result;
  }

  static String _relativePath(String path, String normalizedRoot) {
    var rel =
        path.startsWith(normalizedRoot) ? path.substring(normalizedRoot.length) : path;
    if (rel.startsWith('/')) rel = rel.substring(1);
    return rel;
  }

  /// Recursively scans [Config.musicFolder], skipping
  /// [Config.musicExcludedSubfolders]. Persists the result and updates
  /// [tracks]. A scan failure (folder missing, permission denied) leaves the
  /// previously cached library untouched instead of wiping it out.
  ///
  /// [onTrackScanned] fires once per supported audio file found, with the
  /// running count and that file's final [Track] (already merged with its
  /// previous dateAdded/playCount/manual edits, if any) — how
  /// `MusicMetadataScanPage` reports live scan progress without waiting for
  /// the whole folder to finish.
  Future<List<Track>> rescan(
      {void Function(int scanned, Track track)? onTrackScanned}) async {
    final root = Config.musicFolder.trim();
    if (root.isEmpty) {
      LogService.add('Music', 'rescan: no music folder configured');
      tracks.value = [];
      await _save();
      return tracks.value;
    }
    scanning = true;
    try {
      if (Platform.isAndroid) {
        final status = await Permission.manageExternalStorage.status;
        LogService.add('Music', 'rescan: manageExternalStorage=$status');
      }
      final rootDir = Directory(root);
      final rootExists = await rootDir.exists();
      LogService.add('Music', 'rescan: "$root" exists=$rootExists');
      if (!rootExists) {
        LogService.add(
            'Music',
            'rescan: "$root" not found by Directory.exists() — on Android '
            'this also happens when "All files access" isn\'t granted, not '
            'just a missing/moved folder');
        return tracks.value;
      }
      final excluded = Config.musicExcludedSubfolders;
      final normalizedRoot = normalizePath(root);
      // Keyed by id so each freshly-scanned track can inherit its previous
      // dateAdded/playCount (always) and, when it was manually edited via
      // the Track info page, its title/artist/album/genre/year too — a
      // rescan must never quietly discard a manual fix with a fresh
      // (possibly still empty) tag read.
      final previousById = {for (final t in tracks.value) t.id: t};
      final now = DateTime.now();
      final found = <Track>[];
      var filesSeen = 0;
      var skippedUnsupportedExt = 0;
      var skippedExcludedDir = 0;
      await for (final entity
          in rootDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        filesSeen++;
        final path = normalizePath(entity.path);
        final ext = extensionOf(path);
        if (!supportedExtensions.contains(ext)) {
          skippedUnsupportedExt++;
          continue;
        }
        final rel = _relativePath(path, normalizedRoot);
        final relDir = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
        if (isExcludedRelativeDir(relDir, excluded)) {
          skippedExcludedDir++;
          continue;
        }
        var track = await _buildTrack(entity.path, ext);
        final previous = previousById[track.id];
        track = (previous != null && previous.metadataEdited)
            ? previous.copyWith(durationMs: track.durationMs ?? previous.durationMs)
            : track.copyWith(
                dateAdded: previous?.dateAdded ?? now,
                playCount: previous?.playCount ?? 0,
              );
        found.add(track);
        onTrackScanned?.call(found.length, track);
      }
      found.sort((a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      tracks.value = found;
      await _save();
      LogService.add(
          'Music',
          'rescan: "$root" — $filesSeen file(s) seen, ${found.length} '
          'track(s) kept, $skippedUnsupportedExt unsupported extension, '
          '$skippedExcludedDir in excluded subfolders');
    } catch (e, st) {
      // Keep whatever was loaded/cached before; a partial or failed scan
      // shouldn't wipe out a previously known library.
      debugPrint('MusicLibraryService.rescan: "$root" failed: $e\n$st');
      LogService.add('Music', 'rescan: "$root" failed: $e');
    } finally {
      scanning = false;
    }
    return tracks.value;
  }

  Future<Track> _buildTrack(String filePath, String ext) async {
    final fallbackTitle = baseNameOf(filePath);
    if (ext != 'mp3') {
      return Track.local(filePath: filePath, title: fallbackTitle);
    }
    try {
      final raf = await File(filePath).open();
      final length = await raf.length();
      final headBytes = await raf.read(min(length, id3ReadCap));
      await raf.close();
      final tags = decodeMp3Tags(headBytes);
      return Track.local(
        filePath: filePath,
        title: (tags.title != null && tags.title!.trim().isNotEmpty)
            ? tags.title!.trim()
            : fallbackTitle,
        artist: (tags.artist ?? '').trim(),
        album: (tags.album ?? '').trim(),
        genre: (tags.genre ?? '').trim(),
        year: tags.year,
      );
    } catch (_) {
      return Track.local(filePath: filePath, title: fallbackTitle);
    }
  }

  /// Sets [trackId]'s title/artist/album/genre/year to exactly the given
  /// values (the Track info page's "fill in missing metadata" — not the
  /// file's actual tags, just this app's cached record of them, which is
  /// all rule/smart playlists read) and marks it [Track.metadataEdited] so
  /// a later [rescan] keeps these instead of overwriting them with a fresh
  /// tag read. No-op if the track isn't currently in the library.
  Future<void> updateTrackMetadata(
    String trackId, {
    required String title,
    required String artist,
    required String album,
    required String genre,
    int? year,
  }) async {
    final index = tracks.value.indexWhere((t) => t.id == trackId);
    if (index < 0) return;
    final existing = tracks.value[index];
    final updated = Track(
      id: existing.id,
      source: existing.source,
      filePath: existing.filePath,
      remoteId: existing.remoteId,
      title: title,
      artist: artist,
      album: album,
      durationMs: existing.durationMs,
      genre: genre,
      year: year,
      dateAdded: existing.dateAdded,
      playCount: existing.playCount,
      metadataEdited: true,
    );
    final list = List<Track>.of(tracks.value);
    list[index] = updated;
    tracks.value = list;
    await _save();
  }

  /// Applies a batch of parsed CSV rows (from [MusicMetadataCsv.decode]) to
  /// the matching tracks, keyed by [ParsedMetadataRow.id]. A blank field on
  /// a row leaves that track field untouched — only a non-empty imported
  /// value overwrites it — so a round-trip through a spreadsheet that
  /// happens to clear a cell can't silently erase a value the app already
  /// had. Every matched row is marked [Track.metadataEdited], same as a
  /// manual edit on the Track info page. Rows whose id isn't in the
  /// library are silently skipped. Returns how many rows matched a track.
  Future<int> applyMetadataRows(List<ParsedMetadataRow> rows) async {
    final list = List<Track>.of(tracks.value);
    var applied = 0;
    for (final row in rows) {
      final index = list.indexWhere((t) => t.id == row.id);
      if (index < 0) continue;
      final existing = list[index];
      list[index] = Track(
        id: existing.id,
        source: existing.source,
        filePath: existing.filePath,
        remoteId: existing.remoteId,
        title: row.title.isNotEmpty ? row.title : existing.title,
        artist: row.artist.isNotEmpty ? row.artist : existing.artist,
        album: row.album.isNotEmpty ? row.album : existing.album,
        durationMs: existing.durationMs,
        genre: row.genre.isNotEmpty ? row.genre : existing.genre,
        year: row.year ?? existing.year,
        dateAdded: existing.dateAdded,
        playCount: existing.playCount,
        metadataEdited: true,
      );
      applied++;
    }
    if (applied > 0) {
      tracks.value = list;
      await _save();
    }
    return applied;
  }

  /// Bumps [trackId]'s play count and persists it. No-op if the track isn't
  /// currently in the library (e.g. it was removed since the queue was
  /// built).
  Future<void> incrementPlayCount(String trackId) async {
    final index = tracks.value.indexWhere((t) => t.id == trackId);
    if (index < 0) return;
    final updated = List<Track>.of(tracks.value);
    updated[index] =
        updated[index].copyWith(playCount: updated[index].playCount + 1);
    tracks.value = updated;
    await _save();
  }

  Track? byId(String id) {
    for (final t in tracks.value) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Resets in-memory state (for tests).
  @visibleForTesting
  void resetForTest() {
    tracks.value = [];
    _loaded = false;
    scanning = false;
  }
}
