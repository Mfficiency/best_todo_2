import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';

import 'fakes.dart';

void main() {
  late FakeNative native;
  late FakeHttp http;
  late FakeDownloader downloader;

  setUp(() {
    native = FakeNative();
    http = FakeHttp([release('v99.0.0-100'), release('v0.0.1-1')]);
    downloader = FakeDownloader();
  });
  tearDown(() => native.dispose());

  Future<UpdateController> controller(
    WidgetTester tester, {
    bool auto = true,
    String repo = 'o/app',
    String channel = 'main',
  }) async {
    final c = UpdateController(
      config: UpdateConfig(
        appName: 'App',
        version: '1.0.0',
        build: 10,
        channel: channel,
        githubRepo: repo,
        autoCheck: () => auto,
      ),
      store: MemoryUpdateStore(),
      http: http,
      downloader: downloader,
      platform: UpdatePlatform(supported: true),
      clock: () => DateTime(2026, 10, 12, 11, 20),
    );
    await c.init();
    return c;
  }

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: ListView(children: [child])),
      );

  testWidgets('banner: ready with Install, which opens Android\'s dialog', (
    tester,
  ) async {
    final c = await controller(tester);
    await tester.pumpWidget(host(UpdateBanner(controller: c)));
    expect(find.byType(MaterialBanner), findsNothing);
    await c.check();
    await tester.pumpAndSettle();
    expect(native.installs, hasLength(1));
    expect(find.text('Update ready · 99.0.0 (100)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('update.banner.install')));
    await tester.pumpAndSettle();
    expect(native.installs, hasLength(2), reason: 'a tap always asks');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('banner: a failed download offers Try again', (tester) async {
    downloader.fail = true;
    final c = await controller(tester);
    await tester.pumpWidget(host(UpdateBanner(controller: c)));
    await c.check();
    await tester.pumpAndSettle();
    expect(find.text("Version 99.0.0 (100) couldn't be downloaded"),
        findsOneWidget);
    downloader.fail = false;
    await tester.tap(find.byKey(const Key('update.banner.retry')));
    await tester.pump();
    expect(
      find.textContaining('Downloading version 99.0.0 (100) in the background'),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.text('Update ready · 99.0.0 (100)'), findsOneWidget);
    expect(native.installs, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('banner: automatic checks off, Later hides it', (tester) async {
    final c = await controller(tester, auto: false);
    await tester.pumpWidget(host(UpdateBanner(controller: c)));
    await c.check();
    await tester.pumpAndSettle();
    expect(find.text('Version 99.0.0 (100) is available'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
    expect(downloader.urls, isEmpty);
  });

  testWidgets('status card: version, times, ready, last check', (tester) async {
    final c = await controller(tester, channel: 'dev');
    await tester.pumpWidget(host(UpdateStatusCard(controller: c)));
    expect(find.textContaining('Current version 1.0.0 (10) · dev · Up to date'),
        findsOneWidget);
    expect(find.textContaining('Installed 12.10.2026 11:20'), findsOneWidget);
    expect(find.textContaining('Not checked yet · Pull down'), findsOneWidget);
    await c.check();
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Version 99.0.0 (100) available'), findsOneWidget);
    expect(
      find.textContaining(
          '99.0.0 (100) downloaded 12.10.2026 11:20 · ready to install'),
      findsOneWidget,
    );
    expect(
        find.textContaining('Last checked 12.10.2026 11:20'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Install'), findsOneWidget);
  });

  testWidgets('status card without a source', (tester) async {
    final c = await controller(tester, repo: '');
    await tester.pumpWidget(host(UpdateStatusCard(controller: c)));
    expect(find.textContaining('No update source configured'), findsOneWidget);
    expect(find.textContaining('Pull down'), findsNothing);
  });

  testWidgets('check tile: checks, then installs', (tester) async {
    final c = await controller(tester);
    await tester.pumpWidget(host(UpdateCheckTile(controller: c)));
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Current version 1.0.0 (10)'), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(native.installs, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('version sheet: current, older (rollback), gone', (tester) async {
    final c = await controller(tester);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Column(
            children: [
              for (final v in ['1.0.0', '0.0.1', '0.5.0'])
                TextButton(
                  onPressed: () => c.onVersionTap(context, v),
                  child: Text('tap $v'),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('tap 1.0.0'));
    await tester.pumpAndSettle();
    expect(find.text('You are using this version'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('tap 0.5.0'));
    await tester.pumpAndSettle();
    expect(find.text('Version 0.5.0 is no longer available to download.'),
        findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.text('tap 0.0.1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Android installs an older version'),
        findsOneWidget);
    await tester.tap(find.text('Download version 0.0.1 (1)'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(native.installs, hasLength(1));
    expect(
      (native.installs.single.arguments as Map)['path'],
      '/cache/App-0.0.1-1.apk',
    );
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('strings: the app\'s own', (tester) async {
    final c = UpdateController(
      config: const UpdateConfig(appName: 'A', version: '1.0.0', build: 1),
      store: MemoryUpdateStore(),
      http: http,
      downloader: downloader,
      platform: UpdatePlatform(supported: false),
      strings: (_) => UpdateStrings(
        currentVersion: (v) => 'Aktuelle Version $v',
        notConfigured: 'Keine Quelle',
        neverChecked: 'Nie',
      ),
    );
    await c.init();
    await tester.pumpWidget(host(UpdateStatusCard(controller: c)));
    expect(find.textContaining('Aktuelle Version 1.0.0 (1) · Keine Quelle'),
        findsOneWidget);
  });
}
