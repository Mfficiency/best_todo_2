// Copies the freshly built release APK into `github_releases/` and deletes the
// builds beyond the newest few, so the repo always carries the last two APKs.
//
// That folder is what the app's About page "Check for updates" button reads
// (UpdateService.folderContentsUrl): the newest APK is offered as the update,
// the one kept next to it as "go one version back".
//
// Usage:
//   flutter build apk --release            (or: sh tool/build.sh apk --release)
//   dart run tool/stage_local_release.dart [--apk <path>] [--dir <dir>]
//                                          [--keep <n>] [--dry-run]
//
// Commit the folder afterwards — the app downloads the APKs over HTTPS from
// the branch (`UpdateService.releasesRef`), so a build only becomes installable
// once it is pushed.

import 'dart:io';

/// How many APKs the folder keeps: the newest plus one version back.
const int defaultKeep = 2;

const String defaultDir = 'github_releases';

/// `version: x.y.z+build` from a pubspec.yaml body, or null.
String? readPubspecVersion(String pubspec) {
  final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
  return m?.group(1);
}

/// Where a freshly built release APK may sit, most specific first
/// (`tool/build.sh` renames it, a plain `flutter build apk` does not).
List<String> apkCandidatePaths(String version) => [
      'build/app/outputs/flutter-apk/best_todo_$version.apk',
      'build/app/outputs/flutter-apk/besttodo-$version.apk',
      'build/app/outputs/flutter-apk/app-release.apk',
    ];

/// Name the APK gets in the folder, matching what is already committed there.
String stagedNameFor(String version) => 'best_todo_$version.apk';

/// Numeric components of a version-carrying file name, in order:
/// `best_todo_0.1.143+115.apk` → [0, 1, 143, 115]. Names without digits sort
/// as all-zero (oldest).
List<int> versionNumbers(String name) {
  final base = name.replaceAll(RegExp(r'\.apk$', caseSensitive: false), '');
  return RegExp(r'\d+')
      .allMatches(base)
      .map((m) => int.parse(m.group(0)!))
      .toList();
}

/// Compares two APK file names by version, component-by-component; missing
/// components count as 0. Returns <0, 0 or >0 like [Comparable.compareTo].
int compareVersionedNames(String a, String b) {
  final pa = versionNumbers(a);
  final pb = versionNumbers(b);
  final length = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < length; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// The APK names to delete so only the newest [keep] survive, oldest first.
/// Non-APK entries (the folder's README) are never touched.
List<String> namesToPrune(Iterable<String> names, {int keep = defaultKeep}) {
  final apks = names
      .where((n) => n.toLowerCase().endsWith('.apk'))
      .toList()
    ..sort(compareVersionedNames);
  if (apks.length <= keep) return const [];
  return apks.sublist(0, apks.length - keep);
}

Future<void> main(List<String> args) async {
  String? apkArg;
  var dir = defaultDir;
  var keep = defaultKeep;
  var dryRun = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--apk':
        if (i + 1 >= args.length) return _usage('--apk needs a path');
        apkArg = args[++i];
      case '--dir':
        if (i + 1 >= args.length) return _usage('--dir needs a path');
        dir = args[++i];
      case '--keep':
        if (i + 1 >= args.length) return _usage('--keep needs a number');
        final parsed = int.tryParse(args[++i]);
        if (parsed == null || parsed < 1) return _usage('--keep needs a number ≥ 1');
        keep = parsed;
      case '--dry-run':
        dryRun = true;
      default:
        return _usage('Unknown argument: ${args[i]}');
    }
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found — run from the repository root.');
    exitCode = 1;
    return;
  }
  final version = readPubspecVersion(pubspec.readAsStringSync());
  if (version == null || version.isEmpty) {
    stderr.writeln('Could not read a version from pubspec.yaml.');
    exitCode = 1;
    return;
  }

  final apkPath = apkArg ??
      apkCandidatePaths(version)
          .firstWhere((p) => File(p).existsSync(), orElse: () => '');
  if (apkPath.isEmpty || !File(apkPath).existsSync()) {
    stderr.writeln('No release APK found. Looked for:');
    for (final p in apkCandidatePaths(version)) {
      stderr.writeln('  $p');
    }
    stderr.writeln('Build one first: flutter build apk --release');
    exitCode = 1;
    return;
  }

  final target = Directory(dir);
  final staged = '$dir/${stagedNameFor(version)}';
  stdout.writeln('Staging $apkPath -> $staged');
  if (!dryRun) {
    target.createSync(recursive: true);
    File(apkPath).copySync(staged);
  }

  final present = <String>{
    if (target.existsSync())
      for (final entry in target.listSync())
        if (entry is File) entry.uri.pathSegments.last,
    // In a dry run the copy did not happen; prune as if it had.
    stagedNameFor(version),
  };
  for (final name in namesToPrune(present, keep: keep)) {
    stdout.writeln('Pruning older build $dir/$name');
    if (!dryRun) File('$dir/$name').deleteSync();
  }
  if (dryRun) stdout.writeln('Dry run — nothing written.');
}

void _usage(String message) {
  stderr.writeln(message);
  stderr.writeln('Usage: dart run tool/stage_local_release.dart '
      '[--apk <path>] [--dir <dir>] [--keep <n>] [--dry-run]');
  exitCode = 64;
}
