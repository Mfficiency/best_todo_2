import 'dart:io';

/// Bumps pubspec.yaml's `version:` and prepends a CHANGELOG.md section.
void main(List<String> args) {
  final positional = args.toList();

  if (positional.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/bump_version.dart <version>[+build] [changelog entry]',
    );
    exitCode = 64;
    return;
  }

  final rawVersion = positional.first.trim();
  final changelogEntry =
      positional.length > 1 ? positional.sublist(1).join(' ').trim() : '';
  final versionOnly = rawVersion.split('+').first;

  final versionFile = File('pubspec.yaml');
  final changelogFile = File('CHANGELOG.md');

  if (!versionFile.existsSync()) {
    stderr.writeln('${versionFile.path} not found.');
    exitCode = 1;
    return;
  }
  if (!changelogFile.existsSync()) {
    stderr.writeln('${changelogFile.path} not found.');
    exitCode = 1;
    return;
  }

  final versionFileContents = versionFile.readAsStringSync();
  final versionRegex = RegExp(r'^version:\s*(.+)$', multiLine: true);
  final versionMatch = versionRegex.firstMatch(versionFileContents);

  if (versionMatch == null) {
    stderr.writeln('Could not find a `version:` line in ${versionFile.path}.');
    exitCode = 1;
    return;
  }

  final currentVersion = versionMatch.group(1)!.trim();

  // The `+build` suffix is the Android versionCode. Dropping it makes Flutter
  // fall back to versionCode 1, which names the APK `..._0.1.x+1.apk` and makes
  // Android reject the install as a downgrade. So when the caller passes a bare
  // `x.y.z`, carry the current build number forward and increment it.
  final String newVersion;
  if (rawVersion.contains('+')) {
    newVersion = rawVersion;
  } else {
    final currentParts = currentVersion.split('+');
    final currentBuild =
        currentParts.length > 1 ? int.tryParse(currentParts[1].trim()) ?? 0 : 0;
    newVersion = '$versionOnly+${currentBuild + 1}';
  }

  if (currentVersion == newVersion) {
    stdout.writeln('${versionFile.path} already at version $newVersion.');
  } else {
    final updatedVersionFile =
        versionFileContents.replaceFirst(versionRegex, 'version: $newVersion');
    versionFile.writeAsStringSync(updatedVersionFile);
    stdout.writeln('Updated ${versionFile.path}: $currentVersion -> $newVersion');
  }

  final changelog = changelogFile.readAsStringSync();
  if (changelog.contains('## [$versionOnly] - ')) {
    stdout.writeln('${changelogFile.path} already contains version $versionOnly.');
    return;
  }

  final now = DateTime.now();
  final date =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final entryLine = changelogEntry.isEmpty ? '- TBD' : '- $changelogEntry';
  final newSection = '## [$versionOnly] - $date\n$entryLine\n';

  // Insert the new section right before the first existing `## [...]`
  // release heading, so everything above it — the `# Changelog` title and
  // any preamble paragraph — is kept untouched instead of being collapsed
  // down to a single header line.
  final firstReleaseHeading =
      RegExp(r'^##\s*\[', multiLine: true).firstMatch(changelog);
  final String updated;
  if (firstReleaseHeading == null) {
    // No release section yet (a brand new changelog): keep whatever preamble
    // is there and append the first section after it.
    updated = '${changelog.trimRight()}\n\n$newSection';
  } else {
    final before = changelog.substring(0, firstReleaseHeading.start).trimRight();
    final after = changelog.substring(firstReleaseHeading.start);
    updated = '$before\n\n$newSection\n$after'.trimRight();
  }
  changelogFile.writeAsStringSync('$updated\n');
  stdout.writeln('Updated ${changelogFile.path} entry for $versionOnly.');
}
