import 'dart:convert';
import 'dart:io';

// Import the pure model directly (not the barrel) so this script stays
// Flutter-free and runs under `dart run` without dart:ui.
import 'package:app_template/src/models/test_report.dart' show TestReport;

/// Converts `flutter test --machine` output into `assets/test_report.json`,
/// bundled into the app so the Test Results page can show the results of the
/// exact build it shipped from. Only real CI output goes in — no fabricated
/// numbers.
///
/// Usage:
///   flutter test --machine > machine.jsonl || true
///   dart run tool/generate_test_report.dart \
///     --input machine.jsonl --output assets/test_report.json \
///     --commit <sha> --branch <branch> --version <x.y.z+build>
void main(List<String> args) {
  var input = '';
  var output = 'assets/test_report.json';
  var commit = '';
  var branch = '';
  var version = '';

  for (var i = 0; i + 1 < args.length; i += 2) {
    final value = args[i + 1];
    switch (args[i]) {
      case '--input':
        input = value;
      case '--output':
        output = value;
      case '--commit':
        commit = value;
      case '--branch':
        branch = value;
      case '--version':
        version = value;
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
    generatedAt: DateTime.now().toUtc(),
  );

  File(output).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report.toJson()),
  );
  stdout.writeln('Wrote $output: ${report.passed} passed, ${report.failed} '
      'failed, ${report.skipped} skipped');
}
