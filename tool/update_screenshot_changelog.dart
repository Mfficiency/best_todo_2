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
      : '';

  // Drop any previous table of contents so a fresh one (pointing at this
  // run's screenshots, which is now the topmost/newest entry) replaces it —
  // the anchors GitHub generates for duplicate headers only resolve to the
  // first occurrence in the document, so the ToC must always sit above the
  // latest entry and nowhere else.
  final strippedExisting = existingContent.replaceFirst(_tocPattern, '');

  final newContent = '${buildToc(names)}${entry.toString()}$strippedExisting';
  changelogFile.writeAsStringSync(newContent);
}

final _tocPattern = RegExp(
  r'<!-- screenshot-toc:start -->[\s\S]*?<!-- screenshot-toc:end -->\n*(?:---\n)?\n*',
);

String titleOf(String name) => name
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Mirrors GitHub's markdown heading-anchor algorithm closely enough for our
/// titles (letters, digits and spaces only): lowercase, drop anything that
/// isn't a letter/digit/space/hyphen, then turn spaces into hyphens.
String slugOf(String title) {
  final lower = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 -]'), '');
  return lower.trim().replaceAll(RegExp(r'\s+'), '-');
}

String buildToc(List<String> names) {
  final buffer = StringBuffer()
    ..writeln('<!-- screenshot-toc:start -->')
    ..writeln('# Screenshot Changelog')
    ..writeln()
    ..writeln('## Latest Screenshots')
    ..writeln()
    ..writeln('Jump to a screenshot from the most recent run:')
    ..writeln();
  for (final name in names) {
    final title = titleOf(name);
    buffer.writeln('- [$title](#${slugOf(title)})');
  }
  buffer
    ..writeln('<!-- screenshot-toc:end -->')
    ..writeln()
    ..writeln('---')
    ..writeln();
  return buffer.toString();
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
