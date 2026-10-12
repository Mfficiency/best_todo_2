import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNative native;
  late FakeHttp http;
  late FakeDownloader downloader;
  late MemoryUpdateStore store;
  var now = DateTime(2026, 10, 12, 11, 20);
  final logs = <String>[];

  setUp(() {
    native = FakeNative();
    http = FakeHttp([release('v99.0.0-100'), release('v0.0.1-1')]);
    downloader = FakeDownloader();
    store = MemoryUpdateStore();
    now = DateTime(2026, 10, 12, 11, 20);
    logs.clear();
  });
  tearDown(() => native.dispose());

  Future<UpdateController> controller({
    String version = '1.0.0',
    int build = 10,
    bool private = false,
    String? token,
    bool auto = true,
    bool prereleases = true,
    UpdateProvider provider = UpdateProvider.github,
    String repo = 'o/app',
  }) async {
    final c = UpdateController(
      config: UpdateConfig(
        appName: 'My App',
        version: version,
        build: build,
        provider: provider,
        githubRepo: repo,
        manifestUrl: 'https://example.com/update.json',
        privateRepo: private,
        tokenProvider: () async => token,
        autoCheck: () => auto,
        includePrereleases: () => prereleases,
      ),
      store: store,
      http: http,
      downloader: downloader,
      platform: UpdatePlatform(supported: true),
      log: (level, event, data) => logs.add(event),
      clock: () => now,
    );
    addTearDown(c.dispose);
    await c.init();
    return c;
  }

  test('a newer build downloads silently, then Android asks once', () async {
    final c = await controller();
    final r = await c.check();
    expect(r.status, UpdateStatus.available);
    expect(r.label, '99.0.0 (100)');
    await settle();
    expect(c.ready.value, '99.0.0+100');
    expect(c.readyUpdate?.key, '99.0.0+100');
    expect(native.installs, hasLength(1));
    expect(
      (native.installs.single.arguments as Map)['path'],
      '/cache/MyApp-99.0.0-100.apk',
    );
    expect(c.downloaded.value?.key, '99.0.0+100');
    expect(c.downloaded.value?.at, now);
    expect(c.lastCheck, now);
    // The same build again: no second download, no second dialog.
    await c.check();
    await settle();
    expect(downloader.urls, hasLength(1));
    expect(native.installs, hasLength(1));
    expect(logs, containsAll(['update.check', 'update.ready']));
  });

  test('no higher build: up to date, nothing downloads', () async {
    final c = await controller(version: '100.0.0', build: 100);
    expect((await c.check()).status, UpdateStatus.upToDate);
    await settle();
    expect(downloader.urls, isEmpty);
  });

  test('a lower x.y.z with a higher build is an update', () async {
    http.body = [release('v0.5.0-11-dev', prerelease: true)];
    final c = await controller();
    expect((await c.check()).key, '0.5.0+11');
  });

  test('pre-releases off: only the others', () async {
    http.body = [
      release('v2.0.0-30-dev', prerelease: true),
      release('v1.5.0-20'),
    ];
    final c = await controller(prereleases: false);
    expect((await c.check()).key, '1.5.0+20');
  });

  test('automatic checks off: found, but downloads only on Install', () async {
    final c = await controller(auto: false);
    final r = await c.check();
    await settle();
    expect(downloader.urls, isEmpty);
    expect(c.showsAvailableBanner(r), isTrue);
    c.dismiss(r);
    expect(c.showsAvailableBanner(r), isFalse);
  });

  test('a failed download: Try again, silently', () async {
    downloader.fail = true;
    final c = await controller();
    await c.check();
    await settle();
    expect(c.failed.value?.key, '99.0.0+100');
    expect(c.ready.value, isNull);
    expect(native.installs, isEmpty);
    // The next automatic check doesn't retry by itself.
    await c.check();
    await settle();
    expect(downloader.urls, hasLength(1));
  });

  test('without "install unknown apps": installs when the app is back',
      () async {
    native.installOutcome = 'needs-permission';
    final c = await controller();
    await c.check();
    await settle();
    expect(native.installs, hasLength(1));
    native.installOutcome = 'ok';
    c.handleResume();
    await settle();
    expect(native.installs, hasLength(2));
  });

  test('a download survives a restart, with its time', () async {
    final first = await controller();
    await first.check();
    await settle();
    final at = first.downloaded.value!.at;
    now = now.add(const Duration(hours: 1));
    final again = await controller();
    expect(again.downloaded.value?.at, at);
    await again.check();
    await settle();
    expect(again.ready.value, '99.0.0+100');
    expect(downloader.urls, hasLength(1), reason: 'the APK was still there');
    expect(again.downloaded.value?.at, at);
  });

  test('install time: the first start of a build, Android\'s on a phone',
      () async {
    final c = await controller();
    expect(c.installedAt.value, now);
    expect(store.getInt(UpdateController.installedBuildKey), 10);
    now = now.add(const Duration(days: 1));
    final same = await controller();
    expect(same.installedAt.value, DateTime(2026, 10, 12, 11, 20));
    final next = await controller(build: 11);
    expect(next.installedAt.value, now);

    native.installTime = DateTime(2026, 10, 1, 8);
    await next.init();
    // start() asks Android (no context needed for that part).
    expect(await next.platform.installTime(), DateTime(2026, 10, 1, 8));
  });

  test('isRunning: this build, or this x.y.z without a build', () async {
    final c = await controller();
    expect(c.isRunning('1.0.0+10'), isTrue);
    expect(c.isRunning('1.0.0+0'), isTrue);
    expect(c.isRunning('1.0.0+9'), isFalse);
  });

  test('downloaded record is read from the store', () async {
    await store.setString(
      UpdateController.downloadedKey,
      jsonEncode({
        'key': '1.0.0+10',
        'label': '1.0.0 (10)',
        'at': '2026-10-12T11:00:00'
      }),
    );
    final c = await controller();
    expect(c.downloaded.value?.label, '1.0.0 (10)');
  });

  group('private repo', () {
    test('without a token: asks for one, no request', () async {
      final c = await controller(private: true);
      expect(c.configured, isFalse);
      expect((await c.check()).status, UpdateStatus.needsToken);
      expect(http.requests, isEmpty);
      expect(c.statusLabel(const UpdateStrings()), contains('GitHub token'));
    });

    test('with a token: Authorization, asset API, signed download', () async {
      final c = await controller(private: true, token: ' github_pat_abc ');
      expect(c.hasToken, isTrue);
      final r = await c.check();
      expect(r.url,
          startsWith('https://api.github.com/repos/o/app/releases/assets/'));
      expect(http.requests.last.$2['Authorization'], 'Bearer github_pat_abc');
      expect(http.requests.last.$1.toString(), contains('per_page=30'));
      await settle();
      expect(downloader.signed.single.$2, 'github_pat_abc');
      expect(downloader.urls.single.host, 'objects.example.com');
      expect(c.ready.value, '99.0.0+100');
    });

    test('a refused token (401/403/404) = badToken', () async {
      for (final status in [401, 403, 404]) {
        http.status = status;
        final c = await controller(private: true, token: 't');
        expect((await c.check()).status, UpdateStatus.badToken);
      }
    });

    test('reloadToken reads it again and checks', () async {
      String? token = 't';
      final c = UpdateController(
        config: UpdateConfig(
          appName: 'App',
          version: '1.0.0',
          build: 10,
          githubRepo: 'o/app',
          privateRepo: true,
          tokenProvider: () async => token,
        ),
        store: store,
        http: http,
        downloader: downloader,
        platform: UpdatePlatform(supported: true),
      );
      addTearDown(c.dispose);
      await c.init();
      token = null;
      expect((await c.reloadToken()).status, UpdateStatus.needsToken);
      expect(c.hasToken, isFalse);
    });
  });

  test('a public repo answering 403 (rate limit) failed, not badToken',
      () async {
    http.status = 403;
    final c = await controller();
    expect((await c.check()).status, UpdateStatus.failed);
  });

  test('not configured', () async {
    final c = await controller(repo: '');
    expect((await c.check()).status, UpdateStatus.notConfigured);
    expect(http.requests, isEmpty);
  });

  group('manifest', () {
    test('a newer build', () async {
      http.body = {
        'version': '1.1.0',
        'build': 11,
        'url': 'https://example.com/app.apk',
      };
      final c = await controller(provider: UpdateProvider.manifest);
      final r = await c.check();
      expect(r.label, '1.1.0 (11)');
      expect(http.requests.single.$1.queryParameters, contains('t'));
    });

    test('nothing published (404): not configured', () async {
      http.status = 404;
      final c = await controller(provider: UpdateProvider.manifest);
      expect((await c.check()).status, UpdateStatus.notConfigured);
    });
  });

  test('older versions: every x.y.z with an APK, read once', () async {
    final c = await controller();
    final v = await c.releasesByVersionList();
    expect(v.keys, ['99.0.0', '0.0.1']);
    await c.releasesByVersionList();
    expect(http.requests, hasLength(1));
    expect(http.requests.single.$1.toString(), contains('per_page=100'));
    await c.refresh();
    await c.releasesByVersionList();
    expect(http.requests, hasLength(3), reason: 'pull-down reads it again');
  });

  test('progress label while downloading', () async {
    final c = await controller();
    const s = UpdateStrings();
    expect(c.progressLabel(s), isNull);
    final labels = <String?>[];
    c.addListener(() => labels.add(c.progressLabel(s)));
    await c.check();
    await settle();
    expect(labels, contains('Downloading version 99.0.0 (100)… 50 %'));
  });
}
