import 'package:besttodo/config.dart';
import 'package:besttodo/services/app_updates.dart';
import 'package:besttodo/ui/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'update_fakes.dart';

/// BestToDo's About page: its update section is the package's "Check for
/// updates" tile on the running app's controller, plus "Go back to an older
/// version" (the flow behind both: update_flow_test.dart). GitHub, the
/// download and the installer are faked (update_fakes.dart).
void main() {
  late FakeGithub github;
  late FakeDownloader downloader;
  late FakeInstaller installer;

  setUp(() {
    Config.resetVersionForTest();
    github = FakeGithub();
    downloader = FakeDownloader();
    installer = FakeInstaller();
  });
  tearDown(() {
    installer.dispose();
    AppUpdates.controller?.dispose();
    AppUpdates.controller = null;
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
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a newer release downloads silently; one SnackBar',
      (tester) async {
    github.releases = [release('v0.2.107-2000')];
    await fakeController(github: github, downloader: downloader).init();
    await pumpAboutPage(tester);
    expect(find.text('Current version 0.2.106 (1000)'), findsOneWidget);

    await tapCheck(tester);
    expect(find.textContaining('Downloading version 0.2.107 (2000) in the '
        'background'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(installer.installs, ['/cache/updates/BestToDo-0.2.107-2000.apk']);
  });

  testWidgets('reports up to date when nothing newer exists', (tester) async {
    github.releases = [release('v0.2.106-1000'), release('music-v9.9.9-9999')];
    await fakeController(github: github, downloader: downloader).init();
    await pumpAboutPage(tester);
    await tapCheck(tester);
    expect(find.text('Up to date'), findsOneWidget);
    expect(downloader.urls, isEmpty);
  });

  testWidgets('a failed check says so', (tester) async {
    github.failStatus = 500;
    await fakeController(github: github, downloader: downloader).init();
    await pumpAboutPage(tester);
    await tapCheck(tester);
    expect(find.text('Could not check for updates'), findsOneWidget);
  });

  testWidgets(
      'a release without an APK (still uploading) is never offered: up to '
      'date', (tester) async {
    github.releases = [release('v0.2.107-2000', apk: false)];
    await fakeController(github: github, downloader: downloader).init();
    await pumpAboutPage(tester);
    await tapCheck(tester);
    expect(find.text('Up to date'), findsOneWidget);
    expect(downloader.urls, isEmpty);
    expect(installer.installs, isEmpty);
    expect(installer.calls.map((c) => c.method), isNot(contains('openUrl')));
  });

  testWidgets('without a controller (no updates here) the section is empty',
      (tester) async {
    await pumpAboutPage(tester);
    expect(find.text('Check for updates'), findsNothing);
    expect(find.textContaining('BestToDo v'), findsOneWidget);
  });
}
