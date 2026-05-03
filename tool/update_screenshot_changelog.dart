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

  final entry = StringBuffer()
    ..writeln('## $now | branch: $safeBranch | source: $shortSha')
    ..writeln()
    ..writeln('- Folder: `$screenshotFolder`')
    ..writeln()
    ..writeln('### Home')
    ..writeln('![$now - $safeBranch - home]($screenshotFolder/home_page.png)')
    ..writeln()
    ..writeln('### Menu Open')
    ..writeln('![$now - $safeBranch - menu]($screenshotFolder/menu_open.png)')
    ..writeln()
    ..writeln('### Settings')
    ..writeln(
        '![$now - $safeBranch - settings]($screenshotFolder/settings_page.png)')
    ..writeln()
    ..writeln('### Your Stats')
    ..writeln(
        '![$now - $safeBranch - stats]($screenshotFolder/your_stats_page.png)')
    ..writeln()
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
