import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/test_report.dart';

/// Loads the CI test report bundled into this build
/// (`assets/test_report.json`, written by `tool/generate_test_report.dart`
/// during the APK workflow). The committed placeholder has
/// `available: false`, so local builds report "no data" rather than failures.
class TestReportService {
  TestReportService._();

  static final TestReportService instance = TestReportService._();

  TestReport? _report;
  Future<TestReport>? _loadFuture;

  /// The last loaded report, or null before [load] completes.
  TestReport? get report => _report;

  bool get hasFailures => _report?.hasFailures ?? false;

  Future<TestReport> load() => _loadFuture ??= _load();

  Future<TestReport> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/test_report.json');
      _report = TestReport.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      _report = TestReport(available: false);
    }
    return _report!;
  }

  /// Injects a report so widget tests can exercise the failure UI without a
  /// bundled asset.
  void setReportForTest(TestReport report) {
    _report = report;
    _loadFuture = Future.value(report);
  }

  void resetForTest() {
    _report = null;
    _loadFuture = null;
  }
}
