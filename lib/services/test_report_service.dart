import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../models/test_report.dart';

/// Where a displayed report came from.
enum TestReportSource {
  /// Fetched from the `ci-reports` branch during this session.
  online,

  /// Read from the on-disk copy of the last successful online fetch.
  cached,

  /// Read from `assets/test_report.json`, packaged into this build.
  bundled,
}

/// A test report chosen for display, together with where it came from so the
/// UI can say whether it is fresh off CI, a cached fetch, or the copy baked
/// into the installed build.
class DisplayedTestReport {
  final TestReport report;
  final TestReportSource source;

  const DisplayedTestReport({required this.report, required this.source});

  /// True when [report] was fetched from CI during this session.
  bool get online => source == TestReportSource.online;

  String get sourceLabel {
    switch (source) {
      case TestReportSource.online:
        return 'Fetched just now from CI';
      case TestReportSource.cached:
        return 'Last fetched results (offline)';
      case TestReportSource.bundled:
        return 'Packaged with this build (offline)';
    }
  }
}

/// Loads test reports for the Test Results tool from three layers, and always
/// shows whichever ran **last** (`TestReport.newest`) rather than preferring a
/// layer — so the newest run wins no matter which branch or machine produced
/// it:
///
/// - **Bundled** (`assets/test_report.json`): packaged into every build,
///   Android or web, debug or release. `tool/sync_test_report.dart` fills it
///   in before the build (in CI and locally), and the file is committed, so a
///   fresh checkout — or `flutter run -d chrome` with no network at all — still
///   shows real results. Drives the drawer's red failure dot.
/// - **Cached** (`test_report_cache.json` in the app documents dir): the last
///   report this install fetched online, kept so a later offline launch is not
///   stuck with whatever the build shipped.
/// - **Online** (`latest.json` on the `ci-reports` branch, see
///   [onlineReportUrl]): the newest run CI published from *any* branch. Best
///   effort — every failure degrades to "unavailable" and the offline layers
///   carry the page.
class TestReportService {
  TestReportService._();

  static final TestReportService instance = TestReportService._();

  /// Raw URL of the newest report CI published, across all branches. The
  /// `ci-reports` branch is an orphan report store (no app code, so it never
  /// triggers a build); written by `tool/ci/publish_test_report.sh`.
  static const String onlineReportUrl =
      'https://raw.githubusercontent.com/Mfficiency/best_todo_2/ci-reports/latest.json';

  static const String _cacheFileName = 'test_report_cache.json';

  TestReport? _bundled;
  TestReport? _cached;
  TestReport? _offlineBest;
  Future<TestReport>? _loadFuture;

  Future<TestReport>? _onlineFuture;
  TestReport? _onlineOverrideForTest;
  bool _onlineOverridden = false;

  /// The best report available without a network (newest of bundled and
  /// cached), or null before [load] completes.
  TestReport? get report => _offlineBest;

  /// Whether the newest report available offline has failing tests. Drives the
  /// drawer's red dot: no network, so startup stays fast and works on a plane.
  bool get hasFailures => _offlineBest?.hasFailures ?? false;

  /// Loads the offline layers (bundled asset + disk cache) and keeps the newer.
  Future<TestReport> load() => _loadFuture ??= _load();

  Future<TestReport> _load() async {
    _bundled = await _loadBundled();
    _cached = await _loadCached();
    _offlineBest = TestReport.newest([_bundled, _cached]) ??
        _bundled ??
        TestReport(available: false);
    return _offlineBest!;
  }

  Future<TestReport> _loadBundled() async {
    try {
      final raw = await rootBundle.loadString('assets/test_report.json');
      return TestReport.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return TestReport(available: false);
    }
  }

  Future<TestReport> _loadCached() async {
    if (kIsWeb) return TestReport(available: false);
    try {
      final file = await _cacheFile();
      if (file == null || !await file.exists()) {
        return TestReport(available: false);
      }
      final raw = await file.readAsString();
      return TestReport.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return TestReport(available: false);
    }
  }

  Future<File?> _cacheFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_cacheFileName');
    } catch (_) {
      return null; // No file system (web) or path_provider unavailable.
    }
  }

  Future<void> _writeCache(TestReport report) async {
    if (kIsWeb || !report.available) return;
    try {
      final file = await _cacheFile();
      await file?.writeAsString(jsonEncode(report.toJson()), flush: true);
      _cached = report;
    } catch (_) {
      // Caching is a convenience; a read-only or full disk just means the next
      // offline launch falls back to the bundled report.
    }
  }

  /// Fetches the newest report CI published (see [onlineReportUrl]). Any
  /// network/parse failure yields an unavailable report so callers fall back to
  /// the offline layers. Cached for the session; use [refreshOnline] to force a
  /// re-fetch. A successful fetch is also written to the disk cache.
  Future<TestReport> loadOnline() {
    if (_onlineOverridden) {
      return Future.value(
          _onlineOverrideForTest ?? TestReport(available: false));
    }
    return _onlineFuture ??= _loadOnline();
  }

  Future<TestReport> _loadOnline() async {
    if (kIsWeb) {
      // dart:io networking is unavailable in the browser; the packaged asset is
      // the source of truth for `flutter run -d chrome`.
      return TestReport(available: false);
    }
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(onlineReportUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        return TestReport(available: false);
      }
      final body = await response.transform(utf8.decoder).join();
      final report =
          TestReport.fromJson(jsonDecode(body) as Map<String, dynamic>);
      await _writeCache(report);
      return report;
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

  /// Picks the report the Test Results page should show: whichever of the three
  /// layers ran most recently. Ties (or undated reports) prefer the fresher
  /// source, online → cached → bundled.
  Future<DisplayedTestReport> loadForDisplay() async {
    final online = await loadOnline();
    await load();
    final layers = <TestReportSource, TestReport?>{
      TestReportSource.online: online,
      TestReportSource.cached: _cached,
      TestReportSource.bundled: _bundled,
    };
    final winner = TestReport.newest(layers.values);
    if (winner == null) {
      return DisplayedTestReport(
        report: _bundled ?? TestReport(available: false),
        source: TestReportSource.bundled,
      );
    }
    final source = layers.entries
        .firstWhere((entry) => identical(entry.value, winner))
        .key;
    return DisplayedTestReport(report: winner, source: source);
  }

  /// Injects a bundled report so widget tests can exercise the UI without a
  /// bundled asset.
  void setReportForTest(TestReport report) {
    _bundled = report;
    _cached = TestReport(available: false);
    _offlineBest = report;
    _loadFuture = Future.value(report);
  }

  /// Injects the on-disk cached report (the last online fetch) without touching
  /// the file system.
  void setCachedReportForTest(TestReport report) {
    _cached = report;
    _bundled ??= TestReport(available: false);
    _offlineBest = TestReport.newest([_bundled, _cached]) ?? _bundled;
    _loadFuture = Future.value(_offlineBest!);
  }

  /// Injects (or, with null, disables) the online report so widget tests never
  /// hit the network. Pass an unavailable report to force the offline layers.
  void setOnlineReportForTest(TestReport? report) {
    _onlineOverridden = true;
    _onlineOverrideForTest = report;
    _onlineFuture = null;
  }

  void resetForTest() {
    _bundled = null;
    _cached = null;
    _offlineBest = null;
    _loadFuture = null;
    _onlineFuture = null;
    _onlineOverridden = false;
    _onlineOverrideForTest = null;
  }
}
