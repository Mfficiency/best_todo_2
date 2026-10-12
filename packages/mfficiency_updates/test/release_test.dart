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
}
