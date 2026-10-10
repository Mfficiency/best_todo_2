import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/test_report.dart';

/// Renders a test report as CI job-summary markdown — the same
/// [TestReport] parser the app uses for its Test Results page, so the two
/// can never disagree (see notes/principles.md #7).
///
/// Usage:
///   dart run tool/render_test_report_summary.dart \
///     --report build/ci/test_report.json \
///     --machine test_machine_output.jsonl \
///     --out flutter_test_report.md
///
/// `--report` is preferred; `--machine` is a fallback used only when
/// `--report` is missing or unparseable (this step runs with `if: always()`,
/// so an earlier step may have failed before writing the report). Never
/// fatal: any failure still produces a minimal "no data" summary and exits 0,
/// so it can't turn a red test run into a red *workflow* on its own.
void main(List<String> args) {
  String? reportPath;
  String? machinePath;
  String out = 'flutter_test_report.md';

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--report':
        reportPath = args[++i];
        break;
      case '--machine':
        machinePath = args[++i];
        break;
      case '--out':
        out = args[++i];
        break;
      default:
        stderr.writeln('Unknown option: ${args[i]}');
        exitCode = 64;
        return;
    }
  }

  final report = _loadReport(reportPath) ?? _loadFromMachine(machinePath);
  final markdown = _render(report);

  File(out).writeAsStringSync(markdown);
  stdout.writeln('Wrote $out');

  final summaryFile = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summaryFile != null && summaryFile.isNotEmpty) {
    try {
      File(summaryFile).writeAsStringSync('$markdown\n', mode: FileMode.append);
    } catch (_) {
      // The job summary is a convenience; the artifact file above is the
      // durable copy, so a failed append here is not fatal.
    }
  }
}

TestReport? _loadReport(String? path) {
  if (path == null || !File(path).existsSync()) return null;
  try {
    return TestReport.fromJson(
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

TestReport? _loadFromMachine(String? path) {
  if (path == null || !File(path).existsSync()) return null;
  try {
    return TestReport.fromMachineJsonLines(
      File(path).readAsLinesSync(),
      generatedAt: DateTime.now().toUtc(),
    );
  } catch (_) {
    return null;
  }
}

String _render(TestReport? report) {
  if (report == null || !report.available) {
    return '## Flutter Test Report\n\nNo test data available for this run.\n';
  }

  final buffer = StringBuffer()..writeln('## Flutter Test Report');
  final status = report.hasFailures ? '❌ Failing' : '✅ Passing';
  buffer.writeln();
  buffer.writeln('$status — ${report.passed} passed, ${report.failed} '
      'failed, ${report.skipped} skipped (${report.total} total)');
  if (report.commit.isNotEmpty || report.branch.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('Commit `${report.commit}` on `${report.branch}`'
        '${report.appVersion.isEmpty ? '' : ' (v${report.appVersion})'}');
  }

  if (report.failures.isNotEmpty) {
    buffer.writeln();
    buffer.writeln('### Failures');
    // Bounded so one broken run can't blow up an unreadable job summary.
    for (final failure in report.failures.take(20)) {
      buffer.writeln();
      buffer.writeln('**${failure.name}**');
      if (failure.error.isNotEmpty) {
        final firstLine = failure.error.split('\n').first;
        buffer.writeln();
        buffer.writeln('```');
        buffer.writeln(firstLine);
        buffer.writeln('```');
      }
    }
    if (report.failures.length > 20) {
      buffer.writeln();
      buffer.writeln('… and ${report.failures.length - 20} more.');
    }
  }

  return buffer.toString();
}
