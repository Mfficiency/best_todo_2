library;

import 'dart:async';
import 'dart:convert';

import 'package:besttodo/services/update_service.dart';
import 'package:besttodo/ui/auto_update_dialog.dart';
import 'package:besttodo/ui/changelog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The automatic update ([AutoUpdateFlow], wired in `main.dart` and
/// `main_music.dart`): every download is silent (no notification, no
/// dialog, no progress), and once the APK is complete Android's own install
/// confirm (`installApk`, a PackageInstaller session) is the only question —
/// no "Update ready" dialog of the app's own. A cancelled confirm leaves a
/// slim banner. Android's `DownloadManager` is faked through
/// [UpdateService.downloadChannelOverride].

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

class _ChangelogBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
      Uint8List.fromList(utf8.encode('## [9.9.9] - 2026-10-12\n- x\n')));
}

void main() {
  late List<String> calls;
  late List<String> installed;
  late List<bool> silent;
  late bool failDownloads;
  late bool holdDownloads;
  late String installOutcome;
  final navigatorKey = GlobalKey<NavigatorState>();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateService.resetForTest();
    calls = [];
    installed = [];
    silent = [];
    failDownloads = false;
    holdDownloads = false;
    installOutcome = 'ok';
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
            if (holdDownloads) {
              return {
                'status': 'running',
                'bytesDownloaded': 500,
                'bytesTotal': 1000,
              };
            }
            final fail = failDownloads && silent.length == 1;
            return fail
                ? {'status': 'failed', 'reason': '1000'}
                : {'status': 'successful', 'localPath': '/x/new.apk'};
          case 'installApk':
            installed.add(args['path'] as String);
            return installOutcome;
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

  /// Nothing of the app's own takes the screen: no dialog, no sheet, no
  /// progress bar.
  void expectNothingPoppedUp() {
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Update ready'), findsNothing);
  }

  final readyBanner = find.byKey(const Key('update.banner.ready'));

  testWidgets(
      'a newer build downloads silently, then goes straight to '
      "Android's install confirm (no app dialog)", (tester) async {
    final flow = await pumpApp(tester);
    await tester.runAsync(() async {
      flow.onUpdateFound((await UpdateService.instance.checkForUpdate())!);
    });
    await settle(tester);
    expect(silent, [true], reason: 'no notification, no question first');
    expectNothingPoppedUp();
    expect(installed, ['/x/new.apk'],
        reason: "Android's dialog is the one confirmation");
  });

  testWidgets('a download that completes in the background installs on resume',
      (tester) async {
    final flow = await pumpApp(tester);
    flow.onLifecycleChanged(AppLifecycleState.paused);
    await tester.runAsync(() async {
      flow.onUpdateFound((await UpdateService.instance.checkForUpdate())!);
    });
    await settle(tester);
    expect(flow.readyVersion, '9.9.9+99999');
    expect(installed, isEmpty, reason: 'not while the app is away');

    flow.onLifecycleChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(installed, ['/x/new.apk']);
    expectNothingPoppedUp();
  });

  testWidgets(
      'a cancelled confirm leaves a slim banner and is not popped up again '
      'in this start; its Install reopens it', (tester) async {
    final flow = await pumpApp(tester);
    final info =
        (await tester.runAsync(() => UpdateService.instance.checkForUpdate()))!;
    flow.onUpdateFound(info);
    await settle(tester);
    expect(installed, hasLength(1));
    // The user cancelled Android's dialog: the app keeps running.
    expect(readyBanner, findsOneWidget);
    expect(find.text('Update ready · v9.9.9+99999'), findsOneWidget);

    // The next poll / coming back finds the same build: no new download,
    // no new confirm.
    flow.onUpdateFound(info);
    flow.onLifecycleChanged(AppLifecycleState.paused);
    flow.onLifecycleChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(silent, hasLength(1));
    expect(installed, hasLength(1));
    expect(readyBanner, findsOneWidget);

    await tester.tap(find.byKey(const Key('update.banner.install')));
    await settle(tester);
    expect(installed, ['/x/new.apk', '/x/new.apk']);
    expectNothingPoppedUp();
  });

  testWidgets('an APK downloaded before a restart is reused', (tester) async {
    SharedPreferences.setMockInitialValues({
      'update_downloaded_apk': '{"version":"9.9.9+99999","path":"/x/old.apk"}',
    });
    final flow = await pumpApp(tester);
    await tester.runAsync(() async {
      flow.onUpdateFound((await UpdateService.instance.checkForUpdate())!);
    });
    await settle(tester);
    expect(calls, isNot(contains('startBackgroundDownload')));
    expect(installed, ['/x/old.apk']);
    expectNothingPoppedUp();
  });

  testWidgets(
      'a failed background download leaves a banner; Retry downloads '
      'silently again (no progress dialog) and installs', (tester) async {
    failDownloads = true;
    final flow = await pumpApp(tester);
    await tester.runAsync(() async {
      flow.onUpdateFound((await UpdateService.instance.checkForUpdate())!);
    });
    await settle(tester);
    expect(installed, isEmpty);
    expect(readyBanner, findsNothing, reason: 'no banner before it is ready');
    expect(find.byKey(const Key('update.banner.failed')), findsOneWidget);

    await tester.tap(find.byKey(const Key('update.banner.retry')));
    await tester.pump();
    expect(find.text(updateDownloadingSnack), findsWidgets);
    expectNothingPoppedUp();
    await settle(tester);
    expect(silent, [true, true]);
    expect(installed, ['/x/new.apk']);
    expectNothingPoppedUp();
  });

  testWidgets(
      'without the install permission the settings screen is explained '
      'and the install starts on resume', (tester) async {
    installOutcome = 'needs-permission';
    final flow = await pumpApp(tester);
    await tester.runAsync(() async {
      flow.onUpdateFound((await UpdateService.instance.checkForUpdate())!);
    });
    // Short pumps: the SnackBar is read before it times out.
    for (var i = 0; i < 40 && installed.isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump();
    expect(installed, hasLength(1));
    expect(find.textContaining('Allow installs from BestToDo'), findsWidgets);

    installOutcome = 'ok';
    flow.onLifecycleChanged(AppLifecycleState.paused);
    flow.onLifecycleChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(installed, hasLength(2));
  });

  testWidgets(
      'going back to an older build downloads it silently and opens '
      "Android's confirm when complete", (tester) async {
    final flow = await pumpApp(tester);
    final older = UpdateInfo(
      version: '0.0.1+5',
      releaseName: 'BestToDo 0.0.1+5',
      htmlUrl: 'https://example.com/old',
      apkUrl: 'https://example.com/old.apk',
    );
    unawaited(flow.install(older));
    await tester.pump();
    expect(find.text(updateDownloadingSnack), findsWidgets);
    expectNothingPoppedUp();
    await settle(tester);
    expect(silent, [true]);
    expect(installed, ['/x/new.apk']);
    expectNothingPoppedUp();
  });
  /// Opens the changelog over [pumpApp]'s home and waits for its list.
  Future<void> openChangelog(WidgetTester tester) async {
    // A fresh bundle per test: rootBundle caches the load, and a future
    // from an earlier test's zone never completes in this one.
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => DefaultAssetBundle(
            bundle: _ChangelogBundle(),
            child: const ChangelogPage(assetPath: 'CHANGELOG_MUSIC.md'))));
    final list = find.byKey(const Key('changelog-release-list'));
    for (var i = 0; i < 50 && list.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder statusText(String text) => find.descendant(
      of: find.byKey(const Key('changelog-update-status')),
      matching: find.textContaining(text));

  testWidgets(
      'pulling down on the changelog checks and downloads silently; '
      'the status card follows', (tester) async {
    final flow = AutoUpdateFlow.current = await pumpApp(tester);
    await openChangelog(tester);
    expect(statusText('Not checked yet'), findsOneWidget);

    await tester.fling(find.byKey(const Key('changelog-release-list')),
        const Offset(0, 400), 1000);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('v9.9.9+99999 found'), findsOneWidget);
    await settle(tester);
    expect(silent, [true], reason: 'no dialog or progress first');
    expect(flow.readyVersion, '9.9.9+99999');
    // Android's confirm opens once the APK is complete; nothing of the
    // app's own.
    expect(installed, ['/x/new.apk']);
    expectNothingPoppedUp();

    expect(statusText('Update available 9.9.9 (99999)'), findsOneWidget);
    expect(statusText('9.9.9 (99999) downloaded '), findsOneWidget);
    expect(statusText('ready to install'), findsOneWidget);
    expect(statusText('Last checked '), findsOneWidget);
    expect(statusText('null'), findsNothing);
  });

  testWidgets("the status card's Install installs the downloaded build",
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'update_downloaded_apk': '{"version":"9.9.9+99999","path":"/x/old.apk"}',
    });
    AutoUpdateFlow.current = await pumpApp(tester);
    await tester.runAsync(() => UpdateService.instance.checkForUpdate());
    await openChangelog(tester);
    expect(statusText('Update available 9.9.9 (99999)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('changelog-update-install')));
    await settle(tester);
    expect(calls, isNot(contains('startBackgroundDownload')));
    expect(installed, ['/x/old.apk']);
  });

  testWidgets(
      "the status card's Install for a build that isn't downloaded yet: "
      'one SnackBar, passive progress text, then the confirm', (tester) async {
    holdDownloads = true;
    final flow = AutoUpdateFlow.current = await pumpApp(tester);
    final info =
        (await tester.runAsync(() => UpdateService.instance.checkForUpdate()))!;
    await openChangelog(tester);
    expect(statusText('Update available 9.9.9 (99999)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('changelog-update-install')));
    await tester.pump();
    expect(find.text(updateDownloadingSnack), findsWidgets);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(statusText('Downloading 9.9.9 (99999)… 50%'), findsOneWidget);
    expect(find.byKey(const Key('changelog-update-install')), findsNothing);
    expectNothingPoppedUp();
    expect(installed, isEmpty);

    holdDownloads = false;
    await settle(tester);
    expect(silent, [true]);
    expect(installed, ['/x/new.apk']);
    expect(statusText('Downloading'), findsNothing);
    expectNothingPoppedUp();

    // Cancelled (the automatic confirm of this start is used up); a tap
    // still reopens Android's confirm right away, without a new download.
    await tester.runAsync(() => flow.install(info));
    await settle(tester);
    expect(installed, ['/x/new.apk', '/x/new.apk']);
    expect(silent, [true]);
  });
}
