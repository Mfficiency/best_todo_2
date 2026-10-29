import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/sync_log_entry.dart';
import 'alarm_log_service.dart';
import 'app_updates.dart';
import 'log_service.dart';
import 'sync_service.dart';
import 'todoist_sync_service.dart';

export 'package:mfficiency_updates/mfficiency_updates.dart'
    show
        ProblemReporter,
        ProblemReportSettingsTile,
        ProblemReportTrigger,
        showProblemReport;

/// "Report a problem to Claude" (SPEC.md §11): a double tap on the app name
/// and version in the drawer header opens the shared package's report sheet
/// (`mfficiency_updates`, README.md › Problem reports to Claude). Send makes
/// it a GitHub issue in [AppUpdates.githubRepo] (label `claude-fix`), which
/// `.github/workflows/claude-fix.yml` hands to Claude to fix, merge into
/// `dev` and push — the laptop builder then ships it as the next update.
///
/// This file only holds BestToDo's config: the repo, the logs
/// ([collectLogs]), the token in secure storage ([tokenKey]) and the
/// browser ([openUrl]).
class ProblemReports {
  ProblemReports._();

  /// Secure-storage key of the GitHub token (fine-grained, Issues: read and
  /// write) that lets the app create the issue itself. Without it the
  /// report opens on GitHub's new-issue page in the browser.
  static const String tokenKey = 'problem_report.github_token';

  /// How much of `alarm_log.txt` goes into a report (its newest end): the
  /// file can be 400 KB, the issue body takes 65 536 characters.
  static const int alarmLogChars = 30000;

  static ProblemReporter? _instance;

  /// The app's reporter, made on first use. Tests set their own (fake logs
  /// and token, no file I/O inside `testWidgets`).
  static ProblemReporter get instance => _instance ??= create();

  @visibleForTesting
  static set instance(ProblemReporter? reporter) => _instance = reporter;

  static ProblemReporter create() => ProblemReporter(
        config: ProblemReportConfig(
          appName: 'BestToDo',
          version: Config.version,
          build: int.tryParse(Config.buildNumber) ?? 0,
          channel: Config.channel,
          githubRepo: AppUpdates.githubRepo,
        ),
        collectLogs: collectLogs,
        readToken: _readToken,
        writeToken: _writeToken,
        openUrl: openUrl,
      );

  static Future<String?> _readToken() async {
    try {
      return await AppUpdates.secureStorage.read(key: tokenKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeToken(String? token) async {
    if (token == null) {
      await AppUpdates.secureStorage.delete(key: tokenKey);
    } else {
      await AppUpdates.secureStorage.write(key: tokenKey, value: token);
    }
  }

  static Future<bool> openUrl(String url) async {
    try {
      return await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// The app's logs for a report, one header per source, the most useful
  /// last (the package cuts from the oldest end when the body is too long):
  /// the Obsidian/folder sync and Todoist sync histories, the newest
  /// [alarmLogChars] of `alarm_log.txt`, then the in-memory app log (App
  /// Logs › Events, last 24 hours). Every source is optional; a failing one
  /// says so instead of breaking the report.
  static Future<String> collectLogs() async {
    final parts = <String>[];

    Future<void> section(String title, Future<String> Function() read) async {
      String text;
      try {
        text = (await read()).trim();
      } catch (e) {
        text = '(could not read: $e)';
      }
      parts.add('===== $title =====\n${text.isEmpty ? '(empty)' : text}');
    }

    await section('Sync history (sync_log.json)', () async {
      await SyncService.instance.ensureLoaded();
      return _syncLines(SyncService.instance.entries.value);
    });
    await section('Todoist sync history (todoist_sync_log.json)', () async {
      await TodoistSyncService.instance.ensureLoaded();
      return _syncLines(TodoistSyncService.instance.entries.value);
    });
    await section('Alarm log (alarm_log.txt)', () async {
      final log = await AlarmLog.read();
      if (log.length <= alarmLogChars) return log;
      final cut = log.length - alarmLogChars;
      final nl = log.indexOf('\n', cut);
      return '(older entries left out)\n'
          '${log.substring(nl == -1 ? cut : nl + 1)}';
    });
    await section('App log (App Logs › Events, last 24 h)',
        () async => LogService.logs.value.join('\n'));
    return parts.join('\n\n');
  }

  /// [entries] are newest first; the report lists them oldest first.
  static String _syncLines(List<SyncLogEntry> entries) => [
        for (final e in entries.reversed)
          '${e.at.toIso8601String()} [${e.trigger}] '
              '${e.success ? 'OK' : 'FAIL'} ${e.itemCount} items '
              '${e.durationMs} ms${e.message.isEmpty ? '' : ' — ${e.message}'}',
      ].join('\n');
}
