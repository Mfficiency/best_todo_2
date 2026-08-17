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

  group('github_releases folder listing', () {
    test('reads the version out of the APK file name', () {
      expect(UpdateService.versionFromApkFileName('best_todo_0.1.143+115.apk'),
          '0.1.143+115');
      expect(UpdateService.versionFromApkFileName('BestToDo-0.1.74+45.apk'),
          '0.1.74+45');
      expect(UpdateService.versionFromApkFileName('README.md'), isNull);
      expect(UpdateService.versionFromApkFileName('app-release.apk'), isNull);
    });

    test('maps the listing to builds, newest first', () {
      final builds = UpdateService.folderReleases([
        {'name': 'README.md', 'download_url': 'https://x/README.md'},
        {
          'name': 'best_todo_0.1.142+114.apk',
          'download_url': 'https://x/best_todo_0.1.142%2B114.apk',
          'size': 60803503,
        },
        {
          'name': 'best_todo_0.1.143+115.apk',
          'download_url': 'https://x/best_todo_0.1.143%2B115.apk',
          'size': 60803674,
        },
      ]);
      expect(builds.map((b) => b.version), ['0.1.143+115', '0.1.142+114']);
      expect(builds.first.apkUrl, 'https://x/best_todo_0.1.143%2B115.apk');
      expect(builds.first.apkSizeBytes, 60803674);
      expect(builds.first.source, UpdateSource.repoFolder);
      expect(builds.first.releaseName, 'BestToDo 0.1.143+115');
    });

    test('skips entries without a download url', () {
      expect(
          UpdateService.folderReleases([
            {'name': 'best_todo_0.1.143+115.apk'},
          ]),
          isEmpty);
    });
  });

  group('checkReleases', () {
    String folderJson(List<String> versions) => jsonEncode([
          {'name': 'README.md', 'download_url': 'https://x/README.md'},
          for (final v in versions)
            {
              'name': 'best_todo_$v.apk',
              'download_url': 'https://x/best_todo_$v.apk',
              'size': 60000000,
            },
        ]);

    test('offers the newest folder build and the one before it', () async {
      UpdateService.instance.fetchOverride =
          (url) async => folderJson(['0.1.142+114', '0.1.143+115']);
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.1.142+114');
      expect(check.hasUpdate, isTrue);
      expect(check.latest!.version, '0.1.143+115');
      expect(check.previous!.version, '0.1.142+114');
      // The older kept build is the running version — nothing to roll back to.
      expect(check.rollback, isNull);
    });

    test('up to date still offers a rollback to the kept older build',
        () async {
      UpdateService.instance.fetchOverride =
          (url) async => folderJson(['0.1.142+114', '0.1.143+115']);
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.1.143+115');
      expect(check.hasUpdate, isFalse);
      expect(check.rollback!.version, '0.1.142+114');
    });

    test('a folder with a single build has no rollback', () async {
      UpdateService.instance.fetchOverride =
          (url) async => folderJson(['0.1.143+115']);
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.1.143+115');
      expect(check.previous, isNull);
      expect(check.rollback, isNull);
    });

    test('reads the folder of the release branch first', () async {
      final requested = <String>[];
      UpdateService.instance.fetchOverride = (url) async {
        requested.add(url.toString());
        return folderJson(['0.1.143+115']);
      };
      await UpdateService.instance.checkReleases(currentVersion: '0.1.1+1');
      expect(requested, [
        'https://api.github.com/repos/Mfficiency/best_todo_2/contents/'
            'github_releases?ref=dev',
      ]);
    });

    test('falls back to the latest release when the folder is unavailable',
        () async {
      final requested = <String>[];
      UpdateService.instance.fetchOverride = (url) async {
        requested.add(url.toString());
        if (url.toString().contains('/contents/')) {
          throw Exception('404 — no folder on this branch');
        }
        return jsonEncode({
          'tag_name': 'v0.1.144-116',
          'name': 'BestToDo 0.1.144+116',
          'html_url': 'https://example.com/release',
          'assets': [
            {
              'name': 'BestToDo-0.1.144+116.apk',
              'browser_download_url': 'https://example.com/BestToDo.apk',
              'size': 1000,
            },
          ],
        });
      };
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.1.143+115');
      expect(requested.length, 2);
      expect(check.latest!.version, '0.1.144+116');
      expect(check.latest!.source, UpdateSource.githubRelease);
      expect(check.previous, isNull);
      expect(check.hasUpdate, isTrue);
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
