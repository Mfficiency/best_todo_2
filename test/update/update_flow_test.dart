import 'dart:async';
import 'dart:convert';

import 'package:besttodo/services/app_updates.dart';
import 'package:besttodo/ui/about_page.dart';
import 'package:besttodo/ui/changelog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'update_fakes.dart';

/// The automatic update as BestToDo runs it (the updates package through
/// `AppUpdates`, wired in `main.dart`):
/// every download is silent (no notification, dialog, sheet or progress
/// bar), and once the APK is complete Android's own install confirm (the
/// plugin's `installApk`, a PackageInstaller session) is the only question.
/// A cancelled confirm leaves the slim "Update ready" banner; a failed
/// download a banner with Try again. GitHub, the download and the plugin's
/// channel are faked (update_fakes.dart), so everything runs on the fake
/// clock.

class _ChangelogBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
      Uint8List.fromList(utf8.encode('## [0.2.107] - 2026-10-12\n- new\n\n'
          '## [0.2.106] - 2026-10-11\n- running\n\n'
          '## [0.2.105] - 2026-10-10\n- older\n')));
}

void main() {
  late FakeGithub github;
  late FakeDownloader downloader;
  late FakeInstaller installer;
  late UpdateController updates;
  var disposed = true;

  /// Stops the controller's polling (start() runs a periodic timer).
  void disposeUpdates() {
    if (disposed) return;
    disposed = true;
    updates.dispose();
  }
  var now = DateTime(2026, 10, 12, 11, 20);
  final navigatorKey = GlobalKey<NavigatorState>();

  const newer = '/cache/updates/BestToDo-0.2.107-2000.apk';

  setUp(() {
    now = DateTime(2026, 10, 12, 11, 20);
    github = FakeGithub()
      ..releases = [
        release('v0.2.107-2000-dev', prerelease: true),
        release('v0.2.106-1000'),
        release('v0.2.105-900'),
      ];
    downloader = FakeDownloader();
    installer = FakeInstaller();
  });
  tearDown(() {
    installer.dispose();
    disposeUpdates();
    AppUpdates.controller = null;
  });

  /// The app's shell as `main.dart` builds it: the banner below every
  /// screen.
  Future<void> pumpApp(WidgetTester tester, {UpdateStore? store}) async {
    updates = fakeController(
      github: github,
      downloader: downloader,
      store: store,
      clock: () => now,
    );
    disposed = false;
    await updates.init();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      builder: (context, child) => Column(children: [
        Expanded(child: child!),
        UpdateBanner(controller: updates),
      ]),
      home: const Scaffold(body: Text('home')),
    ));
  }

  /// Lets the check, the download and the install call finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Nothing of the app's own takes the screen.
  void expectNothingPoppedUp() {
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  }

  final readyBanner = find.text('Update ready · 0.2.107 (2000)');
  final bannerInstall = find.byKey(const Key('update.banner.install'));

  testWidgets(
      'a newer build downloads silently, then goes straight to '
      "Android's install confirm (no app dialog)", (tester) async {
    await pumpApp(tester);
    await updates.check();
    await settle(tester);
    expect(downloader.urls.single.toString(),
        'https://github.com/Mfficiency/best_todo_2/releases/download/v0.2.107-2000-dev/v0.2.107-2000-dev.apk');
    expect(installer.installs, [newer],
        reason: "Android's dialog is the one confirmation");
    expectNothingPoppedUp();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a download that completes in the background installs on resume',
      (tester) async {
    await pumpApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await updates.check();
    await settle(tester);
    expect(updates.ready.value, '0.2.107+2000');
    expect(installer.installs, isEmpty, reason: 'not while the app is away');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    updates.handleResume();
    await settle(tester);
    expect(installer.installs, [newer]);
    expectNothingPoppedUp();
  });

  testWidgets(
      'a cancelled confirm leaves a slim banner and is not opened again by '
      'itself in this start; its Install reopens it', (tester) async {
    await pumpApp(tester);
    await updates.check();
    await settle(tester);
    expect(installer.installs, hasLength(1));
    // The user cancelled Android's dialog: the app keeps running.
    expect(readyBanner, findsOneWidget);

    // The next poll / coming back finds the same build: no new download,
    // no new confirm.
    await updates.check();
    updates.handleResume();
    await settle(tester);
    expect(downloader.urls, hasLength(1));
    expect(installer.installs, hasLength(1));
    expect(readyBanner, findsOneWidget);

    await tester.tap(bannerInstall);
    await settle(tester);
    expect(installer.installs, [newer, newer]);
    expectNothingPoppedUp();
  });

  testWidgets('an APK downloaded before a restart is reused', (tester) async {
    downloader.files.add(newer);
    await pumpApp(tester);
    await updates.check();
    await settle(tester);
    expect(downloader.urls, isEmpty);
    expect(installer.installs, [newer]);
  });

  testWidgets(
      'a failed background download leaves a banner; Try again downloads '
      'silently again and installs', (tester) async {
    downloader.fail = true;
    await pumpApp(tester);
    await updates.check();
    await settle(tester);
    expect(installer.installs, isEmpty);
    expect(readyBanner, findsNothing, reason: 'no banner before it is ready');
    expect(find.text("Version 0.2.107 (2000) couldn't be downloaded"),
        findsOneWidget);

    downloader.fail = false;
    await tester.tap(find.byKey(const Key('update.banner.retry')));
    await tester.pump();
    // One SnackBar, nothing else.
    expect(find.textContaining('in the background'), findsOneWidget);
    expectNothingPoppedUp();
    await settle(tester);
    expect(downloader.urls, hasLength(2));
    expect(installer.installs, [newer]);
    expectNothingPoppedUp();
  });

  testWidgets(
      'without the install permission its switch is explained and the '
      'install starts on resume', (tester) async {
    installer.installOutcome = 'needs-permission';
    await pumpApp(tester);
    updates.start(navigatorKey.currentContext!);
    await updates.check();
    await settle(tester);
    expect(installer.installs, hasLength(1));
    expect(find.textContaining('Allow from this source'), findsOneWidget);

    installer.installOutcome = 'ok';
    updates.handleResume();
    await settle(tester);
    expect(installer.installs, hasLength(2));
    // start() polls: stop it before the test ends.
    await tester.pump(const Duration(seconds: 5));
    disposeUpdates();
  });

  testWidgets(
      'a tap on Check for updates: one SnackBar, passive progress, then '
      "Android's confirm", (tester) async {
    downloader.hold = Completer<void>();
    await pumpApp(tester);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: UpdateSection())));
    await tester.pumpAndSettle();
    expect(find.text('Current version 0.2.106 (1000)'), findsOneWidget);

    await tester.tap(find.text('Check for updates'));
    await settle(tester);
    expect(
        find.text("Downloading version 0.2.107 (2000) in the background. "
            "You'll be asked to install it when it's ready."),
        findsOneWidget);
    expect(find.text('Downloading version 0.2.107 (2000)… 50 %'),
        findsOneWidget);
    expectNothingPoppedUp();
    expect(installer.installs, isEmpty);

    downloader.hold!.complete();
    await settle(tester);
    expect(installer.installs, [newer]);
    expectNothingPoppedUp();
  });

  testWidgets('up to date: Check for updates says so in a SnackBar',
      (tester) async {
    github.releases = [release('v0.2.106-1000')];
    await pumpApp(tester);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: UpdateSection())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check for updates'));
    await settle(tester);
    expect(find.text('Up to date'), findsOneWidget);
    expect(downloader.urls, isEmpty);
  });

  /// Opens the changelog over [pumpApp]'s home.
  Future<void> openChangelog(WidgetTester tester) async {
    // A fresh bundle per test: rootBundle caches the load.
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => DefaultAssetBundle(
            bundle: _ChangelogBundle(), child: const ChangelogPage())));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('changelog-release-list')), findsOneWidget);
  }

  Finder statusText(String text) => find.descendant(
      of: find.byKey(const Key('changelog-update-status')),
      matching: find.textContaining(text));

  testWidgets(
      'pulling down on the changelog checks and downloads silently; the '
      'status card follows', (tester) async {
    installer.installTime = DateTime(2026, 10, 11, 8, 5);
    await pumpApp(tester);
    updates.start(navigatorKey.currentContext!);
    await openChangelog(tester);
    expect(statusText('Current version 0.2.106 (1000)'), findsOneWidget);
    expect(statusText('Installed 11.10.26'), findsOneWidget);
    expect(statusText('Not checked yet'), findsOneWidget);
    expect(statusText('Pull down to check for updates'), findsOneWidget);

    await tester.fling(find.byKey(const Key('changelog-release-list')),
        const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(github.requests, isNotEmpty);
    expect(installer.installs, [newer]);
    expectNothingPoppedUp();

    expect(statusText('Version 0.2.107 (2000) available'), findsOneWidget);
    expect(statusText('0.2.107 (2000) downloaded 12.10.26'), findsOneWidget);
    expect(statusText('ready to install'), findsOneWidget);
    expect(statusText('Last checked 12.10.26'), findsOneWidget);
    expect(statusText('null'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    disposeUpdates();
  });

  testWidgets(
      "the status card shows when the running build was downloaded and the "
      "card's Install installs the waiting one", (tester) async {
    final store = MemoryUpdateStore({
      UpdateController.downloadedKey: jsonEncode({
        'key': '0.2.106+1000',
        'label': '0.2.106 (1000)',
        'at': DateTime(2026, 10, 11, 7, 45).toIso8601String(),
      }),
    });
    await pumpApp(tester, store: store);
    await openChangelog(tester);
    expect(statusText('Downloaded 11.10.26'), findsOneWidget);
    expect(statusText('Installed 12.10.26'), findsOneWidget,
        reason: "off a phone: the build's first start");

    downloader.fail = true;
    await updates.check();
    await settle(tester);
    expect(installer.installs, isEmpty);
    downloader.fail = false;
    final install = find.descendant(
        of: find.byKey(const Key('changelog-update-status')),
        matching: find.text('Install'));
    await tester.tap(install);
    await settle(tester);
    expect(installer.installs, [newer]);
    expectNothingPoppedUp();
  });

  testWidgets(
      'going back: a tap on an older version in the changelog offers it; '
      "its download is silent, then Android's confirm", (tester) async {
    await pumpApp(tester);
    await openChangelog(tester);
    await tester.tap(find.byKey(const ValueKey('changelog-version-0.2.105')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Export a backup first'), findsOneWidget);

    await tester.tap(find.text('Download version 0.2.105 (900)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('in the background'), findsOneWidget);
    await settle(tester);
    expect(installer.installs, ['/cache/updates/BestToDo-0.2.105-900.apk']);
    expectNothingPoppedUp();
  });

  testWidgets('the running version: "You are using this version"',
      (tester) async {
    github.releases = [release('v0.2.106-1000')];
    await pumpApp(tester);
    await openChangelog(tester);
    expect(find.byKey(const Key('changelog-installed-version')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('changelog-version-0.2.106')));
    await tester.pumpAndSettle();
    expect(find.text('You are using this version'), findsOneWidget);
  });

  testWidgets("About's \"Go back to an older version\" opens the highest "
      'one below the running version', (tester) async {
    await pumpApp(tester);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: UpdateSection())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go back to an older version'));
    await tester.pumpAndSettle();
    expect(find.text('Version 0.2.105'), findsOneWidget);
    expect(find.text('Download version 0.2.105 (900)'), findsOneWidget);
    expect(downloader.urls, isEmpty, reason: 'nothing before the tap');
  });

  testWidgets('no older version: a SnackBar says so', (tester) async {
    github.releases = [release('v0.2.106-1000')];
    await pumpApp(tester);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: UpdateSection())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go back to an older version'));
    await tester.pumpAndSettle();
    expect(find.text('No older version is available to download.'),
        findsOneWidget);
  });
}
