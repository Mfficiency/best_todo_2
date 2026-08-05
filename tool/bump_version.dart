import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/bump_version.dart <version>[+build] [changelog entry]',
    );
    exitCode = 64;
    return;
  }

  final rawVersion = args.first.trim();
  final changelogEntry = args.length > 1 ? args.sublist(1).join(' ').trim() : '';
  final versionOnly = rawVersion.split('+').first;

  final pubspecFile = File('pubspec.yaml');
  final changelogFile = File('CHANGELOG.md');

  if (!pubspecFile.existsSync()) {
    stderr.writeln('pubspec.yaml not found.');
    exitCode = 1;
    return;
  }
  if (!changelogFile.existsSync()) {
    stderr.writeln('CHANGELOG.md not found.');
    exitCode = 1;
    return;
  }

  final pubspec = pubspecFile.readAsStringSync();
  final versionRegex = RegExp(r'^version:\s*(.+)$', multiLine: true);
  final versionMatch = versionRegex.firstMatch(pubspec);

  if (versionMatch == null) {
    stderr.writeln('Could not find a `version:` line in pubspec.yaml.');
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
    stdout.writeln('pubspec.yaml already at version $newVersion.');
  } else {
    final updatedPubspec =
        pubspec.replaceFirst(versionRegex, 'version: $newVersion');
    pubspecFile.writeAsStringSync(updatedPubspec);
    stdout.writeln('Updated pubspec.yaml: $currentVersion -> $newVersion');
  }

  final changelog = changelogFile.readAsStringSync();
  if (changelog.contains('## [$versionOnly] - ')) {
    stdout.writeln('CHANGELOG.md already contains version $versionOnly.');
    return;
  }

  final now = DateTime.now();
  final date =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final entryLine = changelogEntry.isEmpty ? '- TBD' : '- $changelogEntry';
  final newSection = '## [$versionOnly] - $date\n$entryLine\n';

  const header = '# Changelog';
  final lines = changelog.split(RegExp(r'\r?\n'));
  final bodyStart =
      lines.isNotEmpty && lines.first.trim() == header ? 1 : 0;
  final bodyLines = lines.sublist(bodyStart);

  while (bodyLines.isNotEmpty && bodyLines.first.trim().isEmpty) {
    bodyLines.removeAt(0);
  }

  final updated = '$header\n\n$newSection\n${bodyLines.join('\n').trimRight()}';
  changelogFile.writeAsStringSync('$updated\n');
  stdout.writeln('Updated CHANGELOG.md entry for $versionOnly.');
}
