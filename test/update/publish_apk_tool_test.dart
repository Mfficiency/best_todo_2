import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/services/app_updates.dart';

import '../../tool/publish_apk.dart' as publish_tool;

/// Pure helpers of `tool/publish_apk.dart` — the naming conventions the
/// in-app updater relies on (tag ↔ version mapping) and the changelog
/// extraction that becomes the release notes. The upload itself needs a
/// token + network and is exercised manually.
void main() {
  test('release naming matches the historical convention', () {
    expect(publish_tool.releaseTagFor('0.1.132+104'), 'v0.1.132-104');
    expect(publish_tool.releaseNameFor('0.1.132+104'), 'BestToDo 0.1.132+104');
    expect(publish_tool.assetNameFor('0.1.132+104'), 'BestToDo-0.1.132+104.apk');
  });

  test('reads the version line from a pubspec body', () {
    expect(
        publish_tool.readPubspecVersion(
            'name: besttodo\nversion: 0.1.132+104\n\nenvironment:\n'),
        '0.1.132+104');
    expect(publish_tool.readPubspecVersion('name: besttodo\n'), isNull);
  });

  test('firstChangelogSection returns only the newest entry', () {
    const changelog = '# Changelog\n'
        '\n'
        '## [0.1.132] - 2026-08-06\n'
        '- In-app updates\n'
        '- Something else\n'
        '\n'
        '## [0.1.131] - 2026-08-06\n'
        '- Older entry\n';
    final section = publish_tool.firstChangelogSection(changelog);
    expect(section, startsWith('## [0.1.132]'));
    expect(section, contains('In-app updates'));
    expect(section, isNot(contains('Older entry')));
  });

  test('firstChangelogSection is empty when no section heading exists', () {
    expect(publish_tool.firstChangelogSection('just text'), '');
  });

  test('APK lookup prefers the version-named artifact from build.sh', () {
    final candidates = publish_tool.apkCandidatePaths('0.1.132+104');
    expect(candidates.first,
        'build/app/outputs/flutter-apk/best_todo_0.1.132+104.apk');
    expect(candidates.last, 'build/app/outputs/flutter-apk/app-release.apk');
  });

  group('channel releases', () {
    test('tags, names and assets carry app and channel', () {
      const v = '0.2.101+12199';
      expect(publish_tool.releaseTagFor(v, channel: 'dev'), 'v0.2.101-12199-dev');
      expect(publish_tool.releaseTagFor(v, channel: 'staging'),
          'v0.2.101-12199-staging');
      expect(publish_tool.releaseTagFor(v), 'v0.2.101-12199');
      expect(
          publish_tool.releaseTagFor(v, app: publish_tool.musicApp),
          'music-v0.2.101-12199');
      expect(
          publish_tool.releaseTagFor(v,
              app: publish_tool.musicApp, channel: 'dev'),
          'music-v0.2.101-12199-dev');
      expect(publish_tool.releaseNameFor(v, channel: 'dev'),
          'BestToDo 0.2.101+12199 (dev)');
      expect(publish_tool.releaseNameFor(v, app: publish_tool.musicApp),
          'Best Music 0.2.101+12199');
      expect(publish_tool.assetNameFor(v, channel: 'staging'),
          'BestToDo-0.2.101+12199-staging.apk');
      expect(publish_tool.assetNameFor(v, app: publish_tool.musicApp),
          'BestMusic-0.2.101+12199.apk');
    });

    test('tags round-trip through the in-app updater', () {
      for (final channel in publish_tool.channels) {
        for (final app in [publish_tool.todoApp, publish_tool.musicApp]) {
          final tag = publish_tool.releaseTagFor('1.2.3+12345',
              app: app, channel: channel);
          // Each app's updater only accepts its own tag prefix.
          final own = app.id == 'music' ? UpdatesApp.music : UpdatesApp.todo;
          final other = own == UpdatesApp.music ? UpdatesApp.todo : UpdatesApp.music;
          expect(matchesTagPrefix(tag, own.tagPrefix), isTrue);
          expect(matchesTagPrefix(tag, other.tagPrefix), isFalse);
          expect(releaseVersion(tag, prefix: own.tagPrefix), '1.2.3');
          expect(releaseBuild(tag, prefix: own.tagPrefix), 12345);
          expect(releaseChannel(tag), channel);
        }
      }
    });

    test('release notes leave out build-meta lines', () {
      const changelog = '## [0.2.100] - 2026-10-07\n'
          '- A user-facing change\n'
          '- CI build: 2026-10-10 17:13 UTC\n'
          '- Build duration (apk, CI): 9m 10s\n'
          '- APK size: 63.9 MB\n'
          '- Local build: 2026-10-07 22:30\n'
          '- Build size (windows): 128.8 MB\n';
      expect(publish_tool.firstChangelogSection(changelog),
          '## [0.2.100] - 2026-10-07\n- A user-facing change');
    });

    test('the footer names channel, commit, branch, duration and size', () {
      final footer = publish_tool.buildFooter(
        channel: 'dev',
        commit: 'abc1234',
        branch: 'dev',
        builtAt: DateTime(2026, 10, 11, 14, 3),
        durationSeconds: 192,
        apkBytes: 64 * 1024 * 1024,
      );
      expect(footer, contains('Channel: dev'));
      expect(footer, contains('`abc1234` (branch `dev`)'));
      expect(footer, contains('2026-10-11 14:03'));
      expect(footer, contains('Build duration: 3m 12s'));
      expect(footer, contains('APK size: 64.0 MB'));
      expect(footer, contains('Built on the laptop'));
    });
  });
}
