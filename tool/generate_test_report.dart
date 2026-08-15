import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/test_report.dart';

/// Converts `flutter test --machine` output into `assets/test_report.json`,
/// which gets bundled into the APK so the app can show the test results of
/// the exact build it shipped in (see TestReportService / TestResultsPage).
///
/// Usage:
///   flutter test --machine > machine.jsonl || true
///   dart run tool/generate_test_report.dart \
///     --input machine.jsonl --output assets/test_report.json \
///     --commit <sha> --branch <branch> --version <x.y.z+build> \
///     --run-url <ci run url>
void main(List<String> args) {
  String input = '';
  String output = 'assets/test_report.json';
  String commit = '';
  String branch = '';
  String version = '';
  String runUrl = '';

  for (var i = 0; i + 1 < args.length; i += 2) {
    final value = args[i + 1];
    switch (args[i]) {
      case '--input':
        input = value;
        break;
      case '--output':
        output = value;
        break;
      case '--commit':
        commit = value;
        break;
      case '--branch':
        branch = value;
        break;
      case '--version':
        version = value;
        break;
      case '--run-url':
        runUrl = value;
        break;
      default:
        stderr.writeln('Unknown option: ${args[i]}');
        exitCode = 64;
        return;
    }
  }

  if (input.isEmpty || !File(input).existsSync()) {
    stderr.writeln('Input file not found: "$input" (pass --input <file>)');
    exitCode = 1;
    return;
  }

  final report = TestReport.fromMachineJsonLines(
    File(input).readAsLinesSync(),
    commit: commit,
    branch: branch,
    appVersion: version,
    runUrl: runUrl,
    generatedAt: DateTime.now().toUtc(),
  );

  File(output).parent.createSync(recursive: true);
  File(output).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
  stdout.writeln(
    'Wrote $output: ${report.passed} passed, ${report.failed} failed, '
    '${report.skipped} skipped',
  );
}
