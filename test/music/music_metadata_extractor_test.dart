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

    test('reads the ID3v2.3 text frames (id3_codec\'s "Frames" list shape)',
        () {
      List<int> frame(String id, String text) {
        final data = [0, ...text.codeUnits];
        return [...id.codeUnits, 0, 0, 0, data.length, 0, 0, ...data];
      }

      final body = [
        ...frame('TIT2', 'My Song'),
        ...frame('TPE1', 'Band'),
        ...frame('TALB', 'LP'),
        ...frame('TCON', '(17)Rock'),
        ...frame('TYER', '1999'),
        ...frame('TBPM', '127.6'),
        ...List.filled(32, 0),
      ];
      final n = body.length;
      final tags = decodeMp3Tags(Uint8List.fromList([
        0x49, 0x44, 0x33, 3, 0, 0, //
        (n >> 21) & 0x7f, (n >> 14) & 0x7f, (n >> 7) & 0x7f, n & 0x7f,
        ...body,
        ...List.filled(200, 0xAB), // "audio"
      ]));
      expect(tags.title, 'My Song');
      expect(tags.artist, 'Band');
      expect(tags.album, 'LP');
      expect(tags.genre, 'Rock');
      expect(tags.year, 1999);
      expect(tags.bpm, 128);
    });
  });
}
