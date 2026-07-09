import 'package:besttodo/models/test_report.dart';
import 'package:besttodo/services/test_report_service.dart';
import 'package:besttodo/ui/test_results_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    TestReportService.instance.resetForTest();
  });

  tearDown(() {
    TestReportService.instance.resetForTest();
  });

  testWidgets('shows summary and failing tests of the bundled report',
      (tester) async {
    TestReportService.instance.setReportForTest(TestReport(
      available: true,
      generatedAt: DateTime.utc(2026, 7, 9, 6, 0),
      commit: 'abc123def',
      branch: 'dev',
      passed: 40,
      failed: 2,
      skipped: 1,
      failures: [
        TestFailureDetail(name: 'first broken test', error: 'Expected X'),
        TestFailureDetail(name: 'second broken test'),
      ],
    ));

    await tester.pumpWidget(const MaterialApp(home: TestResultsPage()));
    await tester.pumpAndSettle();

    expect(find.text('2 tests failed'), findsOneWidget);
    expect(
      find.text('40 passed · 2 failed · 1 skipped · 43 total'),
      findsOneWidget,
    );
    expect(find.textContaining('commit abc123def (dev)'), findsOneWidget);
    expect(find.text('first broken test'), findsOneWidget);
    expect(find.text('second broken test'), findsOneWidget);

    // Expanding a failure reveals its error output.
    await tester.tap(find.text('first broken test'));
    await tester.pumpAndSettle();
    expect(find.text('Expected X'), findsOneWidget);
  });

  testWidgets('shows all-green summary without a failure list',
      (tester) async {
    TestReportService.instance.setReportForTest(TestReport(
      available: true,
      passed: 43,
    ));

    await tester.pumpWidget(const MaterialApp(home: TestResultsPage()));
    await tester.pumpAndSettle();

    expect(find.text('All tests passed'), findsOneWidget);
    expect(find.text('Failed tests'), findsNothing);
  });

  testWidgets('explains when no report is bundled (local/dev builds)',
      (tester) async {
    TestReportService.instance.setReportForTest(TestReport(available: false));

    await tester.pumpWidget(const MaterialApp(home: TestResultsPage()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No test report was bundled'),
      findsOneWidget,
    );
  });
}
