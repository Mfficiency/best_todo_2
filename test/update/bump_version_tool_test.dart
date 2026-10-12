import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bump_version.dart' as tool;

/// `tool/bump_version.dart` bumps pubspec.yaml + CHANGELOG.md.
void main() {
  group('main', () {
    late Directory temp;
    late String previousCwd;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('bump_version_test');
      previousCwd = Directory.current.path;
      Directory.current = temp;
    });

    tearDown(() {
      Directory.current = previousCwd;
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {
        // Windows can hold the handle briefly; the temp dir is disposable.
      }
    });

    group('BestToDo (default)', () {
      setUp(() {
        File('${temp.path}/pubspec.yaml')
            .writeAsStringSync('name: besttodo\nversion: 0.2.2+293\n');
        File('${temp.path}/CHANGELOG.md').writeAsStringSync(
            '# Changelog\n\n## [0.2.2] - 2026-08-27\n- Did a thing\n');
      });

      test('bumps pubspec.yaml and prepends a CHANGELOG.md entry', () {
        tool.main(['0.2.3+294', 'Added a widget']);

        final pubspec = File('${temp.path}/pubspec.yaml').readAsStringSync();
        expect(pubspec, contains('version: 0.2.3+294'));

        final changelog =
            File('${temp.path}/CHANGELOG.md').readAsStringSync();
        expect(changelog, startsWith('# Changelog\n\n## [0.2.3] - '));
        expect(changelog, contains('- Added a widget'));
        // The previous release is kept below the new one.
        expect(changelog, contains('## [0.2.2] - 2026-08-27\n- Did a thing'));
        expect(changelog.indexOf('0.2.3') < changelog.indexOf('0.2.2'), isTrue);
      });

      test('a bare version carries the build number forward', () {
        tool.main(['0.2.3', 'Added a widget']);

        final pubspec = File('${temp.path}/pubspec.yaml').readAsStringSync();
        expect(pubspec, contains('version: 0.2.3+294'));
      });

      test('is a no-op on the changelog when already at that version', () {
        tool.main(['0.2.2+293', 'Did a thing']);

        final changelog =
            File('${temp.path}/CHANGELOG.md').readAsStringSync();
        // Only the original entry, not a duplicate section.
        expect('## [0.2.2]'.allMatches(changelog).length, 1);
      });

      test('keeps a preamble paragraph above the first release', () {
        File('${temp.path}/CHANGELOG.md').writeAsStringSync(
          '# Changelog\n\n'
          'User-facing changes, newest first.\n\n'
          '## [0.2.2] - 2026-08-27\n'
          '- Did a thing\n',
        );
        tool.main(['0.2.3+294', 'Added a widget']);

        final changelog =
            File('${temp.path}/CHANGELOG.md').readAsStringSync();
        expect(changelog, startsWith('# Changelog\n\n'
            'User-facing changes, newest first.'));
        // New entry sits above the previous release, preamble stays above both.
        expect(
            changelog.indexOf('User-facing changes') <
                changelog.indexOf('0.2.3'),
            isTrue);
        expect(changelog.indexOf('0.2.3') < changelog.indexOf('0.2.2'),
            isTrue);
      });
    });

    test('prints usage and exits when no version is given', () {
      tool.main([]);
      expect(exitCode, 64);
      exitCode = 0;
    });
  });
}
