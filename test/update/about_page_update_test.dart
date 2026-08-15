import 'dart:convert';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/update_service.dart';
import 'package:besttodo/ui/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The About page's update section, with the release lookup faked through
/// [UpdateService.fetchOverride] so no network is touched. In widget tests the
/// app version is 'unknown' (no PackageInfo), which compares as 0.0.0 — so a
/// v0.0.0-0 release means "up to date" and anything real means "update".
void main() {
  setUp(() {
    Config.resetVersionForTest();
    UpdateService.resetForTest();
  });

  tearDown(() {
    UpdateService.resetForTest();
  });

  String releaseJson(String tag, {bool withApk = true}) => jsonEncode({
        'tag_name': tag,
        'name': 'BestToDo release',
        'html_url': 'https://example.com/release',
        'assets': [
          if (withApk)
            {
              'name': 'BestToDo.apk',
              'browser_download_url': 'https://example.com/BestToDo.apk',
              'size': 52428800,
            },
        ],
      });

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
}
