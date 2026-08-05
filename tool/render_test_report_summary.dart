import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/test_report.dart';

/// Renders a test report JSON (see `generate_test_report.dart`) as the markdown
/// CI writes to `$GITHUB_STEP_SUMMARY` and uploads as an artifact.
///
/// CI runs the suite once with `--machine` (the machine stream is what the app's
/// report is parsed from) and this renders the human view from it, so the same
/// numbers appear in the job summary and in the app.
///
/// Usage:
///   dart run tool/render_test_report_summary.dart --report assets/test_report.json \
///     [--machine machine.jsonl] [--out flutter_test_report.md]
void main(List<String> args) {
  String reportPath = 'assets/test_report.json';
  String? machinePath;
  String out = 'flutter_test_report.md';

  for (var i = 0; i + 1 < args.length; i += 2) {
    final value = args[i + 1];
    switch (args[i]) {
      case '--report':
        reportPath = value;
        break;
      case '--machine':
        machinePath = value;
        break;
      case '--out':
        out = value;
        break;
      default:
        stderr.writeln('Unknown option: ${args[i]}');
        exitCode = 64;
        return;
    }
  }

  final file = File(reportPath);
  if (!file.existsSync()) {
    stderr.writeln('Report not found: $reportPath');
    exitCode = 1;
    return;
  }
  final report =
      TestReport.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);

  final evaluated = report.passed + report.failed;
  final score = evaluated == 0 ? 100.0 : report.passed / evaluated * 100.0;
  final status = report.failed == 0 ? 'PASS' : 'FAIL';

  final lines = <String>[
    '## Test Report: ${score.toStringAsFixed(0)}% '
        '(${report.passed}/$evaluated passed) - $status',
    '',
    '- Passed: ${report.passed}',
    '- Failed: ${report.failed}',
    '- Skipped: ${report.skipped}',
    '- Total evaluated: $evaluated',
    if (report.branch.isNotEmpty || report.commit.isNotEmpty)
      '- Ran on: ${[
        if (report.branch.isNotEmpty) report.branch,
        if (report.commit.isNotEmpty) report.commit,
        if (report.appVersion.isNotEmpty) 'v${report.appVersion}',
      ].join(' · ')}',
    '',
    '### What to do next',
    report.failed == 0
        ? 'All tests passed, so this branch stays ready for merge — keep adding '
            'focused tests for new behavior to hold that line.'
        : 'Fix the first failure below, re-run that suite locally '
            '(`flutter test test/<area>`), and push again. If a failure comes '
            'and goes, stabilize the flaky test before adding features.',
    '',
  ];

  if (report.failures.isNotEmpty) {
    lines.add('### Failures');
    for (final failure in report.failures) {
      lines.addAll([
        '<details><summary>${_escape(failure.name)}</summary>',
        '',
        '```text',
        _clip(failure.error.isEmpty ? 'No error details recorded.' : failure.error,
            4000),
        '```',
        '</details>',
        '',
      ]);
    }
  }

  final printed = machinePath == null ? '' : _printedOutput(machinePath);
  if (printed.isNotEmpty) {
    lines.addAll([
      '### Details',
      '<details><summary>Test output</summary>',
      '',
      '```text',
      _clip(printed, 200000),
      '```',
      '</details>',
      '',
    ]);
  }

  final markdown = lines.join('\n');
  File(out).writeAsStringSync(markdown, encoding: utf8);

  final summaryPath = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summaryPath != null && summaryPath.isNotEmpty) {
    File(summaryPath).writeAsStringSync(markdown, encoding: utf8);
  }
  stdout.writeln('Wrote $out (${report.passed} passed, ${report.failed} failed)');
}

/// Pulls the `print`/`error` messages out of a `flutter test --machine` stream,
/// which is what a human would have seen on stdout from a plain test run.
String _printedOutput(String machinePath) {
  final file = File(machinePath);
  if (!file.existsSync()) return '';
  final out = <String>[];
  for (final line in file.readAsLinesSync()) {
    dynamic event;
    try {
      event = jsonDecode(line.trim());
    } catch (_) {
      continue;
    }
    if (event is! Map<String, dynamic>) continue;
    if (event['type'] == 'print') {
      final message = event['message'] as String? ?? '';
      if (message.trim().isNotEmpty) out.add(message);
    } else if (event['type'] == 'error') {
      final error = event['error'] as String? ?? '';
      final stack = event['stackTrace'] as String? ?? '';
      out.add([error, stack].where((s) => s.trim().isNotEmpty).join('\n'));
    }
  }
  return out.join('\n');
}

String _escape(String value) => value.replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _clip(String value, int max) =>
    value.length <= max ? value : '${value.substring(0, max)}\n…(truncated)';
