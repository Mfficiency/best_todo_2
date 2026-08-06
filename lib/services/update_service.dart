import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';

/// A newer app version published as a GitHub release.
class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.releaseName,
    required this.htmlUrl,
    this.body = '',
    this.apkUrl,
    this.apkSizeBytes,
  });

  /// Full pubspec-style version, `x.y.z+build`.
  final String version;

  /// Release title, e.g. "BestToDo 0.1.132+104".
  final String releaseName;

  /// The release page on GitHub — the browser fallback when the APK can't be
  /// installed in place (web/desktop, or a release without an APK asset).
  final String htmlUrl;

  /// Release notes (the CHANGELOG entry the publish tool put there).
  final String body;

  /// Direct download URL of the `.apk` asset, if the release has one.
  final String? apkUrl;

  /// Size of the APK asset in bytes, for the download progress bar.
  final int? apkSizeBytes;
}

/// Checks GitHub releases for a newer build, downloads its APK and hands it
/// to the Android package installer (via the `besttodo/update` channel).
///
/// The repo is public, so both the release lookup and the asset download are
/// plain unauthenticated HTTPS. Releases are published by
/// `tool/publish_apk.dart` after a local build (see CLAUDE.md).
class UpdateService {
  UpdateService._();

  static UpdateService instance = UpdateService._();

  /// Fresh instance per test, dropping any injected [fetchOverride].
  static void resetForTest() {
    instance = UpdateService._();
  }

  static const String owner = 'Mfficiency';
  static const String repo = 'best_todo_2';
  static const String latestReleaseUrl =
      'https://api.github.com/repos/$owner/$repo/releases/latest';

  static const MethodChannel _channel = MethodChannel('besttodo/update');

  /// Test seam: replaces the real HTTPS GET of the release JSON.
  Future<String> Function(Uri url)? fetchOverride;

  /// Numeric components of a version string, in order. `0.1.74+45` →
  /// [0, 1, 74, 45]. Unparseable strings ("unknown" in tests) yield [] and
  /// compare as all-zero, so any real release counts as newer.
  static List<int> versionNumbers(String version) => RegExp(r'\d+')
      .allMatches(version)
      .map((m) => int.parse(m.group(0)!))
      .toList();

  /// Compares two `x.y.z+build` strings component-by-component; missing
  /// components count as 0. Returns <0, 0 or >0 like [Comparable.compareTo].
  static int compareVersions(String a, String b) {
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

  /// Release tag → pubspec version: `v0.1.74-45` → `0.1.74+45` (git tags
  /// can't carry `+`, so the publisher uses `-` for the build number).
  static String versionFromTag(String tag) {
    var v = tag.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final m = RegExp(r'^(\d+\.\d+\.\d+)[-+](\d+)$').firstMatch(v);
    if (m != null) return '${m.group(1)}+${m.group(2)}';
    return v;
  }

  /// Extracts the fields the updater needs from a GitHub release payload.
  static UpdateInfo releaseInfo(Map<String, dynamic> release) {
    final tag = release['tag_name'] as String? ?? '';
    String? apkUrl;
    int? apkSize;
    final assets = release['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map &&
            (asset['name'] as String? ?? '').toLowerCase().endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          apkSize = (asset['size'] as num?)?.round();
          break;
        }
      }
    }
    return UpdateInfo(
      version: versionFromTag(tag),
      releaseName: release['name'] as String? ?? tag,
      htmlUrl: release['html_url'] as String? ??
          'https://github.com/$owner/$repo/releases',
      body: release['body'] as String? ?? '',
      apkUrl: apkUrl,
      apkSizeBytes: apkSize,
    );
  }

  /// Looks up the newest release and returns it when it is newer than
  /// [currentVersion] (defaults to the running app's version), or null when
  /// the app is up to date. Throws on network/parse failures — the caller
  /// shows the error, this is a user-initiated check.
  Future<UpdateInfo?> checkForUpdate({String? currentVersion}) async {
    var current = currentVersion;
    if (current == null) {
      await Config.ensureVersionLoaded();
      current = Config.versionWithBuild;
    }
    final body = await _fetch(Uri.parse(latestReleaseUrl));
    final release = jsonDecode(body);
    if (release is! Map<String, dynamic>) {
      throw const FormatException('Unexpected release payload');
    }
    final info = releaseInfo(release);
    if (compareVersions(info.version, current) <= 0) return null;
    return info;
  }

  Future<String> _fetch(Uri url) async {
    final override = fetchOverride;
    if (override != null) return override(url);
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'BestToDo-update-check');
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('GitHub replied ${response.statusCode}', uri: url);
      }
      return text;
    } finally {
      client.close();
    }
  }

  /// Downloads the release's APK into the temp dir (covered by the manifest's
  /// FileProvider cache-path) and reports progress. Throws on failure.
  Future<File> downloadApk(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final url = info.apkUrl;
    if (url == null) {
      throw StateError('This release has no APK to download');
    }
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/BestToDo-update-${info.version.replaceAll('+', '-')}.apk');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'BestToDo-update-check');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('Download failed (HTTP ${response.statusCode})',
            uri: Uri.parse(url));
      }
      final total =
          response.contentLength > 0 ? response.contentLength : info.apkSizeBytes;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      return file;
    } finally {
      client.close();
    }
  }

  /// Hands the downloaded APK to the Android package installer. Returns
  /// "ok" when the install UI opened, or "needs-permission" when the app
  /// first has to be allowed to install packages (the settings screen for
  /// that is opened by the platform side; retry after granting).
  Future<String> installApk(String path) async {
    final result =
        await _channel.invokeMethod<String>('installApk', {'path': path});
    return result ?? 'error';
  }
}
