import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/test_report.dart';

/// Keeps `assets/test_report.json` — the report **packaged into every build** —
/// pointed at the newest test run known, wherever that run happened.
///
/// Candidates it considers, keeping the one with the newest `generatedAt`
/// (see `TestReport.newest`):
///  * the file already at `--output` (what the checkout carries),
///  * any `--candidate <file.json>` (e.g. a report another job produced),
///  * `--candidate-machine <machine.jsonl>` (a `flutter test --machine` run,
///    parsed with the same code the app uses),
///  * `latest.json` on the `ci-reports` branch unless `--no-fetch` (the newest
///    run CI published from *any* branch).
///
/// Nothing here is fatal: a missing file or an unreachable network leaves the
/// existing report in place, so an offline build still packages the last one it
/// had. That is what makes the Test Results page work on any branch, offline,
/// and under `flutter run -d chrome`.
///
/// Usage:
///   # before a build / before running the app: pull the newest CI run in
///   dart run tool/sync_test_report.dart
///
///   # after a local test run: package your own results
///   flutter test --machine > machine.jsonl || true
///   dart run tool/sync_test_report.dart --candidate-machine machine.jsonl \
///     --version 0.1.127+98 --branch local
const String defaultReportUrl =
    'https://raw.githubusercontent.com/Mfficiency/best_todo_2/ci-reports/latest.json';

Future<void> main(List<String> args) async {
  var output = 'assets/test_report.json';
  var url = defaultReportUrl;
  var fetch = true;
  var requireFetch = false;
  final candidateFiles = <String>[];
  String? machineInput;
  var commit = '';
  var branch = '';
  var version = '';
  var runUrl = '';

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String next() {
      if (i + 1 >= args.length) {
        stderr.writeln('Missing value for $arg');
        exit(64);
      }
      return args[++i];
    }

    switch (arg) {
      case '--output':
        output = next();
        break;
      case '--candidate':
        candidateFiles.add(next());
        break;
      case '--candidate-machine':
        machineInput = next();
        break;
      case '--url':
        url = next();
        break;
      case '--no-fetch':
        fetch = false;
        break;
      case '--require-fetch':
        requireFetch = true;
        break;
      case '--commit':
        commit = next();
        break;
      case '--branch':
        branch = next();
        break;
      case '--version':
        version = next();
        break;
      case '--run-url':
        runUrl = next();
        break;
      default:
        stderr.writeln('Unknown option: $arg');
        exit(64);
    }
  }

  final candidates = <String, TestReport>{};

  final existing = _readReport(output);
  if (existing != null) candidates['current $output'] = existing;

  for (final path in candidateFiles) {
    final report = _readReport(path);
    if (report == null) {
      stdout.writeln('Skipped unreadable candidate: $path');
      continue;
    }
    candidates[path] = report;
  }

  if (machineInput != null) {
    final file = File(machineInput);
    if (!file.existsSync()) {
      stderr.writeln('Machine output not found: $machineInput');
      exit(1);
    }
    candidates['local run ($machineInput)'] = TestReport.fromMachineJsonLines(
      file.readAsLinesSync(),
      commit: commit,
      branch: branch,
      appVersion: version.isEmpty ? _pubspecVersion() : version,
      runUrl: runUrl,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  if (fetch) {
    final fetched = await _fetchReport(url);
    if (fetched == null) {
      stdout.writeln('Could not fetch $url (offline?) — keeping local data.');
      if (requireFetch) exit(1);
    } else {
      candidates['published $url'] = fetched;
    }
  }

  final winner = TestReport.newest(candidates.values);
  if (winner == null) {
    stdout.writeln(
        'No test report available from any source; leaving $output as is.');
    if (!File(output).existsSync()) {
      _write(output, TestReport(available: false));
      stdout.writeln('Wrote placeholder $output.');
    }
    return;
  }

  final label = candidates.entries
      .firstWhere((entry) => identical(entry.value, winner))
      .key;
  _write(output, winner);
  stdout.writeln(
    'Packaged $output from $label: ${winner.passed} passed, '
    '${winner.failed} failed, ${winner.skipped} skipped'
    '${winner.branch.isEmpty ? '' : ' (${winner.branch})'}'
    '${winner.generatedAt == null ? '' : ' at ${winner.generatedAt!.toIso8601String()}'}',
  );
}

TestReport? _readReport(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return TestReport.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

void _write(String path, TestReport report) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n',
  );
}

Future<TestReport?> _fetchReport(String url) async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) {
      stdout.writeln('Fetch returned HTTP ${response.statusCode}.');
      return null;
    }
    final body = await response.transform(utf8.decoder).join();
    return TestReport.fromJson(jsonDecode(body) as Map<String, dynamic>);
  } catch (_) {
    return null;
  } finally {
    client?.close(force: true);
  }
}

/// Reads `version:` from pubspec.yaml so a local run records the version it
/// tested without the caller having to pass it.
String _pubspecVersion() {
  try {
    for (final line in File('pubspec.yaml').readAsLinesSync()) {
      if (line.startsWith('version:')) {
        return line.substring('version:'.length).trim();
      }
    }
  } catch (_) {
    // Not run from the repo root; the version stays empty.
  }
  return '';
}
