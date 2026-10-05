import 'dart:typed_data';

import 'package:id3_codec/id3_codec.dart';

/// Metadata read from an mp3's ID3v2 tag. Pure Dart — no Flutter
/// dependency — so this module is shared between [MusicLibraryService]'s
/// library scan (which turns it into a [Track]) and the standalone
/// `tool/scan_music_metadata.dart` script, runnable with plain `dart run`
/// without booting the Flutter engine.
class ExtractedTags {
  const ExtractedTags({this.title, this.artist, this.album, this.genre, this.year});

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;

  /// Release year, pulled out of whichever of `TDRC`/`TYER`/`TDOR` is
  /// present.
  final int? year;
}

/// How many bytes of a file's head to read when looking for an ID3v2 tag.
/// Large enough for typical tags (including small embedded art); a file
/// whose tag runs past this is simply scanned without tags rather than
/// reading the whole file for every track.
const int id3ReadCap = 1024 * 1024;

/// Decodes the ID3v2 text frames this app cares about (title/artist/album/
/// genre/year) out of an mp3's head bytes. Returns an all-null
/// [ExtractedTags] when nothing decodes — never throws.
ExtractedTags decodeMp3Tags(Uint8List headBytes) {
  try {
    final tagMap = <String, dynamic>{};
    for (final info in ID3Decoder(headBytes).decodeSync()) {
      tagMap.addAll(info.toTagMap());
    }
    return ExtractedTags(
      title: _frameInfo(tagMap, 'TIT2') ?? tagMap['Title'] as String?,
      artist: _frameInfo(tagMap, 'TPE1') ?? tagMap['Artist'] as String?,
      album: _frameInfo(tagMap, 'TALB') ?? tagMap['Album'] as String?,
      genre: _cleanGenre(_frameInfo(tagMap, 'TCON') ?? tagMap['Genre'] as String?),
      year: _parseYear(_frameInfo(tagMap, 'TDRC') ??
          _frameInfo(tagMap, 'TYER') ??
          _frameInfo(tagMap, 'TDOR')),
    );
  } catch (_) {
    return const ExtractedTags();
  }
}

String? _frameInfo(Map<String, dynamic> tagMap, String frameId) {
  final frame = tagMap['Frame[$frameId]'];
  if (frame is Map) {
    final info = frame['Information'];
    if (info is String) return info;
  }
  return null;
}

/// `TCON` sometimes carries an old ID3v1 numeric genre code in parentheses
/// (e.g. `"(17)"` or `"(17)Rock"`) instead of, or alongside, a plain genre
/// name. This strips that wrapper when a name follows it; a bare numeric
/// code is returned as-is rather than resolved against the full ID3v1
/// genre table, which isn't worth it for a field only used to build
/// playlists.
String? _cleanGenre(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final match = RegExp(r'^\((\d+)\)(.*)$').firstMatch(trimmed);
  if (match != null) {
    final name = match.group(2)!.trim();
    return name.isNotEmpty ? name : trimmed;
  }
  return trimmed;
}

/// Pulls a 4-digit year out of a `TYER` (`"2020"`) or `TDRC`/`TDOR`
/// (`"2020-05-01T00:00:00"` or `"2020-05-01"`) frame value.
int? _parseYear(String? raw) {
  if (raw == null) return null;
  final match = RegExp(r'(\d{4})').firstMatch(raw);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
