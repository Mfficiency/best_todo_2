import 'package:besttodo/config.dart';
import 'package:besttodo/services/app_updates.dart';
import 'package:besttodo/services/problem_reports.dart';
import 'package:besttodo/ui/about_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// About › Other apps (SPEC.md §11): the last row of About opens the shared
/// package's page with every other Mfficiency app (BestToDo itself left
/// out). GitHub is faked: every app has one release with an APK; the
/// plugin's channel answers "not installed" for every app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Uri> asked;
  const channel = MethodChannel(UpdatePlatform.channelName);
  TestDefaultBinaryMessenger messenger() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger().setMockMethodCallHandler(channel, (call) async => null);
    Config.resetVersionForTest();
    SharedPreferences.setMockInitialValues({});
    asked = [];
    ProblemReports.instance = ProblemReporter(
      config: const ProblemReportConfig(
        appName: 'BestToDo',
        version: '1.0.0',
        build: 1,
        channel: 'dev',
        githubRepo: 'Mfficiency/best_todo_2',
      ),
      collectLogs: () async => '',
      readToken: () async => null,
      writeToken: (_) async {},
      openUrl: (_) async => true,
    );
    AppUpdates.otherApps = AppUpdates.createOtherApps(
      platform: UpdatePlatform(supported: false),
      http: UpdateHttp.from((url, headers, cacheFor) async {
        asked.add(url);
        return [
          {
            'tag_name': 'v1.0.0-100',
            'html_url': 'https://github.com/x/releases/v1.0.0-100',
            'draft': false,
            'prerelease': false,
            'assets': [
              {
                'name': 'app.apk',
                'browser_download_url': 'https://github.com/x/app.apk',
                'url': 'https://api.github.com/x/assets/1',
              },
            ],
          },
        ];
      }),
    );
  });

  tearDown(() {
    messenger().setMockMethodCallHandler(channel, null);
    AppUpdates.otherApps = null;
    ProblemReports.instance = null;
  });

  test('BestToDo is left out of its own list', () {
    final apps = AppUpdates.createOtherApps().apps.map((a) => a.name);
    expect(apps, isNot(contains('BestToDo')));
    expect(apps, contains('Best Music'));
  });

  testWidgets('About ends with Other apps, which lists the other apps',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    await tester.pump();

    final link = find.byKey(const Key('otherApps.link'));
    await tester.scrollUntilVisible(link, 300);
    // The very last thing on the page: nothing below its card.
    final column = tester.widget<Column>(find
        .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Column))
        .first);
    expect(column.children.last.key, const Key('about.otherApps'));

    await tester.tap(link);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Other apps'), findsWidgets);
    expect(find.text('Best Music'), findsOneWidget);
    expect(find.text('BestToDo'), findsNothing);
    expect(asked, isNotEmpty);
    expect(asked.any((u) => u.path.contains('best_todo_2')), isFalse);
  });
}
