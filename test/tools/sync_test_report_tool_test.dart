import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/test_report.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/sync_test_report.dart' as sync_tool;

/// Covers `tool/sync_test_report.dart`, the step that packages a report into
/// `assets/test_report.json` for every build (CI and local). It drives the real
/// tool — this is the seam between CI and what the app ships, so a mock would
/// not prove much. `--no-fetch` keeps the network out of it.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_report');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String path(String name) => '${tempDir.path}/$name';

  void writeJson(String name, TestReport report) {
    File(path(name)).writeAsStringSync(jsonEncode(report.toJson()));
  }

  TestReport readJson(String name) => TestReport.fromJson(
      jsonDecode(File(path(name)).readAsStringSync()) as Map<String, dynamic>);

  Future<void> sync(List<String> args) =>
      sync_tool.main(['--no-fetch', ...args]);

  test('packages a newer candidate over what is already there', () async {
    writeJson(
        'out.json',
        TestReport(
            available: true,
            generatedAt: DateTime.utc(2026, 8, 1),
            branch: 'dev',
            passed: 1));
    writeJson(
        'candidate.json',
        TestReport(
            available: true,
            generatedAt: DateTime.utc(2026, 8, 5),
            branch: 'staging',
            passed: 44));

    await sync(
        ['--output', path('out.json'), '--candidate', path('candidate.json')]);

    final packaged = readJson('out.json');
    expect(packaged.branch, 'staging');
    expect(packaged.passed, 44);
  });

  test('keeps the existing report when the candidate is older', () async {
    writeJson(
        'out.json',
        TestReport(
            available: true,
            generatedAt: DateTime.utc(2026, 8, 5),
            branch: 'main',
            passed: 44));
    writeJson(
        'candidate.json',
        TestReport(
            available: true,
            generatedAt: DateTime.utc(2026, 8, 1),
            branch: 'dev',
            passed: 1));

    await sync(
        ['--output', path('out.json'), '--candidate', path('candidate.json')]);

    expect(readJson('out.json').branch, 'main');
  });

  test('turns a local machine run into a packaged report', () async {
    File(path('machine.jsonl')).writeAsStringSync([
      '{"test":{"id":1,"name":"adds numbers"},"type":"testStart"}',
      '{"testID":1,"result":"success","skipped":false,"hidden":false,"type":"testDone"}',
      '{"success":true,"type":"done"}',
    ].join('\n'));

    await sync([
      '--output',
      path('out.json'),
      '--candidate-machine',
      path('machine.jsonl'),
      '--branch',
      'local',
      '--version',
      '9.9.9+99',
    ]);

    final packaged = readJson('out.json');
    expect(packaged.available, isTrue);
    expect(packaged.passed, 1);
    expect(packaged.branch, 'local');
    expect(packaged.appVersion, '9.9.9+99');
    expect(packaged.generatedAt, isNotNull);
  });

  test('nested output paths are created rather than throwing', () async {
    writeJson(
        'candidate.json',
        TestReport(
            available: true,
            generatedAt: DateTime.utc(2026, 8, 5),
            branch: 'dev',
            passed: 2));

    await sync([
      '--output',
      path('branches/dev.json'),
      '--candidate',
      path('candidate.json'),
    ]);

    expect(readJson('branches/dev.json').passed, 2);
  });

  test('writes a placeholder rather than failing when there is nothing to '
      'package', () async {
    await sync(['--output', path('out.json')]);

    expect(readJson('out.json').available, isFalse);
  });
}
