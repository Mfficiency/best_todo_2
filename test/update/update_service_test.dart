import 'dart:convert';

import 'package:besttodo/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure logic of the in-app updater: version comparison, tag parsing and the
/// release-JSON → [UpdateInfo] mapping. Network and installer are platform
/// seams covered by `about_page_update_test.dart` (via [fetchOverride]) and
/// on hardware.
void main() {
  setUp(UpdateService.resetForTest);

  group('compareVersions', () {
    test('orders by major/minor/patch then build', () {
      expect(UpdateService.compareVersions('0.1.132+104', '0.1.131+103') > 0,
          isTrue);
      expect(UpdateService.compareVersions('0.1.131+103', '0.1.132+104') < 0,
          isTrue);
      expect(
          UpdateService.compareVersions('0.1.131+103', '0.1.131+103'), 0);
      expect(UpdateService.compareVersions('0.2.0+1', '0.1.999+999') > 0,
          isTrue);
      expect(UpdateService.compareVersions('1.0.0+1', '0.9.9+99') > 0, isTrue);
    });

    test('same core version, higher build wins', () {
      expect(
          UpdateService.compareVersions('0.1.131+104', '0.1.131+103') > 0,
          isTrue);
    });

    test('missing build number counts as 0', () {
      expect(
          UpdateService.compareVersions('0.1.131', '0.1.131+1') < 0, isTrue);
    });

    test('unparseable version compares as all-zero', () {
      expect(UpdateService.versionNumbers('unknown'), isEmpty);
      expect(UpdateService.compareVersions('0.1.1+1', 'unknown') > 0, isTrue);
    });
  });

  group('versionFromTag', () {
    test('converts the git-safe dash back into +', () {
      expect(UpdateService.versionFromTag('v0.1.74-45'), '0.1.74+45');
      expect(UpdateService.versionFromTag('v0.1.132-104'), '0.1.132+104');
    });

    test('tolerates a plain version tag', () {
      expect(UpdateService.versionFromTag('v0.1.74'), '0.1.74');
      expect(UpdateService.versionFromTag('0.1.74+45'), '0.1.74+45');
    });
  });

  group('releaseInfo', () {
    test('picks the APK asset and the release fields', () {
      final info = UpdateService.releaseInfo({
        'tag_name': 'v0.1.74-45',
        'name': 'BestToDo 0.1.74+45',
        'html_url': 'https://github.com/Mfficiency/best_todo_2/releases/tag/v0.1.74-45',
        'body': '- fixed things',
        'assets': [
          {'name': 'notes.txt', 'browser_download_url': 'https://x/notes.txt'},
          {
            'name': 'BestToDo-0.1.74+45.apk',
            'browser_download_url': 'https://x/BestToDo-0.1.74+45.apk',
            'size': 55005616,
          },
        ],
      });
      expect(info.version, '0.1.74+45');
      expect(info.releaseName, 'BestToDo 0.1.74+45');
      expect(info.apkUrl, 'https://x/BestToDo-0.1.74+45.apk');
      expect(info.apkSizeBytes, 55005616);
      expect(info.body, '- fixed things');
    });

    test('release without an APK asset still parses', () {
      final info = UpdateService.releaseInfo({
        'tag_name': 'v0.1.74-45',
        'assets': <dynamic>[],
      });
      expect(info.apkUrl, isNull);
      expect(info.releaseName, 'v0.1.74-45');
      expect(info.htmlUrl, contains('github.com'));
    });
  });

  group('checkForUpdate', () {
    String releaseJson(String tag) => jsonEncode({
          'tag_name': tag,
          'name': 'BestToDo release',
          'html_url': 'https://example.com/release',
          'assets': [
            {
              'name': 'BestToDo.apk',
              'browser_download_url': 'https://example.com/BestToDo.apk',
              'size': 1000,
            },
          ],
        });

    test('newer release is reported', () async {
      UpdateService.instance.fetchOverride =
          (url) async => releaseJson('v0.1.132-104');
      final info = await UpdateService.instance
          .checkForUpdate(currentVersion: '0.1.131+103');
      expect(info, isNotNull);
      expect(info!.version, '0.1.132+104');
    });

    test('same or older release means up to date', () async {
      UpdateService.instance.fetchOverride =
          (url) async => releaseJson('v0.1.131-103');
      expect(
          await UpdateService.instance
              .checkForUpdate(currentVersion: '0.1.131+103'),
          isNull);
      expect(
          await UpdateService.instance
              .checkForUpdate(currentVersion: '0.1.132+104'),
          isNull);
    });

    test('queries the latest-release endpoint of the app repo', () async {
      Uri? requested;
      UpdateService.instance.fetchOverride = (url) async {
        requested = url;
        return releaseJson('v0.1.1-1');
      };
      await UpdateService.instance.checkForUpdate(currentVersion: '9.9.9+9');
      expect(requested.toString(),
          'https://api.github.com/repos/Mfficiency/best_todo_2/releases/latest');
    });

    test('malformed payload throws instead of pretending up-to-date',
        () async {
      UpdateService.instance.fetchOverride = (url) async => '[]';
      expect(
          () => UpdateService.instance
              .checkForUpdate(currentVersion: '0.1.131+103'),
          throwsA(isA<FormatException>()));
    });
  });
}
