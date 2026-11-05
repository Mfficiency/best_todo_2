// When every app checks for updates by default: every time it opens, every
// 5 minutes while it is open, when it comes back after a minute or more,
// and every hour while it is closed (Android's JobScheduler runs the app's
// background entry point, which only checks and downloads).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';

import 'fakes.dart';

@pragma('vm:entry-point')
Future<void> backgroundEntry() async {}

void main() {
  late FakeNative native;
  late FakeHttp http;
  late FakeDownloader downloader;
  late MemoryUpdateStore store;
  late DateTime now;

  setUp(() {
    native = FakeNative();
    http = FakeHttp([release('v99.0.0-100'), release('v0.0.1-1')]);
    downloader = FakeDownloader();
    store = MemoryUpdateStore();
    now = DateTime(2026, 11, 5, 9, 41);
  });
  tearDown(() => native.dispose());

  Future<UpdateController> controller({
    bool Function()? auto,
    Future<void> Function()? background = backgroundEntry,
  }) async {
    final c = UpdateController(
      config: UpdateConfig(
        appName: 'My App',
        version: '1.0.0',
        build: 10,
        githubRepo: 'o/app',
        autoCheck: auto ?? () => true,
        firstCheckDelay: Duration.zero,
        backgroundCheck: background,
      ),
      store: store,
      http: http,
      downloader: downloader,
      platform: UpdatePlatform(supported: true),
      clock: () => now,
    );
    await c.init();
    return c;
  }

  Future<BuildContext> app(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    return context;
  }

  Future<void> run(WidgetTester tester, [Duration d = Duration.zero]) async {
    await tester.pump(d);
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
  }

  test('the defaults: open, every 5 minutes, back after 1 minute, hourly',
      () {
    const config = UpdateConfig(appName: 'A', version: '1.0.0', build: 1);
    expect(config.checkInterval, Duration.zero);
    expect(config.pollInterval, const Duration(minutes: 5));
    expect(config.resumeCheckAfter, const Duration(minutes: 1));
    expect(config.backgroundInterval, const Duration(hours: 1));
  });

  testWidgets('checks every time the app opens, even right after a check',
      (tester) async {
    await store.setString(UpdateController.lastCheckKey, now.toIso8601String());
    final c = await controller();
    c.start(await app(tester));
    await run(tester);
    expect(http.requests, hasLength(1));
    c.dispose();
  });

  testWidgets('while open: every 5 minutes', (tester) async {
    final c = await controller();
    c.start(await app(tester));
    await run(tester);
    expect(http.requests, hasLength(1));
    await run(tester, const Duration(minutes: 4));
    expect(http.requests, hasLength(1));
    await run(tester, const Duration(minutes: 1));
    expect(http.requests, hasLength(2));
    await run(tester, const Duration(minutes: 5));
    expect(http.requests, hasLength(3));
    c.dispose();
  });

  testWidgets('opened again: checks when the last check is a minute old',
      (tester) async {
    final c = await controller();
    c.start(await app(tester));
    await run(tester);
    expect(http.requests, hasLength(1));
    now = now.add(const Duration(seconds: 30));
    c.handleResume();
    await run(tester);
    expect(http.requests, hasLength(1), reason: 'checked 30 s ago');
    now = now.add(const Duration(seconds: 30));
    c.handleResume();
    await run(tester);
    expect(http.requests, hasLength(2));
    c.dispose();
  });

  testWidgets('start schedules the hourly background check; off cancels it',
      (tester) async {
    final auto = ValueNotifier(true);
    final c = UpdateController(
      config: UpdateConfig(
        appName: 'My App',
        version: '1.0.0',
        build: 10,
        githubRepo: 'o/app',
        autoCheck: () => auto.value,
        autoCheckChanges: auto,
        backgroundCheck: backgroundEntry,
      ),
      store: store,
      http: http,
      downloader: downloader,
      platform: UpdatePlatform(supported: true),
      clock: () => now,
    );
    await c.init();
    c.start(await app(tester));
    await run(tester);
    final scheduled =
        native.calls.where((m) => m.method == 'scheduleBackgroundCheck');
    expect(scheduled, hasLength(1));
    expect(scheduled.single.arguments['minutes'], 60);
    expect(scheduled.single.arguments['handle'], isA<int>());

    auto.value = false;
    await run(tester);
    expect(
      native.calls.where((m) => m.method == 'cancelBackgroundCheck'),
      hasLength(1),
    );
    c.dispose();
  });

  testWidgets('no background entry point: nothing scheduled', (tester) async {
    final c = await controller(background: null);
    c.start(await app(tester));
    await run(tester);
    expect(
      native.calls.where((m) => m.method.contains('BackgroundCheck')),
      isEmpty,
    );
    c.dispose();
  });

  test('in the background: checks and downloads, never opens the installer',
      () async {
    final c = await controller();
    final r = await c.checkInBackground();
    await settle();
    expect(r.status, UpdateStatus.available);
    expect(http.requests, hasLength(1));
    expect(c.ready.value, r.key, reason: 'the APK is complete');
    expect(native.installs, isEmpty);
    c.dispose();
  });

  test('in the background with "check automatically" off: nothing', () async {
    final c = await controller(auto: () => false);
    await c.checkInBackground();
    expect(http.requests, isEmpty);
    c.dispose();
  });

  test('UpdateBackground.run builds the controller, checks, then says done',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final done = <Object?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UpdateBackground.doneChannel, (call) async {
      done.add(call.arguments);
      return null;
    });
    await UpdateBackground.run(() => controller());
    await settle();
    expect(http.requests, hasLength(1));
    expect(native.installs, isEmpty);
    expect(done, [
      {'outcome': 'available'},
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UpdateBackground.doneChannel, null);
  });

  testWidgets('the token goes with the schedule (private repos)',
      (tester) async {
    final c = UpdateController(
      config: UpdateConfig(
        appName: 'My App',
        version: '1.0.0',
        build: 10,
        githubRepo: 'o/app',
        privateRepo: true,
        tokenProvider: () async => 'secret',
        backgroundCheck: backgroundEntry,
      ),
      store: store,
      http: http,
      downloader: downloader,
      platform: UpdatePlatform(supported: true),
      clock: () => now,
    );
    await c.init();
    c.start(await app(tester));
    await run(tester);
    final call =
        native.calls.firstWhere((m) => m.method == 'scheduleBackgroundCheck');
    expect(call.arguments['token'], 'secret');
    c.dispose();
  });

  test('in the background, a private repo uses the handed-over token',
      () async {
    native.backgroundToken = 'kept';
    final c = UpdateController(
      config: const UpdateConfig(
        appName: 'My App',
        version: '1.0.0',
        build: 10,
        githubRepo: 'o/app',
        privateRepo: true,
      ),
      store: store,
      http: http,
      downloader: downloader,
      platform: UpdatePlatform(supported: true),
      clock: () => now,
    );
    await c.init();
    expect(c.configured, isFalse, reason: 'no token from the app');
    final r = await c.checkInBackground();
    expect(r.status, UpdateStatus.available);
    expect(http.requests.first.$2['Authorization'], 'Bearer kept');
    c.dispose();
  });
}
