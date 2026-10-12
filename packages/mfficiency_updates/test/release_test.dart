import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';

Map<String, Object?> rel(
  String tag, {
  bool draft = false,
  bool prerelease = false,
  List<Map<String, Object?>>? assets,
}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'html_url': 'https://github.com/o/r/releases/tag/$tag',
      'body': 'notes $tag',
      'assets': assets ??
          [
            {
              'name': 'app.apk',
              'url': 'https://api.github.com/repos/o/r/releases/assets/1',
              'browser_download_url':
                  'https://github.com/o/r/download/$tag.apk',
            },
          ],
    };

void main() {
  test('compareVersions', () {
    expect(compareVersions('1.10.0', '1.9.3'), greaterThan(0));
    expect(compareVersions('v2.0.0', '2.0.0'), 0);
    expect(compareVersions('1.0.0-beta.1', '1.0.0'), 0);
    expect(compareVersions('1.0', '1.0.1'), lessThan(0));
  });

  test('tag: version, build, channel', () {
    expect(releaseVersion('v0.10.1-12345-staging'), '0.10.1');
    expect(releaseVersion('1.2.0+5'), '1.2.0');
    expect(releaseBuild('v0.10.1-12345-dev'), 12345);
    expect(releaseBuild('v0.10.1-19'), 19);
    expect(releaseBuild('v0.10.1'), isNull);
    expect(releaseChannel('v0.10.1-12345'), 'main');
    expect(releaseChannel('v0.10.1-12345-dev'), 'dev');
    expect(releaseChannel('v0.10.1-12345-staging'), 'staging');
    expect(releaseVersion('music-v2.1.0-77', prefix: 'music-v'), '2.1.0');
    expect(releaseBuild('music-v2.1.0-77-dev', prefix: 'music-v'), 77);
  });

  test('tag prefix: two apps in one repo', () {
    expect(matchesTagPrefix('v1.2.0-5', 'v'), isTrue);
    expect(matchesTagPrefix('V1.2.0-5', 'v'), isTrue);
    expect(matchesTagPrefix('1.2.0+5', 'v'), isTrue);
    expect(matchesTagPrefix('music-v1.2.0-5', 'v'), isFalse);
    expect(matchesTagPrefix('music-v1.2.0-5', 'music-v'), isTrue);
    expect(matchesTagPrefix('v1.2.0-5', 'music-v'), isFalse);
  });

  test('isNewerRelease compares the build number, whatever the x.y.z', () {
    UpdateResult r(String v, int? b) =>
        UpdateResult(UpdateStatus.available, version: v, build: b);
    bool newer(UpdateResult u) =>
        isNewerRelease(u, version: '1.2.0', build: 100);
    expect(newer(r('1.2.0', 100)), isFalse);
    expect(newer(r('1.2.0', 101)), isTrue);
    expect(newer(r('0.0.1', 101)), isTrue,
        reason: 'a lower x.y.z, newer build');
    expect(newer(r('99.0.0', 99)), isFalse);
    expect(newer(r('99.0.0', null)), isTrue, reason: 'no build: x.y.z');
    expect(newer(r('0.0.1', null)), isFalse);
    expect(newer(const UpdateResult(UpdateStatus.available)), isFalse);
  });

  test(
      'every channel and pre-releases count; drafts, other apps and old '
      'separate dev/staging builds do not', () {
    const f = ReleaseFilter(legacyBuildLimit: 1000000);
    final all = [
      rel('v1.0.0-3600100'),
      rel('v1.0.1-3600200-dev', prerelease: true),
      rel('v1.0.1-3600150-staging', prerelease: true),
      rel('v1.0.2-3600300', draft: true),
      rel('v0.9.0-10050-dev', prerelease: true), // legacy separate app
      rel('v0.9.0-10040'), // legacy main: still counts
      rel('music-v5.0.0-3600900'),
    ];
    expect(f.sort(all).map((r) => r['tag_name']), [
      'v1.0.1-3600200-dev',
      'v1.0.1-3600150-staging',
      'v1.0.0-3600100',
      'v0.9.0-10040',
    ]);
    const noPre = ReleaseFilter(includePrereleases: false);
    expect(noPre.sort(all).map((r) => r['tag_name']), [
      'v1.0.0-3600100',
      'v0.9.0-10040',
    ]);
    const music = ReleaseFilter(tagPrefix: 'music-v');
    expect(music.sort(all).single['tag_name'], 'music-v5.0.0-3600900');
  });

  test('highest build first, not newest by date nor highest x.y.z', () {
    final list = const ReleaseFilter().sort([
      rel('v2.0.0-5'),
      rel('v1.0.0-9'),
      rel('v1.1.0-9'),
      rel('v3.0.0-7-dev'),
    ]);
    expect(list.map((r) => r['tag_name']), [
      'v1.1.0-9',
      'v1.0.0-9',
      'v3.0.0-7-dev',
      'v2.0.0-5',
    ]);
  });

  test('a release as an update: its APK asset, else the page', () {
    final r = releaseResult(rel('v1.2.0-7-dev'));
    expect(r.status, UpdateStatus.available);
    expect(r.version, '1.2.0');
    expect(r.build, 7);
    expect(r.channel, 'dev');
    expect(r.key, '1.2.0+7');
    expect(r.label, '1.2.0 (7)');
    expect(r.notes, 'notes v1.2.0-7-dev');
    expect(r.url, 'https://github.com/o/r/download/v1.2.0-7-dev.apk');
    expect(isApkUrl(r.url), isTrue);

    // A private repo downloads through the asset API (with the token).
    final p = releaseResult(rel('v1.2.0-7'), privateRepo: true);
    expect(p.url, 'https://api.github.com/repos/o/r/releases/assets/1');
    expect(isApkUrl(p.url), isTrue);

    final page = releaseResult(rel('v1.2.0-7', assets: const []));
    expect(page.url, 'https://github.com/o/r/releases/tag/v1.2.0-7');
    expect(isApkUrl(page.url), isFalse);

    final picked = releaseResult(
      rel(
        'v1.2.0-7',
        assets: [
          {'name': 'debug.apk', 'browser_download_url': 'https://x/debug.apk'},
          {'name': 'app-arm64.apk', 'browser_download_url': 'https://x/a.apk'},
        ],
      ),
      assetPattern: RegExp(r'arm64'),
    );
    expect(picked.url, 'https://x/a.apk');
  });

  test('a manifest as an update', () {
    final r = manifestResult({
      'version': '1.3.0',
      'build': 12,
      'url': 'https://x/app.apk',
      'notes': 'n',
    });
    expect(r.label, '1.3.0 (12)');
    expect(r.url, 'https://x/app.apk');
    expect(manifestResult({'version': '1.3.0'}).label, '1.3.0');
  });

  test('older versions: the highest build of each x.y.z with an APK', () {
    final map = releasesByVersion([
      rel('v1.0.0-5'),
      rel('v1.0.0-8-dev'),
      rel('v0.9.0-3', assets: const []),
      rel('v0.8.0-2', draft: true),
      rel('v0.7.0-1'),
    ], const ReleaseFilter());
    expect(map.keys, ['1.0.0', '0.7.0']);
    expect(map['1.0.0']!.build, 8);
  });

  group('tag formats', () {
    test('a build prefix: vesta-immo-v0.1.19-b3600000-dev', () {
      const f = TagFormat(prefix: 'vesta-immo-v', buildPrefix: 'b');
      final t = f.parse('vesta-immo-v0.1.19-b3600000-dev')!;
      expect(t.version, '0.1.19');
      expect(t.build, 3600000);
      expect(t.channel, 'dev');
      expect(f.parse('vesta-immo-v0.1.19-b3600000')!.channel, 'main');
      // Lenient: an older CI-era tag still parses ...
      expect(f.parse('vesta-immo-v0.1.13-b1019-00d2e9d')!.build, 1019);
      expect(f.parse('v0.1.19-b3600000'), isNull, reason: 'another app');
    });

    test('strict: only the exact format', () {
      const f =
          TagFormat(prefix: 'vesta-immo-v', buildPrefix: 'b', strict: true);
      expect(
          f.parse('vesta-immo-v0.1.19-b3600000-staging')!.channel, 'staging');
      expect(f.parse('vesta-immo-v0.1.19-b3600000')!.build, 3600000);
      // ... strict drops it, and anything else off the scheme.
      expect(f.parse('vesta-immo-v0.1.13-b1019-00d2e9d'), isNull);
      expect(f.parse('vesta-immo-v0.1.19-3600000'), isNull);
      expect(f.parse('vesta-immo-v0.1.19'), isNull);
      expect(f.parse('vesta-immo-v0.1.19-b1-beta'), isNull);
      const plain = TagFormat(strict: true);
      expect(plain.parse('v1.2.0-5-dev')!.build, 5);
      expect(plain.parse('v1.2.0+5')!.build, 5);
      expect(plain.parse('v1.2.0-5-abc'), isNull);
      expect(plain.parse('music-v1.2.0-5'), isNull);
    });

    test('lenient default: as before', () {
      const f = TagFormat();
      expect(f.parse('v1.2.0-5-dev'),
          (version: '1.2.0', build: 5, channel: 'dev'));
      expect(f.parse('1.2.0+5'), (version: '1.2.0', build: 5, channel: 'main'));
      expect(
          f.parse('v1.2.0'), (version: '1.2.0', build: null, channel: 'main'));
      expect(f.parse('music-v1.2.0-5'), isNull);
    });

    test('an app\'s own RegExp with named groups', () {
      final f = TagFormat(
        pattern: RegExp(
            r'^app-(?<version>\d+\.\d+\.\d+)_(?<build>\d+)(?:_(?<channel>dev|staging))?$'),
      );
      expect(f.parse('app-2.0.0_77_staging'),
          (version: '2.0.0', build: 77, channel: 'staging'));
      expect(f.parse('app-2.0.0_77'),
          (version: '2.0.0', build: 77, channel: 'main'));
      expect(f.parse('v2.0.0-77'), isNull);
      final versionOnly = TagFormat(pattern: RegExp(r'^r(?<version>[\d.]+)$'));
      expect(versionOnly.parse('r1.0.0'),
          (version: '1.0.0', build: null, channel: 'main'));
    });

    test('the filter and the result read the format', () {
      const f = ReleaseFilter(
        tagFormat:
            TagFormat(prefix: 'vesta-immo-v', buildPrefix: 'b', strict: true),
      );
      final list = f.sort([
        rel('vesta-immo-v0.1.13-b9999999-00d2e9d'),
        rel('vesta-immo-v0.1.18-b3500000'),
        rel('vesta-immo-v0.1.19-b3600000-dev'),
      ]);
      expect(list.map((r) => r['tag_name']), [
        'vesta-immo-v0.1.19-b3600000-dev',
        'vesta-immo-v0.1.18-b3500000',
      ]);
      final r = releaseResult(list.first, tagFormat: f.format);
      expect(r.key, '0.1.19+3600000');
      expect(r.channel, 'dev');
    });
  });

  test('equal builds: main, then staging, then dev', () {
    final list = const ReleaseFilter().sort([
      rel('v1.0.0-50-dev'),
      rel('v1.0.0-50-staging'),
      rel('v1.0.0-50'),
      rel('v1.0.0-49'),
    ]);
    expect(list.map((r) => r['tag_name']),
        ['v1.0.0-50', 'v1.0.0-50-staging', 'v1.0.0-50-dev', 'v1.0.0-49']);
    expect(channelRank('main'), lessThan(channelRank('staging')));
    expect(channelRank('staging'), lessThan(channelRank('dev')));
  });

  test('releases without an APK: skipped unless requireApk is off', () {
    final all = [rel('v1.0.0-9', assets: const []), rel('v1.0.0-8')];
    expect(const ReleaseFilter().sort(all).single['tag_name'], 'v1.0.0-8');
    expect(const ReleaseFilter(requireApk: false).sort(all).first['tag_name'],
        'v1.0.0-9');
    // The asset pattern decides what an APK is.
    expect(
      ReleaseFilter(assetPattern: RegExp('arm64')).sort(all),
      isEmpty,
    );
  });

  test('browserUrl: the github.com APK link, or the page', () {
    final p = releaseResult(rel('v1.2.0-7'), privateRepo: true);
    expect(p.browserUrl, 'https://github.com/o/r/download/v1.2.0-7.apk');
    final page = releaseResult(rel('v1.2.0-7', assets: const []));
    expect(page.browserUrl, 'https://github.com/o/r/releases/tag/v1.2.0-7');
  });

  group('rate limit', () {
    final now = DateTime(2026, 10, 12, 12);
    test('which answers are the limit', () {
      const e429 = UpdateHttpException(429);
      expect(e429.isRateLimit(), isTrue);
      expect(const UpdateHttpException(403).isRateLimit(), isFalse);
      expect(
          const UpdateHttpException(403).isRateLimit(anonymous: true), isTrue);
      expect(
        const UpdateHttpException(403, null, {'x-ratelimit-remaining': '0'})
            .isRateLimit(),
        isTrue,
      );
      expect(
        const UpdateHttpException(403, null, {'x-ratelimit-remaining': '12'})
            .isRateLimit(),
        isFalse,
      );
      expect(
        const UpdateHttpException(403, null, {'retry-after': '60'})
            .isRateLimit(),
        isTrue,
      );
      expect(
          const UpdateHttpException(404).isRateLimit(anonymous: true), isFalse);
      expect(const UpdateHttpException(null).isRateLimit(), isFalse);
    });

    test('when it resets', () {
      expect(
        const UpdateHttpException(429, null, {'retry-after': '90'})
            .rateLimitReset(now),
        now.add(const Duration(seconds: 90)),
      );
      final reset = now.add(const Duration(minutes: 7));
      expect(
        UpdateHttpException(403, null, {
          'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
        }).rateLimitReset(now),
        reset,
      );
      expect(
        UpdateHttpException(403, null, {
          'x-ratelimit-reset':
              '${now.millisecondsSinceEpoch ~/ 1000 - 60}', // in the past
        }).rateLimitReset(now),
        isNull,
      );
      expect(const UpdateHttpException(429).rateLimitReset(now), isNull);
    });
  });

  test('config: user agent, due interval, tag format', () {
    const c = UpdateConfig(appName: 'Hally Remote', version: '1.0.0', build: 1);
    expect(c.httpUserAgent, 'HallyRemote-update-check');
    expect(
      const UpdateConfig(appName: 'A', version: '1', build: 1, userAgent: 'X/1')
          .httpUserAgent,
      'X/1',
    );
    expect(c.dueAfter, const Duration(hours: 24));
    expect(
      const UpdateConfig(
        appName: 'A',
        version: '1',
        build: 1,
        pollInterval: Duration(minutes: 15),
      ).dueAfter,
      const Duration(minutes: 15),
    );
    expect(c.requireApk, isTrue);
    expect(c.checkOnResume, isTrue);
    expect(c.rateLimitPause, const Duration(minutes: 30));
    expect(
      const UpdateConfig(
        appName: 'A',
        version: '1',
        build: 1,
        tagPrefix: 'vesta-immo-v',
        buildPrefix: 'b',
        strictTags: true,
      ).tagFormat.parse('vesta-immo-v0.1.19-b5-dev')?.build,
      5,
    );
  });
}
