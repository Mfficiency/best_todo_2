import 'dart:convert';

/// One executed test case — any outcome, not just failures — grouped under the
/// suite (test file) that ran it. This is what lets the Test Results page show
/// detail for green runs too.
class TestCaseResult {
  String name;

  /// 'passed', 'failed' or 'skipped'.
  String result;

  /// Wall-clock time the test took, in milliseconds. Null when the machine
  /// stream carried no timestamps (older reports, hand-written fixtures).
  int? durationMs;

  TestCaseResult({this.name = '', this.result = 'passed', this.durationMs});

  Map<String, dynamic> toJson() => {
        'name': name,
        'result': result,
        'durationMs': durationMs,
      };

  factory TestCaseResult.fromJson(Map<String, dynamic> json) {
    return TestCaseResult(
      name: json['name'] as String? ?? '',
      result: json['result'] as String? ?? 'passed',
      durationMs: (json['durationMs'] as num?)?.round(),
    );
  }
}

/// All test cases of one suite (one `*_test.dart` file) from a run.
class TestSuiteResult {
  /// Suite path relative to the repo root (`test/core/task_test.dart`); the
  /// machine stream's absolute path is trimmed at parse time. Empty when the
  /// stream never named the suite.
  String path;
  List<TestCaseResult> tests;

  TestSuiteResult({this.path = '', List<TestCaseResult>? tests})
      : tests = tests ?? [];

  int get passed => tests.where((t) => t.result == 'passed').length;
  int get failed => tests.where((t) => t.result == 'failed').length;
  int get skipped => tests.where((t) => t.result == 'skipped').length;

  bool get hasFailures => failed > 0;

  /// Sum of the known per-test durations, or null when no test carried one.
  int? get durationMs {
    int? total;
    for (final test in tests) {
      final ms = test.durationMs;
      if (ms != null) total = (total ?? 0) + ms;
    }
    return total;
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'tests': tests.map((t) => t.toJson()).toList(),
      };

  factory TestSuiteResult.fromJson(Map<String, dynamic> json) {
    return TestSuiteResult(
      path: json['path'] as String? ?? '',
      tests: (json['tests'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(TestCaseResult.fromJson)
              .toList() ??
          [],
    );
  }
}

/// One failed test case from the CI run bundled into this build.
class TestFailureDetail {
  String name;
  String error;

  TestFailureDetail({this.name = '', this.error = ''});

  Map<String, dynamic> toJson() => {
        'name': name,
        'error': error,
      };

  factory TestFailureDetail.fromJson(Map<String, dynamic> json) {
    return TestFailureDetail(
      name: json['name'] as String? ?? '',
      error: json['error'] as String? ?? '',
    );
  }
}

/// Result of the `flutter test` run performed by CI right before the APK of
/// this build was produced. Serialized into `assets/test_report.json` by
/// `tool/generate_test_report.dart`; the committed placeholder has
/// `available: false` so local builds show "no report" instead of stale data.
class TestReport {
  /// False for the committed placeholder (local/dev builds without CI data).
  bool available;
  DateTime? generatedAt;
  String commit;
  String branch;

  /// App version (`x.y.z+build`) the tests were run against, taken from
  /// `pubspec.yaml` at CI time. Empty for the placeholder / older reports.
  String appVersion;
  int passed;
  int failed;
  int skipped;
  List<TestFailureDetail> failures;

  /// Per-suite breakdown of every executed test (passes included). Empty for
  /// reports produced before 0.1.129 — the page then falls back to the counts.
  List<TestSuiteResult> suites;

  TestReport({
    this.available = false,
    this.generatedAt,
    this.commit = '',
    this.branch = '',
    this.appVersion = '',
    this.passed = 0,
    this.failed = 0,
    this.skipped = 0,
    List<TestFailureDetail>? failures,
    List<TestSuiteResult>? suites,
  })  : failures = failures ?? [],
        suites = suites ?? [];

  bool get hasFailures => available && failed > 0;

  int get total => passed + failed + skipped;

  /// Total wall-clock time of all tests with a known duration, or null when
  /// the report carries no per-suite detail (older reports).
  int? get durationMs {
    int? total;
    for (final suite in suites) {
      final ms = suite.durationMs;
      if (ms != null) total = (total ?? 0) + ms;
    }
    return total;
  }

  Map<String, dynamic> toJson() => {
        'available': available,
        'generatedAt': generatedAt?.toIso8601String(),
        'commit': commit,
        'branch': branch,
        'appVersion': appVersion,
        'passed': passed,
        'failed': failed,
        'skipped': skipped,
        'failures': failures.map((f) => f.toJson()).toList(),
        'suites': suites.map((s) => s.toJson()).toList(),
      };

  /// Picks whichever of two reports is more recent by [generatedAt],
  /// treating a null/unavailable report as always older. The one place
  /// "which run is the latest" gets decided, so build packaging, the
  /// `ci-reports` merge, and job-summary rendering can never disagree.
  static TestReport? newest(TestReport? a, TestReport? b) {
    if (a == null || !a.available) return (b != null && b.available) ? b : null;
    if (b == null || !b.available) return a;
    final aTime = a.generatedAt;
    final bTime = b.generatedAt;
    if (aTime == null) return bTime == null ? a : b;
    if (bTime == null) return a;
    return bTime.isAfter(aTime) ? b : a;
  }

  factory TestReport.fromJson(Map<String, dynamic> json) {
    return TestReport(
      available: json['available'] as bool? ?? false,
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
      commit: json['commit'] as String? ?? '',
      branch: json['branch'] as String? ?? '',
      appVersion: json['appVersion'] as String? ?? '',
      passed: (json['passed'] as num?)?.round() ?? 0,
      failed: (json['failed'] as num?)?.round() ?? 0,
      skipped: (json['skipped'] as num?)?.round() ?? 0,
      failures: (json['failures'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(TestFailureDetail.fromJson)
              .toList() ??
          [],
      suites: (json['suites'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(TestSuiteResult.fromJson)
              .toList() ??
          [],
    );
  }

  /// Builds a report from `flutter test --machine` output (one JSON event per
  /// line, package:test JSON reporter). Non-JSON lines are ignored so build
  /// banners or tool chatter mixed into the stream don't break parsing.
  factory TestReport.fromMachineJsonLines(
    Iterable<String> lines, {
    String commit = '',
    String branch = '',
    String appVersion = '',
    DateTime? generatedAt,
  }) {
    final namesById = <int, String>{};
    final errorsById = <int, String>{};
    var passed = 0, failed = 0, skipped = 0;
    final failedIds = <int>[];
    final suitePathsById = <int, String>{};
    final suiteIdByTestId = <int, int>{};
    final startTimeById = <int, int>{};
    // Executed cases grouped by suiteID (-1 = suite never named), in the order
    // suites first produced a visible test.
    final casesBySuite = <int, List<TestCaseResult>>{};

    for (final line in lines) {
      dynamic event;
      try {
        event = jsonDecode(line.trim());
      } catch (_) {
        continue;
      }
      if (event is! Map<String, dynamic>) continue;

      switch (event['type']) {
        case 'suite':
          final suite = event['suite'];
          if (suite is Map<String, dynamic>) {
            final id = (suite['id'] as num?)?.round();
            if (id != null) {
              suitePathsById[id] =
                  _relativeSuitePath(suite['path'] as String? ?? '');
            }
          }
          break;
        case 'testStart':
          final test = event['test'];
          if (test is Map<String, dynamic>) {
            final id = (test['id'] as num?)?.round();
            if (id != null) {
              namesById[id] = test['name'] as String? ?? '';
              final suiteId = (test['suiteID'] as num?)?.round();
              if (suiteId != null) suiteIdByTestId[id] = suiteId;
              final time = (event['time'] as num?)?.round();
              if (time != null) startTimeById[id] = time;
            }
          }
          break;
        case 'error':
          final id = (event['testID'] as num?)?.round();
          if (id != null && !errorsById.containsKey(id)) {
            final error = event['error'] as String? ?? '';
            final stack = event['stackTrace'] as String? ?? '';
            errorsById[id] =
                stack.trim().isEmpty ? error : '$error\n${stack.trim()}';
          }
          break;
        case 'testDone':
          // Hidden tests are bookkeeping entries (e.g. "loading foo_test.dart")
          // and only matter when they fail.
          final id = (event['testID'] as num?)?.round();
          final hidden = event['hidden'] as bool? ?? false;
          final success = event['result'] == 'success';
          String? result;
          if (event['skipped'] == true) {
            skipped++;
            result = 'skipped';
          } else if (success) {
            if (!hidden) {
              passed++;
              result = 'passed';
            }
          } else {
            failed++;
            result = 'failed';
            if (id != null) failedIds.add(id);
          }
          if (result != null && id != null) {
            final start = startTimeById[id];
            final done = (event['time'] as num?)?.round();
            casesBySuite
                .putIfAbsent(suiteIdByTestId[id] ?? -1, () => [])
                .add(TestCaseResult(
                  name: namesById[id] ?? 'Unknown test (id $id)',
                  result: result,
                  durationMs:
                      start == null || done == null ? null : done - start,
                ));
          }
          break;
      }
    }

    return TestReport(
      available: true,
      generatedAt: generatedAt,
      commit: commit,
      branch: branch,
      appVersion: appVersion,
      passed: passed,
      failed: failed,
      skipped: skipped,
      failures: failedIds
          .map((id) => TestFailureDetail(
                name: namesById[id] ?? 'Unknown test (id $id)',
                error: errorsById[id] ?? '',
              ))
          .toList(),
      suites: casesBySuite.entries
          .map((entry) => TestSuiteResult(
                path: suitePathsById[entry.key] ?? '',
                tests: entry.value,
              ))
          .toList(),
    );
  }

  /// The machine stream names suites by absolute path
  /// (`/home/runner/work/…/test/core/task_test.dart`); trim to the repo-root
  /// relative part so reports read the same from any machine.
  static String _relativeSuitePath(String path) {
    final unified = path.replaceAll('\\', '/');
    final match =
        RegExp(r'(?:^|/)((?:test|integration_test)/.*)$').firstMatch(unified);
    return match?.group(1) ?? unified;
  }
}
