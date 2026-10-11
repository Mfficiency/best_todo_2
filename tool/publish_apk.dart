// Uploads a release APK to a GitHub release of Mfficiency/best_todo_2, which
// is where both apps' in-app updaters look for new versions
// (lib/services/update_service.dart reads the releases list, filtered by app
// and channel).
//
// Normally run by `tool\build.ps1 release` (the laptop builder, one call per
// app); can also be run by hand after a release build.
//
// Usage:
//   dart run tool/publish_apk.dart [--app todo|music] [--channel main|staging|dev]
//       [--build-number N] [--apk <path>] [--duration <secs>] [--dry-run]
//   dart run tool/publish_apk.dart --app music --channel dev --build-number N --exists
//       (exit 0 when that release already exists, 2 when it doesn't)
//
// Defaults: --app todo, --channel $BUILD_CHANNEL (else main), --build-number
// $BUILD_NUMBER (else the build part of pubspec.yaml / MUSIC_VERSION).
//
// Auth: a GitHub token with repo write access, taken from the GITHUB_TOKEN or
// GH_TOKEN environment variable, or from `gh auth token` when the GitHub CLI
// is installed and logged in.
//
// Conventions (the in-app updater relies on the tags):
//   tag      BestToDo   v<x.y.z>-<build>        (git tags can't carry '+')
//            Best Music music-v<x.y.z>-<build>
//            + `-dev` / `-staging` for those channels (prerelease)
//   name     BestToDo 0.2.100+12199 (dev)      (no channel for main)
//   asset    BestToDo-0.2.100+12199-dev.apk    / BestMusic-0.3.19+12199.apk
//   body     the app's newest CHANGELOG section (user-facing bullets only)
//            + a build footer (channel, commit, branch, time, duration, size)
//
// After a successful upload it prints one line for the laptop builder:
//   LAPTOP_BUILD_RESULT app=<App Name> version=<x.y.z+build> channel=<c> tag=<tag>
//
// Re-running for the same tag reuses the existing release and replaces its
// APK asset (tool\build.ps1 release skips existing tags before building).

import 'dart:convert';
import 'dart:io';

const String owner = 'Mfficiency';
const String repo = 'best_todo_2';
const String apiBase = 'https://api.github.com';
const String uploadsBase = 'https://uploads.github.com';

const List<String> channels = ['main', 'staging', 'dev'];

/// One of the two apps published from this repo.
class AppSpec {
  const AppSpec({
    required this.id,
    required this.displayName,
    required this.tagPrefix,
    required this.assetPrefix,
    required this.versionFile,
    required this.changelogFile,
  });

  /// `todo` / `music` — the Gradle flavor.
  final String id;
  final String displayName;
  final String tagPrefix;
  final String assetPrefix;
  final String versionFile;
  final String changelogFile;
}

const AppSpec todoApp = AppSpec(
  id: 'todo',
  displayName: 'BestToDo',
  tagPrefix: 'v',
  assetPrefix: 'BestToDo',
  versionFile: 'pubspec.yaml',
  changelogFile: 'CHANGELOG.md',
);

const AppSpec musicApp = AppSpec(
  id: 'music',
  displayName: 'Best Music',
  tagPrefix: 'music-v',
  assetPrefix: 'BestMusic',
  versionFile: 'MUSIC_VERSION',
  changelogFile: 'CHANGELOG_MUSIC.md',
);

AppSpec? appFor(String id) => switch (id) {
      'todo' => todoApp,
      'music' => musicApp,
      _ => null,
    };

/// `version: x.y.z+build` from a pubspec.yaml / MUSIC_VERSION body, or null.
String? readPubspecVersion(String pubspec) {
  final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
  return m?.group(1);
}

String _channelSuffix(String channel) => channel == 'main' ? '' : '-$channel';

/// Git-safe release tag: `0.1.132+104` → `v0.1.132-104` (BestToDo, main),
/// `music-v0.3.19-12199-dev` (Best Music, dev).
String releaseTagFor(String version,
        {AppSpec app = todoApp, String channel = 'main'}) =>
    '${app.tagPrefix}${version.replaceAll('+', '-')}${_channelSuffix(channel)}';

String releaseNameFor(String version,
        {AppSpec app = todoApp, String channel = 'main'}) =>
    '${app.displayName} $version${channel == 'main' ? '' : ' ($channel)'}';

String assetNameFor(String version,
        {AppSpec app = todoApp, String channel = 'main'}) =>
    '${app.assetPrefix}-$version${_channelSuffix(channel)}.apk';

/// Build-meta lines tool/append_build_time.dart writes into changelog
/// sections; they aren't user-facing, so release notes leave them out.
bool isBuildNoteLine(String line) {
  final l = line.trimLeft();
  return l.startsWith('- Local build:') ||
      l.startsWith('- CI build:') ||
      l.startsWith('- Build duration') ||
      l.startsWith('- Build size') ||
      l.startsWith('- APK size:');
}

/// The newest CHANGELOG section: from the first `## [` heading up to (not
/// including) the next one, without build-meta lines. Empty string when no
/// heading is found.
String firstChangelogSection(String changelog) {
  final lines = changelog.split('\n').map((l) => l.trimRight()).toList();
  final start = lines.indexWhere((l) => l.startsWith('## ['));
  if (start == -1) return '';
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (lines[i].startsWith('## [')) {
      end = i;
      break;
    }
  }
  return lines
      .sublist(start, end)
      .where((l) => !isBuildNoteLine(l))
      .join('\n')
      .trim();
}

/// `52.3 MB` / `812 KB`.
String formatSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).round()} KB';
}

/// `9m 05s` / `42s`.
String formatDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${s}s';
}

/// The build footer appended to the release notes.
String buildFooter({
  required String channel,
  required String commit,
  required String branch,
  required DateTime builtAt,
  int? durationSeconds,
  int? apkBytes,
}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final offset = builtAt.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final tz =
      'UTC$sign${two(offset.inHours.abs())}:${two(offset.inMinutes.abs() % 60)}';
  final when = '${builtAt.year}-${two(builtAt.month)}-${two(builtAt.day)} '
      '${two(builtAt.hour)}:${two(builtAt.minute)} $tz';
  return [
    '---',
    '- Channel: $channel',
    '- Commit: `$commit` (branch `$branch`)',
    '- Built: $when',
    if (durationSeconds != null)
      '- Build duration: ${formatDuration(durationSeconds)}',
    if (apkBytes != null) '- APK size: ${formatSize(apkBytes)}',
    '- Built on the laptop',
  ].join('\n');
}

/// Where a freshly built release APK may sit, most specific first.
List<String> apkCandidatePaths(String version, {AppSpec app = todoApp}) => [
      'build/app/outputs/flutter-apk/best_${app.id}_$version.apk',
      'build/app/outputs/flutter-apk/app-${app.id}-release.apk',
      if (app.id == 'todo') 'build/app/outputs/flutter-apk/app-release.apk',
    ];

Future<void> main(List<String> args) async {
  String? apkArg;
  var appId = 'todo';
  String? channelArg;
  String? buildNumberArg;
  int? durationSeconds;
  var dryRun = false;
  var existsOnly = false;
  const usage = 'Usage: dart run tool/publish_apk.dart [--app todo|music] '
      '[--channel main|staging|dev] [--build-number N] [--apk <path>] '
      '[--duration <secs>] [--exists] [--dry-run]';
  const valued = {'--apk', '--app', '--channel', '--build-number', '--duration'};

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    String? v;
    if (valued.contains(arg)) {
      if (i + 1 >= args.length) {
        stderr.writeln('$arg needs a value');
        exitCode = 64;
        return;
      }
      v = args[++i];
    }
    switch (arg) {
      case '--apk':
        apkArg = v;
      case '--app':
        appId = v!;
      case '--channel':
        channelArg = v;
      case '--build-number':
        buildNumberArg = v;
      case '--duration':
        durationSeconds = int.tryParse(v!);
      case '--exists':
        existsOnly = true;
      case '--dry-run':
        dryRun = true;
      default:
        stderr.writeln('Unknown argument: $arg');
        stderr.writeln(usage);
        exitCode = 64;
        return;
    }
  }

  final app = appFor(appId);
  if (app == null) {
    stderr.writeln('--app must be todo or music (got "$appId")');
    exitCode = 64;
    return;
  }
  final env = Platform.environment;
  var channel = (channelArg ?? env['BUILD_CHANNEL'] ?? '').trim().toLowerCase();
  if (channel.isEmpty) channel = 'main';
  if (!channels.contains(channel)) {
    stderr.writeln(
        'Channel must be one of ${channels.join(', ')} (got "$channel")');
    exitCode = 64;
    return;
  }

  final versionFile = File(app.versionFile);
  if (!versionFile.existsSync()) {
    stderr.writeln(
        '${app.versionFile} not found — run from the repository root.');
    exitCode = 1;
    return;
  }
  final fileVersion = readPubspecVersion(versionFile.readAsStringSync());
  if (fileVersion == null || !fileVersion.contains('+')) {
    stderr.writeln(
        'Could not read an x.y.z+build version from ${app.versionFile}.');
    exitCode = 1;
    return;
  }
  final buildNumber = (buildNumberArg ?? env['BUILD_NUMBER'] ?? '').trim();
  if (buildNumber.isNotEmpty && int.tryParse(buildNumber) == null) {
    stderr.writeln('Build number must be an integer (got "$buildNumber")');
    exitCode = 64;
    return;
  }
  final version = buildNumber.isEmpty
      ? fileVersion
      : '${fileVersion.split('+').first}+$buildNumber';
  final tag = releaseTagFor(version, app: app, channel: channel);

  if (existsOnly) {
    final token = await _resolveToken();
    if (token == null) {
      stderr.writeln('No GitHub token (GITHUB_TOKEN/GH_TOKEN or gh auth).');
      exitCode = 1;
      return;
    }
    final client = HttpClient();
    try {
      await _api(client, token, 'GET',
          Uri.parse('$apiBase/repos/$owner/$repo/releases/tags/$tag'));
      stdout.writeln('Release $tag already exists.');
      exitCode = 0;
    } on _ApiException catch (e) {
      if (e.statusCode == 404) {
        stdout.writeln('Release $tag does not exist yet.');
        exitCode = 2;
      } else {
        stderr.writeln(e.message);
        exitCode = 1;
      }
    } finally {
      client.close();
    }
    return;
  }

  final candidates =
      apkArg != null ? [apkArg] : apkCandidatePaths(fileVersion, app: app);
  final apkPath =
      candidates.firstWhere((p) => File(p).existsSync(), orElse: () => '');
  if (apkPath.isEmpty) {
    stderr.writeln('No release APK found. Looked for:');
    for (final p in candidates) {
      stderr.writeln('  $p');
    }
    stderr.writeln('Build one first: powershell -File tool\\build.ps1 release');
    exitCode = 1;
    return;
  }
  final apkBytes = File(apkPath).lengthSync();

  final assetName = assetNameFor(version, app: app, channel: channel);
  final name = releaseNameFor(version, app: app, channel: channel);
  var notes = '';
  final changelog = File(app.changelogFile);
  if (changelog.existsSync()) {
    notes = firstChangelogSection(changelog.readAsStringSync());
  }
  final commit = await _git(['rev-parse', 'HEAD']);
  var branch = await _git(['rev-parse', '--abbrev-ref', 'HEAD']) ?? '';
  if (branch.isEmpty || branch == 'HEAD') {
    branch = env['BUILD_BRANCH'] ?? channel;
  }
  final footer = buildFooter(
    channel: channel,
    commit: commit == null ? 'unknown' : commit.substring(0, 7),
    branch: branch,
    builtAt: DateTime.now(),
    durationSeconds: durationSeconds,
    apkBytes: apkBytes,
  );
  final body = notes.isEmpty ? footer : '$notes\n\n$footer';

  stdout.writeln('Publishing $apkPath');
  stdout.writeln(
      '  release: $name  (tag $tag${channel == 'main' ? '' : ', prerelease'})');
  stdout.writeln('  asset:   $assetName (${formatSize(apkBytes)})');
  if (dryRun) {
    stdout.writeln('--- notes ---\n$body\n-------------');
    stdout.writeln('Dry run — nothing uploaded.');
    return;
  }

  final token = await _resolveToken();
  if (token == null) {
    stderr.writeln(
        'No GitHub token. Set GITHUB_TOKEN (or GH_TOKEN), or log in with the '
        'gh CLI so `gh auth token` works.');
    exitCode = 1;
    return;
  }

  final client = HttpClient();
  try {
    final release = await _findOrCreateRelease(client, token,
        tag: tag,
        name: name,
        body: body,
        prerelease: channel != 'main',
        makeLatest: app.id == 'todo' && channel == 'main',
        commit: commit);
    final releaseId = release['id'];
    // Replace a leftover asset of the same name, so re-publishing a rebuilt
    // APK for the same version works.
    final assets = release['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map && asset['name'] == assetName) {
          stdout.writeln('Deleting existing asset $assetName …');
          await _api(client, token, 'DELETE',
              Uri.parse('$apiBase/repos/$owner/$repo/releases/assets/${asset['id']}'));
        }
      }
    }

    stdout.writeln('Uploading APK …');
    final bytes = File(apkPath).readAsBytesSync();
    final uploadUri = Uri.parse(
        '$uploadsBase/repos/$owner/$repo/releases/$releaseId/assets'
        '?name=${Uri.encodeQueryComponent(assetName)}');
    // The multi-tens-of-MB asset upload is the flakiest call here (seen
    // failing with a bare SocketException: Broken pipe partway through) —
    // retry it a couple of times before giving up.
    final uploaded = await _apiWithRetry(client, token, 'POST', uploadUri,
        bodyBytes: bytes,
        contentType: 'application/vnd.android.package-archive');
    stdout.writeln('Done: ${uploaded['browser_download_url']}');
    stdout.writeln('LAPTOP_BUILD_RESULT app=${app.displayName} '
        'version=$version channel=$channel tag=$tag');
  } on _ApiException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } finally {
    client.close();
  }
}

Future<String?> _git(List<String> args) async {
  try {
    final r = await Process.run('git', args);
    if (r.exitCode != 0) return null;
    final out = (r.stdout as String).trim();
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}

Future<String?> _resolveToken() async {
  final env = Platform.environment;
  final fromEnv = env['GITHUB_TOKEN'] ?? env['GH_TOKEN'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  try {
    final result = await Process.run('gh', ['auth', 'token']);
    if (result.exitCode == 0) {
      final token = (result.stdout as String).trim();
      if (token.isNotEmpty) return token;
    }
  } catch (_) {
    // gh CLI not installed — fall through.
  }
  return null;
}

Future<Map<String, dynamic>> _findOrCreateRelease(
  HttpClient client,
  String token, {
  required String tag,
  required String name,
  required String body,
  required bool prerelease,
  required bool makeLatest,
  String? commit,
}) async {
  try {
    final existing = await _api(client, token, 'GET',
        Uri.parse('$apiBase/repos/$owner/$repo/releases/tags/$tag'));
    stdout.writeln('Reusing existing release for $tag.');
    return existing;
  } on _ApiException catch (e) {
    if (e.statusCode != 404) rethrow;
  }

  final payload = <String, dynamic>{
    'tag_name': tag,
    'name': name,
    'body': body,
    'prerelease': prerelease,
    // Only BestToDo's main channel is "Latest" (very old installs read
    // releases/latest), never a prerelease or a Best Music build.
    'make_latest': makeLatest ? 'true' : 'false',
    if (commit != null) 'target_commitish': commit,
  };
  try {
    return await _api(client, token, 'POST',
        Uri.parse('$apiBase/repos/$owner/$repo/releases'),
        bodyBytes: utf8.encode(jsonEncode(payload)),
        contentType: 'application/json');
  } on _ApiException catch (e) {
    // GitHub rejects a SHA it doesn't know (not pushed) with 422.
    if (e.statusCode == 422 && commit != null) {
      throw _ApiException(
          422,
          '${e.message}\nCommit $commit is probably not on GitHub yet — '
          'push it first; a release must point at the built commit.');
    }
    rethrow;
  }
}

/// Like [_api], but retries a transient transport failure (a dropped
/// connection mid-upload, not an HTTP error response from GitHub, which
/// [_ApiException] already carries and isn't worth retrying).
Future<Map<String, dynamic>> _apiWithRetry(
  HttpClient client,
  String token,
  String method,
  Uri url, {
  List<int>? bodyBytes,
  String? contentType,
  int attempts = 3,
}) async {
  for (var attempt = 1;; attempt++) {
    try {
      return await _api(client, token, method, url,
          bodyBytes: bodyBytes, contentType: contentType);
    } on _ApiException {
      rethrow;
    } catch (e) {
      if (attempt >= attempts) rethrow;
      final delay = Duration(seconds: attempt * 5);
      stdout.writeln(
          'Upload attempt $attempt/$attempts failed ($e); retrying in '
          '${delay.inSeconds}s …');
      await Future<void>.delayed(delay);
    }
  }
}

class _ApiException implements Exception {
  _ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
}

Future<Map<String, dynamic>> _api(
  HttpClient client,
  String token,
  String method,
  Uri url, {
  List<int>? bodyBytes,
  String? contentType,
}) async {
  final request = await client.openUrl(method, url);
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
  request.headers.set(HttpHeaders.userAgentHeader, 'besttodo-publish-apk');
  if (bodyBytes != null) {
    request.headers.contentType =
        ContentType.parse(contentType ?? 'application/octet-stream');
    request.contentLength = bodyBytes.length;
    request.add(bodyBytes);
  }
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw _ApiException(response.statusCode,
        '$method $url failed (HTTP ${response.statusCode}): $text');
  }
  if (text.isEmpty) return const {};
  final decoded = jsonDecode(text);
  return decoded is Map<String, dynamic> ? decoded : const {};
}
