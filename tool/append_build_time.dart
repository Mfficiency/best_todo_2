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
//   dart run tool/append_build_time.dart --app music --duration 102 --target apk
//   dart run tool/append_build_time.dart --duration 102 --target apk \
//       --artifact build/app/outputs/flutter-apk/best_todo_1.2.3+4.apk
//   dart run tool/append_build_time.dart --source ci --duration 330 --target apk ...
//
// `--artifact` (an APK file, or a build output folder such as the Windows
// Release dir) adds its size: a "- APK size: 52.3 MB" line (or "- Build
// size (<target>): ..." for non-APK targets) and `sizeBytes` in the history
// record, so app size is tracked over time alongside build duration.
//
// `--source ci` is for the GitHub Actions build jobs: the notes read
// "- CI build: <UTC time>" and "- Build duration (<target>, CI): ...", so a
// version only ever built by CI still gets its build notes (it used to get
// none, since only tool/build.sh / build.ps1 called this), without being
// mistaken for a local build. The history record gets `"source": "ci"`.
//
// Notes go into the section of the version being built (read from
// pubspec.yaml / MUSIC_VERSION), falling back to the newest section — so a
// CI job that rebased onto a newer version bump can't mislabel it (CI also
// passes `--version <built version>` explicitly for the same reason).
//
// `--app music` notes the build in Best Music's own CHANGELOG_MUSIC.md and
// reads its version from MUSIC_VERSION instead of pubspec.yaml — the two
// apps version and changelog independently since the split
// (CLAUDE.md/SPEC.md §10.6i). Default (no `--app`) stays BestToDo.

import 'dart:convert';
import 'dart:io';

/// Line prefix used to find/replace the existing build-time note, so
/// building the same version repeatedly updates one line instead of piling
/// up a new one per build.
const String buildTimeLinePrefix = '- Local build: ';

/// Build-time note prefix for a CI build (`--source ci`).
const String ciBuildTimeLinePrefix = '- CI build: ';

/// Size note prefix: `- APK size: ` for APK targets, else per target.
String buildSizeLinePrefix(String target) => target.contains('apk')
    ? '- APK size: '
    : '- Build size ($target): ';

/// `52.3 MB` / `812 KB`.
String formatSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).round()} KB';
}

/// Size in bytes of [path]: a file's length, or the total of every file
/// under a directory. Null when it doesn't exist.
int? artifactSize(String path) {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.file) return File(path).lengthSync();
  if (type == FileSystemEntityType.directory) {
    var total = 0;
    for (final entity in Directory(path).listSync(recursive: true)) {
      if (entity is File) total += entity.lengthSync();
    }
    return total;
  }
  return null;
}

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
String buildDurationLinePrefix(String target, {bool ci = false}) =>
    ci ? '- Build duration ($target, CI): ' : '- Build duration ($target): ';

/// Inserts/updates a note line (identified by [prefix]) inside the
/// `## [<version>]` section of [changelog] ([version] without its `+build`
/// part), or the first (newest) section when [version] is null or has no
/// section. Returns the updated text, or null when there is no section to
/// attach it to.
String? _withNoteLine(String changelog, String prefix, String value,
    {String? version}) {
  final headerRegex = RegExp(r'^##\s*\[[^\]]+\]\s*-\s*.+$', multiLine: true);
  final headers = headerRegex.allMatches(changelog).toList();
  if (headers.isEmpty) return null;
  final wanted = version?.split('+').first;
  final firstHeader = headers.firstWhere(
    (h) => wanted != null && h.group(0)!.contains('[$wanted]'),
    orElse: () => headers.first,
  );

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
String? withBuildTimeNote(String changelog, String buildTime,
        {String? version, bool ci = false}) =>
    _withNoteLine(changelog, ci ? ciBuildTimeLinePrefix : buildTimeLinePrefix,
        buildTime,
        version: version);

/// Inserts/updates a `- Build duration (<target>): <text>` line inside the
/// newest CHANGELOG.md section. Returns null when there is no section to
/// attach to.
String? withBuildDurationNote(
        String changelog, String target, String durationText,
        {String? version, bool ci = false}) =>
    _withNoteLine(
        changelog, buildDurationLinePrefix(target, ci: ci), durationText,
        version: version);

/// Inserts/updates the size note (see [buildSizeLinePrefix]).
String? withBuildSizeNote(String changelog, String target, int bytes,
        {String? version}) =>
    _withNoteLine(changelog, buildSizeLinePrefix(target), formatSize(bytes),
        version: version);

/// One recorded local build: version, target, how long it took, when it
/// finished and on what OS. Appended to build_history.json after every
/// successful build that reports a duration.
Map<String, dynamic> historyRecord({
  required String version,
  required String target,
  required int durationSeconds,
  required DateTime finishedAt,
  String app = 'todo',
  int? sizeBytes,
  String source = 'local',
}) =>
    {
      'version': version,
      'app': app,
      'target': target,
      'durationSeconds': durationSeconds,
      if (sizeBytes != null) 'sizeBytes': sizeBytes,
      'source': source,
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

/// `version: x.y.z+build` read from [path] (pubspec.yaml or MUSIC_VERSION,
/// both share that line shape), or null if it can't be found.
String? readVersionFrom(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final match = RegExp(r'^version:\s*(\S+)', multiLine: true)
      .firstMatch(file.readAsStringSync());
  return match?.group(1);
}

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  int? durationSeconds;
  String? target;
  String? app;
  String? artifact;
  String? versionArg;
  var source = 'local';
  for (var i = 0; i < args.length; i++) {
    final value = i + 1 < args.length ? args[i + 1] : null;
    switch (args[i]) {
      case '--duration' when value != null:
        durationSeconds = int.tryParse(value);
        i++;
      case '--target' when value != null:
        target = value;
        i++;
      case '--app' when value != null:
        app = value;
        i++;
      case '--artifact' when value != null:
        artifact = value;
        i++;
      case '--source' when value != null:
        source = value;
        i++;
      case '--version' when value != null:
        versionArg = value;
        i++;
    }
  }
  final hasDuration =
      durationSeconds != null && target != null && target.isNotEmpty;
  final isMusic = app == 'music';
  final ci = source == 'ci';

  final changelogPath = isMusic ? 'CHANGELOG_MUSIC.md' : 'CHANGELOG.md';
  final changelogFile = File(changelogPath);
  if (!changelogFile.existsSync()) {
    stderr.writeln('$changelogPath not found.');
    exitCode = 1;
    return;
  }

  final versionPath = isMusic ? 'MUSIC_VERSION' : 'pubspec.yaml';
  // --version: the version that was actually built, for a CI job that has
  // since rebased onto a newer version bump.
  final version = versionArg ?? readVersionFrom(versionPath);

  final changelog = changelogFile.readAsStringSync();
  final now = DateTime.now();
  // CI runners are on UTC; say so rather than pass it off as local time.
  final buildTime =
      ci ? '${formatBuildTime(now.toUtc())} UTC' : formatBuildTime(now);

  var updated =
      withBuildTimeNote(changelog, buildTime, version: version, ci: ci);
  if (updated == null) {
    stdout.writeln('No "## [version] - date" section found; skipping.');
    return;
  }

  String? durationText;
  if (hasDuration) {
    durationText = formatDuration(durationSeconds);
    updated = withBuildDurationNote(updated, target, durationText,
            version: version, ci: ci) ??
        updated;
  }

  int? sizeBytes;
  if (artifact != null) {
    sizeBytes = artifactSize(artifact);
    if (sizeBytes == null) {
      stdout.writeln('Artifact $artifact not found; size not recorded.');
    } else {
      updated = withBuildSizeNote(updated, target ?? 'apk', sizeBytes,
              version: version) ??
          updated;
    }
  }

  final summary = [
    buildTime,
    if (durationText != null) '$target: $durationText',
    if (sizeBytes != null) formatSize(sizeBytes),
  ].join(', ');
  final kind = ci ? 'CI' : 'local';

  if (updated == changelog) {
    stdout.writeln('$changelogPath already notes this build.');
  } else if (dryRun) {
    stdout.writeln('Would record $kind build in $changelogPath: $summary');
  } else {
    changelogFile.writeAsStringSync(updated);
    stdout.writeln('Recorded $kind build in $changelogPath: $summary');
  }

  if (!hasDuration) return;
  if (version == null) {
    stdout.writeln('No version in $versionPath; skipping $historyFileName.');
    return;
  }

  final historyFile = File(historyFileName);
  final history = readHistory(historyFile);
  final record = historyRecord(
    version: version,
    app: isMusic ? 'music' : 'todo',
    target: target,
    durationSeconds: durationSeconds,
    finishedAt: now,
    sizeBytes: sizeBytes,
    source: source,
  );
  final updatedHistory = appendHistoryRecord(history, record);

  if (dryRun) {
    stdout.writeln('Would append to $historyFileName: $record');
    return;
  }
  historyFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(updatedHistory)}\n');
  stdout.writeln('Recorded build in $historyFileName ($summary)');
}
