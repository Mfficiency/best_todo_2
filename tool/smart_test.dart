// Smart test runner: looks at what changed and runs only the matching
// suite(s) instead of the whole `flutter test`, mirroring the file->suite
// map in test/README.md ("Which suites to run"). Keep the two in sync when
// that map changes.
//
// Running a handful of suites on every edit is fast, but never running the
// full suite risks a silent gap (a suite that should have caught something
// but was never picked). So besides the targeted run, this also forces a
// full `flutter test` periodically: after every `fullRunEveryMods` targeted
// runs, or after `fullRunEveryDays` days since the last full run, whichever
// comes first. State (mods since the last full run, when the last full run
// happened) is kept in `.smart_test_state.json`, gitignored: it is a
// per-machine cache, not shared history.
//
// A change with no matching rule below (a new lib/ file, an unrecognised
// platform file, ...) is treated the same as a "cross-cutting" change
// (theme, navigation, pubspec.yaml) and forces a full run rather than
// silently testing nothing for it.
//
// Usage:
//   dart run tool/smart_test.dart                    (decide + run)
//   dart run tool/smart_test.dart --dry-run           (decide, print, run nothing)
//   dart run tool/smart_test.dart --full              (force a full run)
//   dart run tool/smart_test.dart --base <git-ref>    (diff against <ref> instead
//                                                       of the working tree/last commit)
//   dart run tool/smart_test.dart --files a.dart,b.dart   (explicit file list,
//                                                           skips git entirely)
//   dart run tool/smart_test.dart --state <path>      (use a different state file)

import 'dart:convert';
import 'dart:io';

const String defaultStateFilePath = '.smart_test_state.json';
const int fullRunEveryMods = 10;
const int fullRunEveryDays = 7;

/// A changed path pulls in [suites] (core is always added on top) when it
/// matches one of [paths]. A path entry ending in `/` matches anything
/// starting with it (a directory); otherwise it matches either the exact
/// repo-relative path or any path ending in `/<entry>` (so a platform file
/// can be named just by its basename regardless of its full directory).
class SuiteRule {
  final List<String> paths;
  final Set<String> suites;
  const SuiteRule(this.paths, this.suites);

  bool matches(String path) => _matchesAny(path, paths);
}

/// A path entry ending in `/` matches anything starting with it (a
/// directory); otherwise it matches either the exact repo-relative path or
/// any path ending in `/<entry>` (a basename match, direction-agnostic).
bool _matchesAny(String path, List<String> entries) => entries.any((p) {
      if (p.endsWith('/')) return path.startsWith(p);
      return path == p || path.endsWith('/$p');
    });

/// Files/directories whose change can't break a test (docs, changelogs,
/// generated reports, staged binaries): skipped entirely, not even core.
const List<String> noTestImpactPaths = [
  'CHANGELOG.md',
  'SCREENSHOT_CHANGELOG.md',
  'SPEC.md',
  'README.md',
  'LICENSE',
  'promptlinks.md',
  '.gitignore',
  'docs/',
  '.claude/',
  '.github/',
  'github_releases/',
  'build_history.json',
  'assets/test_report.json',
];

/// Cross-cutting files: force a full run rather than a targeted guess.
/// Deliberately narrow — dependency/lint config that isn't covered by any
/// suite mapping at all. `lib/main.dart` carries the app's theme/navigation
/// setup but test/README.md maps it to core like the other model/service
/// fundamentals below, so it's a targeted rule, not a full-run trigger.
const List<String> crossCuttingPaths = [
  'pubspec.yaml',
  'pubspec.lock',
  'analysis_options.yaml',
];

/// Mirrors test/README.md's "Which suites to run" table.
final List<SuiteRule> suiteRules = [
  SuiteRule(['lib/models/task.dart', 'lib/services/storage_service.dart', 'lib/utils/', 'lib/config.dart', 'lib/main.dart'], {}),
  SuiteRule(['lib/models/attachment.dart', 'lib/services/attachment_storage_service.dart', 'lib/ui/attachments_field.dart'], {'home'}),
  SuiteRule(['lib/models/view_filter_rules.dart', 'lib/services/item_views.dart'], {'home', 'projects', 'tools'}),
  SuiteRule(['lib/models/alarm.dart'], {'alarms'}),
  SuiteRule(['lib/ui/widget_previews_page.dart'], {'home', 'alarms', 'tools'}),
  SuiteRule(['lib/models/project.dart', 'lib/services/project_service.dart', 'lib/ui/projects_page.dart', 'lib/ui/project_board_page.dart'], {'projects'}),
  SuiteRule(['lib/services/recurrence_service.dart', 'lib/models/recurrence_config.dart', 'lib/ui/recurrence_editor.dart', 'lib/ui/recurrence_scope_dialog.dart'], {'recurrence', 'home'}),
  SuiteRule(['lib/ui/home_page.dart', 'lib/ui/task_tile.dart', 'lib/ui/settings_page.dart', 'lib/ui/dice_timer_page.dart'], {'home', 'projects', 'streaks', 'recurrence', 'music'}),
  SuiteRule([
    'lib/models/track.dart', 'lib/models/music_playlist.dart', 'lib/services/music_library_service.dart',
    'lib/services/music_playlist_service.dart', 'lib/services/music_audio_handler.dart', 'lib/services/music_player_service.dart',
    'lib/services/music_widget_service.dart', 'lib/services/m3u_playlist_service.dart', 'lib/services/subsonic_client.dart',
    'lib/utils/artist_utils.dart', 'lib/ui/music_player_page.dart', 'lib/ui/now_playing_page.dart',
  ], {'music', 'home'}),
  SuiteRule(['lib/services/task_mutation_service.dart', 'lib/models/task_change_source.dart'], {'history', 'home'}),
  SuiteRule([
    'lib/services/streak_service.dart', 'lib/models/streak_kind.dart', 'lib/models/streak_goal.dart',
    'lib/models/streak_reminder.dart', 'lib/services/streak_flame_display.dart', 'lib/ui/streak_page.dart',
    'lib/ui/streak_flame_button.dart', 'lib/ui/streak_goal_dialog.dart', 'lib/ui/streak_calendar_page.dart',
    'lib/ui/streak_celebration.dart',
  ], {'streaks'}),
  SuiteRule([
    'lib/models/sms_recipient.dart', 'lib/models/sms_report_config.dart',
    'lib/services/sms_report_service.dart', 'lib/services/sms_report_scheduler.dart',
    'lib/services/sms_report_config_service.dart', 'lib/models/sms_report_log_entry.dart',
    'lib/services/sms_report_log_service.dart', 'lib/ui/sms_report_log_page.dart',
  ], {'sms', 'home', 'streaks'}),
  SuiteRule([
    'lib/services/sync_service.dart', 'lib/services/sync_markdown.dart', 'lib/services/todoist_sync_service.dart',
    'lib/services/todoist_api_client.dart', 'lib/services/todoist_metadata_codec.dart', 'lib/models/sync_log_entry.dart',
    'lib/models/todoist_sync_map_entry.dart', 'lib/ui/waiting_approval_page.dart', 'lib/ui/app_logs_page.dart',
  ], {'sync', 'home'}),
  SuiteRule(['lib/services/share_intent_service.dart', 'lib/models/shared_payload.dart', 'lib/ui/quick_add_share_page.dart',
    'ShareActivity.kt', 'MainActivity.kt'], {'share', 'home'}),
  SuiteRule([
    'lib/services/usage_data_service.dart', 'lib/services/startup_time_service.dart', 'lib/ui/startup_times_page.dart',
    'lib/ui/chronize_page.dart', 'lib/ui/changelog_page.dart', 'lib/models/countdown_timer.dart', 'lib/models/test_report.dart',
    'lib/services/test_report_service.dart', 'lib/ui/test_results_page.dart', 'lib/services/wishlist_migration.dart',
    'lib/services/wishlist_shipped.dart', 'lib/ui/wishlist_page.dart', 'lib/ui/your_stats_page.dart',
    'tool/generate_test_report.dart', 'lib/models/weekly_hours_plan.dart', 'lib/services/weekly_hours_service.dart',
    'lib/ui/weekly_hours_planner_page.dart', 'lib/models/gcal_event.dart', 'lib/services/google_calendar_service.dart',
  ], {'tools', 'home'}),
  SuiteRule(['lib/models/auto_tag_group.dart', 'lib/services/auto_tag_service.dart', 'lib/ui/auto_tag_rules_page.dart'], {'home', 'tools'}),
  SuiteRule([
    'lib/services/update_service.dart', 'lib/services/auto_update_checker.dart', 'lib/ui/about_page.dart',
    'lib/ui/auto_update_dialog.dart', 'tool/publish_apk.dart', 'tool/stage_local_release.dart', 'tool/append_build_time.dart',
  ], {'update'}),
  SuiteRule(['lib/utils/linkified_text.dart', 'lib/ui/task_detail_page.dart'], {'home', 'tools'}),
  SuiteRule(['AlarmsWidgetProvider.kt'], {'alarms', 'home'}),
  SuiteRule(['SimpleWidgetProvider.kt'], {'home'}),
];

/// Maps a `test/<area>/...` path straight to that area's own suite.
String? testSuiteFor(String path) {
  final match = RegExp(r'^test/([^/]+)/').firstMatch(path);
  if (match == null) return null;
  final dir = match.group(1)!;
  return dir == 'core' ? null : dir;
}

/// What a set of changed files implies for testing: the extra suites (beyond
/// core) a targeted run should include, whether a full run is warranted
/// regardless, and (for a human/log) which files drove that full-run call.
class Classification {
  final Set<String> suites;
  final bool crossCutting;
  final List<String> crossCuttingFiles;
  final bool anyTestRelevant;
  const Classification(this.suites, this.crossCutting, this.crossCuttingFiles, this.anyTestRelevant);
}

Classification classify(List<String> changedFiles) {
  final suites = <String>{};
  final crossCuttingFiles = <String>[];
  var anyTestRelevant = false;

  for (final raw in changedFiles) {
    final path = raw.replaceAll('\\', '/').trim();
    if (path.isEmpty) continue;
    if (_matchesAny(path, noTestImpactPaths)) continue;

    anyTestRelevant = true;

    if (_matchesAny(path, crossCuttingPaths)) {
      crossCuttingFiles.add(path);
      continue;
    }

    final testSuite = testSuiteFor(path);
    if (testSuite != null) {
      suites.add(testSuite);
      continue;
    }
    if (path.startsWith('test/core/')) continue;

    var matchedAny = false;
    for (final rule in suiteRules) {
      if (rule.matches(path)) {
        matchedAny = true;
        suites.addAll(rule.suites);
      }
    }
    if (!matchedAny && path.startsWith('lib/')) {
      // No rule recognises this lib/ file: don't guess, fall back to full.
      crossCuttingFiles.add(path);
      continue;
    }
    if (!matchedAny && !path.startsWith('lib/') && !path.startsWith('test/')) {
      // Unrecognised non-lib, non-test, non-doc file (tool/, android/, ...):
      // same fallback.
      crossCuttingFiles.add(path);
    }
  }

  return Classification(
      suites, crossCuttingFiles.isNotEmpty, crossCuttingFiles, anyTestRelevant);
}

/// Persisted between runs: how many targeted runs happened since the last
/// full run, and when that full run was.
class SmartTestState {
  final int modsSinceFullRun;
  final DateTime? lastFullRun;
  final int totalRuns;
  const SmartTestState({
    required this.modsSinceFullRun,
    required this.lastFullRun,
    required this.totalRuns,
  });

  static const initial = SmartTestState(modsSinceFullRun: 0, lastFullRun: null, totalRuns: 0);

  static SmartTestState fromJson(Map<String, dynamic> json) => SmartTestState(
        modsSinceFullRun: json['modsSinceFullRun'] as int? ?? 0,
        lastFullRun: json['lastFullRun'] == null
            ? null
            : DateTime.tryParse(json['lastFullRun'] as String),
        totalRuns: json['totalRuns'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'modsSinceFullRun': modsSinceFullRun,
        'lastFullRun': lastFullRun?.toIso8601String(),
        'totalRuns': totalRuns,
      };

  SmartTestState afterRun({required bool full}) => SmartTestState(
        modsSinceFullRun: full ? 0 : modsSinceFullRun + 1,
        lastFullRun: full ? DateTime.now() : lastFullRun,
        totalRuns: totalRuns + 1,
      );
}

SmartTestState readState(File file) {
  if (!file.existsSync()) return SmartTestState.initial;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, dynamic>) return SmartTestState.fromJson(decoded);
  } catch (_) {
    // Corrupt/foreign content: start fresh rather than fail the run.
  }
  return SmartTestState.initial;
}

void writeState(File file, SmartTestState state) {
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(state.toJson())}\n');
}

/// What to actually run, and why, given a classification and the current
/// state. Pure and independent of the clock/state source so it's directly
/// testable.
class RunDecision {
  final bool full;
  final String reason;
  final Set<String> suites;
  const RunDecision({required this.full, required this.reason, this.suites = const {}});
}

RunDecision decide({
  required Classification classification,
  required SmartTestState state,
  required DateTime now,
  bool forceFull = false,
}) {
  if (forceFull) {
    return const RunDecision(full: true, reason: '--full requested');
  }
  if (classification.crossCutting) {
    final files = classification.crossCuttingFiles.join(', ');
    return RunDecision(full: true, reason: 'cross-cutting/unrecognised change: $files');
  }
  if (state.modsSinceFullRun >= fullRunEveryMods) {
    return RunDecision(
        full: true,
        reason: '$fullRunEveryMods targeted runs since the last full run '
            '(safety net)');
  }
  final lastFullRun = state.lastFullRun;
  if (lastFullRun == null) {
    return const RunDecision(full: true, reason: 'no recorded full run yet');
  }
  if (now.difference(lastFullRun) >= Duration(days: fullRunEveryDays)) {
    return RunDecision(
        full: true,
        reason: '$fullRunEveryDays+ days since the last full run (safety net)');
  }
  if (!classification.anyTestRelevant) {
    return const RunDecision(full: false, reason: 'no test-relevant files changed', suites: {});
  }
  return RunDecision(
      full: false, reason: 'targeted run', suites: {'core', ...classification.suites});
}

Future<List<String>> _gitChangedFiles({String? base}) async {
  final files = <String>{};

  Future<void> addFrom(List<String> args) async {
    final result = await Process.run('git', args);
    if (result.exitCode != 0) return;
    for (final line in (result.stdout as String).split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) files.add(trimmed);
    }
  }

  if (base != null) {
    await addFrom(['diff', '--name-only', '$base...HEAD']);
  }

  // Uncommitted work: staged, unstaged and untracked (not ignored).
  final status = await Process.run('git', ['status', '--porcelain']);
  if (status.exitCode == 0) {
    for (final line in (status.stdout as String).split('\n')) {
      if (line.length < 4) continue;
      files.add(line.substring(3).trim());
    }
  }

  if (base == null && files.isEmpty) {
    // Nothing pending locally: fall back to what the last commit touched.
    await addFrom(['diff', '--name-only', 'HEAD~1', 'HEAD']);
  }

  return files.toList();
}

Future<int> _runFlutterTest(List<String> suites) async {
  final args = ['test', if (suites.isNotEmpty) ...suites.map((s) => 'test/$s')];
  stdout.writeln('==> flutter ${args.join(' ')}');
  final process = await Process.start('flutter', args, mode: ProcessStartMode.inheritStdio);
  return process.exitCode;
}

void _usage([String? error]) {
  if (error != null) stderr.writeln(error);
  stderr.writeln('Usage: dart run tool/smart_test.dart '
      '[--dry-run] [--full] [--base <ref>] [--files a.dart,b.dart] [--state <path>]');
}

Future<void> main(List<String> args) async {
  var dryRun = false;
  var forceFull = false;
  String? base;
  List<String>? explicitFiles;
  var statePath = defaultStateFilePath;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dry-run':
        dryRun = true;
      case '--full':
        forceFull = true;
      case '--base':
        if (i + 1 >= args.length) return _usage('--base needs a git ref');
        base = args[++i];
      case '--files':
        if (i + 1 >= args.length) return _usage('--files needs a comma-separated list');
        explicitFiles = args[++i].split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      case '--state':
        if (i + 1 >= args.length) return _usage('--state needs a path');
        statePath = args[++i];
      default:
        return _usage('Unknown argument: ${args[i]}');
    }
  }

  final changedFiles = explicitFiles ?? await _gitChangedFiles(base: base);
  final classification = classify(changedFiles);
  final stateFile = File(statePath);
  final state = readState(stateFile);
  final decision = decide(
    classification: classification,
    state: state,
    now: DateTime.now(),
    forceFull: forceFull,
  );

  stdout.writeln('Smart test: ${changedFiles.length} changed file(s)'
      '${changedFiles.isEmpty ? '' : ':\n  ' + changedFiles.join('\n  ')}');
  stdout.writeln('Decision: ${decision.full ? 'FULL run' : 'targeted run'} '
      '(${decision.reason})');
  if (!decision.full) {
    stdout.writeln(decision.suites.isEmpty
        ? 'Nothing to test.'
        : 'Suites: ${decision.suites.join(', ')}');
  }
  stdout.writeln('State: ${state.modsSinceFullRun} mod(s) since last full run'
      '${state.lastFullRun == null ? ', never run in full' : ', last full run ${state.lastFullRun!.toIso8601String()}'}');

  if (dryRun) {
    stdout.writeln('Dry run — not running tests or updating state.');
    return;
  }

  int exitResult = 0;
  if (decision.full) {
    exitResult = await _runFlutterTest(const []);
  } else if (decision.suites.isNotEmpty) {
    exitResult = await _runFlutterTest(decision.suites.toList()..sort());
  } else {
    stdout.writeln('Skipping flutter test — no suites touched.');
  }

  final ranSomething = decision.full || decision.suites.isNotEmpty;
  if (ranSomething) {
    writeState(stateFile, state.afterRun(full: decision.full));
  }

  exitCode = exitResult;
}
