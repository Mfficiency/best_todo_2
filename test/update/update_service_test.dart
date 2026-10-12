import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pure logic of the in-app updater: version comparison, tag parsing and the
/// release-JSON → [UpdateInfo] mapping. Network and installer are platform
/// seams covered by `about_page_update_test.dart` (via [fetchOverride]) and
/// on hardware.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    UpdateService.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

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

  /// A releases-list entry the way the laptop builder publishes them.
  Map<String, dynamic> rel(String tag,
          {bool prerelease = false, bool draft = false, bool withApk = true}) =>
      {
        'tag_name': tag,
        'name': 'release $tag',
        'html_url': 'https://example.com/$tag',
        'prerelease': prerelease,
        'draft': draft,
        'assets': [
          if (withApk)
            {
              'name': '$tag.apk',
              'browser_download_url': 'https://example.com/$tag.apk',
              'size': 1000,
            },
        ],
      };

  /// Both apps × all three channels, mixed up like the real list.
  List<Map<String, dynamic>> mixedReleases() => [
        rel('v0.2.101-12210-dev', prerelease: true),
        rel('music-v0.1.20-12210-dev', prerelease: true),
        rel('v0.2.100-12150-staging', prerelease: true),
        rel('music-v0.1.19-12150-staging', prerelease: true),
        rel('v0.2.99-12100'),
        rel('music-v0.1.18-12100'),
        rel('v0.2.101-12200-dev', prerelease: true),
        rel('v0.2.98-12050'),
        rel('v0.2.97-300'), // a pre-channel release (old scheme)
      ];

  group('ReleaseTag', () {
    test('parses app, version and channel', () {
      final dev = ReleaseTag.parse('v0.2.100-12199-dev')!;
      expect(dev.music, isFalse);
      expect(dev.version, '0.2.100+12199');
      expect(dev.channel, 'dev');
      final staging = ReleaseTag.parse('music-v0.1.5-12000-staging')!;
      expect(staging.music, isTrue);
      expect(staging.version, '0.1.5+12000');
      expect(staging.channel, 'staging');
      final main = ReleaseTag.parse('v0.1.132-104')!;
      expect(main.channel, 'main');
      expect(main.music, isFalse);
    });

    test('rejects tags that are not app builds', () {
      expect(ReleaseTag.parse('v0.1.74'), isNull);
      expect(ReleaseTag.parse('v0.1.74-45-beta'), isNull);
      expect(ReleaseTag.parse('obsidian-1.0.0'), isNull);
    });

    test('versionFromTag strips the app prefix and channel suffix', () {
      expect(UpdateService.versionFromTag('music-v0.1.5-12000-dev'),
          '0.1.5+12000');
      expect(UpdateService.versionFromTag('v0.2.100-12199-staging'),
          '0.2.100+12199');
    });
  });

  group('build numbers', () {
    test('buildNumberOf reads the part after +, else 0', () {
      expect(UpdateService.buildNumberOf('0.2.104+3600000'), 3600000);
      expect(UpdateService.buildNumberOf('0.1.131'), 0);
      expect(UpdateService.buildNumberOf('unknown'), 0);
    });

    test('isNewerBuild compares only the build number', () {
      expect(UpdateService.isNewerBuild('0.1.0+3600001', '9.9.9+3600000'),
          isTrue);
      expect(UpdateService.isNewerBuild('9.9.9+3600000', '0.1.0+3600001'),
          isFalse);
      expect(UpdateService.isNewerBuild('0.3.0+5', '0.2.0+5'), isFalse);
      expect(UpdateService.isNewerBuild('0.1.0+1', 'unknown'), isTrue);
    });
  });

  /// dev, staging and main build the same app: the update check looks at
  /// every channel's releases and takes the highest build number.
  group('release selection over all channels', () {
    List<String> versions(String tagPrefix) =>
        UpdateService.appReleases(mixedReleases(), tagPrefix: tagPrefix)
            .map((b) => b.version)
            .toList();

    test('BestToDo sees dev, staging and main builds, highest build first',
        () {
      expect(versions('v'), [
        '0.2.101+12210', // dev
        '0.2.101+12200', // dev
        '0.2.100+12150', // staging
        '0.2.99+12100', // main
        '0.2.98+12050', // main
        '0.2.97+300', // main, old scheme
      ]);
    });

    test('Best Music sees only music-v tags, of every channel', () {
      expect(versions('music-v'),
          ['0.1.20+12210', '0.1.19+12150', '0.1.18+12100']);
    });

    test('prereleases count, drafts never do', () {
      final list = [
        rel('v0.3.0-13000', prerelease: true),
        rel('v0.3.1-13001', draft: true),
        rel('v0.3.1-13002-dev', prerelease: true, draft: true),
        rel('v0.3.1-12500-staging', prerelease: true),
        rel('v0.2.0-12000'),
      ];
      expect(
          UpdateService.appReleases(list, tagPrefix: 'v').map((b) => b.version),
          ['0.3.0+13000', '0.3.1+12500', '0.2.0+12000']);
    });

    test('the build number decides, not x.y.z (equal numbers: x.y.z)', () {
      final list = [
        rel('v0.2.110-3600000-dev', prerelease: true),
        rel('v0.2.104-3600100'),
        rel('v0.2.9-12999'),
        rel('v0.2.10-12999-staging', prerelease: true),
      ];
      expect(
          UpdateService.appReleases(list, tagPrefix: 'v').map((b) => b.version),
          ['0.2.104+3600100', '0.2.110+3600000', '0.2.10+12999', '0.2.9+12999']);
    });
  });

  group('checkReleases', () {
    test('queries the releases list, not releases/latest', () async {
      final requested = <String>[];
      final todo = UpdateService.forApp(
          appDisplayName: 'BestToDo', apkPrefix: 'best_todo');
      todo.fetchOverride = (url) async {
        requested.add(url.toString());
        return jsonEncode(mixedReleases());
      };
      await todo.checkReleases(currentVersion: '0.1.1+1');
      expect(requested, [
        'https://api.github.com/repos/Mfficiency/best_todo_2/releases?per_page=30',
      ]);
    });

    test('a build from main is offered the newer dev build', () async {
      UpdateService.instance.fetchOverride =
          (url) async => jsonEncode(mixedReleases());
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.2.99+12100');
      expect(check.hasUpdate, isTrue);
      expect(check.latest!.version, '0.2.101+12210');
      expect(check.latest!.apkUrl,
          'https://example.com/v0.2.101-12210-dev.apk');
      expect(check.latest!.source, UpdateSource.githubRelease);
      expect(check.rollback!.version, '0.2.98+12050');
    });

    test('a build from dev is offered a newer staging or main build',
        () async {
      UpdateService.instance.fetchOverride = (url) async => jsonEncode([
            rel('v0.2.105-3600000-dev', prerelease: true),
            rel('v0.2.104-3600200-staging', prerelease: true),
            rel('v0.2.104-3600100'),
          ]);
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.2.105+3600000');
      expect(check.hasUpdate, isTrue);
      // Lower x.y.z, but a higher build number: Android installs it.
      expect(check.latest!.version, '0.2.104+3600200');
      expect(check.latest!.apkUrl,
          'https://example.com/v0.2.104-3600200-staging.apk');
      expect(check.rollback, isNull);
    });

    test('a higher x.y.z with a lower build number is not an update',
        () async {
      UpdateService.instance.fetchOverride = (url) async => jsonEncode([
            rel('v0.3.0-3600000-staging', prerelease: true),
          ]);
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.2.104+3600050');
      expect(check.hasUpdate, isFalse);
      expect(
          await UpdateService.instance
              .checkForUpdate(currentVersion: '0.2.104+3600050'),
          isNull);
    });

    test('a new-scheme build number is above old versionCodes', () async {
      UpdateService.instance.fetchOverride = (url) async => jsonEncode([
            rel('v0.2.104-3600000-dev', prerelease: true),
          ]);
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.2.103+12199');
      expect(check.hasUpdate, isTrue);
      expect(check.latest!.version, '0.2.104+3600000');
      expect(check.previous, isNull);
    });

    test('up to date still offers a rollback to the next lower build',
        () async {
      UpdateService.instance.fetchOverride =
          (url) async => jsonEncode(mixedReleases());
      final check = await UpdateService.instance
          .checkReleases(currentVersion: '0.2.101+12210');
      expect(check.hasUpdate, isFalse);
      expect(check.latest!.version, '0.2.101+12210');
      expect(check.rollback!.version, '0.2.101+12200');
    });

    test('no release for this app means no update', () async {
      final music = UpdateService.forApp(
          appDisplayName: 'Best Music', apkPrefix: 'best_music');
      music.fetchOverride = (url) async => jsonEncode([rel('v9.9.9-99999-dev')]);
      final check = await music.checkReleases(currentVersion: '0.1.0+1');
      expect(check.latest, isNull);
      expect(check.hasUpdate, isFalse);
    });

    test('malformed payload throws instead of pretending up-to-date',
        () async {
      UpdateService.instance.fetchOverride = (url) async => '{}';
      expect(
          () => UpdateService.instance
              .checkForUpdate(currentVersion: '0.1.131+103'),
          throwsA(isA<FormatException>()));
    });
  });

  group('rate limit', () {
    test('403/429 backs off without further requests until it resets',
        () async {
      var calls = 0;
      UpdateService.instance.fetchOverride = (url) async {
        calls++;
        throw const HttpException('GitHub replied 403');
      };
      await expectLater(
          UpdateService.instance.checkForUpdate(currentVersion: '0.1.0+1'),
          throwsA(isA<UpdateRateLimitedException>()));
      await expectLater(
          UpdateService.instance.checkForUpdate(currentVersion: '0.1.0+1'),
          throwsA(isA<UpdateRateLimitedException>()));
      expect(calls, 1);
      expect(UpdateService.instance.rateLimitedUntil, isNotNull);
    });

    test('requests resume once the back-off has passed', () async {
      UpdateService.instance.rateLimitedUntil =
          DateTime.now().subtract(const Duration(seconds: 1));
      UpdateService.instance.fetchOverride =
          (url) async => jsonEncode(mixedReleases());
      final info = await UpdateService.instance
          .checkForUpdate(currentVersion: '0.2.98+12050');
      expect(info!.version, '0.2.101+12210');
      expect(UpdateService.instance.rateLimitedUntil, isNull);
    });

    test('other HTTP errors are plain errors', () async {
      UpdateService.instance.fetchOverride =
          (url) async => throw const HttpException('GitHub replied 500');
      await expectLater(
          UpdateService.instance.checkForUpdate(currentVersion: '0.1.0+1'),
          throwsA(isA<HttpException>()));
      expect(UpdateService.instance.rateLimitedUntil, isNull);
    });
  });

  group('channel of the running build', () {
    test('defaults to main outside a laptop channel build; only shown', () {
      expect(Config.channel, 'main');
      expect(Config.versionWithChannel, Config.versionWithBuild);
      expect(UpdateService.instance.tagPrefix, 'v');
      expect(
          UpdateService.forApp(
                  appDisplayName: 'Best Music', apkPrefix: 'best_music')
              .tagPrefix,
          'music-v');
    });
  });

  /// Downloads are handed off to Android's `DownloadManager` (native side —
  /// see `MainActivity.kt`), which is what makes them survive the app being
  /// backgrounded and a Wi-Fi/mobile handover mid-download. Here that native
  /// channel is faked through [UpdateService.downloadChannelOverride], so
  /// these only cover the Dart-side plumbing: request shape, wire-status
  /// mapping, polling until a terminal status, and the pending-download
  /// bookkeeping used to resume after a restart.
  group('background download (DownloadManager)', () {
    UpdateInfo makeInfo({String? apkUrl = 'https://example.com/BestToDo.apk'}) =>
        UpdateInfo(
          version: '0.1.150+120',
          releaseName: 'BestToDo 0.1.150+120',
          htmlUrl: 'https://example.com/release',
          apkUrl: apkUrl,
        );

    test('startBackgroundDownload sends the apk url and a versioned file name',
        () async {
      String? method;
      Map<String, dynamic>? args;
      UpdateService.instance.downloadChannelOverride = (m, a) async {
        method = m;
        args = a;
        return {'downloadId': 42};
      };
      final id =
          await UpdateService.instance.startBackgroundDownload(makeInfo());
      expect(method, 'startBackgroundDownload');
      expect(args!['url'], 'https://example.com/BestToDo.apk');
      expect(args!['fileName'], 'BestToDo-update-0.1.150-120.apk');
      expect(args!['title'], 'BestToDo update 0.1.150+120');
      expect(id, 42);
    });

    test('notification title names the app and version being downloaded',
        () async {
      Map<String, dynamic>? args;
      final music = UpdateService.forApp(
          appDisplayName: 'Best Music', apkPrefix: 'best_music');
      music.downloadChannelOverride = (m, a) async {
        args = a;
        return {'downloadId': 3};
      };
      await music.startBackgroundDownload(makeInfo());
      expect(args!['title'], 'Best Music update 0.1.150+120');
    });

    test('throws instead of calling the channel when the release has no APK',
        () async {
      var called = false;
      UpdateService.instance.downloadChannelOverride = (m, a) async {
        called = true;
        return {'downloadId': 1};
      };
      await expectLater(
        UpdateService.instance.startBackgroundDownload(makeInfo(apkUrl: null)),
        throwsA(isA<StateError>()),
      );
      expect(called, isFalse);
    });

    test('queryDownload maps the DownloadManager wire status', () async {
      UpdateService.instance.downloadChannelOverride = (m, a) async => {
            'status': 'running',
            'bytesDownloaded': 512,
            'bytesTotal': 2048,
            'localPath': null,
            'reason': null,
          };
      final progress = await UpdateService.instance.queryDownload(42);
      expect(progress.status, DownloadStatus.running);
      expect(progress.bytesDownloaded, 512);
      expect(progress.bytesTotal, 2048);
      expect(progress.localPath, isNull);
    });

    test('watchDownload polls until a terminal status', () async {
      final responses = [
        {'status': 'pending', 'bytesDownloaded': 0, 'bytesTotal': 2048},
        {'status': 'running', 'bytesDownloaded': 1024, 'bytesTotal': 2048},
        {
          'status': 'successful',
          'bytesDownloaded': 2048,
          'bytesTotal': 2048,
          'localPath': '/data/updates/BestToDo.apk',
        },
      ];
      var i = 0;
      UpdateService.instance.downloadChannelOverride = (m, a) async {
        final response = responses[i];
        if (i < responses.length - 1) i++;
        return response;
      };
      final progresses = await UpdateService.instance
          .watchDownload(42, interval: const Duration(milliseconds: 1))
          .toList();
      expect(progresses.map((p) => p.status), [
        DownloadStatus.pending,
        DownloadStatus.running,
        DownloadStatus.successful,
      ]);
      expect(progresses.last.localPath, '/data/updates/BestToDo.apk');
    });

    test('watchDownload stops as soon as the download fails', () async {
      UpdateService.instance.downloadChannelOverride = (m, a) async => {
            'status': 'failed',
            'bytesDownloaded': 0,
            'bytesTotal': 0,
            'reason': '1008',
          };
      final progresses = await UpdateService.instance
          .watchDownload(1, interval: const Duration(milliseconds: 1))
          .toList();
      expect(progresses, hasLength(1));
      expect(progresses.single.status, DownloadStatus.failed);
      expect(progresses.single.reason, '1008');
    });

    test(
        'downloadInBackground clears the pending download once it finishes',
        () async {
      UpdateService.instance.downloadChannelOverride = (method, args) async {
        if (method == 'startBackgroundDownload') return {'downloadId': 7};
        return {
          'status': 'successful',
          'bytesDownloaded': 100,
          'bytesTotal': 100,
          'localPath': '/data/updates/BestToDo.apk',
        };
      };
      final progresses = await UpdateService.instance
          .downloadInBackground(makeInfo(),
              interval: const Duration(milliseconds: 1))
          .toList();
      expect(progresses.single.status, DownloadStatus.successful);
      expect(await UpdateService.instance.pendingDownload(), isNull);
      // The pending record is gone, but the version stays remembered as
      // downloaded — that's what stops a re-prompt on the next check.
      expect(await UpdateService.instance.wasDownloaded('0.1.150+120'), isTrue);
    });

    test(
        'wasDownloaded is true for a version that is still downloading',
        () async {
      UpdateService.instance.downloadChannelOverride = (method, args) async {
        if (method == 'startBackgroundDownload') return {'downloadId': 11};
        return {'status': 'running', 'bytesDownloaded': 10, 'bytesTotal': 100};
      };
      final iterator = StreamIterator(UpdateService.instance.downloadInBackground(
          makeInfo(),
          interval: const Duration(milliseconds: 1)));
      expect(await iterator.moveNext(), isTrue);
      expect(await UpdateService.instance.wasDownloaded('0.1.150+120'), isTrue);
      expect(await UpdateService.instance.wasDownloaded('0.1.151+121'), isFalse);
      await iterator.cancel();
    });

    test('wasDownloaded is false for a different, unrelated version',
        () async {
      await UpdateService.instance.markVersionDownloaded('0.1.150+120');
      expect(await UpdateService.instance.wasDownloaded('0.1.151+121'), isFalse);
    });

    test(
        'a failed download does not mark the version as downloaded',
        () async {
      UpdateService.instance.downloadChannelOverride = (method, args) async {
        if (method == 'startBackgroundDownload') return {'downloadId': 12};
        return {
          'status': 'failed',
          'bytesDownloaded': 0,
          'bytesTotal': 100,
          'reason': '1008',
        };
      };
      await UpdateService.instance
          .downloadInBackground(makeInfo(), interval: const Duration(milliseconds: 1))
          .toList();
      expect(await UpdateService.instance.wasDownloaded('0.1.150+120'), isFalse);
    });

    test(
        'downloadInBackground records the download while it is still running, '
        'so a later launch can find it', () async {
      var queryCount = 0;
      UpdateService.instance.downloadChannelOverride = (method, args) async {
        if (method == 'startBackgroundDownload') return {'downloadId': 9};
        queryCount++;
        if (queryCount == 1) {
          return {
            'status': 'running',
            'bytesDownloaded': 10,
            'bytesTotal': 100,
          };
        }
        return {
          'status': 'successful',
          'bytesDownloaded': 100,
          'bytesTotal': 100,
          'localPath': '/data/updates/BestToDo.apk',
        };
      };
      final iterator = StreamIterator(UpdateService.instance.downloadInBackground(
          makeInfo(),
          interval: const Duration(milliseconds: 1)));

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.status, DownloadStatus.running);
      final pending = await UpdateService.instance.pendingDownload();
      expect(pending, isNotNull);
      expect(pending!['downloadId'], 9);
      expect(pending['version'], '0.1.150+120');

      expect(await iterator.moveNext(), isTrue);
      expect(iterator.current.status, DownloadStatus.successful);
      expect(await iterator.moveNext(), isFalse);
      expect(await UpdateService.instance.pendingDownload(), isNull);
    });
  });

  group('updateDownloadsDirectory', () {
    test('returns the folder the native side reports', () async {
      String? method;
      UpdateService.instance.downloadChannelOverride = (m, a) async {
        method = m;
        return '/storage/emulated/0/Android/data/x/files/updates';
      };
      expect(await UpdateService.instance.updateDownloadsDirectory(),
          '/storage/emulated/0/Android/data/x/files/updates');
      expect(method, 'updateDownloadsDir');
    });

    test('is null when the native side has no folder or fails', () async {
      UpdateService.instance.downloadChannelOverride = (m, a) async => null;
      expect(await UpdateService.instance.updateDownloadsDirectory(), isNull);
      UpdateService.instance.downloadChannelOverride =
          (m, a) async => throw StateError('no storage');
      expect(await UpdateService.instance.updateDownloadsDirectory(), isNull);
    });

    test('is null off Android without touching the channel', () async {
      // The test host is never Android, and no override is installed.
      expect(await UpdateService.instance.updateDownloadsDirectory(), isNull);
    });
  });
}
