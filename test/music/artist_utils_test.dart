import 'package:besttodo/utils/artist_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitArtistCredit', () {
    test('splits on "feat."', () {
      final credit = splitArtistCredit('49th & Main feat. SKYLAR');
      expect(credit.mainArtist, '49th & Main');
      expect(credit.featuring, 'SKYLAR');
    });

    test('splits on "feat" without a trailing period', () {
      final credit = splitArtistCredit('50 Cent feat Justin Timberlake');
      expect(credit.mainArtist, '50 Cent');
      expect(credit.featuring, 'Justin Timberlake');
    });

    test('splits on "ft." and "ft"', () {
      expect(splitArtistCredit('Artist ft. Other').mainArtist, 'Artist');
      expect(splitArtistCredit('Artist ft Other').mainArtist, 'Artist');
    });

    test('splits on "featuring", case-insensitively', () {
      final credit = splitArtistCredit('Artist FEATURING Other');
      expect(credit.mainArtist, 'Artist');
      expect(credit.featuring, 'Other');
    });

    test('an artist with no featuring marker returns an empty featuring',
        () {
      final credit = splitArtistCredit('50 Cent');
      expect(credit.mainArtist, '50 Cent');
      expect(credit.featuring, isEmpty);
    });

    test('trims surrounding whitespace', () {
      final credit = splitArtistCredit('  Artist  feat.  Other  ');
      expect(credit.mainArtist, 'Artist');
      expect(credit.featuring, 'Other');
    });
  });
}
