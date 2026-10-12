import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/vendoring.dart';

void main() {
  test('sha256 test vectors', () {
    expect(
      sha256Hex(const []),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      sha256Hex(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      sha256Hex(
        utf8.encode('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
      ),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
    expect(
      sha256Hex(List.filled(1000000, 0x61)),
      'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
    );
  });

  test('CR bytes do not count (Windows checkouts)', () {
    expect(
        fileHash(utf8.encode('a\r\nb\r\n')), fileHash(utf8.encode('a\nb\n')));
  });

  group('vendoredCopyProblems', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('vendored');
      File('${dir.path}/lib/a.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('a\n');
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
      File('${dir.path}/ORIGIN').writeAsStringSync(
        'commit: abc\n'
        '${fileHash(utf8.encode('a\n'))}  lib/a.dart\n'
        '${fileHash(utf8.encode('name: x\n'))}  pubspec.yaml\n',
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('an untouched copy has none; tool folders are ignored', () {
      File('${dir.path}/.dart_tool/x').createSync(recursive: true);
      File('${dir.path}/pubspec.lock').writeAsStringSync('');
      expect(vendoredCopyProblems(dir), isEmpty);
    });

    test('a hand edit, a new file and a deleted one are reported', () {
      File('${dir.path}/lib/a.dart').writeAsStringSync('b\n');
      File('${dir.path}/lib/new.dart').writeAsStringSync('');
      File('${dir.path}/pubspec.yaml').deleteSync();
      expect(
          vendoredCopyProblems(dir),
          [
            'lib/a.dart: changed by hand',
            'lib/new.dart: not in the template (added by hand?)',
            'pubspec.yaml: missing',
          ]..sort());
    });

    test('no ORIGIN', () {
      File('${dir.path}/ORIGIN').deleteSync();
      expect(vendoredCopyProblems(dir).single, contains('ORIGIN is missing'));
    });
  });
}
