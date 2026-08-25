// Records when a local build finished by writing/updating a "- Local build:"
// line inside the newest `## [version] - date` section of CHANGELOG.md.
//
// Run this *after* `flutter build`, not before: CHANGELOG.md is bundled as an
// app asset at build time, so a build can never show its own timestamp — only
// the one written by the previous build. That's expected (see CLAUDE.md).
//
// Usage:
//   dart run tool/append_build_time.dart            (called by tool/build.sh)
//   dart run tool/append_build_time.dart --dry-run

import 'dart:io';

/// Line prefix used to find/replace the existing build-time note, so
/// building the same version repeatedly updates one line instead of piling
/// up a new one per build.
const String buildTimeLinePrefix = '- Local build: ';

/// `HH:MM` local time appended after the release date, e.g. `2026-08-21 14:47`.
String formatBuildTime(DateTime now) {
  final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  final time =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  return '$date $time';
}

/// Inserts/updates the `- Local build: <time>` line inside the first (i.e.
/// newest) `## [...]` section of [changelog]. Returns the updated text, or
/// null when there is no section to attach it to.
String? withBuildTimeNote(String changelog, String buildTime) {
  final headerRegex = RegExp(r'^##\s*\[[^\]]+\]\s*-\s*.+$', multiLine: true);
  final firstHeader = headerRegex.firstMatch(changelog);
  if (firstHeader == null) return null;

  final sectionStart = firstHeader.end;
  final nextHeader = headerRegex.firstMatch(changelog.substring(sectionStart));
  final sectionEnd = nextHeader == null
      ? changelog.length
      : sectionStart + nextHeader.start;

  final section = changelog.substring(sectionStart, sectionEnd);
  final noteLine = '$buildTimeLinePrefix$buildTime';

  final lines = section.split('\n');
  final existingIndex =
      lines.indexWhere((l) => l.trim().startsWith(buildTimeLinePrefix));
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

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');

  final changelogFile = File('CHANGELOG.md');
  if (!changelogFile.existsSync()) {
    stderr.writeln('CHANGELOG.md not found.');
    exitCode = 1;
    return;
  }

  final changelog = changelogFile.readAsStringSync();
  final buildTime = formatBuildTime(DateTime.now());
  final updated = withBuildTimeNote(changelog, buildTime);

  if (updated == null) {
    stdout.writeln('No "## [version] - date" section found; skipping.');
    return;
  }
  if (updated == changelog) {
    stdout.writeln('CHANGELOG.md already notes this build time.');
    return;
  }

  if (dryRun) {
    stdout.writeln('Would record local build time: $buildTime');
    return;
  }

  changelogFile.writeAsStringSync(updated);
  stdout.writeln('Recorded local build time in CHANGELOG.md: $buildTime');
}
