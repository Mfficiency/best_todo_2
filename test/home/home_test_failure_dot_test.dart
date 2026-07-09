import 'dart:io';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/test_report.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/test_report_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
    TestReportService.instance.resetForTest();
    // The Test Results page pulls online; keep the network out of tests so it
    // falls back to the bundled report set per test.
    TestReportService.instance
        .setOnlineReportForTest(TestReport(available: false));
  });

  tearDown(() {
    TestReportService.instance.resetForTest();
  });

  Future<void> pumpHomeUntilLoaded(WidgetTester tester) async {
    await tester.runAsync(() => StorageService()
        .saveTaskList([Task(title: 'Alpha', dueDate: DateTime.now())]));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    // Iterate real-event-loop slices until HomePage's file loads finish (see
    // home_search_test.dart for why a single delay is not enough).
    final marker = find.text('Alpha');
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(marker, findsOneWidget, reason: 'HomePage never loaded the tasks');
  }

  testWidgets(
      'hamburger icon carries a red dot when the bundled test report has '
      'failures, and Test Results opens from the Tools section', (tester) async {
    TestReportService.instance.setReportForTest(TestReport(
      available: true,
      passed: 42,
      failed: 1,
      failures: [TestFailureDetail(name: 'broken test', error: 'boom')],
    ));

    await pumpHomeUntilLoaded(tester);

    final dot = find.byKey(const Key('test-failure-dot'));
    expect(dot, findsOneWidget);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    // Test Results now lives under the Tools expander; open it, then the
    // entry (with its own failure dot) appears.
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Test Results'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(dot, findsWidgets);
    await tester.tap(find.text('Test Results'));
    // The page loads through a FutureBuilder; pump fixed frames rather than
    // pumpAndSettle (see test_results_page_test.dart).
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('1 test failed'), findsOneWidget);
    expect(find.text('broken test'), findsOneWidget);
  });

  testWidgets('no red dot when no report is bundled', (tester) async {
    TestReportService.instance.setReportForTest(TestReport(available: false));

    await pumpHomeUntilLoaded(tester);

    expect(find.byKey(const Key('test-failure-dot')), findsNothing);
    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
  });

  testWidgets('no red dot when the bundled report is all green',
      (tester) async {
    TestReportService.instance.setReportForTest(TestReport(
      available: true,
      passed: 43,
    ));

    await pumpHomeUntilLoaded(tester);

    expect(find.byKey(const Key('test-failure-dot')), findsNothing);
  });
}
