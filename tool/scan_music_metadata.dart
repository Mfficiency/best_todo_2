// Standalone metadata scan: walks a music folder (recursively) and prints a
// JSON array of {path, title, artist, album, genre, year} for every
// supported audio file, reading ID3 tags for mp3s through the very same
// `decodeMp3Tags`/`id3ReadCap` from lib/services/music_metadata_extractor.dart
// that `MusicLibraryService`'s own in-app scan uses — so this always shows
// exactly what the app itself would extract, without opening it.
//
// Useful to sanity-check a whole collection's metadata coverage (which
// files actually have a readable genre/year) before relying on it to build
// rule-based playlists. Pure Dart — no Flutter dependency — so it runs with
// plain `dart run`, not `flutter run`/`flutter test`:
//
//   dart run tool/scan_music_metadata.dart "/path/to/Music"
//   dart run tool/scan_music_metadata.dart "/path/to/Music" --out metadata.json
//
// With no --out, the JSON is printed to stdout; a summary line (files
// scanned, how many had genre/year) always goes to stderr so it doesn't mix
// into piped/redirected JSON output.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:besttodo/services/music_metadata_extractor.dart';

const Set<String> _supportedExtensions = {
  'mp3',
  'm4a',
  'flac',
  'wav',
  'ogg',
  'aac',
  'wma',
};

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return '';
  return path.substring(dot + 1).toLowerCase();
}

String _baseNameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  final name = slash >= 0 ? normalized.substring(slash + 1) : normalized;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

Future<Map<String, dynamic>> _scanFile(File file, String ext) async {
  final fallbackTitle = _baseNameOf(file.path);
  if (ext != 'mp3') {
    // Matches MusicLibraryService._buildTrack: only mp3 gets ID3 tag reads
    // today, everything else falls back to its filename.
    return {'path': file.path, 'title': fallbackTitle, 'extension': ext};
  }
  try {
    final raf = await file.open();
    final length = await raf.length();
    final headBytes = await raf.read(min(length, id3ReadCap));
    await raf.close();
    final tags = decodeMp3Tags(headBytes);
    return {
      'path': file.path,
      'title': (tags.title != null && tags.title!.trim().isNotEmpty)
          ? tags.title!.trim()
          : fallbackTitle,
      if ((tags.artist ?? '').trim().isNotEmpty) 'artist': tags.artist!.trim(),
      if ((tags.album ?? '').trim().isNotEmpty) 'album': tags.album!.trim(),
      if ((tags.genre ?? '').trim().isNotEmpty) 'genre': tags.genre!.trim(),
      if (tags.year != null) 'year': tags.year,
    };
  } catch (e) {
    return {'path': file.path, 'title': fallbackTitle, 'error': '$e'};
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
        'Usage: dart run tool/scan_music_metadata.dart <folder> [--out <file.json>]');
    exitCode = 64;
    return;
  }
  final root = args.first;
  String? outPath;
  final outIndex = args.indexOf('--out');
  if (outIndex >= 0 && outIndex + 1 < args.length) outPath = args[outIndex + 1];

  final rootDir = Directory(root);
  if (!await rootDir.exists()) {
    stderr.writeln('Folder not found: $root');
    exitCode = 1;
    return;
  }

  final results = <Map<String, dynamic>>[];
  var scanned = 0;
  var withMetadata = 0;
  await for (final entity
      in rootDir.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final ext = _extensionOf(entity.path);
    if (!_supportedExtensions.contains(ext)) continue;
    scanned++;
    final entry = await _scanFile(entity, ext);
    if (entry.containsKey('genre') || entry.containsKey('year')) {
      withMetadata++;
    }
    results.add(entry);
  }
  results.sort((a, b) =>
      (a['path'] as String).compareTo(b['path'] as String));

  final json = const JsonEncoder.withIndent('  ').convert(results);
  if (outPath != null) {
    await File(outPath).writeAsString(json);
    stderr.writeln('Wrote ${results.length} track(s) to $outPath');
  } else {
    stdout.writeln(json);
  }
  stderr.writeln(
      'Scanned $scanned file(s), $withMetadata with genre and/or year metadata.');
}
