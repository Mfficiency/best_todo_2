import 'package:flutter_test/flutter_test.dart';

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
}
