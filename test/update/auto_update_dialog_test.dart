library;

import 'dart:convert';

import 'package:besttodo/services/update_service.dart';
import 'package:besttodo/ui/auto_update_dialog.dart';
import 'package:besttodo/ui/changelog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The automatic update ([AutoUpdateFlow], wired in `main.dart` and
/// `main_music.dart`): a newer build downloads silently, the app asks once
/// it is complete, Later keeps a banner, and only a tap installs it — through
/// a PackageInstaller session (`installApk`). Android's `DownloadManager` is
/// faked through [UpdateService.downloadChannelOverride].

/// One `main` release of BestToDo, as GitHub's releases list returns it.
String releases(String tag) => jsonEncode([
      {
        'tag_name': tag,
        'name': 'BestToDo $tag',
        'html_url': 'https://example.com/$tag',
        'prerelease': false,
        'draft': false,
        'assets': [
          {
            'name': '$tag.apk',
            'browser_download_url': 'https://example.com/$tag.apk',
            'size': 1000,
          },
        ],
      },
    ]);

void main() {
  late List<String> calls;
  late List<String> installed;
  late List<bool> silent;
  late bool failDownloads;
  final navigatorKey = GlobalKey<NavigatorState>();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateService.resetForTest(channel: 'main');
    calls = [];
    installed = [];
    silent = [];
    failDownloads = false;
    UpdateService.instance
      ..fetchOverride = ((_) async => releases('v9.9.9-99999'))
      ..fileExistsOverride = ((_) => true)
      ..downloadChannelOverride = (method, args) async {
        calls.add(method);
        switch (method) {
          case 'startBackgroundDownload':
            silent.add(args['silent'] == true);
            return {'downloadId': calls.length};
          case 'queryDownload':
            final fail = failDownloads && silent.length == 1;
            return fail
                ? {'status': 'failed', 'reason': '1000'}
                : {'status': 'successful', 'localPath': '/x/new.apk'};
          case 'installApk':
            installed.add(args['path'] as String);
            return 'ok';
        }
        return null;
      };
  });
  tearDown(() => AutoUpdateFlow.current = null);

  Future<AutoUpdateFlow> pumpApp(WidgetTester tester) async {
    final flow = AutoUpdateFlow(navigatorKey: navigatorKey);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('home')),
    ));
    return flow;
  }

  /// The download and its bookkeeping run outside the fake clock.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 800));
    }
  }

  testWidgets('a newer build downloads silently, then the app asks; '
      'Install hands it to Android', (tester) async {
    final flow = await pumpApp(tester);
    await tester.runAsync(() async {
      flow.onUpdateFound((await UpdateService.instance.checkForUpdate())!);
    });
    await settle(tester);
    expect(silent, [true], reason: 'no notification, no question first');
    expect(installed, isEmpty, reason: 'nothing installs without a tap');
    expect(find.text('Update ready'), findsOneWidget);

    await tester.tap(find.byKey(const Key('update.ready.install')));
    await settle(tester);
    expect(installed, ['/x/new.apk']);
  });

  testWidgets('Later keeps a banner; the same build is not asked again',
      (tester) async {
    final flow = await pumpApp(tester);
    final info = (await tester
        .runAsync(() => UpdateService.instance.checkForUpdate()))!;
    flow.onUpdateFound(info);
    await settle(tester);
    await tester.tap(find.text('Later'));
    await settle(tester);
    expect(find.text('Update ready'), findsNothing);
    expect(find.text('v9.9.9+99999 is downloaded and ready to install'),
        findsOneWidget);

    // The next poll finds the same build: no new download, no new dialog.
    flow.onUpdateFound(info);
    await settle(tester);
    expect(silent, hasLength(1));
    expect(find.text('Update ready'), findsNothing);

    await tester.tap(find.byKey(const Key('update.banner.install')));
    await settle(tester);
    expect(installed, ['/x/new.apk']);
  });

  testWidgets('an APK downloaded before a restart is reused', (tester) async {
    SharedPreferences.setMockInitialValues({
      'update_downloaded_apk':
          '{"version":"9.9.9+99999","path":"/x/old.apk"}',
    });
    final flow = await pumpApp(tester);
    await tester.runAsync(() async {
      flow.onUpdateFound((await UpdateService.instance.checkForUpdate())!);
    });
    await settle(tester);
    expect(calls, isNot(contains('startBackgroundDownload')));
    expect(find.text('Update ready'), findsOneWidget);
  });

  testWidgets('a failed background download leaves a banner; Install '
      'downloads it again and installs', (tester) async {
    failDownloads = true;
    final flow = await pumpApp(tester);
    await tester.runAsync(() async {
      flow.onUpdateFound((await UpdateService.instance.checkForUpdate())!);
    });
    await settle(tester);
    expect(find.text('Update ready'), findsNothing);
    expect(find.byKey(const Key('update.banner.download')), findsOneWidget);

    await tester.tap(find.byKey(const Key('update.banner.download')));
    await settle(tester);
    expect(silent, [true, false]);
    expect(installed, ['/x/new.apk']);
  });

  testWidgets('pulling down on the changelog checks and downloads',
      (tester) async {
    final flow = AutoUpdateFlow.current = await pumpApp(tester);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const ChangelogPage(assetPath: 'CHANGELOG_MUSIC.md')));
    for (var i = 0; i < 50 && find.byType(Markdown).evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.fling(find.byType(Markdown), const Offset(0, 400), 1000);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('v9.9.9+99999 found'), findsOneWidget);
    await settle(tester);
    expect(silent, [true]);
    expect(flow.readyVersion, '9.9.9+99999');
  });
}
