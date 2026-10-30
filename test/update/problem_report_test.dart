import 'dart:io';

import 'package:besttodo/models/sync_log_entry.dart';
import 'package:besttodo/services/log_service.dart';
import 'package:besttodo/services/problem_reports.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/sync_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:besttodo/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart'
    show ProblemReportConfig;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// A reporter on fakes: no file I/O, no secure storage, no network.
ProblemReporter _fakeReporter({String? token}) {
  var saved = token;
  return ProblemReporter(
    config: const ProblemReportConfig(
      appName: 'BestToDo',
      version: '1.0.0',
      build: 1,
      channel: 'dev',
      githubRepo: 'Mfficiency/best_todo_2',
    ),
    collectLogs: () async => 'fake log line',
    readToken: () async => saved,
    writeToken: (t) async => saved = t,
    openUrl: (_) async => true,
  );
}

void main() {
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
    ProblemReports.instance = _fakeReporter();
  });

  tearDown(() => ProblemReports.instance = null);

  test('the app reports to its own repo', () {
    final reporter = ProblemReports.create();
    expect(reporter.config.githubRepo, 'Mfficiency/best_todo_2');
    expect(reporter.config.appName, 'BestToDo');
  });

  test('the report carries every log source, app log last', () async {
    LogService.clear();
    LogService.add('test', 'something happened');
    SyncService.instance.entries.value = [
      SyncLogEntry(
          at: DateTime(2026, 1, 2),
          durationMs: 5,
          itemCount: 3,
          success: false,
          message: 'folder gone'),
    ];
    final logs = await ProblemReports.collectLogs();
    expect(logs, contains('===== Sync history'));
    expect(logs, contains('FAIL 3 items 5 ms — folder gone'));
    expect(logs, contains('===== Todoist sync history'));
    expect(logs, contains('===== Alarm log'));
    expect(logs, contains('[test] something happened'));
    expect(logs.indexOf('===== App log'),
        greaterThan(logs.indexOf('===== Alarm log')));
    LogService.clear();
  });

  testWidgets('a double tap on the name/version in the menu opens the report',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    final header = find.byKey(const Key('problemReport.trigger'));
    expect(header, findsOneWidget);
    expect(find.descendant(of: header, matching: find.textContaining('BestToDo v')),
        findsOneWidget);
    await tester.tap(header);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(header);
    await tester.pumpAndSettle();

    expect(find.text('Report a problem to Claude'), findsOneWidget);
    expect(find.text('Send to Claude'), findsOneWidget);
    expect(find.byKey(const Key('problemReport.text')), findsOneWidget);
    expect(find.byKey(const Key('problemReport.logs')), findsOneWidget);
  });

  testWidgets('Settings › Debugging token dialog: the field, the steps folded away',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    final header = find.byTooltip('Expand Debugging');
    await tester.scrollUntilVisible(header, 80,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();

    final tile = find.byKey(const Key('problemReport.settings'));
    await tester.scrollUntilVisible(tile, 80,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();

    // The field first, close always there; the steps are folded away.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byKey(const Key('githubToken.close')), findsOneWidget);
    expect(find.textContaining('Issues: "Read and write"'), findsNothing);
    await tester.tap(find.byKey(const Key('githubToken.howTo')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Issues: "Read and write"'), findsOneWidget);
    expect(find.textContaining('CLAUDE_CODE_OAUTH_TOKEN'), findsWidgets);
  });
}
