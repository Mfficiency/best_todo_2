import 'package:besttodo/services/track_title.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseTrackTitle', () {
    test('splits "Artist - Title" and strips an official-video annotation',
        () {
      final r = parseTrackTitle(
        'Rick Astley - Never Gonna Give You Up (Official Music Video)',
        'Rick Astley',
      );
      expect(r.artist, 'Rick Astley');
      expect(r.title, 'Never Gonna Give You Up');
      expect(r.fileBaseName, 'Rick Astley - Never Gonna Give You Up');
    });

    test('strips a (Lyrics) annotation', () {
      final r = parseTrackTitle('Artist - Song Title (Lyrics)', 'Artist');
      expect(r.title, 'Song Title');
    });

    test('strips an [Official Video] bracketed annotation', () {
      final r = parseTrackTitle('Artist - Song Title [Official Video]', 'x');
      expect(r.title, 'Song Title');
    });

    test('strips stacked annotations', () {
      final r =
          parseTrackTitle('Artist - Title (HD) (Official Video)', 'Chan');
      expect(r.title, 'Title');
    });

    test('keeps an annotation that is not just promotional filler', () {
      final r =
          parseTrackTitle('Artist - Title (Live at Wembley)', 'Chan');
      expect(r.title, 'Title (Live at Wembley)');
      final r2 =
          parseTrackTitle('Artist - Title (feat. Other Artist)', 'Chan');
      expect(r2.title, 'Title (feat. Other Artist)');
    });

    test('falls back to the channel as artist when there is no separator',
        () {
      final r = parseTrackTitle('Song Without A Dash', 'Cool Artist - Topic');
      expect(r.artist, 'Cool Artist');
      expect(r.title, 'Song Without A Dash');
      expect(r.fileBaseName, 'Cool Artist - Song Without A Dash');
    });

    test('handles en dash and em dash separators', () {
      expect(parseTrackTitle('Artist – Title (4K)', 'Chan').fileBaseName,
          'Artist - Title');
      expect(
          parseTrackTitle('Artist — Title', 'Chan').fileBaseName,
          'Artist - Title');
    });

    test('a title with no artist at all is left as just the title', () {
      final r = parseTrackTitle('Just A Title', '');
      expect(r.artist, isEmpty);
      expect(r.fileBaseName, 'Just A Title');
    });

    test('blank title falls back to "audio" rather than an empty name', () {
      final r = parseTrackTitle('   ', 'Chan');
      expect(r.title, 'audio');
      expect(r.fileBaseName, 'Chan - audio');
    });
  });

  group('formatTrackFileBaseName', () {
    test('matches parseTrackTitle().fileBaseName', () {
      expect(
        formatTrackFileBaseName(
            'ABBA - Mamma Mia (Official Video)', 'ABBAVEVO'),
        'ABBA - Mamma Mia',
      );
    });
  });
}
