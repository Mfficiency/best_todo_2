import 'package:besttodo/config.dart';
import 'package:besttodo/models/test_report.dart';
import 'package:besttodo/services/test_report_service.dart';
import 'package:besttodo/ui/test_results_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  // The page loads its report through a FutureBuilder. pumpAndSettle can hang
  // between tests on a scheduled frame the harness carries over, so round-pump
  // with runAsync until the version card (always shown once loaded) appears.
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: TestResultsPage()));
    final loaded = find.byType(Card);
    for (var i = 0; i < 60 && loaded.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  setUp(() {
    // Deterministic "current" version so the version card's match/mismatch
    // logic is testable. Config reads it lazily via PackageInfo; reset its
    // memoized future so each test reloads it in its own async zone.
    Config.resetVersionForTest();
    PackageInfo.setMockInitialValues(
      appName: 'BestToDo',
      packageName: 'com.example.besttodo',
      version: '9.9.9',
      buildNumber: '99',
      buildSignature: '',
    );
    TestReportService.instance.resetForTest();
    // Default: no online report, so tests exercise the bundled fallback unless
    // they opt into an online report explicitly. Keeps the network out of tests.
    TestReportService.instance
        .setOnlineReportForTest(TestReport(available: false));
  });

  tearDown(() {
    TestReportService.instance.resetForTest();
  });

  testWidgets('falls back to the bundled report when offline', (tester) async {
    TestReportService.instance.setReportForTest(TestReport(
      available: true,
      generatedAt: DateTime.utc(2026, 7, 9, 6, 0),
      commit: 'abc123def',
      branch: 'dev',
      appVersion: '0.1.90+60',
      passed: 40,
      failed: 2,
      skipped: 1,
      failures: [
        TestFailureDetail(name: 'first broken test', error: 'Expected X'),
        TestFailureDetail(name: 'second broken test'),
      ],
    ));

    await pumpPage(tester);

    expect(find.text('Bundled with this build (offline)'), findsOneWidget);
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
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(find.text('Expected X'), findsOneWidget);
  });

  testWidgets('prefers the latest online report over the bundled one',
      (tester) async {
    TestReportService.instance.setReportForTest(TestReport(
      available: true,
      passed: 1,
      appVersion: '0.1.90+60',
    ));
    TestReportService.instance.setOnlineReportForTest(TestReport(
      available: true,
      branch: 'dev',
      appVersion: '9.9.9+99',
      passed: 43,
    ));

    await pumpPage(tester);

    expect(find.text('Latest online run · dev'), findsOneWidget);
    expect(find.text('All tests passed'), findsOneWidget);
    expect(
      find.text('43 passed · 0 failed · 0 skipped · 43 total'),
      findsOneWidget,
    );
  });

  testWidgets('states current vs tested version and flags a mismatch',
      (tester) async {
    TestReportService.instance.setOnlineReportForTest(TestReport(
      available: true,
      branch: 'dev',
      appVersion: '0.1.90+60',
      passed: 43,
    ));

    await pumpPage(tester);

    expect(find.text('You are running'), findsOneWidget);
    expect(find.text('9.9.9+99'), findsOneWidget); // current
    expect(find.text('Version tested'), findsOneWidget);
    expect(find.text('0.1.90+60'), findsOneWidget); // tested
    expect(find.textContaining('different version'), findsOneWidget);
  });

  testWidgets('confirms a match when tested version equals current',
      (tester) async {
    TestReportService.instance.setOnlineReportForTest(TestReport(
      available: true,
      branch: 'dev',
      appVersion: '9.9.9+99',
      passed: 43,
    ));

    await pumpPage(tester);

    expect(
      find.text('These results are for the version you are running.'),
      findsOneWidget,
    );
  });

  testWidgets('shows all-green summary without a failure list',
      (tester) async {
    TestReportService.instance.setOnlineReportForTest(TestReport(
      available: true,
      passed: 43,
    ));

    await pumpPage(tester);

    expect(find.text('All tests passed'), findsOneWidget);
    expect(find.text('Failed tests'), findsNothing);
  });

  testWidgets('explains when neither online nor bundled report is available',
      (tester) async {
    TestReportService.instance.setReportForTest(TestReport(available: false));

    await pumpPage(tester);

    expect(find.textContaining('no report was bundled'), findsOneWidget);
  });
}
