import 'dart:io';

void main(List<String> args) {
  final parsed = _parseArgs(args);
  final screenshotFolder = parsed['screenshot-folder'];
  final branch = parsed['branch'];
  final sourceSha = parsed['source-sha'];

  if (screenshotFolder == null || screenshotFolder.isEmpty) {
    stderr.writeln('Missing required argument: --screenshot-folder');
    exit(1);
  }

  final now = DateTime.now().toUtc().toIso8601String();
  final shortSha = (sourceSha == null || sourceSha.isEmpty)
      ? 'unknown'
      : sourceSha.substring(0, sourceSha.length < 7 ? sourceSha.length : 7);
  final safeBranch = (branch == null || branch.isEmpty) ? 'unknown' : branch;

  // One section per PNG in the folder so newly captured pages are picked up
  // without touching this tool. Falls back to the historical four names when
  // the folder cannot be listed (e.g. dry runs outside the repo).
  var names = <String>[
    'home_page',
    'menu_open',
    'settings_page',
    'your_stats_page',
  ];
  final dir = Directory(screenshotFolder);
  if (dir.existsSync()) {
    final found = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.png'))
        .map((f) => f.uri.pathSegments.last.replaceAll('.png', ''))
        .toList()
      ..sort();
    if (found.isNotEmpty) names = found;
  }

  String titleOf(String name) => name
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  final entry = StringBuffer()
    ..writeln('## $now | branch: $safeBranch | source: $shortSha')
    ..writeln()
    ..writeln('- Folder: `$screenshotFolder`')
    ..writeln();
  for (final name in names) {
    entry
      ..writeln('### ${titleOf(name)}')
      ..writeln('![$now - $safeBranch - $name]($screenshotFolder/$name.png)')
      ..writeln();
  }
  entry
    ..writeln('---')
    ..writeln();

  final changelogFile = File('SCREENSHOT_CHANGELOG.md');
  final existingContent = changelogFile.existsSync()
      ? changelogFile.readAsStringSync()
      : '# Screenshot Changelog\n\n';

  final newContent = '${entry.toString()}$existingContent';
  changelogFile.writeAsStringSync(newContent);
}

Map<String, String> _parseArgs(List<String> args) {
  final map = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) {
      continue;
    }
    final key = arg.substring(2);
    if (i + 1 >= args.length) {
      continue;
    }
    final value = args[i + 1];
    if (value.startsWith('--')) {
      continue;
    }
    map[key] = value;
    i++;
  }
  return map;
}
