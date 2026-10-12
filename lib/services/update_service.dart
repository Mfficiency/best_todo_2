import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// Where an [UpdateInfo] was found. Every build now comes from a published
/// GitHub release of its own app (any channel); [repoFolder] is the legacy
/// `github_releases/` folder (still in the repo for old installs, no longer
/// read or written by current builds).
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

/// The outcome of one update check: this app's highest build number over
/// every channel (main, staging, dev) and the highest one below the running
/// build, so the About page can offer both an update and a rollback.
class UpdateCheck {
  UpdateCheck({required this.currentVersion, this.latest, this.previous});

  /// The version the app is running, `x.y.z+build`.
  final String currentVersion;

  /// Highest build found, whatever its build relative to [currentVersion].
  final UpdateInfo? latest;

  /// Highest build below the running one (any channel), if there is one.
  final UpdateInfo? previous;

  /// True when [latest]'s build number (the versionCode) is above the running
  /// app's, the same rule Android applies to the install.
  bool get hasUpdate =>
      latest != null &&
      UpdateService.isNewerBuild(latest!.version, currentVersion);

  /// The build to offer as "one version back": [previous], unless that is the
  /// version already running.
  UpdateInfo? get rollback {
    final candidate = previous;
    if (candidate == null) return null;
    if (UpdateService.buildNumberOf(candidate.version) ==
        UpdateService.buildNumberOf(currentVersion)) {
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

/// Thrown by an update check while GitHub's anonymous API rate limit
/// (60 requests/hour/IP) is exhausted — a "try again later", not a failure.
class UpdateRateLimitedException implements Exception {
  UpdateRateLimitedException(this.retryAfter);

  /// When the limit resets (or a 15-minute back-off when GitHub didn't say).
  final DateTime retryAfter;

  @override
  String toString() {
    final t = retryAfter.toLocal();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return 'GitHub rate limit reached, try again after $hh:$mm';
  }
}

/// A release tag split into app, version and channel. Tags (published by the
/// laptop builder through `tool/publish_apk.dart`):
///   BestToDo   `v<x.y.z>-<build>`        + `-dev` / `-staging`
///   Best Music `music-v<x.y.z>-<build>`  + `-dev` / `-staging`
class ReleaseTag {
  const ReleaseTag(
      {required this.music, required this.version, required this.channel});

  /// True for a Best Music tag (`music-v...`).
  final bool music;

  /// `x.y.z+build`.
  final String version;

  /// `main`, `staging` or `dev`.
  final String channel;

  static final RegExp _pattern = RegExp(
      r'^(music-)?v(\d+\.\d+\.\d+)-(\d+)(?:-(dev|staging))?$',
      caseSensitive: false);

  /// Null for anything that isn't one of the app tags above.
  static ReleaseTag? parse(String tag) {
    final m = _pattern.firstMatch(tag.trim());
    if (m == null) return null;
    return ReleaseTag(
      music: m.group(1) != null,
      version: '${m.group(2)}+${m.group(3)}',
      channel: (m.group(4) ?? 'main').toLowerCase(),
    );
  }
}

/// Finds installable builds, downloads an APK and hands it to the Android
/// package installer (via the `besttodo/update` channel).
///
/// Source: the GitHub releases list of `Mfficiency/best_todo_2`
/// ([releasesListUrl]), where the laptop builder publishes one release per
/// app, channel and build. dev, staging and main builds are the same Android
/// app, so the releases of all three channels count (prereleases included,
/// drafts never): the one with the highest build number wins, whichever
/// branch it came from. Only this app's own tags ([tagPrefix]) are ever
/// considered — BestToDo never offers a Best Music APK and vice versa.
/// Newer = higher build number (the versionCode: minutes since 2020 of the
/// built commit, so it rises across all branches).
///
/// The repo is public, so the lookup and the download are anonymous HTTPS
/// (60 API requests/hour/IP): [AutoUpdateChecker] polls at most every 15
/// minutes and a 403/429 backs off ([UpdateRateLimitedException]).
///
/// The old `github_releases/` repo folder is legacy — old installs still
/// read it, current builds neither read nor write it.
class UpdateService {
  UpdateService._(
      {this.appDisplayName = 'BestToDo', this.apkPrefix = 'best_todo'});

  static UpdateService instance = UpdateService._();

  /// A second app built from this same repo (Best Music) gets its own
  /// instance rather than reusing [instance], so its `appDisplayName` and
  /// tags never leak into BestToDo's own update check.
  static UpdateService forApp(
          {required String appDisplayName, required String apkPrefix}) =>
      UpdateService._(appDisplayName: appDisplayName, apkPrefix: apkPrefix);

  /// Fresh instance per test, dropping any injected [fetchOverride].
  static void resetForTest() {
    instance = UpdateService._();
  }

  /// Shown in release names and the background-download file name, e.g.
  /// "BestToDo 0.1.132+104" / "BestToDo-update-0.1.132-104.apk".
  final String appDisplayName;

  /// Which app this is: `best_todo` (BestToDo) or `best_music` (Best Music).
  /// Picks the release tag family ([tagPrefix]).
  final String apkPrefix;

  /// `v` for BestToDo, `music-v` for Best Music.
  String get tagPrefix => apkPrefix == 'best_music' ? 'music-v' : 'v';

  static const String owner = 'Mfficiency';
  static const String repo = 'best_todo_2';

  /// The releases list (newest first). `releases/latest` is repo-wide and
  /// ignores prereleases, so it can't serve two apps × three channels.
  static const String releasesListUrl =
      'https://api.github.com/repos/$owner/$repo/releases?per_page=30';

  static const MethodChannel _channel = MethodChannel('besttodo/update');

  /// Test seam: replaces the real HTTPS GET of the release JSON. Throwing an
  /// `HttpException('GitHub replied 403')` simulates the rate limit.
  Future<String> Function(Uri url)? fetchOverride;

  /// Set after a 403/429: no request is made before this time.
  DateTime? rateLimitedUntil;

  /// Back-off after a 403/429 that didn't say when the limit resets.
  static const Duration rateLimitBackoff = Duration(minutes: 15);

  /// The newest finished check of this app (About, background poll or the
  /// Changelog's pull-down); null until one finished this session. The
  /// Changelog's status card shows it.
  final ValueNotifier<UpdateCheck?> lastCheck = ValueNotifier(null);

  /// True while a check runs (the status card shows a spinner).
  final ValueNotifier<bool> checking = ValueNotifier(false);

  /// When the last check succeeded, also from an earlier run
  /// ([loadUpdateStatus]).
  final ValueNotifier<DateTime?> lastCheckedAt = ValueNotifier(null);

  /// The last APK that finished downloading and when, also from an earlier
  /// run ([loadUpdateStatus]).
  final ValueNotifier<({String version, DateTime at})?> lastDownload =
      ValueNotifier(null);

  static const String _lastCheckedPrefsKey = 'update_last_checked';
  static const String _lastDownloadPrefsKey = 'update_last_download';

  /// Reads [lastCheckedAt] and [lastDownload] from an earlier run, unless
  /// this run already knows newer ones. Errors are swallowed.
  Future<void> loadUpdateStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final checked = prefs.getInt(_lastCheckedPrefsKey);
      if (checked != null && lastCheckedAt.value == null) {
        lastCheckedAt.value = DateTime.fromMillisecondsSinceEpoch(checked);
      }
      final raw = prefs.getString(_lastDownloadPrefsKey);
      if (raw != null && lastDownload.value == null) {
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        lastDownload.value = (
          version: saved['version'] as String,
          at: DateTime.fromMillisecondsSinceEpoch(saved['at'] as int),
        );
      }
    } catch (_) {}
  }

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

  /// The build number (versionCode) of an `x.y.z+build` string; 0 when it
  /// has none ("unknown" in tests, a version without `+build`).
  static int buildNumberOf(String version) {
    final plus = version.indexOf('+');
    if (plus < 0) return 0;
    final m = RegExp(r'^\d+').firstMatch(version.substring(plus + 1).trim());
    return m == null ? 0 : int.parse(m.group(0)!);
  }

  /// True when [candidate]'s build number is above [current]'s, which is what
  /// makes a build an update: Android installs over the running app exactly
  /// when the versionCode rises, whatever the x.y.z or the channel.
  static bool isNewerBuild(String candidate, String current) =>
      buildNumberOf(candidate) > buildNumberOf(current);

  /// Orders builds by build number, then by x.y.z for equal numbers.
  /// Returns <0, 0 or >0 like [Comparable.compareTo].
  static int compareBuilds(String a, String b) {
    final byNumber = buildNumberOf(a).compareTo(buildNumberOf(b));
    return byNumber != 0 ? byNumber : compareVersions(a, b);
  }

  /// Release tag → pubspec version: `v0.1.74-45` → `0.1.74+45` (git tags
  /// can't carry `+`, so the publisher uses `-` for the build number). Also
  /// drops a `music-` app prefix and a `-dev`/`-staging` channel suffix.
  static String versionFromTag(String tag) {
    final parsed = ReleaseTag.parse(tag);
    if (parsed != null) return parsed.version;
    var v = tag.trim();
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
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

  /// True when [release] (a releases-list entry) is a published build of
  /// the app with [tagPrefix] (`v` / `music-v`), on any channel (main,
  /// staging or dev; prereleases count). Drafts never count.
  static bool isAppRelease(Map<String, dynamic> release,
      {required String tagPrefix}) {
    if (release['draft'] == true) return false;
    final tag = ReleaseTag.parse(release['tag_name'] as String? ?? '');
    if (tag == null) return false;
    return tag.music == (tagPrefix == 'music-v');
  }

  /// This app's builds of every channel out of a releases-list payload,
  /// highest build number first ([compareBuilds]).
  static List<UpdateInfo> appReleases(List<dynamic> releases,
      {required String tagPrefix}) {
    final builds = <UpdateInfo>[];
    for (final release in releases) {
      if (release is! Map<String, dynamic>) continue;
      if (!isAppRelease(release, tagPrefix: tagPrefix)) continue;
      builds.add(releaseInfo(release));
    }
    builds.sort((a, b) => compareBuilds(b.version, a.version));
    return builds;
  }

  /// This app's builds of all channels, highest build number first. Throws
  /// on network/parse failures, and [UpdateRateLimitedException] while rate
  /// limited.
  Future<List<UpdateInfo>> fetchAppReleases() async {
    final decoded = jsonDecode(await _fetch(Uri.parse(releasesListUrl)));
    if (decoded is! List) {
      throw const FormatException('Unexpected releases payload');
    }
    return appReleases(decoded, tagPrefix: tagPrefix);
  }

  /// The running app's `x.y.z+build`.
  Future<String> currentVersionWithBuild() async {
    await Config.ensureVersionLoaded();
    return Config.versionWithBuild;
  }

  /// Looks up this app's highest build over all channels plus the highest
  /// one below the running build (the rollback). Throws on network/parse
  /// failures — the About page shows the error, the background poll retries.
  Future<UpdateCheck> checkReleases({String? currentVersion}) async {
    var current = currentVersion;
    if (current == null) {
      await Config.ensureVersionLoaded();
      current = Config.versionWithBuild;
    }
    checking.value = true;
    try {
      final builds = await fetchAppReleases();
      UpdateInfo? previous;
      for (final b in builds) {
        if (buildNumberOf(b.version) < buildNumberOf(current)) {
          previous = b;
          break;
        }
      }
      final check = UpdateCheck(
        currentVersion: current,
        latest: builds.isEmpty ? null : builds.first,
        previous: previous,
      );
      lastCheck.value = check;
      final now = DateTime.now();
      lastCheckedAt.value = now;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_lastCheckedPrefsKey, now.millisecondsSinceEpoch);
      } catch (_) {}
      return check;
    } finally {
      checking.value = false;
    }
  }

  /// The highest build when its build number is above [currentVersion]'s
  /// (defaults to the running app's version), or null when up to date.
  Future<UpdateInfo?> checkForUpdate({String? currentVersion}) async {
    final check = await checkReleases(currentVersion: currentVersion);
    return check.hasUpdate ? check.latest : null;
  }

  /// A background poll (see [AutoUpdateChecker]) is guarded by
  /// a single in-flight flag; a request that never completes — flaky mobile
  /// data, Doze-mode network suspension — would otherwise wedge that flag
  /// forever and silently stop checking for the rest of the session. This
  /// timeout, plus force-closing the client on it, guarantees every fetch
  /// resolves one way or another.
  static const Duration _fetchTimeout = Duration(seconds: 20);

  Future<String> _fetch(Uri url) async {
    final until = rateLimitedUntil;
    if (until != null) {
      if (DateTime.now().isBefore(until)) {
        throw UpdateRateLimitedException(until);
      }
      rateLimitedUntil = null;
    }
    final override = fetchOverride;
    if (override != null) {
      try {
        return await override(url);
      } on HttpException catch (e) {
        final status = RegExp(r'replied (\d+)').firstMatch(e.message);
        _throwIfRateLimited(int.tryParse(status?.group(1) ?? ''), null);
        rethrow;
      }
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      return await _fetchWith(client, url).timeout(
        _fetchTimeout,
        onTimeout: () {
          client.close(force: true);
          throw TimeoutException(
              'GitHub update check timed out', _fetchTimeout);
        },
      );
    } finally {
      client.close();
    }
  }

  /// 403/429 = GitHub's anonymous rate limit: remember when to try again
  /// (its `x-ratelimit-reset`, else [rateLimitBackoff]) and throw
  /// [UpdateRateLimitedException]. No-op for any other status.
  void _throwIfRateLimited(int? status, String? resetHeader) {
    if (status != 403 && status != 429) return;
    final reset = int.tryParse(resetHeader ?? '');
    final until = reset != null
        ? DateTime.fromMillisecondsSinceEpoch(reset * 1000)
        : DateTime.now().add(rateLimitBackoff);
    rateLimitedUntil = until;
    throw UpdateRateLimitedException(until);
  }

  Future<String> _fetchWith(HttpClient client, Uri url) async {
    final request = await client.getUrl(url);
    request.headers
        .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, 'BestToDo-update-check');
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    _throwIfRateLimited(
        response.statusCode, response.headers.value('x-ratelimit-reset'));
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

  /// Version whose APK was last downloaded successfully (handed to the
  /// installer), so a re-prompt for the same build — the auto-checker polls
  /// every 15 minutes, and a fresh app launch has no in-memory record of what an
  /// earlier run already fetched — can be skipped instead of asking the user
  /// to download it again. Naturally stops mattering once that version is
  /// actually installed, since `checkForUpdate` then no longer reports it as
  /// newer than the running app.
  static const String _downloadedVersionPrefsKey = 'update_downloaded_version';

  /// Title of the system download notification, e.g.
  /// "Best Music update 0.1.12+30" — names the app and the exact version so
  /// a BestToDo and a Best Music download can't be told apart only by guesswork.
  String downloadNotificationTitle(UpdateInfo info) =>
      '$appDisplayName update ${info.version}';

  /// Hands [info]'s APK to Android's `DownloadManager` and returns its
  /// download id. The transfer then runs as a system service, independent of
  /// the app process — it keeps going if the app is backgrounded and rides
  /// out a Wi-Fi/mobile handover, unlike a plain HTTP socket held open by the
  /// app. Progress is polled with [queryDownload]/[watchDownload].
  ///
  /// [silent] (the automatic update) downloads without a notification; the
  /// app asks to install once it is complete.
  Future<int> startBackgroundDownload(UpdateInfo info,
      {bool silent = false}) async {
    final url = info.apkUrl;
    if (url == null) {
      throw StateError('This release has no APK to download');
    }
    final fileName =
        '$appDisplayName-update-${info.version.replaceAll('+', '-')}.apk';
    final result = await _invokeDownloadChannel('startBackgroundDownload', {
      'url': url,
      'fileName': fileName,
      'title': downloadNotificationTitle(info),
      'silent': silent,
    });
    return (result as Map)['downloadId'] as int;
  }

  /// One snapshot of [downloadId]'s progress.
  Future<DownloadProgress> queryDownload(int downloadId) async {
    final raw = await _invokeDownloadChannel(
        'queryDownload', {'downloadId': downloadId});
    final map = Map<Object?, Object?>.from(raw as Map);
    return DownloadProgress(
      status:
          DownloadProgress.statusFromWire(map['status'] as String? ?? 'failed'),
      bytesDownloaded: (map['bytesDownloaded'] as num?)?.toInt() ?? 0,
      bytesTotal: (map['bytesTotal'] as num?)?.toInt(),
      localPath: map['localPath'] as String?,
      reason: map['reason']?.toString(),
    );
  }

  /// Absolute path of the folder update APKs are downloaded into (the app's
  /// external files dir + `updates/`, e.g.
  /// `/storage/emulated/0/Android/data/<app id>/files/updates`), shown in
  /// Settings. Null off Android — no in-app downloads happen there — or when
  /// the native side can't resolve it (external storage unavailable).
  Future<String?> updateDownloadsDirectory() async {
    if (downloadChannelOverride == null && (kIsWeb || !Platform.isAndroid)) {
      return null;
    }
    try {
      final result = await _invokeDownloadChannel('updateDownloadsDir', {});
      return result is String && result.isNotEmpty ? result : null;
    } catch (_) {
      return null;
    }
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
    bool silent = false,
  }) async* {
    final id = await startBackgroundDownload(info, silent: silent);
    await _savePendingDownload(id, info.version);
    await for (final progress in watchDownload(id, interval: interval)) {
      yield progress;
      if (progress.status == DownloadStatus.successful) {
        await markVersionDownloaded(info.version, path: progress.localPath);
        await clearPendingDownload();
      } else if (progress.status == DownloadStatus.failed) {
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

  /// Records that [version]'s APK was downloaded and handed to the
  /// installer, so [wasDownloaded] recognizes it on a later check even after
  /// [clearPendingDownload] has dropped the in-progress record.
  /// Also records when ([lastDownload], for the Changelog's status card).
  Future<void> markVersionDownloaded(String version,
      {String? path, DateTime? at}) async {
    final download = (version: version, at: at ?? DateTime.now());
    lastDownload.value = download;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadedVersionPrefsKey, version);
    await prefs.setString(
        _lastDownloadPrefsKey,
        jsonEncode({
          'version': version,
          'at': download.at.millisecondsSinceEpoch,
        }));
    if (path != null) {
      await prefs.setString(_downloadedApkPrefsKey,
          jsonEncode({'version': version, 'path': path}));
    }
  }

  /// Where the complete APK of the last download is, as `{version, path}`.
  static const String _downloadedApkPrefsKey = 'update_downloaded_apk';

  /// Test seam: replaces the check that a downloaded APK is still on disk.
  bool Function(String path)? fileExistsOverride;

  /// Path of [version]'s completely downloaded APK — also from before a
  /// restart — or null when it isn't (or no longer is) on disk.
  Future<String?> readyApk(String version) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_downloadedApkPrefsKey);
    if (raw == null) return null;
    try {
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      final path = saved['path'] as String?;
      if (saved['version'] != version || path == null) return null;
      final exists = fileExistsOverride ?? (p) => File(p).existsSync();
      return exists(path) ? path : null;
    } catch (_) {
      return null;
    }
  }

  /// True when [version] is either downloading right now or was already
  /// downloaded and handed to the installer — the two cases in which the app
  /// should not ask the user to download it again.
  Future<bool> wasDownloaded(String version) async {
    final pending = await pendingDownload();
    if (pending != null && pending['version'] == version) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_downloadedVersionPrefsKey) == version;
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

  /// Hands the downloaded APK to Android in a PackageInstaller session
  /// (`ApkInstaller.kt`), so Android's "Update this app?" is the only step.
  /// Returns "ok" when that opened, or "needs-permission" when the app
  /// first has to be allowed to install packages (the settings screen for
  /// that is opened by the platform side; retry after granting).
  Future<String> installApk(String path) async {
    final result = await _invokeDownloadChannel('installApk', {'path': path});
    return result is String ? result : 'error';
  }
}
