import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:id3_codec/id3_codec.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/track.dart';

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

  /// How many bytes of an mp3 file's head to read when looking for an ID3v2
  /// tag. Large enough for typical tags (including small embedded art);
  /// files whose tag runs past this are simply scanned without tags rather
  /// than reading the whole file for every track.
  static const int _id3ReadCap = 1024 * 1024;

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
    } catch (_) {}
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
  Future<List<Track>> rescan() async {
    final root = Config.musicFolder.trim();
    if (root.isEmpty) {
      tracks.value = [];
      await _save();
      return tracks.value;
    }
    scanning = true;
    try {
      final rootDir = Directory(root);
      if (!await rootDir.exists()) return tracks.value;
      final excluded = Config.musicExcludedSubfolders;
      final normalizedRoot = normalizePath(root);
      final found = <Track>[];
      await for (final entity
          in rootDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = normalizePath(entity.path);
        final ext = extensionOf(path);
        if (!supportedExtensions.contains(ext)) continue;
        final rel = _relativePath(path, normalizedRoot);
        final relDir = rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '';
        if (isExcludedRelativeDir(relDir, excluded)) continue;
        found.add(await _buildTrack(entity.path, ext));
      }
      found.sort((a, b) =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      tracks.value = found;
      await _save();
    } catch (_) {
      // Keep whatever was loaded/cached before; a partial or failed scan
      // shouldn't wipe out a previously known library.
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
      final headBytes = await raf.read(min(length, _id3ReadCap));
      await raf.close();
      final tagMap = <String, dynamic>{};
      for (final info in ID3Decoder(headBytes).decodeSync()) {
        tagMap.addAll(info.toTagMap());
      }
      final title = _frameInfo(tagMap, 'TIT2') ?? tagMap['Title'] as String?;
      final artist = _frameInfo(tagMap, 'TPE1') ?? tagMap['Artist'] as String?;
      final album = _frameInfo(tagMap, 'TALB') ?? tagMap['Album'] as String?;
      return Track.local(
        filePath: filePath,
        title: (title != null && title.trim().isNotEmpty)
            ? title.trim()
            : fallbackTitle,
        artist: (artist ?? '').trim(),
        album: (album ?? '').trim(),
      );
    } catch (_) {
      return Track.local(filePath: filePath, title: fallbackTitle);
    }
  }

  static String? _frameInfo(Map<String, dynamic> tagMap, String frameId) {
    final frame = tagMap['Frame[$frameId]'];
    if (frame is Map) {
      final info = frame['Information'];
      if (info is String) return info;
    }
    return null;
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
