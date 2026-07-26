import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../models/test_report.dart';

/// A report chosen for display, plus where it came from so the UI can label it
/// "latest online run" vs "bundled with this build (offline)".
class DisplayedTestReport {
  final TestReport report;
  final bool online;
  const DisplayedTestReport({required this.report, required this.online});
}

/// Loads CI test reports for the Test Results page. Two sources:
///
///  * **Bundled** (`assets/test_report.json`, written by
///    `tool/generate_test_report.dart` during the build): the results of the
///    exact build this binary shipped from. Loaded offline; the committed
///    placeholder is `available: false`.
///  * **Online** (optional): set [onlineReportUrl] to a raw URL your CI
///    publishes so an old install can still show the freshest results. Empty by
///    default — nothing is hard-coded to a specific repo.
class TestReportService {
  TestReportService._();
  static final TestReportService instance = TestReportService._();

  /// Raw URL of the latest CI report, or empty to disable online fetching.
  /// Point this at e.g. a `docs/ci/test_report.json` published on your default
  /// branch. Configure per app.
  static String onlineReportUrl = '';

  TestReport? _report;
  Future<TestReport>? _loadFuture;
  Future<TestReport>? _onlineFuture;
  TestReport? _onlineOverrideForTest;
  bool _onlineOverridden = false;

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

  Future<TestReport> loadOnline() {
    if (_onlineOverridden) {
      return Future.value(
          _onlineOverrideForTest ?? TestReport(available: false));
    }
    if (onlineReportUrl.isEmpty) return Future.value(TestReport(available: false));
    return _onlineFuture ??= _loadOnline();
  }

  Future<TestReport> _loadOnline() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(onlineReportUrl));
      final response = await request.close();
      if (response.statusCode != 200) return TestReport(available: false);
      final body = await response.transform(utf8.decoder).join();
      return TestReport.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return TestReport(available: false);
    } finally {
      client?.close(force: true);
    }
  }

  void refreshOnline() {
    if (!_onlineOverridden) _onlineFuture = null;
  }

  /// Picks the report to show: the latest online report when reachable,
  /// otherwise the bundled one.
  Future<DisplayedTestReport> loadForDisplay() async {
    final online = await loadOnline();
    if (online.available) {
      return DisplayedTestReport(report: online, online: true);
    }
    return DisplayedTestReport(report: await load(), online: false);
  }

  void setReportForTest(TestReport report) {
    _report = report;
    _loadFuture = Future.value(report);
  }

  void setOnlineReportForTest(TestReport? report) {
    _onlineOverridden = true;
    _onlineOverrideForTest = report;
    _onlineFuture = null;
  }

  void resetForTest() {
    _report = null;
    _loadFuture = null;
    _onlineFuture = null;
    _onlineOverridden = false;
    _onlineOverrideForTest = null;
  }
}
