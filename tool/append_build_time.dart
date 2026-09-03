// Records when a local build finished and (when known) how long it took, by
// writing/updating notes inside the newest `## [version] - date` section of
// CHANGELOG.md, and appends a durable per-build record to build_history.json
// so build durations can be tracked across builds, versions and machines
// over time (that file is committed, not gitignored).
//
// Run this *after* `flutter build`, not before: CHANGELOG.md is bundled as an
// app asset at build time, so a build can never show its own timestamp or
// duration — only the ones written by the previous build. That's expected
// (see CLAUDE.md).
//
// Usage:
//   dart run tool/append_build_time.dart                     (called by tool/build.sh)
//   dart run tool/append_build_time.dart --duration 102 --target apk
//   dart run tool/append_build_time.dart --dry-run

import 'dart:convert';
import 'dart:io';

/// Line prefix used to find/replace the existing build-time note, so
/// building the same version repeatedly updates one line instead of piling
/// up a new one per build.
const String buildTimeLinePrefix = '- Local build: ';

/// Where per-build duration history is persisted. Committed to the repo (not
/// gitignored) so build times are tracked across machines and over the life
/// of the project, not just on whichever machine last built.
const String historyFileName = 'build_history.json';

/// Cap on stored history entries so the file doesn't grow without bound.
const int maxHistoryEntries = 1000;

/// `HH:MM` local time appended after the release date, e.g. `2026-08-21 14:47`.
String formatBuildTime(DateTime now) {
  final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  final time =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

/// Formats a whole-second duration as `45s`, `1m 42s` or `1h 03m`.
String formatDuration(int seconds) {
  final clamped = seconds < 0 ? 0 : seconds;
  final hours = clamped ~/ 3600;
  final minutes = (clamped % 3600) ~/ 60;
  final secs = clamped % 60;
  if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  if (minutes > 0) return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
  return '${secs}s';
}

/// Note-line prefix for a build-duration line, keyed by target (`apk`,
/// `windows`, ...) so each target keeps its own line inside a version's
/// section instead of overwriting the other's.
String buildDurationLinePrefix(String target) =>
    '- Build duration ($target): ';

/// Inserts/updates a note line (identified by [prefix]) inside the first
/// (i.e. newest) `## [...]` section of [changelog]. Returns the updated
/// text, or null when there is no section to attach it to.
String? _withNoteLine(String changelog, String prefix, String value) {
  final headerRegex = RegExp(r'^##\s*\[[^\]]+\]\s*-\s*.+$', multiLine: true);
  final firstHeader = headerRegex.firstMatch(changelog);
  if (firstHeader == null) return null;

  final sectionStart = firstHeader.end;
  final nextHeader = headerRegex.firstMatch(changelog.substring(sectionStart));
  final sectionEnd =
      nextHeader == null ? changelog.length : sectionStart + nextHeader.start;

  final section = changelog.substring(sectionStart, sectionEnd);
  final noteLine = '$prefix$value';

  final lines = section.split('\n');
  final existingIndex = lines.indexWhere((l) => l.trim().startsWith(prefix));
  if (existingIndex != -1) {
    lines[existingIndex] = noteLine;
  } else {
    // Insert right after the header, trailing blank lines in the section
    // (if any) stay at the end so formatting matches the rest of the file.
    var insertAt = 0;
    while (insertAt < lines.length && lines[insertAt].trim().isEmpty) {
      insertAt++;
    }
    while (insertAt < lines.length && lines[insertAt].trim().isNotEmpty) {
      insertAt++;
    }
    lines.insert(insertAt, noteLine);
  }

  final updatedSection = lines.join('\n');
  return changelog.substring(0, sectionStart) +
      updatedSection +
      changelog.substring(sectionEnd);
}

/// Inserts/updates a `- Local build: <time>` line inside the newest
/// CHANGELOG.md section. Returns null when there is no section to attach to.
String? withBuildTimeNote(String changelog, String buildTime) =>
    _withNoteLine(changelog, buildTimeLinePrefix, buildTime);

/// Inserts/updates a `- Build duration (<target>): <text>` line inside the
/// newest CHANGELOG.md section. Returns null when there is no section to
/// attach to.
String? withBuildDurationNote(
        String changelog, String target, String durationText) =>
    _withNoteLine(changelog, buildDurationLinePrefix(target), durationText);

/// One recorded local build: version, target, how long it took, when it
/// finished and on what OS. Appended to build_history.json after every
/// successful build that reports a duration.
Map<String, dynamic> historyRecord({
  required String version,
  required String target,
  required int durationSeconds,
  required DateTime finishedAt,
}) =>
    {
      'version': version,
      'target': target,
      'durationSeconds': durationSeconds,
      'finishedAt': finishedAt.toIso8601String(),
      'os': Platform.operatingSystem,
    };

/// Appends [record] to [history], capping the result at
/// [maxHistoryEntries] entries (oldest dropped first).
List<dynamic> appendHistoryRecord(
    List<dynamic> history, Map<String, dynamic> record) {
  final updated = [...history, record];
  if (updated.length > maxHistoryEntries) {
    return updated.sublist(updated.length - maxHistoryEntries);
  }
  return updated;
}

/// Reads the JSON array from [file], or an empty list if it's missing,
/// empty or not a JSON array.
List<dynamic> readHistory(File file) {
  if (!file.existsSync()) return <dynamic>[];
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is List) return decoded;
  } catch (_) {
    // Corrupt/foreign content: start a fresh history rather than fail the build.
  }
  return <dynamic>[];
}

/// `version: x.y.z+build` read from pubspec.yaml in the current directory,
/// or null if it can't be found.
String? readPubspecVersion() {
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) return null;
  final match = RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(pubspec.readAsStringSync());
  return match?.group(1);
}

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  int? durationSeconds;
  String? target;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--duration' && i + 1 < args.length) {
      durationSeconds = int.tryParse(args[i + 1]);
      i++;
    } else if (args[i] == '--target' && i + 1 < args.length) {
      target = args[i + 1];
      i++;
    }
  }
  final hasDuration =
      durationSeconds != null && target != null && target.isNotEmpty;

  final changelogFile = File('CHANGELOG.md');
  if (!changelogFile.existsSync()) {
    stderr.writeln('CHANGELOG.md not found.');
    exitCode = 1;
    return;
  }

  final changelog = changelogFile.readAsStringSync();
  final now = DateTime.now();
  final buildTime = formatBuildTime(now);

  var updated = withBuildTimeNote(changelog, buildTime);
  if (updated == null) {
    stdout.writeln('No "## [version] - date" section found; skipping.');
    return;
  }

  String? durationText;
  if (hasDuration) {
    final durationSecondsValue = durationSeconds!;
    final targetValue = target!;
    durationText = formatDuration(durationSecondsValue);
    updated =
        withBuildDurationNote(updated, targetValue, durationText) ?? updated;
  }

  final summary = durationText == null
      ? buildTime
      : '$buildTime ($target: $durationText)';

  if (updated == changelog) {
    stdout.writeln('CHANGELOG.md already notes this build.');
  } else if (dryRun) {
    stdout.writeln('Would record local build in CHANGELOG.md: $summary');
  } else {
    changelogFile.writeAsStringSync(updated);
    stdout.writeln('Recorded local build in CHANGELOG.md: $summary');
  }

  if (!hasDuration) return;
  final durationSecondsValue = durationSeconds!;
  final targetValue = target!;

  final version = readPubspecVersion();
  if (version == null) {
    stdout.writeln('No version in pubspec.yaml; skipping $historyFileName.');
    return;
  }

  final historyFile = File(historyFileName);
  final history = readHistory(historyFile);
  final record = historyRecord(
    version: version,
    target: targetValue,
    durationSeconds: durationSecondsValue,
    finishedAt: now,
  );
  final updatedHistory = appendHistoryRecord(history, record);

  if (dryRun) {
    stdout.writeln('Would append to $historyFileName: $record');
    return;
  }
  historyFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(updatedHistory)}\n');
  stdout.writeln(
      'Recorded build duration in $historyFileName ($targetValue: $durationText)');
}
