import 'package:app_template/app_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TestReport', () {
    test('json round-trips', () {
      final report = TestReport(
        available: true,
        passed: 10,
        failed: 2,
        skipped: 1,
        branch: 'dev',
        commit: 'abc1234',
        appVersion: '1.2.3+4',
        failures: [TestFailureDetail(name: 't1', error: 'boom')],
      );
      final decoded = TestReport.fromJson(report.toJson());
      expect(decoded.passed, 10);
      expect(decoded.failed, 2);
      expect(decoded.total, 13);
      expect(decoded.hasFailures, isTrue);
      expect(decoded.failures.single.name, 't1');
      expect(decoded.appVersion, '1.2.3+4');
    });

    test('placeholder is not available and has no failures', () {
      final report = TestReport();
      expect(report.available, isFalse);
      expect(report.hasFailures, isFalse);
    });

    test('parses flutter test --machine output', () {
      const lines = [
        '{"type":"testStart","test":{"id":1,"name":"passes"}}',
        '{"type":"testDone","testID":1,"result":"success","hidden":false}',
        '{"type":"testStart","test":{"id":2,"name":"fails"}}',
        '{"type":"error","testID":2,"error":"expected true","stackTrace":"at x"}',
        '{"type":"testDone","testID":2,"result":"error","hidden":false}',
        '{"type":"testStart","test":{"id":3,"name":"skips"}}',
        '{"type":"testDone","testID":3,"result":"success","skipped":true,"hidden":false}',
        'not json — should be ignored',
      ];
      final report = TestReport.fromMachineJsonLines(lines,
          branch: 'main', commit: 'deadbeef', appVersion: '9.9.9');
      expect(report.available, isTrue);
      expect(report.passed, 1);
      expect(report.failed, 1);
      expect(report.skipped, 1);
      expect(report.failures.single.name, 'fails');
      expect(report.failures.single.error, contains('expected true'));
      expect(report.appVersion, '9.9.9');
    });
  });
}
