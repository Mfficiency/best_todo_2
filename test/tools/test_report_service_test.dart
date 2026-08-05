import 'dart:convert';
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
    tempDir = await Directory.systemTemp.createTemp('report_cache');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    TestReportService.instance.resetForTest();
    TestReportService.instance
        .setOnlineReportForTest(TestReport(available: false));
  });

  tearDown(() async {
    TestReportService.instance.resetForTest();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  void writeCache(TestReport report) {
    File('${tempDir.path}/test_report_cache.json')
        .writeAsStringSync(jsonEncode(report.toJson()));
  }

  test('reads the cached report an earlier online fetch left on disk', () async {
    // Dated far ahead so it beats whatever real report the asset carries: the
    // point is that the newest run wins, not which layer it came from.
    writeCache(TestReport(
      available: true,
      generatedAt: DateTime.utc(2030, 1, 1),
      branch: 'staging',
      passed: 10,
      failed: 1,
      failures: [TestFailureDetail(name: 'cached failure')],
    ));

    final report = await TestReportService.instance.load();

    expect(report.branch, 'staging');
    expect(report.passed, 10);
    // The drawer dot works offline off this cache, not just off the asset.
    expect(TestReportService.instance.hasFailures, isTrue);
  });

  test('a corrupt cache file degrades instead of throwing', () async {
    File('${tempDir.path}/test_report_cache.json')
        .writeAsStringSync('{not json');

    await TestReportService.instance.load();

    // No exception; whatever the bundled asset says stands.
    expect(TestReportService.instance.report, isNotNull);
  });

  group('loadForDisplay picks the newest layer', () {
    test('online when it is the freshest', () async {
      TestReportService.instance.setReportForTest(TestReport(
        available: true,
        generatedAt: DateTime.utc(2026, 8, 1),
        passed: 1,
      ));
      TestReportService.instance.setOnlineReportForTest(TestReport(
        available: true,
        generatedAt: DateTime.utc(2026, 8, 5),
        passed: 2,
      ));

      final displayed = await TestReportService.instance.loadForDisplay();

      expect(displayed.source, TestReportSource.online);
      expect(displayed.online, isTrue);
      expect(displayed.report.passed, 2);
      expect(displayed.sourceLabel, 'Fetched just now from CI');
    });

    test('the packaged report when the online one is older', () async {
      TestReportService.instance.setReportForTest(TestReport(
        available: true,
        generatedAt: DateTime.utc(2026, 8, 5),
        passed: 3,
      ));
      TestReportService.instance.setOnlineReportForTest(TestReport(
        available: true,
        generatedAt: DateTime.utc(2026, 8, 1),
        passed: 2,
      ));

      final displayed = await TestReportService.instance.loadForDisplay();

      expect(displayed.source, TestReportSource.bundled);
      expect(displayed.report.passed, 3);
      expect(displayed.sourceLabel, 'Packaged with this build (offline)');
    });

    test('the disk cache when it beats both other layers', () async {
      TestReportService.instance.setReportForTest(TestReport(
        available: true,
        generatedAt: DateTime.utc(2026, 8, 1),
        passed: 1,
      ));
      TestReportService.instance.setCachedReportForTest(TestReport(
        available: true,
        generatedAt: DateTime.utc(2026, 8, 4),
        passed: 9,
      ));
      TestReportService.instance.setOnlineReportForTest(
          TestReport(available: false));

      final displayed = await TestReportService.instance.loadForDisplay();

      expect(displayed.source, TestReportSource.cached);
      expect(displayed.report.passed, 9);
      expect(displayed.sourceLabel, 'Last fetched results (offline)');
    });

    test('falls back to an unavailable report when no layer has data', () async {
      TestReportService.instance.setReportForTest(TestReport(available: false));

      final displayed = await TestReportService.instance.loadForDisplay();

      expect(displayed.report.available, isFalse);
      expect(displayed.source, TestReportSource.bundled);
    });
  });
}
