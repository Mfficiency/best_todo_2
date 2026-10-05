import 'dart:convert';
import 'dart:io';

import '../models/music_playlist.dart';
import '../models/track.dart';
import 'music_library_service.dart';
import 'music_playlist_service.dart';

/// Result of importing an M3U/M3U8 file: the created [MusicPlaylist] plus
/// which entries in the file could and couldn't be matched to a track in
/// the scanned library.
class M3uImportResult {
  final MusicPlaylist playlist;
  final int matchedCount;
  final List<String> unmatchedEntries;

  const M3uImportResult({
    required this.playlist,
    required this.matchedCount,
    required this.unmatchedEntries,
  });
}

/// Imports an M3U/M3U8 playlist file — the format Samsung Music (and most
/// other music apps) produces when you share/export a playlist — as a new
/// [MusicPlaylist].
///
/// Entries are matched against the already-scanned local library, in order:
///  1. by exact file path (normalized, so `\` vs `/` doesn't matter),
///  2. by file basename, case- and extension-insensitive — the common case,
///     since a playlist made on another device/app rarely carries the exact
///     path this app's configured music folder uses.
/// An entry matching neither is skipped and reported back so the UI can
/// show what didn't make it in (e.g. a track that isn't under the
/// configured music folder at all).
class M3uPlaylistService {
  M3uPlaylistService._();

  static Future<M3uImportResult> importFile(File file) async {
    final content = await file.readAsString();
    final entries = parseEntries(content);
    final library = MusicLibraryService.instance.tracks.value;

    final byPath = <String, Track>{
      for (final t in library)
        if (t.filePath != null)
          MusicLibraryService.normalizePath(t.filePath!): t,
    };
    final byBaseName = <String, Track>{};
    for (final t in library) {
      byBaseName.putIfAbsent(t.fileBaseName.toLowerCase(), () => t);
    }

    final matchedIds = <String>[];
    final unmatched = <String>[];
    for (final entry in entries) {
      final path = _toFilePath(entry);
      final direct = byPath[MusicLibraryService.normalizePath(path)];
      if (direct != null) {
        matchedIds.add(direct.id);
        continue;
      }
      final baseNameMatch =
          byBaseName[MusicLibraryService.baseNameOf(path).toLowerCase()];
      if (baseNameMatch != null) {
        matchedIds.add(baseNameMatch.id);
        continue;
      }
      unmatched.add(entry);
    }

    final name = _titleFromFileName(file.path);
    final playlist =
        await MusicPlaylistService.instance.createPlaylist(name, matchedIds);
    return M3uImportResult(
      playlist: playlist,
      matchedCount: matchedIds.length,
      unmatchedEntries: unmatched,
    );
  }

  /// Extracts the playable file paths/URLs from raw M3U/M3U8 text, in
  /// order, skipping blank lines, comments and `#EXT...` directives.
  static List<String> parseEntries(String content) {
    final withoutBom = content.replaceFirst('﻿', '');
    final entries = <String>[];
    for (final rawLine in const LineSplitter().convert(withoutBom)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      entries.add(line);
    }
    return entries;
  }

  static String _toFilePath(String entry) {
    if (entry.startsWith('file://')) {
      try {
        return Uri.parse(entry).toFilePath();
      } catch (_) {
        return entry;
      }
    }
    return entry;
  }

  static String _titleFromFileName(String path) {
    final base = MusicLibraryService.baseNameOf(path);
    return base.isEmpty ? 'Imported playlist' : base;
  }
}
