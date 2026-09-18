import '../models/track.dart';
import 'usage_data_service.dart';

/// One row of edits parsed back from a re-imported metadata CSV — see
/// [MusicMetadataCsv.decode].
class ParsedMetadataRow {
  const ParsedMetadataRow({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.year,
  });

  /// [Track.id] — the match key. Never edited by whoever filled in the
  /// sheet; a row whose id doesn't match any known track is simply skipped
  /// on import.
  final String id;

  /// Blank ("") means "leave this field alone" for every one of these —
  /// [MusicLibraryService.applyMetadataRows] only overwrites a field when
  /// the imported value is non-empty, so a spreadsheet round-trip that
  /// happens to clear a cell can't silently wipe out a value the app
  /// already had.
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int? year;
}

/// Round-trips track metadata through a CSV a person can hand to an AI (or
/// edit by hand) to fill in whatever [MusicMetadataScanPage] shows as
/// missing, then bring back into the app: [encode] exports every scanned
/// track's current metadata, [decode] reads the edited file back, and
/// [MusicLibraryService.applyMetadataRows] applies it, matching rows to
/// tracks by the `id` column.
class MusicMetadataCsv {
  MusicMetadataCsv._();

  /// Column order [encode] writes and [decode] looks for by name (not
  /// position, so reordering columns in a spreadsheet doesn't break
  /// re-import). `id` and `filename` are there for matching/context only —
  /// the export instructions tell the person filling this in to leave both
  /// alone; `filename` is the one piece of context left when a file has no
  /// tags at all to go on (title/artist/album empty too).
  static const List<String> columns = [
    'id',
    'filename',
    'title',
    'artist',
    'album',
    'genre',
    'year',
  ];

  static String encode(List<Track> tracks) {
    final rows = <List<Object?>>[columns];
    for (final track in tracks) {
      rows.add([
        track.id,
        track.fileBaseName,
        track.title,
        track.artist,
        track.album,
        track.genre,
        track.year,
      ]);
    }
    return UsageDataService.toCsv(rows);
  }

  /// Parses a (possibly hand- or AI-edited) CSV back into rows keyed by
  /// `id`. Tolerates missing/reordered/extra columns (looked up by header
  /// name) and a missing trailing newline; a file with no recognizable
  /// `id` column yields no rows at all rather than guessing.
  static List<ParsedMetadataRow> decode(String csvText) {
    final rows = _parseCsvRows(csvText);
    if (rows.isEmpty) return const [];
    final header = rows.first.map((c) => c.trim().toLowerCase()).toList();
    final idIndex = header.indexOf('id');
    if (idIndex < 0) return const [];
    final titleIndex = header.indexOf('title');
    final artistIndex = header.indexOf('artist');
    final albumIndex = header.indexOf('album');
    final genreIndex = header.indexOf('genre');
    final yearIndex = header.indexOf('year');

    String cell(List<String> row, int index) =>
        (index >= 0 && index < row.length) ? row[index].trim() : '';

    final result = <ParsedMetadataRow>[];
    for (final row in rows.skip(1)) {
      final id = cell(row, idIndex);
      if (id.isEmpty) continue;
      final yearText = cell(row, yearIndex);
      result.add(ParsedMetadataRow(
        id: id,
        title: cell(row, titleIndex),
        artist: cell(row, artistIndex),
        album: cell(row, albumIndex),
        genre: cell(row, genreIndex),
        year: yearText.isEmpty ? null : int.tryParse(yearText),
      ));
    }
    return result;
  }

  /// A small RFC 4180-ish decoder — comma-separated fields, `"`-quoted
  /// fields with doubled-quote escaping, CRLF or bare LF line endings —
  /// the inverse of [UsageDataService.toCsv]/[UsageDataService.csvField].
  static List<List<String>> _parseCsvRows(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var i = 0;
    final length = text.length;

    while (i < length) {
      final char = text[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < length && text[i + 1] == '"') {
            field.write('"');
            i += 2;
          } else {
            inQuotes = false;
            i++;
          }
        } else {
          field.write(char);
          i++;
        }
        continue;
      }
      if (char == '"') {
        inQuotes = true;
        i++;
      } else if (char == ',') {
        row.add(field.toString());
        field.clear();
        i++;
      } else if (char == '\r') {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = [];
        i++;
        if (i < length && text[i] == '\n') i++;
      } else if (char == '\n') {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = [];
        i++;
      } else {
        field.write(char);
        i++;
      }
    }
    // A file ending in a newline (every file this app writes does) leaves
    // both field and row empty here — only flush a trailing partial row
    // for input that doesn't end that way.
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    return rows;
  }
}
