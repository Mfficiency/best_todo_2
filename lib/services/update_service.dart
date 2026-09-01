import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Where an [UpdateInfo] was found: an APK committed to the repo's
/// `github_releases/` folder (the primary source — see
/// [UpdateService.folderContentsUrl]) or a published GitHub release (the
/// fallback for branches where the folder does not exist yet).
enum UpdateSource { repoFolder, githubRelease }

/// An installable app build — the newest one, or the one kept for a rollback.
class UpdateInfo {
  UpdateInfo({
    required this.version,
    required this.releaseName,
    required this.htmlUrl,
    this.body = '',
    this.apkUrl,
    this.apkSizeBytes,
    this.source = UpdateSource.githubRelease,
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

  /// Which of the two lookups produced this build.
  final UpdateSource source;
}

/// The outcome of one update check: the newest installable build and the one
/// version back that the `github_releases/` folder still keeps, so the About
/// page can offer both an update and a rollback.
class UpdateCheck {
  UpdateCheck({required this.currentVersion, this.latest, this.previous});

  /// The version the app is running, `x.y.z+build`.
  final String currentVersion;

  /// Newest build found, whatever its version relative to [currentVersion].
  final UpdateInfo? latest;

  /// Second-newest build kept in the repo folder, if there is one.
  final UpdateInfo? previous;

  /// True when [latest] is actually newer than the running app.
  bool get hasUpdate =>
      latest != null &&
      UpdateService.compareVersions(latest!.version, currentVersion) > 0;

  /// The build to offer as "one version back": [previous], unless that is the
  /// version already running (which happens right after an update is
  /// published, when the folder keeps new + current).
  UpdateInfo? get rollback {
    final candidate = previous;
    if (candidate == null) return null;
    if (UpdateService.compareVersions(candidate.version, currentVersion) == 0) {
      return null;
    }
    return candidate;
  }
}

/// State of a download handed off to Android's `DownloadManager`. The OS
/// service — not the Dart isolate — owns the transfer, so it keeps running
/// while the app is backgrounded and survives switching between Wi-Fi and
/// mobile data mid-download (DownloadManager resumes on whatever network
/// comes back, using HTTP range requests).
enum DownloadStatus { pending, running, paused, successful, failed }

/// One snapshot of a background download, as reported by
/// [UpdateService.queryDownload].
class DownloadProgress {
  DownloadProgress({
    required this.status,
    this.bytesDownloaded = 0,
    this.bytesTotal,
    this.localPath,
    this.reason,
  });

  final DownloadStatus status;
  final int bytesDownloaded;
  final int? bytesTotal;

  /// Filesystem path of the downloaded APK, set once [status] is
  /// [DownloadStatus.successful].
  final String? localPath;

  /// `DownloadManager.COLUMN_REASON` value on a paused/failed download —
  /// opaque, only useful in an error message.
  final String? reason;

  static DownloadStatus statusFromWire(String value) {
    switch (value) {
      case 'successful':
        return DownloadStatus.successful;
      case 'failed':
        return DownloadStatus.failed;
      case 'running':
        return DownloadStatus.running;
      case 'paused':
        return DownloadStatus.paused;
      default:
        return DownloadStatus.pending;
    }
  }
}

/// Finds installable builds, downloads an APK and hands it to the Android
/// package installer (via the `besttodo/update` channel).
///
/// Primary source is the repo's `github_releases/` folder, which
/// `tool/stage_local_release.dart` (run from `tool/build.sh`) keeps at the last
/// two APKs — that is what makes "one version back" possible. When the folder
/// is missing or empty the lookup falls back to the newest published GitHub
/// release (`tool/publish_apk.dart` / the build-apk workflow).
///
/// The repo is public, so both the lookup and the download are plain
/// unauthenticated HTTPS.
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

  /// Repo folder holding the last two built APKs.
  static const String releasesFolder = 'github_releases';

  /// Branch the folder is read from. `dev` is where every build lands first
  /// (both local `tool/build.sh` runs and the build-apk workflow publish from
  /// it), so it always carries the two newest APKs.
  static const String releasesRef = 'dev';

  /// Directory listing of [releasesFolder]. Entries carry `name`, `size` and a
  /// ready-made `download_url` (percent-encoded, which matters because the
  /// file names contain `+`).
  static const String folderContentsUrl =
      'https://api.github.com/repos/$owner/$repo/contents/$releasesFolder'
      '?ref=$releasesRef';

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

  /// `best_todo_0.1.143+115.apk` → `0.1.143+115`. Also accepts the release
  /// asset spelling (`BestToDo-0.1.143+115.apk`) and a `-build` separator.
  /// Returns null for names that are not a versioned APK.
  static String? versionFromApkFileName(String name) {
    if (!name.toLowerCase().endsWith('.apk')) return null;
    final m =
        RegExp(r'(\d+\.\d+\.\d+)(?:[+\-_](\d+))?').firstMatch(name);
    if (m == null) return null;
    final build = m.group(2);
    return build == null ? m.group(1)! : '${m.group(1)}+$build';
  }

  /// Maps a GitHub contents-API directory listing to installable builds,
  /// newest first. Non-APK entries (the folder's README) are skipped.
  static List<UpdateInfo> folderReleases(List<dynamic> contents) {
    final builds = <UpdateInfo>[];
    for (final entry in contents) {
      if (entry is! Map) continue;
      final name = entry['name'] as String? ?? '';
      final version = versionFromApkFileName(name);
      final url = entry['download_url'] as String? ?? '';
      if (version == null || url.isEmpty) continue;
      builds.add(UpdateInfo(
        version: version,
        releaseName: 'BestToDo $version',
        htmlUrl: entry['html_url'] as String? ??
            'https://github.com/$owner/$repo/tree/$releasesRef/$releasesFolder',
        apkUrl: url,
        apkSizeBytes: (entry['size'] as num?)?.round(),
        source: UpdateSource.repoFolder,
      ));
    }
    builds.sort((a, b) => compareVersions(b.version, a.version));
    return builds;
  }

  /// The APKs currently kept in the repo folder, newest first. Empty when the
  /// folder holds no versioned APK; throws when the listing can't be fetched.
  Future<List<UpdateInfo>> fetchFolderReleases() async {
    final decoded = jsonDecode(await _fetch(Uri.parse(folderContentsUrl)));
    if (decoded is! List) return const [];
    return folderReleases(decoded);
  }

  /// Looks up the installable builds: the repo folder first (newest + one
  /// version back), the newest published release as a fallback. Throws on
  /// network/parse failures of the fallback — the caller shows the error, this
  /// is a user-initiated check.
  Future<UpdateCheck> checkReleases({String? currentVersion}) async {
    var current = currentVersion;
    if (current == null) {
      await Config.ensureVersionLoaded();
      current = Config.versionWithBuild;
    }
    var folder = const <UpdateInfo>[];
    try {
      folder = await fetchFolderReleases();
    } catch (_) {
      // No folder on this branch (or offline for it) — the release lookup
      // below is the fallback and reports the failure instead.
    }
    if (folder.isNotEmpty) {
      return UpdateCheck(
        currentVersion: current,
        latest: folder.first,
        previous: folder.length > 1 ? folder[1] : null,
      );
    }
    final body = await _fetch(Uri.parse(latestReleaseUrl));
    final release = jsonDecode(body);
    if (release is! Map<String, dynamic>) {
      throw const FormatException('Unexpected release payload');
    }
    return UpdateCheck(currentVersion: current, latest: releaseInfo(release));
  }

  /// The newest build when it is newer than [currentVersion] (defaults to the
  /// running app's version), or null when the app is up to date.
  Future<UpdateInfo?> checkForUpdate({String? currentVersion}) async {
    final check = await checkReleases(currentVersion: currentVersion);
    return check.hasUpdate ? check.latest : null;
  }

  /// A background poll runs every minute (see [AutoUpdateChecker]) guarded by
  /// a single in-flight flag; a request that never completes — flaky mobile
  /// data, Doze-mode network suspension — would otherwise wedge that flag
  /// forever and silently stop checking for the rest of the session. This
  /// timeout, plus force-closing the client on it, guarantees every fetch
  /// resolves one way or another.
  static const Duration _fetchTimeout = Duration(seconds: 20);

  Future<String> _fetch(Uri url) async {
    final override = fetchOverride;
    if (override != null) return override(url);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      return await _fetchWith(client, url).timeout(
        _fetchTimeout,
        onTimeout: () {
          client.close(force: true);
          throw TimeoutException('GitHub update check timed out', _fetchTimeout);
        },
      );
    } finally {
      client.close();
    }
  }

  Future<String> _fetchWith(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, 'BestToDo-update-check');
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw HttpException('GitHub replied ${response.statusCode}', uri: url);
    }
    return text;
  }

  /// Test seam: replaces the real `besttodo/update` platform-channel call
  /// used by [startBackgroundDownload], [queryDownload] and [cancelDownload].
  Future<dynamic> Function(String method, Map<String, dynamic> args)?
      downloadChannelOverride;

  Future<dynamic> _invokeDownloadChannel(
      String method, Map<String, dynamic> args) {
    final override = downloadChannelOverride;
    if (override != null) return override(method, args);
    return _channel.invokeMethod(method, args);
  }

  static const String _pendingDownloadPrefsKey = 'update_pending_download';

  /// Hands [info]'s APK to Android's `DownloadManager` and returns its
  /// download id. The transfer then runs as a system service, independent of
  /// the app process — it keeps going if the app is backgrounded and rides
  /// out a Wi-Fi/mobile handover, unlike a plain HTTP socket held open by the
  /// app. Progress is polled with [queryDownload]/[watchDownload].
  Future<int> startBackgroundDownload(UpdateInfo info) async {
    final url = info.apkUrl;
    if (url == null) {
      throw StateError('This release has no APK to download');
    }
    final fileName =
        'BestToDo-update-${info.version.replaceAll('+', '-')}.apk';
    final result = await _invokeDownloadChannel(
        'startBackgroundDownload', {'url': url, 'fileName': fileName});
    return (result as Map)['downloadId'] as int;
  }

  /// One snapshot of [downloadId]'s progress.
  Future<DownloadProgress> queryDownload(int downloadId) async {
    final raw = await _invokeDownloadChannel(
        'queryDownload', {'downloadId': downloadId});
    final map = Map<Object?, Object?>.from(raw as Map);
    return DownloadProgress(
      status: DownloadProgress.statusFromWire(
          map['status'] as String? ?? 'failed'),
      bytesDownloaded: (map['bytesDownloaded'] as num?)?.toInt() ?? 0,
      bytesTotal: (map['bytesTotal'] as num?)?.toInt(),
      localPath: map['localPath'] as String?,
      reason: map['reason']?.toString(),
    );
  }

  /// Removes a download from `DownloadManager` (and its partial file).
  Future<void> cancelDownload(int downloadId) =>
      _invokeDownloadChannel('cancelDownload', {'downloadId': downloadId});

  /// Polls [downloadId] until it reaches a terminal status, yielding every
  /// snapshot along the way.
  Stream<DownloadProgress> watchDownload(
    int downloadId, {
    Duration interval = const Duration(milliseconds: 700),
  }) async* {
    while (true) {
      final progress = await queryDownload(downloadId);
      yield progress;
      if (progress.status == DownloadStatus.successful ||
          progress.status == DownloadStatus.failed) {
        return;
      }
      await Future<void>.delayed(interval);
    }
  }

  /// Starts a background download of [info] and streams its progress,
  /// persisting the download id so [pendingDownload] can find it again if
  /// the app is closed and reopened before it finishes (cleared once the
  /// download reaches a terminal status).
  Stream<DownloadProgress> downloadInBackground(
    UpdateInfo info, {
    Duration interval = const Duration(milliseconds: 700),
  }) async* {
    final id = await startBackgroundDownload(info);
    await _savePendingDownload(id, info.version);
    await for (final progress in watchDownload(id, interval: interval)) {
      yield progress;
      if (progress.status == DownloadStatus.successful ||
          progress.status == DownloadStatus.failed) {
        await clearPendingDownload();
      }
    }
  }

  Future<void> _savePendingDownload(int downloadId, String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingDownloadPrefsKey,
        jsonEncode({'downloadId': downloadId, 'version': version}));
  }

  Future<void> clearPendingDownload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingDownloadPrefsKey);
  }

  /// A download started in an earlier app run that had not finished (or
  /// whose completion was never seen) by the time the app closed, as
  /// `{downloadId, version}` — null when there is none. The caller resumes
  /// watching it with [watchDownload].
  Future<Map<String, dynamic>?> pendingDownload() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingDownloadPrefsKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
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
