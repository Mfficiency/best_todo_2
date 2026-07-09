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
    });

    test('round-trips through toJson', () {
      final original = TestReport(
        available: true,
        generatedAt: DateTime.utc(2026, 7, 9, 12, 30),
        commit: 'abc123def',
        branch: 'dev',
        passed: 41,
        failed: 2,
        skipped: 1,
        failures: [
          TestFailureDetail(name: 'a failing test', error: 'Expected 1, got 2'),
        ],
      );
      final restored =
          TestReport.fromJson(jsonDecode(jsonEncode(original.toJson())));
      expect(restored.available, isTrue);
      expect(restored.generatedAt, DateTime.utc(2026, 7, 9, 12, 30));
      expect(restored.commit, 'abc123def');
      expect(restored.branch, 'dev');
      expect(restored.passed, 41);
      expect(restored.failed, 2);
      expect(restored.skipped, 1);
      expect(restored.total, 44);
      expect(restored.hasFailures, isTrue);
      expect(restored.failures, hasLength(1));
      expect(restored.failures.first.name, 'a failing test');
      expect(restored.failures.first.error, 'Expected 1, got 2');
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
        generatedAt: DateTime.utc(2026, 7, 9),
      );
      expect(report.available, isTrue);
      expect(report.passed, 1);
      expect(report.failed, 1);
      expect(report.skipped, 1);
      expect(report.hasFailures, isTrue);
      expect(report.commit, 'deadbeef1');
      expect(report.branch, 'dev');
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
  });
}
