import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_metadata_csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MusicMetadataCsv.encode', () {
    test('writes a header row followed by one row per track', () {
      final csv = MusicMetadataCsv.encode([
        Track.local(
          filePath: '/music/song.mp3',
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          genre: 'Rock',
          year: 2021,
        ),
      ]);

      final lines = csv.split('\r\n');
      expect(lines[0], 'id,filename,title,artist,album,genre,year');
      expect(lines[1], 'local:/music/song.mp3,song,Song,Artist,Album,Rock,2021');
    });

    test('leaves genre/year empty for a track with no known value', () {
      final csv = MusicMetadataCsv.encode([
        Track.local(filePath: '/music/untagged.mp3', title: 'untagged'),
      ]);

      final lines = csv.split('\r\n');
      expect(lines[1], 'local:/music/untagged.mp3,untagged,untagged,,,,');
    });

    test('quotes a field containing a comma', () {
      final csv = MusicMetadataCsv.encode([
        Track.local(
          filePath: '/a.mp3',
          title: 'Song, Reprise',
          artist: 'Artist',
        ),
      ]);

      expect(csv, contains('"Song, Reprise"'));
    });

    test('an empty track list still writes just the header row', () {
      final csv = MusicMetadataCsv.encode(const []);
      expect(csv.trim(), 'id,filename,title,artist,album,genre,year');
    });
  });

  group('MusicMetadataCsv.decode', () {
    test('round-trips what encode wrote', () {
      final tracks = [
        Track.local(
          filePath: '/a.mp3',
          title: 'A',
          artist: 'Artist A',
          album: 'Album A',
          genre: 'Rock',
          year: 2020,
        ),
        Track.local(filePath: '/b.mp3', title: 'b'),
      ];

      final rows = MusicMetadataCsv.decode(MusicMetadataCsv.encode(tracks));

      expect(rows, hasLength(2));
      expect(rows[0].id, 'local:/a.mp3');
      expect(rows[0].title, 'A');
      expect(rows[0].artist, 'Artist A');
      expect(rows[0].album, 'Album A');
      expect(rows[0].genre, 'Rock');
      expect(rows[0].year, 2020);
      expect(rows[1].id, 'local:/b.mp3');
      expect(rows[1].genre, '');
      expect(rows[1].year, isNull);
    });

    test('handles quoted fields containing commas and escaped quotes', () {
      const csv = 'id,filename,title,artist,album,genre,year\r\n'
          '"local:/a.mp3",a,"Song, ""Reprise""",Artist,Album,Rock,2020\r\n';

      final rows = MusicMetadataCsv.decode(csv);

      expect(rows, hasLength(1));
      expect(rows.single.title, 'Song, "Reprise"');
    });

    test('looks columns up by header name, tolerating reordering', () {
      const csv = 'genre,id,year,title\r\n'
          'Jazz,local:/a.mp3,1999,A Song\r\n';

      final rows = MusicMetadataCsv.decode(csv);

      expect(rows.single.id, 'local:/a.mp3');
      expect(rows.single.genre, 'Jazz');
      expect(rows.single.year, 1999);
      expect(rows.single.title, 'A Song');
      // Columns this header doesn't have at all come back blank.
      expect(rows.single.artist, '');
    });

    test('skips rows with a blank id', () {
      const csv = 'id,title\r\n,No Id\r\nlocal:/a.mp3,Has Id\r\n';

      final rows = MusicMetadataCsv.decode(csv);

      expect(rows, hasLength(1));
      expect(rows.single.id, 'local:/a.mp3');
    });

    test('an unparsable year comes back null rather than throwing', () {
      const csv = 'id,year\r\nlocal:/a.mp3,not-a-year\r\n';

      final rows = MusicMetadataCsv.decode(csv);

      expect(rows.single.year, isNull);
    });

    test('tolerates a missing trailing newline', () {
      const csv = 'id,title\r\nlocal:/a.mp3,A';

      final rows = MusicMetadataCsv.decode(csv);

      expect(rows, hasLength(1));
      expect(rows.single.title, 'A');
    });

    test('bare LF line endings also work, not just CRLF', () {
      const csv = 'id,title\nlocal:/a.mp3,A\nlocal:/b.mp3,B\n';

      final rows = MusicMetadataCsv.decode(csv);

      expect(rows, hasLength(2));
      expect(rows[1].id, 'local:/b.mp3');
    });

    test('a file with no id column yields no rows', () {
      const csv = 'title,artist\r\nA,Artist\r\n';

      expect(MusicMetadataCsv.decode(csv), isEmpty);
    });

    test('an empty string decodes to no rows', () {
      expect(MusicMetadataCsv.decode(''), isEmpty);
    });
  });
}
