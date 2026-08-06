// Uploads the locally built release APK to a GitHub release, which is where
// the app's About page "Check for updates" button looks for new versions.
//
// Usage:
//   flutter build apk --release            (or: sh tool/build.sh apk --release)
//   dart run tool/publish_apk.dart [--apk <path>] [--dry-run]
//
// Or build and publish in one go:
//   PUBLISH_APK=1 sh tool/build.sh apk --release
//
// Auth: a GitHub token with repo write access, taken from the GITHUB_TOKEN or
// GH_TOKEN environment variable, or from `gh auth token` when the GitHub CLI
// is installed and logged in.
//
// Conventions (matching the historical CI releases and the in-app updater):
//   tag      v<x.y.z>-<build>     (git tags can't carry '+')
//   name     BestToDo <x.y.z>+<build>
//   asset    BestToDo-<x.y.z>+<build>.apk
//   body     the newest CHANGELOG.md section
//
// Re-running for the same version reuses the existing release and replaces
// its APK asset, so a rebuilt APK can be re-published safely.

import 'dart:convert';
import 'dart:io';

const String owner = 'Mfficiency';
const String repo = 'best_todo_2';
const String apiBase = 'https://api.github.com';
const String uploadsBase = 'https://uploads.github.com';

/// `version: x.y.z+build` from a pubspec.yaml body, or null.
String? readPubspecVersion(String pubspec) {
  final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
  return m?.group(1);
}

/// Git-safe release tag for a pubspec version: `0.1.132+104` → `v0.1.132-104`.
String releaseTagFor(String version) => 'v${version.replaceAll('+', '-')}';

String releaseNameFor(String version) => 'BestToDo $version';

String assetNameFor(String version) => 'BestToDo-$version.apk';

/// The newest CHANGELOG section: from the first `## [` heading up to (not
/// including) the next one. Empty string when no heading is found.
String firstChangelogSection(String changelog) {
  final lines = changelog.split('\n');
  final start = lines.indexWhere((l) => l.startsWith('## ['));
  if (start == -1) return '';
  var end = lines.length;
  for (var i = start + 1; i < lines.length; i++) {
    if (lines[i].startsWith('## [')) {
      end = i;
      break;
    }
  }
  return lines.sublist(start, end).join('\n').trim();
}

/// Where a freshly built release APK may sit, most specific first
/// (`tool/build.sh` renames it, a plain `flutter build apk` does not).
List<String> apkCandidatePaths(String version) => [
      'build/app/outputs/flutter-apk/best_todo_$version.apk',
      'build/app/outputs/flutter-apk/besttodo-$version.apk',
      'build/app/outputs/flutter-apk/app-release.apk',
    ];

Future<void> main(List<String> args) async {
  String? apkArg;
  var dryRun = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--apk':
        if (i + 1 >= args.length) {
          stderr.writeln('--apk needs a path');
          exitCode = 64;
          return;
        }
        apkArg = args[++i];
      case '--dry-run':
        dryRun = true;
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        stderr.writeln(
            'Usage: dart run tool/publish_apk.dart [--apk <path>] [--dry-run]');
        exitCode = 64;
        return;
    }
  }

  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found — run from the repository root.');
    exitCode = 1;
    return;
  }
  final version = readPubspecVersion(pubspec.readAsStringSync());
  if (version == null || !version.contains('+')) {
    stderr.writeln('Could not read an x.y.z+build version from pubspec.yaml.');
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

  final tag = releaseTagFor(version);
  final assetName = assetNameFor(version);
  var body = '';
  final changelog = File('CHANGELOG.md');
  if (changelog.existsSync()) {
    body = firstChangelogSection(changelog.readAsStringSync());
  }

  stdout.writeln('Publishing $apkPath');
  stdout.writeln('  release: ${releaseNameFor(version)}  (tag $tag)');
  stdout.writeln('  asset:   $assetName');
  if (dryRun) {
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
    final release =
        await _findOrCreateRelease(client, token, tag, version, body);
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
    final uploaded = await _api(client, token, 'POST', uploadUri,
        bodyBytes: bytes, contentType: 'application/vnd.android.package-archive');
    stdout.writeln('Done: ${uploaded['browser_download_url']}');
    stdout.writeln(
        'The About page "Check for updates" button now offers $version.');
  } on _ApiException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
  } finally {
    client.close();
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

Future<Map<String, dynamic>> _findOrCreateRelease(HttpClient client,
    String token, String tag, String version, String body) async {
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
    'name': releaseNameFor(version),
    'body': body,
  };
  // Tag the commit this build came from when it is known to the remote;
  // GitHub rejects unknown SHAs with 422, in which case the tag simply goes
  // on the default branch instead.
  final head = await Process.run('git', ['rev-parse', 'HEAD']);
  if (head.exitCode == 0) {
    payload['target_commitish'] = (head.stdout as String).trim();
  }
  try {
    return await _api(client, token, 'POST',
        Uri.parse('$apiBase/repos/$owner/$repo/releases'),
        bodyBytes: utf8.encode(jsonEncode(payload)),
        contentType: 'application/json');
  } on _ApiException catch (e) {
    if (e.statusCode != 422 || !payload.containsKey('target_commitish')) {
      rethrow;
    }
    stdout.writeln(
        'Local HEAD is not on GitHub yet — tagging the default branch instead.');
    payload.remove('target_commitish');
    return _api(client, token, 'POST',
        Uri.parse('$apiBase/repos/$owner/$repo/releases'),
        bodyBytes: utf8.encode(jsonEncode(payload)),
        contentType: 'application/json');
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
    request.headers.contentType = ContentType.parse(
        contentType ?? 'application/octet-stream');
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
