import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

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

  static const String _seenFileName = 'test_report_seen.json';

  TestReport? _report;
  Future<TestReport>? _loadFuture;

  /// Acknowledgement state for the red failure dot: the newest run date the
  /// user has looked at on the Test Results page, plus fingerprints of the
  /// exact reports they saw (so undated reports can be acknowledged too).
  DateTime? _seenGeneratedAt;
  final Set<String> _seenFingerprints = <String>{};

  Future<TestReport>? _onlineFuture;
  TestReport? _onlineOverrideForTest;
  bool _onlineOverridden = false;

  /// The last loaded bundled report, or null before [load] completes.
  TestReport? get report => _report;

  /// Whether the report bundled with this build has failing tests. Drives the
  /// drawer's red dot; uses the bundled report (no network) so startup stays
  /// fast and offline.
  bool get hasFailures => _report?.hasFailures ?? false;

  /// Whether the report bundled with this build has failing tests the user has
  /// not looked at yet. Drives the red dots on the drawer icon and the Test
  /// Results entry: opening the Test Results page calls [markSeen], which
  /// switches this off until a newer failing run shows up.
  bool get hasUnseenFailures {
    final report = _report;
    if (report == null || !report.hasFailures) return false;
    return !_isSeen(report);
  }

  Future<TestReport> load() => _loadFuture ??= _load();

  Future<TestReport> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/test_report.json');
      _report = TestReport.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      _report = TestReport(available: false);
    }
    await _loadSeen();
    return _report!;
  }

  /// A report identity that survives a JSON round-trip, so acknowledging a
  /// report also acknowledges the same run re-read from disk on a later
  /// launch. Dated reports are additionally covered by [_seenGeneratedAt].
  String _fingerprint(TestReport report) =>
      '${report.commit}|${report.generatedAt?.toIso8601String() ?? ''}'
      '|${report.passed}|${report.failed}|${report.skipped}';

  bool _isSeen(TestReport report) {
    if (_seenFingerprints.contains(_fingerprint(report))) return true;
    final date = report.generatedAt;
    final seenUpTo = _seenGeneratedAt;
    return date != null && seenUpTo != null && !date.isAfter(seenUpTo);
  }

  /// Acknowledges [report] (the one the Test Results page just displayed) and
  /// the bundled report driving the red dot. In-memory state updates
  /// synchronously so the UI redraws without the dot right away; the marker
  /// is persisted best-effort so the dot stays off across restarts — until a
  /// run newer than anything acknowledged fails again.
  Future<void> markSeen(TestReport report) {
    var changed = false;
    for (final r in [report, _report]) {
      if (r == null || !r.available) continue;
      final date = r.generatedAt;
      if (date != null &&
          (_seenGeneratedAt == null || date.isAfter(_seenGeneratedAt!))) {
        _seenGeneratedAt = date;
        changed = true;
      }
      if (_seenFingerprints.add(_fingerprint(r))) changed = true;
    }
    return changed ? _writeSeen() : Future.value();
  }

  Future<void> _loadSeen() async {
    if (kIsWeb) return;
    try {
      final file = await _docFile(_seenFileName);
      if (file == null || !await file.exists()) return;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _seenGeneratedAt = DateTime.tryParse(data['generatedAt'] as String? ?? '');
      final prints = data['fingerprints'];
      if (prints is List) _seenFingerprints.addAll(prints.whereType<String>());
    } catch (_) {
      // Unreadable marker just means the dot reappears until re-acknowledged.
    }
  }

  Future<void> _writeSeen() async {
    if (kIsWeb) return;
    try {
      final file = await _docFile(_seenFileName);
      await file?.writeAsString(
        jsonEncode({
          'generatedAt': _seenGeneratedAt?.toIso8601String(),
          // Bounded: only the last few distinct reports need remembering.
          'fingerprints': _seenFingerprints.toList().reversed.take(12).toList(),
        }),
        flush: true,
      );
    } catch (_) {
      // Persisting the acknowledgement is a convenience; a failed write only
      // means the dot comes back on the next launch.
    }
  }

  Future<File?> _docFile(String name) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$name');
    } catch (_) {
      return null; // No file system (web) or path_provider unavailable.
    }
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
  /// Reading the acknowledgement marker is part of a real [load], so the
  /// injected report goes through it too — that is what lets a test assert the
  /// dot stays off across a "restart".
  void setReportForTest(TestReport report) {
    _report = report;
    _loadFuture = _loadSeen().then((_) => report);
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
    _seenGeneratedAt = null;
    _seenFingerprints.clear();
  }
}
