import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/test_report.dart';

/// Keeps `assets/test_report.json` (or any `--output` path) pointed at the
/// newest known test report, merging up to four sources through
/// [TestReport.newest]: whatever is already at `--output` (never regressed),
/// `--candidate` (a report JSON just generated this run), `--candidate-machine`
/// (raw `flutter test --machine` output, converted on the fly), and — unless
/// `--no-fetch` — the `ci-reports` branch's `latest.json`, published by
/// `tool/ci/publish_test_report.sh` from every branch's CI run.
///
/// Usage:
///   dart run tool/sync_test_report.dart \
///     --candidate build/ci/test_report.json --output assets/test_report.json
///   dart run tool/sync_test_report.dart --no-fetch \
///     --candidate-machine build/ci/machine.jsonl
///
/// Every failure path (network down, missing/corrupt file) is non-fatal: the
/// existing report at `--output` is left untouched and the script exits 0, so
/// this never breaks a build or a commit.
const String _repoSlug = 'Mfficiency/best_todo_2';
const String _storeBranch = 'ci-reports';
const String _storeReportPath = 'latest.json';

Future<void> main(List<String> args) async {
  String output = 'assets/test_report.json';
  String? candidatePath;
  String? candidateMachinePath;
  bool fetch = true;
  String? url;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--output':
        output = args[++i];
        break;
      case '--candidate':
        candidatePath = args[++i];
        break;
      case '--candidate-machine':
        candidateMachinePath = args[++i];
        break;
      case '--no-fetch':
        fetch = false;
        break;
      case '--fetch':
        fetch = true;
        break;
      case '--url':
        url = args[++i];
        break;
      default:
        stderr.writeln('Unknown option: ${args[i]}');
        exitCode = 64;
        return;
    }
  }

  TestReport? best = _readReport(output);

  if (candidatePath != null) {
    best = TestReport.newest(best, _readReport(candidatePath));
  }

  if (candidateMachinePath != null && File(candidateMachinePath).existsSync()) {
    final fromMachine = TestReport.fromMachineJsonLines(
      File(candidateMachinePath).readAsLinesSync(),
      generatedAt: DateTime.now().toUtc(),
    );
    best = TestReport.newest(best, fromMachine);
  }

  if (fetch) {
    final target = url ??
        'https://raw.githubusercontent.com/$_repoSlug/$_storeBranch/$_storeReportPath';
    best = TestReport.newest(best, await _fetchReport(target));
  }

  if (best == null) {
    stdout.writeln('No usable report found; leaving $output untouched.');
    return;
  }

  final dir = File(output).parent;
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File(output).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(best.toJson()),
  );
  stdout.writeln(
    'Wrote $output: ${best.passed} passed, ${best.failed} failed, '
    '${best.skipped} skipped (commit ${best.commit}, branch ${best.branch}).',
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

Future<TestReport?> _fetchReport(String target) async {
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final request = await client.getUrl(Uri.parse(target));
    final response = await request.close();
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    return TestReport.fromJson(jsonDecode(body) as Map<String, dynamic>);
  } catch (_) {
    return null;
  } finally {
    client?.close(force: true);
  }
}
