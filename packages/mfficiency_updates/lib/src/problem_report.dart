import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'http.dart';
import 'problem_report_stub.dart' if (dart.library.io) 'problem_report_io.dart'
    as impl;

/// Where a problem report goes: the app's GitHub repo, as an issue Claude
/// picks up (the repo's `.github/workflows/claude-fix.yml`), fixes, merges
/// into dev and ships as the next update. See README.md › Problem reports.
class ProblemReportConfig {
  const ProblemReportConfig({
    required this.appName,
    required this.version,
    required this.build,
    this.channel = 'main',
    required this.githubRepo,
    this.label = claudeFixLabel,
    this.maxBodyChars = 60000,
    this.maxUrlChars = 7000,
    this.userAgent,
  });

  /// The label (and [marker]) the repo's Claude workflow reacts to.
  static const claudeFixLabel = 'claude-fix';

  /// Hidden in every report's body: the workflow only runs on issues that
  /// carry it (and that the owner wrote), so a stranger's issue never does.
  static const marker = '<!-- mfficiency-problem-report -->';

  final String appName;
  final String version;
  final int build;
  final String channel;

  /// "owner/repo"; empty = not configured (the sheet says so).
  final String githubRepo;
  final String label;

  /// GitHub's limit for an issue body is 65536 characters; logs are cut
  /// from the oldest end to stay below this.
  final int maxBodyChars;

  /// The browser fallback (no token) puts the report in the URL, which
  /// GitHub only takes up to about 8 KB.
  final int maxUrlChars;

  /// `User-Agent` of the default dart:io request (spaces removed).
  final String? userAgent;

  /// The page where a fine-grained token is made (README.md has the steps).
  static const tokenPage =
      'https://github.com/settings/personal-access-tokens/new';
}

/// One report as it goes out: [title] and [body] (markdown).
@immutable
class ProblemReport {
  const ProblemReport({required this.title, required this.body});
  final String title;
  final String body;
}

enum ProblemReportOutcome {
  /// The issue is on GitHub ([ProblemReportResult.issueUrl]).
  sent,

  /// No token: GitHub's new-issue page opened in the browser, filled in.
  openedInBrowser,

  /// GitHub refused the token (401, 403, or 404: it can't see the repo).
  badToken,

  /// No repo configured.
  notConfigured,

  /// Offline, GitHub down, or the browser didn't open.
  failed,
}

@immutable
class ProblemReportResult {
  const ProblemReportResult(this.outcome, {this.issueUrl, this.issueNumber});
  final ProblemReportOutcome outcome;
  final String? issueUrl;
  final int? issueNumber;
}

/// POSTs [body] as JSON and returns the decoded answer; throws
/// [UpdateHttpException] for an error status (or no answer).
typedef ProblemReportPost = Future<Object?> Function(
  Uri url,
  Map<String, String> headers,
  Object? body,
);

/// Sends problem reports: the user's description, the app's facts and its
/// logs, as a GitHub issue labelled [ProblemReportConfig.label]. With a
/// token (Settings, [ProblemReportSettingsTile]) straight from the app;
/// without one GitHub's new-issue page opens filled in, for the user to
/// submit (logs shortened to fit the URL).
class ProblemReporter extends ChangeNotifier {
  ProblemReporter({
    required this.config,
    Future<String> Function()? collectLogs,
    Future<String?> Function()? readToken,
    Future<void> Function(String? token)? writeToken,
    ProblemReportPost? post,
    required Future<bool> Function(String url) openUrl,
    DateTime Function()? clock,
    String? platformName,
  })  : _collectLogs = collectLogs,
        _readToken = readToken ?? _prefsRead,
        _writeToken = writeToken ?? _prefsWrite,
        _post = post ??
            impl.postJson(
              userAgent:
                  (config.userAgent ?? '${config.appName}-problem-report')
                      .replaceAll(' ', ''),
            ),
        _openUrl = openUrl,
        _clock = clock ?? DateTime.now,
        _platformName =
            platformName ?? (kIsWeb ? 'web' : defaultTargetPlatform.name);

  final ProblemReportConfig config;
  final Future<String> Function()? _collectLogs;
  final Future<String?> Function() _readToken;
  final Future<void> Function(String?) _writeToken;
  final ProblemReportPost _post;
  final Future<bool> Function(String url) _openUrl;
  final DateTime Function() _clock;
  final String _platformName;

  static const prefsKey = 'problem_report.github_token';

  static Future<String?> _prefsRead() async =>
      (await SharedPreferences.getInstance()).getString(prefsKey);

  static Future<void> _prefsWrite(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(prefsKey);
    } else {
      await prefs.setString(prefsKey, token);
    }
  }

  /// Opens [url] with the app's opener (the token page); false on failure.
  Future<bool> openUrl(String url) async {
    try {
      return await _openUrl(url);
    } on Object {
      return false;
    }
  }

  bool get isConfigured => config.githubRepo.contains('/');

  /// The saved token, trimmed; null when none.
  Future<String?> token() async {
    try {
      final t = (await _readToken())?.trim();
      return t == null || t.isEmpty ? null : t;
    } on Object {
      return null;
    }
  }

  /// Saves [token] (empty or null removes it); listeners hear of it.
  Future<void> setToken(String? token) async {
    final t = token?.trim();
    await _writeToken(t == null || t.isEmpty ? null : t);
    notifyListeners();
  }

  /// The app's logs; a failure becomes a line in the report instead.
  Future<String> logs() async {
    final collect = _collectLogs;
    if (collect == null) return '';
    try {
      return await collect();
    } on Object catch (e) {
      return '(collecting the logs failed: $e)';
    }
  }

  String _channelSuffix() =>
      config.channel == 'main' ? '' : ' · ${config.channel}';

  /// The issue for [description] and [logs] (null: none attached), cut to
  /// [maxChars] (the oldest log lines go first). [secret] is blanked out.
  ProblemReport compose(
    String description, {
    String? logs,
    int? maxChars,
    String? secret,
  }) {
    final text = description.trim();
    final firstLine = text.split('\n').first.trim();
    final title = firstLine.isEmpty
        ? 'Problem report: ${config.appName} ${config.version}'
        : 'Problem report: ${firstLine.length > 80 ? '${firstLine.substring(0, 79)}…' : firstLine}';
    final head = StringBuffer()
      ..writeln(ProblemReportConfig.marker)
      ..writeln('## What went wrong')
      ..writeln()
      ..writeln(text.isEmpty ? '_(no description, see the logs)_' : text)
      ..writeln()
      ..writeln('## App')
      ..writeln()
      ..writeln('- ${config.appName} ${config.version} '
          '(build ${config.build})${_channelSuffix()}')
      ..writeln('- Platform: $_platformName')
      ..writeln('- Sent: ${_clock().toIso8601String()}')
      ..writeln();
    final tail = StringBuffer()
      ..writeln('---')
      ..writeln('_Sent from the app (double-tap on the version in the menu). '
          'Claude: find the cause in the logs and the code, fix it and ship it '
          'to dev._');
    var log = logs?.trimRight() ?? '';
    if (secret != null && secret.isNotEmpty)
      log = log.replaceAll(secret, '***');
    if (logs == null) {
      return ProblemReport(
        title: title,
        body: '${head}_No logs attached._\n\n$tail',
      );
    }
    const open = '## Logs\n\n<details><summary>Logs</summary>\n\n```text\n';
    const close = '\n```\n\n</details>\n\n';
    final limit = maxChars ?? config.maxBodyChars;
    final room = limit - head.length - tail.length - open.length - close.length;
    if (log.length > room) {
      final keep = room - 60 < 0 ? 0 : room - 60;
      final cut = log.length - keep;
      log = '… ($cut older characters cut)\n'
          '${log.substring(log.length - keep)}';
    }
    if (log.isEmpty) log = '(no log lines)';
    return ProblemReport(title: title, body: '$head$open$log$close$tail');
  }

  /// GitHub's new-issue page with [report] filled in and labelled.
  String browserUrl(ProblemReport report) => Uri.https(
        'github.com',
        '/${config.githubRepo}/issues/new',
        {
          'title': report.title,
          'body': report.body,
          'labels': config.label,
        },
      ).toString();

  Future<ProblemReportResult> _viaBrowser(
      String description, String? log) async {
    // The URL is percent-encoded, up to 3x longer than the text: shrink the
    // logs until it fits.
    var max = config.maxUrlChars;
    var report = compose(description, logs: log, maxChars: max);
    while (log != null &&
        browserUrl(report).length > config.maxUrlChars &&
        max > 800) {
      max = (max * 0.7).round();
      report = compose(description, logs: log, maxChars: max);
    }
    final ok = await openUrl(browserUrl(report));
    return ProblemReportResult(
      ok ? ProblemReportOutcome.openedInBrowser : ProblemReportOutcome.failed,
    );
  }

  /// Sends [description] (and the logs when [includeLogs]): as an issue
  /// with the token, else through the browser.
  Future<ProblemReportResult> send(
    String description, {
    bool includeLogs = true,
  }) async {
    if (!isConfigured) {
      return const ProblemReportResult(ProblemReportOutcome.notConfigured);
    }
    final token = await this.token();
    final log = includeLogs ? await logs() : null;
    if (token == null) return _viaBrowser(description, log);
    final report = compose(description, logs: log, secret: token);
    try {
      final answer = await _post(
        Uri.https('api.github.com', '/repos/${config.githubRepo}/issues'),
        {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'Content-Type': 'application/json; charset=utf-8',
        },
        {
          'title': report.title,
          'body': report.body,
          'labels': [config.label],
        },
      );
      final map = answer is Map ? answer : const {};
      return ProblemReportResult(
        ProblemReportOutcome.sent,
        issueUrl: map['html_url'] as String?,
        issueNumber: (map['number'] as num?)?.toInt(),
      );
    } on UpdateHttpException catch (e) {
      // A browser build without dart:io: the new-issue page instead.
      if (e.status == null && e.cause == 'unsupported') {
        return _viaBrowser(description, log);
      }
      final refused = e.status == 401 || e.status == 403 || e.status == 404;
      return ProblemReportResult(
        refused ? ProblemReportOutcome.badToken : ProblemReportOutcome.failed,
      );
    } on Object {
      return const ProblemReportResult(ProblemReportOutcome.failed);
    }
  }
}
