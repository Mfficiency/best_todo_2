import 'dart:io';

/// Files a fresh screenshot run and updates the newest-first gallery.
///
/// What it does:
///  1. Reads the app version from pubspec.yaml (never hard-coded).
///  2. Copies every PNG from the capture folder into
///     `docs/screenshots/v<version>/<date>_<time>/` — a new folder per run, so
///     previous runs are always preserved.
///  3. Prepends a section to `docs/screenshots/SCREENSHOTS.md` listing each
///     screen name, the version, the date/time, and a relative image link,
///     newest run first.
///
/// Usage (from the package root, after the screenshot test has run):
///   dart run tool/screenshot_report.dart
///   dart run tool/screenshot_report.dart --source build/e2e_screenshots \
///     --dest docs/screenshots --branch dev --commit <sha>
void main(List<String> args) {
  final opts = _parseArgs(args);
  final source = opts['source'] ?? 'build/e2e_screenshots';
  final destRoot = opts['dest'] ?? 'docs/screenshots';
  final branch = opts['branch'] ?? '';
  final commit = opts['commit'] ?? '';

  final sourceDir = Directory(source);
  if (!sourceDir.existsSync()) {
    stderr.writeln('No screenshot folder at "$source". '
        'Run the screenshot test first.');
    exitCode = 1;
    return;
  }

  final pngs = sourceDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.png'))
      .toList()
    ..sort((a, b) => _name(a).compareTo(_name(b)));

  if (pngs.isEmpty) {
    stderr.writeln('No PNGs found in "$source".');
    exitCode = 1;
    return;
  }

  final version = _readVersion();
  final now = DateTime.now();
  final date = _date(now);
  final time = _time(now); // filesystem-safe: HHmmss
  final displayTime = _displayTime(now); // human-readable: HH:MM:SS
  final runFolderName = '${date}_$time';

  // docs/screenshots/v<version>/<date>_<time>/
  final runDir = Directory('$destRoot/v$version/$runFolderName')
    ..createSync(recursive: true);

  for (final png in pngs) {
    final target = File('${runDir.path}/${_name(png)}.png');
    target.writeAsBytesSync(png.readAsBytesSync());
  }
  stdout.writeln('Copied ${pngs.length} screenshot(s) to ${runDir.path}');

  // Build the gallery section (relative links from the gallery file location).
  final relBase = 'v$version/$runFolderName';
  final meta = [
    'version: v$version',
    'date: $date $displayTime',
    if (branch.isNotEmpty) 'branch: $branch',
    if (commit.isNotEmpty) 'commit: ${_short(commit)}',
  ].join(' · ');

  final section = StringBuffer()
    ..writeln('## $date $displayTime — v$version')
    ..writeln()
    ..writeln('_${meta}_')
    ..writeln();
  for (final png in pngs) {
    final name = _name(png);
    section
      ..writeln('### ${_title(name)}')
      ..writeln('![v$version $name]($relBase/$name.png)')
      ..writeln();
  }
  section
    ..writeln('---')
    ..writeln();

  final galleryFile = File('$destRoot/SCREENSHOTS.md');
  const header = '# Screenshots\n\nNewest run first. Each run is preserved in '
      'its own `v<version>/<date>_<time>/` folder.\n\n';
  final existing = galleryFile.existsSync()
      ? galleryFile.readAsStringSync()
      : header;
  // Keep the header at the very top; insert the new section right after it.
  final body = existing.startsWith('# Screenshots')
      ? existing.substring(existing.indexOf('\n\n') + 2)
      : existing;
  galleryFile.writeAsStringSync('$header$section$body');
  stdout.writeln('Updated ${galleryFile.path} (newest run on top).');
}

String _name(File f) =>
    f.uri.pathSegments.last.replaceAll(RegExp(r'\.png$', caseSensitive: false), '');

String _title(String name) => name
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String _short(String sha) =>
    sha.length <= 7 ? sha : sha.substring(0, 7);

String _date(DateTime n) => '${n.year}-${_two(n.month)}-${_two(n.day)}';
String _time(DateTime n) => '${_two(n.hour)}${_two(n.minute)}${_two(n.second)}';
String _displayTime(DateTime n) =>
    '${_two(n.hour)}:${_two(n.minute)}:${_two(n.second)}';
String _two(int v) => v.toString().padLeft(2, '0');

/// Reads `version:` from pubspec.yaml so the report always matches the build.
String _readVersion() {
  try {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(pubspec);
    if (match != null) return match.group(1)!.trim();
  } catch (_) {}
  return 'unknown';
}

Map<String, String> _parseArgs(List<String> args) {
  final map = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    if (i + 1 >= args.length || args[i + 1].startsWith('--')) continue;
    map[arg.substring(2)] = args[i + 1];
    i++;
  }
  return map;
}
