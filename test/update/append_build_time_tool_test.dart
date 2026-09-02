import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/append_build_time.dart' as tool;

/// `tool/append_build_time.dart` notes when a local build finished (and how
/// long it took) in CHANGELOG.md, and appends a duration record to
/// build_history.json. Pure helpers are tested directly.
void main() {
  group('formatBuildTime', () {
    test('zero-pads month/day/hour/minute', () {
      expect(tool.formatBuildTime(DateTime(2026, 1, 5, 7, 3)),
          '2026-01-05 07:03');
    });
  });

  group('formatDuration', () {
    test('seconds only under a minute', () {
      expect(tool.formatDuration(0), '0s');
      expect(tool.formatDuration(45), '45s');
    });

    test('minutes and seconds under an hour', () {
      expect(tool.formatDuration(60), '1m 00s');
      expect(tool.formatDuration(102), '1m 42s');
    });

    test('hours and minutes at an hour or more', () {
      expect(tool.formatDuration(3600), '1h 00m');
      expect(tool.formatDuration(3723), '1h 02m');
    });

    test('clamps a negative duration to zero', () {
      expect(tool.formatDuration(-5), '0s');
    });
  });

  group('withBuildTimeNote', () {
    test('inserts a new line into the newest section', () {
      const changelog = '# Changelog\n\n'
          '## [0.2.0] - 2026-08-27\n'
          '- Did a thing\n\n'
          '## [0.1.0] - 2026-08-01\n'
          '- Older\n';
      final updated = tool.withBuildTimeNote(changelog, '2026-08-27 14:47');
      expect(updated, contains('- Local build: 2026-08-27 14:47'));
      // Only touches the newest section.
      expect(
          updated!.indexOf('- Local build:') <
              updated.indexOf('## [0.1.0]'),
          isTrue);
      expect('## [0.1.0]'.allMatches(updated).length, 1);
    });

    test('replaces an existing line instead of piling up a new one', () {
      const changelog = '## [0.2.0] - 2026-08-27\n'
          '- Local build: 2026-08-27 09:00\n'
          '- Did a thing\n';
      final updated = tool.withBuildTimeNote(changelog, '2026-08-27 14:47');
      expect(updated, isNot(contains('09:00')));
      expect('- Local build:'.allMatches(updated!).length, 1);
    });

    test('returns null when there is no version section', () {
      expect(tool.withBuildTimeNote('# Changelog\n\nnothing here\n', '14:47'),
          isNull);
    });
  });

  group('withBuildDurationNote', () {
    test('keeps a separate line per target', () {
      const changelog = '## [0.2.0] - 2026-08-27\n- Did a thing\n';
      var updated =
          tool.withBuildDurationNote(changelog, 'apk', '1m 42s')!;
      updated = tool.withBuildDurationNote(updated, 'windows', '3m 05s')!;

      expect(updated, contains('- Build duration (apk): 1m 42s'));
      expect(updated, contains('- Build duration (windows): 3m 05s'));
    });

    test('updates the same target in place on a repeat build', () {
      const changelog = '## [0.2.0] - 2026-08-27\n'
          '- Build duration (apk): 2m 00s\n'
          '- Did a thing\n';
      final updated =
          tool.withBuildDurationNote(changelog, 'apk', '1m 30s')!;
      expect(updated, contains('- Build duration (apk): 1m 30s'));
      expect(updated, isNot(contains('2m 00s')));
      expect('- Build duration (apk):'.allMatches(updated).length, 1);
    });
  });

  group('history records', () {
    test('historyRecord captures version/target/duration/timestamp', () {
      final record = tool.historyRecord(
        version: '0.2.2+293',
        target: 'apk',
        durationSeconds: 102,
        finishedAt: DateTime(2026, 8, 27, 14, 47),
      );
      expect(record['version'], '0.2.2+293');
      expect(record['target'], 'apk');
      expect(record['durationSeconds'], 102);
      expect(record['finishedAt'], DateTime(2026, 8, 27, 14, 47).toIso8601String());
      expect(record['os'], isNotEmpty);
    });

    test('appendHistoryRecord caps at maxHistoryEntries, dropping oldest',
        () {
      final history = List.generate(
          tool.maxHistoryEntries, (i) => {'version': '$i'});
      final updated = tool.appendHistoryRecord(history, {'version': 'new'});
      expect(updated.length, tool.maxHistoryEntries);
      expect(updated.last, {'version': 'new'});
      expect(updated.first, {'version': '1'});
    });

    test('appendHistoryRecord just appends below the cap', () {
      final updated = tool.appendHistoryRecord(
          [
            {'version': 'a'}
          ],
          {'version': 'b'});
      expect(updated, [
        {'version': 'a'},
        {'version': 'b'},
      ]);
    });
  });

  group('main', () {
    late Directory temp;
    late String previousCwd;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('append_build_time_test');
      previousCwd = Directory.current.path;
      Directory.current = temp;
      File('${temp.path}/pubspec.yaml')
          .writeAsStringSync('name: besttodo\nversion: 0.2.2+293\n');
      File('${temp.path}/CHANGELOG.md').writeAsStringSync(
          '# Changelog\n\n## [0.2.2] - 2026-08-27\n- Did a thing\n');
    });

    tearDown(() {
      Directory.current = previousCwd;
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {
        // Windows can hold the handle briefly; the temp dir is disposable.
      }
    });

    test('writes the build-time note without a duration', () {
      tool.main([]);

      final changelog = File('${temp.path}/CHANGELOG.md').readAsStringSync();
      expect(changelog, contains('- Local build: '));
      expect(changelog, isNot(contains('Build duration')));
      expect(File('${temp.path}/build_history.json').existsSync(), isFalse);
    });

    test('records the note and history entry when given a duration', () {
      tool.main(['--duration', '102', '--target', 'apk']);

      final changelog = File('${temp.path}/CHANGELOG.md').readAsStringSync();
      expect(changelog, contains('- Local build: '));
      expect(changelog, contains('- Build duration (apk): 1m 42s'));

      final historyFile = File('${temp.path}/build_history.json');
      expect(historyFile.existsSync(), isTrue);
      final history = jsonDecode(historyFile.readAsStringSync()) as List;
      expect(history, hasLength(1));
      expect(history.single['version'], '0.2.2+293');
      expect(history.single['target'], 'apk');
      expect(history.single['durationSeconds'], 102);
    });

    test('appends a second history entry on the next build', () {
      tool.main(['--duration', '102', '--target', 'apk']);
      tool.main(['--duration', '210', '--target', 'windows']);

      final history = jsonDecode(
          File('${temp.path}/build_history.json').readAsStringSync()) as List;
      expect(history, hasLength(2));
      expect(history[0]['target'], 'apk');
      expect(history[1]['target'], 'windows');
    });

    test('a dry run reports without touching either file', () {
      tool.main(['--duration', '102', '--target', 'apk', '--dry-run']);

      final changelog = File('${temp.path}/CHANGELOG.md').readAsStringSync();
      expect(changelog, isNot(contains('Local build')));
      expect(File('${temp.path}/build_history.json').existsSync(), isFalse);
    });
  });
}
