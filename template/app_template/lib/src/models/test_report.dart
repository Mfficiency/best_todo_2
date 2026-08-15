import 'dart:convert';

/// One failed test case from a CI run.
class TestFailureDetail {
  String name;
  String error;

  TestFailureDetail({this.name = '', this.error = ''});

  Map<String, dynamic> toJson() => {'name': name, 'error': error};

  factory TestFailureDetail.fromJson(Map<String, dynamic> json) =>
      TestFailureDetail(
        name: json['name'] as String? ?? '',
        error: json['error'] as String? ?? '',
      );
}

/// Result of a `flutter test` run. Serialised into `assets/test_report.json`
/// by `tool/generate_test_report.dart` during the CI/APK workflow; the
/// committed placeholder has `available: false` so local builds show
/// "no report" instead of stale/fake data.
///
/// Do not fabricate these numbers — an unavailable report is the honest state
/// until CI produces a real one.
class TestReport {
  bool available;
  DateTime? generatedAt;
  String commit;
  String branch;

  /// App version (`x.y.z+build`) the tests ran against, read from pubspec at
  /// CI time. Never hard-coded.
  String appVersion;
  int passed;
  int failed;
  int skipped;
  List<TestFailureDetail> failures;

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
  }) : failures = failures ?? [];

  bool get hasFailures => available && failed > 0;
  int get total => passed + failed + skipped;

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
      };

  factory TestReport.fromJson(Map<String, dynamic> json) => TestReport(
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
      );

  /// Builds a report from `flutter test --machine` output (one package:test
  /// JSON event per line). Non-JSON lines are ignored so build banners mixed
  /// into the stream don't break parsing.
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

    for (final line in lines) {
      dynamic event;
      try {
        event = jsonDecode(line.trim());
      } catch (_) {
        continue;
      }
      if (event is! Map<String, dynamic>) continue;

      switch (event['type']) {
        case 'testStart':
          final test = event['test'];
          if (test is Map<String, dynamic>) {
            final id = (test['id'] as num?)?.round();
            if (id != null) namesById[id] = test['name'] as String? ?? '';
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
          final id = (event['testID'] as num?)?.round();
          final hidden = event['hidden'] as bool? ?? false;
          final success = event['result'] == 'success';
          if (event['skipped'] == true) {
            skipped++;
          } else if (success) {
            if (!hidden) passed++;
          } else {
            failed++;
            if (id != null) failedIds.add(id);
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
    );
  }
}
