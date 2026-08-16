import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../models/test_report.dart';

/// A test report chosen for display, together with where it came from so the
/// UI can label it "latest online run" vs "bundled with this build (offline)".
class DisplayedTestReport {
  final TestReport report;

  /// True when [report] was fetched from the latest online CI build; false
  /// when it fell back to the asset bundled into this APK.
  final bool online;

  const DisplayedTestReport({required this.report, required this.online});
}

/// Loads CI test reports for the Test Results tool.
///
/// Two sources:
/// - **Bundled** (`assets/test_report.json`, written by
///   `tool/generate_test_report.dart` during the APK workflow): the results of
///   the exact build this APK shipped from. Loaded offline at startup to drive
///   the drawer's red failure dot. The committed placeholder has
///   `available: false`, so local builds report "no data" rather than failures.
/// - **Online**: the latest report published by CI on the `dev` branch
///   (`docs/ci/test_report.json`), fetched over the network so the app can show
///   the freshest results even when the installed APK is older. This is the
///   primary source for the Test Results page; the bundled report is the
///   offline fallback.
class TestReportService {
  TestReportService._();

  static final TestReportService instance = TestReportService._();

  /// Raw URL of the latest CI test report, published on `dev` by the APK
  /// workflow. Kept in sync with the publish step in `build-apk.yml`.
  static const String onlineReportUrl =
      'https://raw.githubusercontent.com/Mfficiency/best_todo_2/dev/docs/ci/test_report.json';

  TestReport? _report;
  Future<TestReport>? _loadFuture;

  Future<TestReport>? _onlineFuture;
  TestReport? _onlineOverrideForTest;
  bool _onlineOverridden = false;

  /// The last loaded bundled report, or null before [load] completes.
  TestReport? get report => _report;

  /// Whether the report bundled with this build has failing tests. Drives the
  /// drawer's red dot; uses the bundled report (no network) so startup stays
  /// fast and offline.
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

  /// Fetches the latest CI test report published online (see [onlineReportUrl]).
  /// Any network/parse failure yields an unavailable report so callers can fall
  /// back to the bundled asset. Cached for the session; use [refreshOnline] to
  /// force a re-fetch.
  Future<TestReport> loadOnline() {
    if (_onlineOverridden) {
      return Future.value(_onlineOverrideForTest ?? TestReport(available: false));
    }
    return _onlineFuture ??= _loadOnline();
  }

  Future<TestReport> _loadOnline() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(onlineReportUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        return TestReport(available: false);
      }
      final body = await response.transform(utf8.decoder).join();
      return TestReport.fromJson(jsonDecode(body) as Map<String, dynamic>);
    } catch (_) {
      return TestReport(available: false);
    } finally {
      client?.close(force: true);
    }
  }

  /// Clears the cached online report so the next [loadOnline]/[loadForDisplay]
  /// re-fetches (used by the Test Results page's refresh action).
  void refreshOnline() {
    if (!_onlineOverridden) _onlineFuture = null;
  }

  /// Picks the report the Test Results page should show: the latest online
  /// report when reachable, otherwise the report bundled with this build.
  Future<DisplayedTestReport> loadForDisplay() async {
    final online = await loadOnline();
    if (online.available) {
      return DisplayedTestReport(report: online, online: true);
    }
    final bundled = await load();
    return DisplayedTestReport(report: bundled, online: false);
  }

  /// Injects a bundled report so widget tests can exercise the UI without a
  /// bundled asset.
  void setReportForTest(TestReport report) {
    _report = report;
    _loadFuture = Future.value(report);
  }

  /// Injects (or, with null, disables) the online report so widget tests never
  /// hit the network. Pass an unavailable report to force the bundled fallback.
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
