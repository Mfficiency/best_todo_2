import 'dart:typed_data';

import 'package:besttodo/services/music_metadata_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeMp3Tags', () {
    test('never throws and returns all-null tags for bytes with no ID3 tag',
        () {
      final tags = decodeMp3Tags(Uint8List.fromList([0, 0, 0]));

      expect(tags.title, isNull);
      expect(tags.artist, isNull);
      expect(tags.album, isNull);
      expect(tags.genre, isNull);
      expect(tags.year, isNull);
    });

    test('never throws on an empty byte list', () {
      expect(() => decodeMp3Tags(Uint8List(0)), returnsNormally);
    });
  });
}
