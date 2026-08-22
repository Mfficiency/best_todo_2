import 'dart:convert';

import 'package:besttodo/models/test_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TestReport.fromJson', () {
    test('is tolerant of missing keys', () {
      final report = TestReport.fromJson(const {});
      expect(report.available, isFalse);
      expect(report.passed, 0);
      expect(report.failed, 0);
      expect(report.skipped, 0);
      expect(report.failures, isEmpty);
      expect(report.hasFailures, isFalse);
      // Reports written before 0.1.129 carry no 'suites' key.
      expect(report.suites, isEmpty);
      expect(report.durationMs, isNull);
    });

    test('round-trips through toJson', () {
      final original = TestReport(
        available: true,
        generatedAt: DateTime.utc(2026, 7, 9, 12, 30),
        commit: 'abc123def',
        branch: 'dev',
        appVersion: '0.1.97+67',
        passed: 41,
        failed: 2,
        skipped: 1,
        failures: [
          TestFailureDetail(name: 'a failing test', error: 'Expected 1, got 2'),
        ],
        suites: [
          TestSuiteResult(path: 'test/core/task_test.dart', tests: [
            TestCaseResult(name: 'adds', result: 'passed', durationMs: 120),
            TestCaseResult(name: 'a failing test', result: 'failed'),
          ]),
        ],
      );
      final restored =
          TestReport.fromJson(jsonDecode(jsonEncode(original.toJson())));
      expect(restored.available, isTrue);
      expect(restored.generatedAt, DateTime.utc(2026, 7, 9, 12, 30));
      expect(restored.commit, 'abc123def');
      expect(restored.branch, 'dev');
      expect(restored.appVersion, '0.1.97+67');
      expect(restored.passed, 41);
      expect(restored.failed, 2);
      expect(restored.skipped, 1);
      expect(restored.total, 44);
      expect(restored.hasFailures, isTrue);
      expect(restored.failures, hasLength(1));
      expect(restored.failures.first.name, 'a failing test');
      expect(restored.failures.first.error, 'Expected 1, got 2');
      expect(restored.suites, hasLength(1));
      final suite = restored.suites.first;
      expect(suite.path, 'test/core/task_test.dart');
      expect(suite.tests, hasLength(2));
      expect(suite.tests.first.name, 'adds');
      expect(suite.tests.first.result, 'passed');
      expect(suite.tests.first.durationMs, 120);
      expect(suite.tests.last.result, 'failed');
      expect(suite.tests.last.durationMs, isNull);
      expect(suite.passed, 1);
      expect(suite.failed, 1);
      expect(suite.hasFailures, isTrue);
      // Suite duration sums only the known times; one is enough.
      expect(suite.durationMs, 120);
      expect(restored.durationMs, 120);
    });

    test('failures with failed=0 means no red dot when unavailable', () {
      final report = TestReport.fromJson(const {'available': false, 'failed': 3});
      // A placeholder report must never light up the dot, even if malformed.
      expect(report.hasFailures, isFalse);
    });
  });

  group('TestReport.fromMachineJsonLines', () {
    List<String> sampleRun() => [
          '{"protocolVersion":"0.1.1","runnerVersion":"1.24.0","type":"start"}',
          'non-json build banner line',
          // Hidden loading "test": passes, must not be counted.
          '{"test":{"id":0,"name":"loading test/foo_test.dart"},"type":"testStart"}',
          '{"testID":0,"result":"success","skipped":false,"hidden":true,"type":"testDone"}',
          // Regular passing test.
          '{"test":{"id":1,"name":"adds numbers"},"type":"testStart"}',
          '{"testID":1,"result":"success","skipped":false,"hidden":false,"type":"testDone"}',
          // Failing test with an error event.
          '{"test":{"id":2,"name":"bucketing puts tasks in Today"},"type":"testStart"}',
          '{"testID":2,"error":"Expected: <1>\\n  Actual: <2>","stackTrace":"package:matcher  expect","isFailure":true,"type":"error"}',
          '{"testID":2,"result":"failure","skipped":false,"hidden":false,"type":"testDone"}',
          // Skipped test.
          '{"test":{"id":3,"name":"skipped on purpose"},"type":"testStart"}',
          '{"testID":3,"result":"success","skipped":true,"hidden":false,"type":"testDone"}',
          '{"success":false,"type":"done"}',
        ];

    test('counts passed, failed, skipped and collects failure details', () {
      final report = TestReport.fromMachineJsonLines(
        sampleRun(),
        commit: 'deadbeef1',
        branch: 'dev',
        appVersion: '0.1.97+67',
        generatedAt: DateTime.utc(2026, 7, 9),
      );
      expect(report.available, isTrue);
      expect(report.passed, 1);
      expect(report.failed, 1);
      expect(report.skipped, 1);
      expect(report.hasFailures, isTrue);
      expect(report.commit, 'deadbeef1');
      expect(report.branch, 'dev');
      expect(report.appVersion, '0.1.97+67');
      expect(report.failures, hasLength(1));
      expect(report.failures.first.name, 'bucketing puts tasks in Today');
      expect(report.failures.first.error, contains('Expected: <1>'));
      expect(report.failures.first.error, contains('package:matcher'));
    });

    test('all-green run has no failures', () {
      final report = TestReport.fromMachineJsonLines([
        '{"test":{"id":1,"name":"adds numbers"},"type":"testStart"}',
        '{"testID":1,"result":"success","skipped":false,"hidden":false,"type":"testDone"}',
        '{"success":true,"type":"done"}',
      ]);
      expect(report.available, isTrue);
      expect(report.passed, 1);
      expect(report.failed, 0);
      expect(report.hasFailures, isFalse);
      expect(report.failures, isEmpty);
    });

    test('empty or garbage input yields an available-but-empty report', () {
      final report =
          TestReport.fromMachineJsonLines(['not json', '', '[1,2,3]']);
      expect(report.available, isTrue);
      expect(report.total, 0);
      expect(report.hasFailures, isFalse);
    });

    test('groups every executed test per suite, with durations', () {
      final report = TestReport.fromMachineJsonLines([
        '{"suite":{"id":0,"platform":"vm","path":"/home/runner/work/repo/test/core/task_test.dart"},"type":"suite","time":0}',
        // Hidden loading entry: never becomes a listed test case.
        '{"test":{"id":1,"name":"loading test/core/task_test.dart","suiteID":0},"type":"testStart","time":1}',
        '{"testID":1,"result":"success","skipped":false,"hidden":true,"type":"testDone","time":90}',
        '{"test":{"id":2,"name":"adds numbers","suiteID":0},"type":"testStart","time":100}',
        '{"testID":2,"result":"success","skipped":false,"hidden":false,"type":"testDone","time":340}',
        '{"suite":{"id":5,"platform":"vm","path":"C:\\\\work\\\\repo\\\\test\\\\home\\\\home_test.dart"},"type":"suite","time":400}',
        '{"test":{"id":6,"name":"renders the drawer","suiteID":5},"type":"testStart","time":410}',
        '{"testID":6,"error":"boom","type":"error"}',
        '{"testID":6,"result":"failure","skipped":false,"hidden":false,"type":"testDone","time":1510}',
        '{"test":{"id":7,"name":"skipped on purpose","suiteID":5},"type":"testStart","time":1520}',
        '{"testID":7,"result":"success","skipped":true,"hidden":false,"type":"testDone","time":1530}',
        '{"success":false,"type":"done"}',
      ]);

      expect(report.suites, hasLength(2));

      final core = report.suites.first;
      // Absolute CI paths are trimmed to the repo-relative suite path.
      expect(core.path, 'test/core/task_test.dart');
      expect(core.tests, hasLength(1)); // the hidden loading entry is not a test
      expect(core.tests.first.name, 'adds numbers');
      expect(core.tests.first.result, 'passed');
      expect(core.tests.first.durationMs, 240);

      final home = report.suites.last;
      // Windows-style local paths normalize the same way.
      expect(home.path, 'test/home/home_test.dart');
      expect(home.tests, hasLength(2));
      expect(home.tests.first.result, 'failed');
      expect(home.tests.first.durationMs, 1100);
      expect(home.tests.last.result, 'skipped');
      expect(home.hasFailures, isTrue);

      expect(report.durationMs, 240 + 1100 + 10);
      // The suite detail agrees with the counters the page shows.
      expect(report.passed, 1);
      expect(report.failed, 1);
      expect(report.skipped, 1);
    });

    test('a run without suite events still counts, with no suite detail', () {
      final report = TestReport.fromMachineJsonLines([
        '{"test":{"id":1,"name":"adds numbers"},"type":"testStart"}',
        '{"testID":1,"result":"success","skipped":false,"hidden":false,"type":"testDone"}',
      ]);
      expect(report.passed, 1);
      expect(report.suites, hasLength(1));
      expect(report.suites.first.path, isEmpty);
      expect(report.suites.first.tests.single.name, 'adds numbers');
      expect(report.suites.first.tests.single.durationMs, isNull);
      expect(report.durationMs, isNull);
    });
  });
}
