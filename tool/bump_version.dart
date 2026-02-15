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
  if (currentVersion == rawVersion) {
    stdout.writeln('pubspec.yaml already at version $rawVersion.');
  } else {
    final updatedPubspec =
        pubspec.replaceFirst(versionRegex, 'version: $rawVersion');
    pubspecFile.writeAsStringSync(updatedPubspec);
    stdout.writeln('Updated pubspec.yaml: $currentVersion -> $rawVersion');
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
  final newSection = '## [$versionOnly] - $date\n$entryLine\n\n';

  const header = '# Changelog';
  if (changelog.startsWith('$header\n\n')) {
    final updated = changelog.replaceFirst('$header\n\n', '$header\n\n$newSection');
    changelogFile.writeAsStringSync(updated);
    stdout.writeln('Prepended CHANGELOG.md entry for $versionOnly.');
    return;
  }

  final updated = '$header\n\n$newSection${changelog.trimLeft()}';
  changelogFile.writeAsStringSync('$updated\n');
  stdout.writeln('Normalized CHANGELOG.md and added entry for $versionOnly.');
}
