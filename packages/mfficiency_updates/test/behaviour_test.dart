// The behaviour every app gets the same way (resume check, the automatic
// switch, GitHub's rate limit, link opener, APK-less releases, pre-install
// hook, holding back the install prompt).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';

import 'fakes.dart';

void main() {
  late FakeNative native;
  late FakeHttp http;
  late FakeDownloader downloader;
  late MemoryUpdateStore store;
  late DateTime now;
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
    bool Function()? auto,
    Listenable? autoChanges,
    Duration pollInterval = Duration.zero,
    Duration checkInterval = const Duration(hours: 1),
    bool checkOnResume = true,
    bool private = false,
    String? token,
    bool requireApk = true,
    bool supported = true,
    Future<bool> Function(String url)? openUrl,
    ValueListenable<bool>? promptAllowed,
    Future<void> Function(UpdateResult r, String path)? beforeInstall,
  }) async {
    final c = UpdateController(
      config: UpdateConfig(
        appName: 'My App',
        version: '1.0.0',
        build: 10,
        githubRepo: 'o/app',
        privateRepo: private,
        tokenProvider: () async => token,
        autoCheck: auto ?? () => true,
        autoCheckChanges: autoChanges,
        pollInterval: pollInterval,
        checkInterval: checkInterval,
        firstCheckDelay: Duration.zero,
        checkOnResume: checkOnResume,
        requireApk: requireApk,
      ),
      store: store,
      http: http,
      downloader: downloader,
      platform: UpdatePlatform(supported: supported, openUrl: openUrl),
      log: (level, event, data) => logs.add(event),
      clock: () => now,
      promptAllowed: promptAllowed,
      beforeInstall: beforeInstall,
    );
    await c.init();
    return c;
  }

  Future<BuildContext> app(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return context;
  }

  /// Lets timers, the check and the download run in the fake clock.
  Future<void> run(WidgetTester tester, [Duration d = Duration.zero]) async {
    await tester.pump(d);
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  }

  group('check on resume', () {
    testWidgets('back in the app: checks when the last check is too old',
        (tester) async {
      await store.setString(
          UpdateController.lastCheckKey, now.toIso8601String());
      final c = await controller();
      c.start(await app(tester));
      await run(tester);
      expect(http.requests, isEmpty, reason: 'checked a moment ago');
      c.handleResume();
      await run(tester);
      expect(http.requests, isEmpty, reason: 'not due yet');
      now = now.add(const Duration(hours: 1));
      c.handleResume();
      await run(tester);
      expect(http.requests, hasLength(1));
      expect(c.result.value?.status, UpdateStatus.available);
      c.handleResume();
      await run(tester);
      expect(http.requests, hasLength(1), reason: 'just checked');
      c.dispose();
    });

    testWidgets('with polling, due after the poll interval', (tester) async {
      await store.setString(
          UpdateController.lastCheckKey, now.toIso8601String());
      final c = await controller(
        pollInterval: const Duration(minutes: 15),
        checkInterval: const Duration(hours: 24),
      );
      expect(c.config.dueAfter, const Duration(minutes: 15));
      c.start(await app(tester));
      now = now.add(const Duration(minutes: 16));
      c.handleResume();
      await run(tester);
      expect(http.requests, hasLength(1));
      c.dispose();
    });

    testWidgets('not before start, not when turned off, not when auto is off',
        (tester) async {
      final early = await controller();
      early.handleResume();
      await run(tester);
      expect(http.requests, isEmpty, reason: 'start() not called yet');
      early.dispose();

      await store.setString(UpdateController.lastCheckKey,
          now.subtract(const Duration(days: 1)).toIso8601String());
      final context = await app(tester);
      for (final c in [
        await controller(checkOnResume: false),
        await controller(auto: () => false),
      ]) {
        c.start(context);
        await run(tester);
        http.requests.clear();
        c.handleResume();
        await run(tester);
        expect(http.requests, isEmpty);
        c.dispose();
      }
    });
  });

  group('automatic switch', () {
    testWidgets('turned on: checks and polls; off: polling stops',
        (tester) async {
      final auto = ValueNotifier(false);
      final c = await controller(
        auto: () => auto.value,
        autoChanges: auto,
        pollInterval: const Duration(minutes: 15),
      );
      c.start(await app(tester));
      await run(tester, const Duration(minutes: 20));
      expect(http.requests, isEmpty);

      auto.value = true;
      await run(tester);
      expect(http.requests, hasLength(1), reason: 'never checked: due');
      now = now.add(const Duration(minutes: 15));
      await run(tester, const Duration(minutes: 15));
      expect(http.requests, hasLength(2), reason: 'polling');

      // Other notifications (the same switch value) change nothing, even
      // when a check would be due.
      now = now.add(const Duration(minutes: 20));
      auto.notifyListeners(); // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      await run(tester);
      expect(http.requests, hasLength(2));

      auto.value = false;
      now = now.add(const Duration(hours: 1));
      await run(tester, const Duration(hours: 1));
      expect(http.requests, hasLength(2));
      c.dispose();
    });

    testWidgets('autoCheckChanged(): an update found meanwhile downloads',
        (tester) async {
      var auto = false;
      final c = await controller(auto: () => auto);
      c.start(await app(tester));
      c.autoCheckChanged(); // before anything: harmless
      final r = await c.check(); // e.g. "Check for updates"
      await run(tester);
      expect(r.status, UpdateStatus.available);
      expect(downloader.urls, isEmpty, reason: 'automatic checks are off');
      expect(c.showsAvailableBanner(r), isTrue);

      auto = true;
      c.autoCheckChanged();
      await run(tester);
      expect(http.requests, hasLength(1), reason: 'just checked: not due');
      expect(downloader.urls, hasLength(1));
      expect(c.ready.value, '99.0.0+100');
      c.dispose();
    });
  });

  group('GitHub rate limit', () {
    test('pauses automatic checks until the reset; taps still check', () async {
      final reset = now.add(const Duration(minutes: 12));
      http
        ..status = 403
        ..responseHeaders = {
          'x-ratelimit-remaining': '0',
          'x-ratelimit-reset': '${reset.millisecondsSinceEpoch ~/ 1000}',
        };
      final c = await controller(token: 't');
      final r = await c.check();
      expect(r.status, UpdateStatus.rateLimited);
      expect(c.pausedUntil, reset);
      expect(c.rateLimited, isTrue);
      expect(
        c.statusLabel(const UpdateStrings()),
        'GitHub is limiting update checks right now — try again later.',
      );
      expect(logs, contains('update.rate_limited'));

      // A restart keeps the pause.
      final again = await controller(token: 't');
      expect(again.pausedUntil, reset);
      expect(again.statusLabel(const UpdateStrings()),
          const UpdateStrings().rateLimited);

      // A tap checks anyway; success ends the pause.
      http.status = 200;
      expect((await again.check()).status, UpdateStatus.available);
      expect(again.pausedUntil, isNull);
      c.dispose();
      again.dispose();
    });

    testWidgets('while paused the poll and resume ask nothing', (tester) async {
      http
        ..status = 429
        ..responseHeaders = const {};
      final c = await controller(pollInterval: const Duration(minutes: 15));
      c.start(await app(tester));
      await run(tester);
      expect(http.requests, hasLength(1));
      expect(c.result.value?.status, UpdateStatus.rateLimited);
      expect(c.pausedUntil, now.add(const Duration(minutes: 30)),
          reason: 'no reset given: 30 minutes');

      http.status = 200;
      now = now.add(const Duration(minutes: 15));
      await run(tester, const Duration(minutes: 15));
      c.handleResume();
      await run(tester);
      expect(http.requests, hasLength(1));
      expect(logs, contains('update.paused'));

      now = now.add(const Duration(minutes: 16));
      await run(tester, const Duration(minutes: 15));
      expect(http.requests, hasLength(2), reason: 'the pause is over');
      expect(c.result.value?.status, UpdateStatus.available);
      c.dispose();
    });

    test('Retry-After; a token refused without rate-limit headers is badToken',
        () async {
      http
        ..status = 403
        ..responseHeaders = {'retry-after': '120'};
      final c = await controller();
      expect((await c.check()).status, UpdateStatus.rateLimited);
      expect(c.pausedUntil, now.add(const Duration(minutes: 2)));
      http.responseHeaders = const {};
      final withToken = await controller(token: 't');
      expect((await withToken.check()).status, UpdateStatus.badToken);
      c.dispose();
      withToken.dispose();
    });
  });

  group('opening links off a phone', () {
    testWidgets(
        'the app\'s opener; a private asset: signed link, else '
        'its github.com link', (tester) async {
      final opened = <String>[];
      final c = await controller(
        supported: false,
        private: true,
        token: 't',
        openUrl: (url) async {
          opened.add(url);
          return true;
        },
      );
      final context = await app(tester);
      final r = await c.check();
      await tester.runAsync(() => c.install(context, r));
      expect(opened.single, 'https://objects.example.com/apk?sig=1');
      expect(native.calls.where((m) => m.method == 'openUrl'), isEmpty);

      downloader.signedUrl = null; // e.g. in a browser
      await tester.runAsync(() => c.install(context, r));
      expect(
          opened.last, 'https://github.com/o/app/download/v99.0.0-100/app.apk');
      c.dispose();
    });

    test('an opener that throws counts as not opened', () async {
      final p = UpdatePlatform(
        supported: false,
        openUrl: (_) => throw StateError('no browser'),
      );
      expect(await p.openUrl('https://example.com'), isFalse);
      // Default: the Android plugin.
      expect(await UpdatePlatform(supported: false).openUrl('https://x.y'),
          isTrue);
      expect(native.calls.single.method, 'openUrl');
    });
  });

  group('releases without an APK', () {
    test('skipped by default: the newest with an APK is offered', () async {
      http.body = [
        release('v99.0.1-101', apk: false), // its APK is still uploading
        release('v99.0.0-100'),
      ];
      final c = await controller();
      expect((await c.check()).key, '99.0.0+100');
      c.dispose();
    });

    test('requireApk: false offers the release page', () async {
      http.body = [release('v99.0.1-101', apk: false)];
      final c = await controller(requireApk: false);
      final r = await c.check();
      expect(r.url, 'https://github.com/o/app/releases/tag/v99.0.1-101');
      expect(c.showsAvailableBanner(r), isTrue);
      c.dispose();
    });
  });

  test('equal build numbers: main before staging before dev', () async {
    http.body = [
      release('v2.0.0-100-dev', prerelease: true),
      release('v2.0.0-100'),
      release('v2.0.0-100-staging', prerelease: true),
    ];
    final c = await controller();
    expect((await c.check()).channel, 'main');
    c.dispose();
  });

  group('before install', () {
    test('runs before Android\'s installer, with the APK', () async {
      final order = <String>[];
      native = FakeNative();
      final c = await controller(beforeInstall: (r, path) async {
        order.add('backup ${r.key} $path');
        expect(native.installs, isEmpty);
      });
      await c.check();
      await settle();
      expect(order, ['backup 99.0.0+100 /cache/MyApp-99.0.0-100.apk']);
      expect(native.installs, hasLength(1));
      c.dispose();
    });

    test('a failing hook is logged; the install goes on', () async {
      final c = await controller(
        beforeInstall: (r, path) async => throw StateError('disk full'),
      );
      await c.check();
      await settle();
      expect(logs, contains('update.before_install_failed'));
      expect(native.installs, hasLength(1));
      c.dispose();
    });
  });

  group('prompt allowed', () {
    test('busy: no dialog by itself; when free, it opens once', () async {
      final allowed = ValueNotifier(false);
      final c = await controller(promptAllowed: allowed);
      await c.check();
      await settle();
      expect(c.ready.value, '99.0.0+100');
      expect(native.installs, isEmpty);
      c.handleResume();
      await settle();
      expect(native.installs, isEmpty, reason: 'still busy');

      allowed.value = true;
      await settle();
      expect(native.installs, hasLength(1));
      allowed
        ..value = false
        ..value = true;
      await settle();
      expect(native.installs, hasLength(1), reason: 'once per build and start');
      c.dispose();
    });

    testWidgets('a tap on Install opens it even while busy', (tester) async {
      final allowed = ValueNotifier(false);
      final c = await controller(promptAllowed: allowed);
      final context = await app(tester);
      final r = await c.check();
      await run(tester);
      expect(native.installs, isEmpty);
      await c.install(context, r);
      await run(tester);
      expect(native.installs, hasLength(1));
      c.dispose();
    });
  });
}
