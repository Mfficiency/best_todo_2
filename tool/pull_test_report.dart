import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/test_report.dart';

/// Pulls the latest CI test report published on GitHub and writes it into
/// `assets/test_report.json`, so a LOCAL build bundles real CI results and the
/// app can display them offline (drawer failure dot + Test Results page's
/// offline fallback) instead of the committed `{"available": false}`
/// placeholder.
///
/// Run automatically by `tool/build.sh` before every local build; can also be
/// invoked by hand:
///
///   dart run tool/pull_test_report.dart
///   dart run tool/pull_test_report.dart --branch main
///
/// Network-failure-safe: if the report can't be fetched (offline, 404, bad
/// JSON) the existing asset is left untouched and the script still exits 0, so
/// building offline keeps working — you just ship the placeholder / previous
/// pull rather than fresh data.
///
/// The default URL mirrors `TestReportService.onlineReportUrl` and the publish
/// step in `.github/workflows/build-apk.yml` — keep the three in sync.
const String _repoSlug = 'Mfficiency/best_todo_2';
const String _defaultBranch = 'dev';
const String _reportPath = 'docs/ci/test_report.json';

String _rawUrl(String branch) =>
    'https://raw.githubusercontent.com/$_repoSlug/$branch/$_reportPath';

Future<void> main(List<String> args) async {
  String? url;
  String branch = _defaultBranch;
  String output = 'assets/test_report.json';

  for (var i = 0; i + 1 < args.length; i += 2) {
    final value = args[i + 1];
    switch (args[i]) {
      case '--url':
        url = value;
        break;
      case '--branch':
        branch = value;
        break;
      case '--output':
        output = value;
        break;
      default:
        stderr.writeln('Unknown option: ${args[i]}');
        exitCode = 64;
        return;
    }
  }

  final target = url ?? _rawUrl(branch);
  stdout.writeln('Pulling latest test report from $target');

  final String body;
  HttpClient? client;
  try {
    client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final request = await client.getUrl(Uri.parse(target));
    final response = await request.close();
    if (response.statusCode != 200) {
      _warn('server returned HTTP ${response.statusCode}', output);
      return;
    }
    body = await response.transform(utf8.decoder).join();
  } catch (e) {
    _warn('could not reach GitHub ($e)', output);
    return;
  } finally {
    client?.close(force: true);
  }

  // Validate before overwriting so a truncated/HTML error body never clobbers
  // the bundled asset with junk.
  final TestReport report;
  try {
    report = TestReport.fromJson(jsonDecode(body) as Map<String, dynamic>);
  } catch (e) {
    _warn('response was not a valid test report ($e)', output);
    return;
  }
  if (!report.available) {
    _warn('online report is marked unavailable — nothing to bundle', output);
    return;
  }

  File(output).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report.toJson()),
  );
  stdout.writeln(
    'Wrote $output from CI run ${report.commit} on ${report.branch}: '
    '${report.passed} passed, ${report.failed} failed, ${report.skipped} '
    'skipped (app v${report.appVersion}).',
  );
}

void _warn(String reason, String output) {
  stderr.writeln(
    'WARN: $reason — keeping existing $output. The build will bundle the '
    'previous report (or the offline placeholder).',
  );
}
