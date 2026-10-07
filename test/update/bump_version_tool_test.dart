import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/bump_version.dart' as tool;

/// `tool/bump_version.dart` bumps BestToDo's pubspec.yaml + CHANGELOG.md, or
/// — with `--music` — Best Music's own MUSIC_VERSION + CHANGELOG_MUSIC.md
/// instead, since the two apps version and changelog independently
/// (CLAUDE.md/SPEC.md §10.6f).
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

      test('never touches MUSIC_VERSION or CHANGELOG_MUSIC.md', () {
        tool.main(['0.2.3+294', 'Added a widget']);

        expect(File('${temp.path}/MUSIC_VERSION').existsSync(), isFalse);
        expect(
            File('${temp.path}/CHANGELOG_MUSIC.md').existsSync(), isFalse);
      });
    });

    group('--music', () {
      setUp(() {
        File('${temp.path}/MUSIC_VERSION')
            .writeAsStringSync('version: 0.2.80+371\n');
        File('${temp.path}/CHANGELOG_MUSIC.md').writeAsStringSync(
          '# Best Music Changelog\n\n'
          "Best Music's own changelog, split from BestToDo's.\n\n"
          '## [0.2.80] - 2026-09-18\n'
          '- Best Music now keeps its own changelog\n',
        );
        // A --music run must never touch BestToDo's own files.
        File('${temp.path}/pubspec.yaml')
            .writeAsStringSync('name: besttodo\nversion: 0.2.2+293\n');
        File('${temp.path}/CHANGELOG.md').writeAsStringSync(
            '# Changelog\n\n## [0.2.2] - 2026-08-27\n- Did a thing\n');
      });

      test('bumps MUSIC_VERSION and prepends a CHANGELOG_MUSIC.md entry', () {
        tool.main(['0.2.81+372', 'Added playlist sorting', '--music']);

        final versionFile =
            File('${temp.path}/MUSIC_VERSION').readAsStringSync();
        expect(versionFile.trim(), 'version: 0.2.81+372');

        final changelog =
            File('${temp.path}/CHANGELOG_MUSIC.md').readAsStringSync();
        expect(changelog, contains('## [0.2.81] - '));
        expect(changelog, contains('- Added playlist sorting'));
      });

      test('keeps the preamble paragraph above the first release', () {
        tool.main(['0.2.81+372', 'Added playlist sorting', '--music']);

        final changelog =
            File('${temp.path}/CHANGELOG_MUSIC.md').readAsStringSync();
        expect(changelog, startsWith('# Best Music Changelog\n\n'
            "Best Music's own changelog, split from BestToDo's."));
        // New entry sits above the previous release, preamble stays above both.
        expect(
            changelog.indexOf("Best Music's own changelog") <
                changelog.indexOf('0.2.81'),
            isTrue);
        expect(changelog.indexOf('0.2.81') < changelog.indexOf('0.2.80'),
            isTrue);
      });

      test('leaves pubspec.yaml and CHANGELOG.md untouched', () {
        tool.main(['0.2.81+372', 'Added playlist sorting', '--music']);

        final pubspec = File('${temp.path}/pubspec.yaml').readAsStringSync();
        expect(pubspec, contains('version: 0.2.2+293'));
        final changelog =
            File('${temp.path}/CHANGELOG.md').readAsStringSync();
        expect(changelog, isNot(contains('0.2.81')));
      });
    });

    test('prints usage and exits when no version is given', () {
      tool.main([]);
      expect(exitCode, 64);
      exitCode = 0;
    });
  });
}
