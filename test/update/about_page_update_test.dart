import 'dart:convert';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/update_service.dart';
import 'package:besttodo/ui/about_page.dart';
import 'package:besttodo/ui/auto_update_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The About page's update section, with the release lookup (the GitHub
/// releases list) faked through [UpdateService.fetchOverride] so no network
/// is touched. The running version is mocked to 0.0.0+0 — so a v0.0.0-0
/// release means "up to date" and anything real means "update".
void main() {
  void mockRunningVersion(String version, String build) =>
      PackageInfo.setMockInitialValues(
          appName: 'BestToDo',
          packageName: 'com.mfficiency.best_todo_2',
          version: version,
          buildNumber: build,
          buildSignature: '');

  setUp(() {
    mockRunningVersion('0.0.0', '0');
    Config.resetVersionForTest();
    UpdateService.resetForTest();
  });

  tearDown(() {
    UpdateService.resetForTest();
  });

  Map<String, dynamic> release(String tag, {bool withApk = true}) => {
        'tag_name': tag,
        'name': 'BestToDo release',
        'html_url': 'https://example.com/release',
        'prerelease': false,
        'assets': [
          if (withApk)
            {
              'name': 'BestToDo.apk',
              'browser_download_url': 'https://example.com/$tag.apk',
              'size': 52428800,
            },
        ],
      };

  String releaseJson(String tag, {bool withApk = true}) =>
      jsonEncode([release(tag, withApk: withApk)]);

  Future<void> pumpAboutPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pump();
  }

  Future<void> tapCheck(WidgetTester tester) async {
    // The update section sits below the fold of the 600px test viewport.
    await tester.ensureVisible(find.text('Check for updates'));
    await tester.pump();
    await tester.tap(find.text('Check for updates'));
    // The check awaits PackageInfo (a platform-channel call): give the real
    // event loop a few slices so the await chain completes (see CLAUDE.md on
    // I/O started inside a tap handler).
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('offers a newer release for download', (tester) async {
    UpdateService.instance.fetchOverride =
        (url) async => releaseJson('v9.9.9-999');

    await pumpAboutPage(tester);
    expect(find.text('Check for updates'), findsOneWidget);

    await tapCheck(tester);

    expect(find.text('Version 9.9.9+999 is available.'), findsOneWidget);
    expect(find.textContaining('Download & install'), findsOneWidget);
  });

  testWidgets('reports up to date when nothing newer exists', (tester) async {
    UpdateService.instance.fetchOverride =
        (url) async => releaseJson('v0.0.0-0');

    await pumpAboutPage(tester);
    await tapCheck(tester);

    expect(find.textContaining('You are on the latest version'),
        findsOneWidget);
    expect(find.textContaining('Download & install'), findsNothing);
  });

  testWidgets('release without an APK falls back to the release page',
      (tester) async {
    UpdateService.instance.fetchOverride =
        (url) async => releaseJson('v9.9.9-999', withApk: false);

    await pumpAboutPage(tester);
    await tapCheck(tester);

    expect(find.text('Open release page'), findsOneWidget);
  });

  /// Several releases of this app, plus the other app's newer one that must
  /// be ignored.
  String releasesJson(List<String> tags) => jsonEncode([
        for (final t in tags) release(t),
        release('music-v9.9.9-99999'),
      ]);

  testWidgets('offers the highest build plus one version back',
      (tester) async {
    mockRunningVersion('0.1.143', '115');
    UpdateService.instance.fetchOverride = (url) async =>
        releasesJson(['v0.1.142-114', 'v0.1.143-115', 'v0.1.144-116']);

    await pumpAboutPage(tester);
    await tapCheck(tester);

    expect(find.text('Version 0.1.144+116 is available.'), findsOneWidget);
    expect(find.textContaining('Download & install'), findsOneWidget);
    expect(find.textContaining('Go back to 0.1.142+114'), findsOneWidget);
    expect(
        find.textContaining('Reinstalls the previous build'), findsOneWidget);
  });

  testWidgets('the highest build of any channel is offered',
      (tester) async {
    mockRunningVersion('0.1.143', '115');
    UpdateService.instance.fetchOverride = (url) async => releasesJson(
        ['v0.1.144-116', 'v0.1.143-118-dev', 'v0.1.145-117-staging']);

    await pumpAboutPage(tester);
    await tapCheck(tester);

    expect(find.text('Version 0.1.143+118 is available.'), findsOneWidget);
    expect(find.textContaining('Download & install'), findsOneWidget);
  });

  testWidgets('no rollback button without a lower build',
      (tester) async {
    UpdateService.instance.fetchOverride =
        (url) async => releasesJson(['v0.1.143-115']);

    await pumpAboutPage(tester);
    await tapCheck(tester);

    expect(find.text('Version 0.1.143+115 is available.'), findsOneWidget);
    expect(find.textContaining('Go back to'), findsNothing);
  });

  testWidgets('a failed check shows the error and allows a retry',
      (tester) async {
    UpdateService.instance.fetchOverride =
        (url) async => throw Exception('offline');

    await pumpAboutPage(tester);
    await tapCheck(tester);

    expect(find.textContaining('Update check failed'), findsOneWidget);
    // The check button stays usable for a retry.
    UpdateService.instance.fetchOverride =
        (url) async => releaseJson('v9.9.9-999');
    await tapCheck(tester);
    expect(find.text('Version 9.9.9+999 is available.'), findsOneWidget);
  });

  group('downloads are silent', () {
    late List<bool> silent;
    late List<String> installed;
    late bool hold;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      silent = [];
      installed = [];
      hold = false;
    });
    tearDown(() => AutoUpdateFlow.current = null);

    void fakeDownloads() {
      UpdateService.instance
        ..fileExistsOverride = ((_) => true)
        ..downloadChannelOverride = (method, args) async {
          switch (method) {
            case 'startBackgroundDownload':
              silent.add(args['silent'] == true);
              return {'downloadId': 1};
            case 'queryDownload':
              return hold
                  ? {
                      'status': 'running',
                      'bytesDownloaded': 26214400,
                      'bytesTotal': 52428800,
                    }
                  : {'status': 'successful', 'localPath': '/x/u.apk'};
            case 'installApk':
              installed.add(args['path'] as String);
              return 'ok';
          }
          return null;
        };
    }

    Future<void> settle(WidgetTester tester, {int rounds = 10}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    void expectNothingPoppedUp() {
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    }

    testWidgets(
        'Download & install: one SnackBar and passive text, no progress '
        "bar; Android's confirm once complete", (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      UpdateService.instance.fetchOverride =
          (url) async => releaseJson('v9.9.9-999');
      fakeDownloads();
      hold = true;
      await pumpAboutPage(tester);
      await tapCheck(tester);

      await tester.ensureVisible(find.textContaining('Download & install'));
      await tester.tap(find.textContaining('Download & install'));
      await settle(tester, rounds: 4);
      expect(find.text(updateDownloadingSnack), findsOneWidget);
      expect(find.textContaining('Downloading 9.9.9+999 in the background… 50%'),
          findsOneWidget);
      expectNothingPoppedUp();
      expect(silent, [true]);
      expect(installed, isEmpty);

      hold = false;
      await settle(tester);
      expect(installed, ['/x/u.apk']);
      expect(find.byKey(const Key('about.update.downloading')), findsNothing);
      expectNothingPoppedUp();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        "Go back to: the running app's flow downloads the older build "
        'silently and opens the confirm', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      mockRunningVersion('0.1.143', '115');
      UpdateService.instance.fetchOverride =
          (url) async => releasesJson(['v0.1.142-114', 'v0.1.143-115']);
      fakeDownloads();
      final navigatorKey = GlobalKey<NavigatorState>();
      AutoUpdateFlow.current = AutoUpdateFlow(navigatorKey: navigatorKey);
      await tester.pumpWidget(
          MaterialApp(navigatorKey: navigatorKey, home: const AboutPage()));
      await tester.pump();
      await tapCheck(tester);

      await tester.ensureVisible(find.textContaining('Go back to 0.1.142+114'));
      await tester.tap(find.textContaining('Go back to 0.1.142+114'));
      await tester.pump();
      expect(find.text(updateDownloadingSnack), findsOneWidget);
      expect(find.textContaining('Android blocks downgrades'), findsOneWidget);
      expectNothingPoppedUp();
      await settle(tester, rounds: 20);
      expect(silent, [true]);
      expect(installed, ['/x/u.apk']);
      expectNothingPoppedUp();
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
