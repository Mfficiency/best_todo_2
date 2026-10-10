import 'dart:io';

import 'package:besttodo/models/test_report.dart';
import 'package:besttodo/services/test_report_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('report_seen');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    TestReportService.instance.resetForTest();
    TestReportService.instance
        .setOnlineReportForTest(TestReport(available: false));
  });

  tearDown(() async {
    TestReportService.instance.resetForTest();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('failure-dot acknowledgement', () {
    TestReport failingReport(DateTime? generatedAt) => TestReport(
          available: true,
          generatedAt: generatedAt,
          commit: 'abc123',
          passed: 10,
          failed: 1,
          failures: [TestFailureDetail(name: 'broken test')],
        );

    /// A "restart": drop every in-memory trace, then load again so the
    /// persisted marker is re-read from disk.
    Future<void> restartWith(TestReport report) async {
      TestReportService.instance.resetForTest();
      TestReportService.instance
          .setOnlineReportForTest(TestReport(available: false));
      TestReportService.instance.setReportForTest(report);
      await TestReportService.instance.load();
    }

    test('markSeen clears the unseen flag and survives a restart', () async {
      final report = failingReport(DateTime.utc(2030, 1, 1));
      TestReportService.instance.setReportForTest(report);
      await TestReportService.instance.load();
      expect(TestReportService.instance.hasUnseenFailures, isTrue);

      await TestReportService.instance.markSeen(report);

      // The failures are still there, but they have been looked at.
      expect(TestReportService.instance.hasFailures, isTrue);
      expect(TestReportService.instance.hasUnseenFailures, isFalse);

      await restartWith(failingReport(DateTime.utc(2030, 1, 1)));
      expect(TestReportService.instance.hasFailures, isTrue);
      expect(TestReportService.instance.hasUnseenFailures, isFalse);
    });

    test('a newer failing run lights the dot up again', () async {
      final report = failingReport(DateTime.utc(2030, 1, 1));
      TestReportService.instance.setReportForTest(report);
      await TestReportService.instance.load();
      await TestReportService.instance.markSeen(report);

      await restartWith(failingReport(DateTime.utc(2030, 2, 1)));

      expect(TestReportService.instance.hasUnseenFailures, isTrue);
    });

    test('an undated report is acknowledged by its fingerprint', () async {
      final report = failingReport(null);
      TestReportService.instance.setReportForTest(report);
      await TestReportService.instance.load();
      expect(TestReportService.instance.hasUnseenFailures, isTrue);

      await TestReportService.instance.markSeen(report);
      expect(TestReportService.instance.hasUnseenFailures, isFalse);

      // The same run read back from disk is recognised, dateless as it is.
      await restartWith(failingReport(null));
      expect(TestReportService.instance.hasUnseenFailures, isFalse);
    });

    test('an all-green run never counts as unseen failures', () async {
      TestReportService.instance.setReportForTest(TestReport(
        available: true,
        generatedAt: DateTime.utc(2030, 1, 1),
        passed: 12,
      ));
      await TestReportService.instance.load();

      expect(TestReportService.instance.hasFailures, isFalse);
      expect(TestReportService.instance.hasUnseenFailures, isFalse);
    });
  });
}
