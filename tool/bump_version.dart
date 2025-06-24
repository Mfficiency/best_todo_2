import 'dart:io';

void main() {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('pubspec.yaml not found');
    exit(1);
  }

  // Read pubspec.yaml and extract current version
  final pubspecLines = pubspecFile.readAsLinesSync();
  final versionIndex = pubspecLines.indexWhere((l) => l.startsWith('version:'));
  if (versionIndex == -1) {
    stderr.writeln('version not found in pubspec.yaml');
    exit(1);
  }
  final currentVersion = pubspecLines[versionIndex].split(':')[1].trim();
  final parts = currentVersion.split('.');
  if (parts.length != 3) {
    stderr.writeln('version format invalid: $currentVersion');
    exit(1);
  }
  final major = int.parse(parts[0]);
  final minor = int.parse(parts[1]);
  var patch = int.parse(parts[2]);
  patch++;
  final newVersion = '$major.$minor.$patch';

  pubspecLines[versionIndex] = 'version: $newVersion';
  pubspecFile.writeAsStringSync(pubspecLines.join('\n'));

  // Update lib/config.dart version constant
  final configFile = File('lib/config.dart');
  if (configFile.existsSync()) {
    final configContent = configFile.readAsStringSync();
    final updated = configContent.replaceFirst(
        RegExp("version = '[^']+'"), "version = '$newVersion'");
    configFile.writeAsStringSync(updated);
  }

  // Update CHANGELOG
  final changelogFile = File('CHANGELOG.md');
  if (changelogFile.existsSync()) {
    final lines = changelogFile.readAsLinesSync();
    if (lines.length >= 2 && lines[1].contains('Unreleased')) {
      final date = DateTime.now().toIso8601String().split('T').first;
      lines[1] = lines[1].replaceFirst('Unreleased', date);
    }
    lines.insert(1, '## [$newVersion] - Unreleased');
    lines.insert(2, '');
    changelogFile.writeAsStringSync(lines.join('\n'));
  }

  stdout.writeln('Bumped version to $newVersion');
}
