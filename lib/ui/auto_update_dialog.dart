import 'dart:async';

import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// A download the app is running in the background, for passive inline
/// status text (the Changelog's status card, the About page).
typedef UpdateDownload = ({String version, int received, int? total});

/// "42%" of [download], or null while its size is unknown.
String? updateDownloadPercent(UpdateDownload download) {
  final total = download.total;
  if (total == null || total <= 0) return null;
  final pct = (download.received / total * 100).clamp(0, 100);
  return '${pct.toStringAsFixed(0)}%';
}

/// What a tap that starts a download shows — the only feedback for it.
const String updateDownloadingSnack =
    "Downloading in the background — you'll be asked to install it when "
    "it's ready";

/// The automatic update of a running app (BestToDo in `main.dart`, Best
/// Music in `main_music.dart`; same flow as BestCollage and Hally Remote):
///
/// 1. **Every** download is silent: Android's `DownloadManager` with no
///    notification, no dialog, no progress sheet, no banner — the
///    background poll ([onUpdateFound]), a pull-down on the changelog
///    ([checkNow]), Install on the Changelog card or the About page for a
///    build that isn't downloaded yet ([install]) and going back to an
///    older build alike. A tap that starts one shows one SnackBar; while it
///    runs, only passive text says so ([downloading]: the Changelog status
///    card, the About page).
/// 2. When the APK is complete, the app hands it straight to a
///    PackageInstaller session (`ApkInstaller.kt`), so Android's own
///    "Update this app?" is the only confirmation — no dialog of the app's
///    own in front of it. Only while the app is in the foreground (else on
///    the next resume), and automatically once per version and start: a
///    cancelled confirm isn't popped up again in that start, but leaves a
///    slim "Update ready" banner whose Install reopens it. A build the user
///    asked for (a tap on Install / an older version) opens it as soon as it
///    is complete, also after an earlier cancel.
/// 3. Without the one-time "install unknown apps" switch, its settings
///    screen opens first (with a SnackBar saying why) and the install starts
///    when the user comes back.
///
/// The finished APK is remembered ([UpdateService.readyApk]) and reused
/// after a restart. If the silent download fails, a banner offers Retry,
/// which downloads it silently again.
class AutoUpdateFlow {
  AutoUpdateFlow({
    required this.navigatorKey,
    UpdateService Function()? service,
    bool Function()? canAsk,
  })  : _service = service ?? (() => UpdateService.instance),
        _canAsk = canAsk ?? (() => true);

  /// The running app's flow, for the changelog's pull-down and the About
  /// page; null in tests and off Android.
  static AutoUpdateFlow? current;

  final GlobalKey<NavigatorState> navigatorKey;
  final UpdateService Function() _service;

  /// False while something else owns the screen (intro, pickers); the
  /// install waits until the next check or coming back to the app.
  final bool Function() _canAsk;

  UpdateService get service => _service();

  final Set<String> _downloadingVersions = {};
  String? _failedVersion;
  ({String version, String path})? _ready;

  /// Versions Android's confirm was opened for automatically this start.
  final Set<String> _promptedVersions = {};

  /// A version the user tapped Install for: opened once it is complete,
  /// whatever was cancelled before.
  String? _requestedVersion;
  bool _installOnResume = false;
  bool _inForeground = true;

  /// What the banner shows right now: `ready:<version>`, `failed:<version>`
  /// or null — so a repeated poll doesn't re-show the same one.
  String? _banner;

  /// The version that is downloaded and waiting to be installed, if any.
  String? get readyVersion => _ready?.version;

  /// [readyVersion], for the Changelog's status card to follow.
  final ValueNotifier<String?> ready = ValueNotifier(null);

  /// The download running in the background right now (null when none),
  /// for passive inline text only.
  final ValueNotifier<UpdateDownload?> downloading = ValueNotifier(null);

  BuildContext? get _context => navigatorKey.currentContext;

  void onUpdateFound(UpdateInfo info) => unawaited(_downloadSilently(info));

  /// Pull-down on the changelog: checks right away and handles a newer build
  /// like the background poll does. Returns that build, or null when this
  /// is the newest; throws when GitHub can't be read.
  Future<UpdateInfo?> checkNow() async {
    final update = await service.checkForUpdate();
    if (update != null && update.apkUrl != null) {
      _failedVersion = null; // asked for: try the download again
      onUpdateFound(update);
    }
    return update;
  }

  /// App lifecycle: installs when coming back if a download finished
  /// meanwhile, or finishes an install that first needed the permission
  /// switch.
  void onLifecycleChanged(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    if (!_inForeground) return;
    if (_installOnResume) {
      _installOnResume = false;
      unawaited(installReady());
      return;
    }
    installWhenReady();
  }

  /// True while [version] downloads in the background.
  bool isDownloading(String version) => _downloadingVersions.contains(version);

  Future<void> _downloadSilently(UpdateInfo info) async {
    final version = info.version;
    if (isDownloading(version) || version == _failedVersion) return;
    if (_ready?.version == version) return installWhenReady();
    // Downloaded before (also by an earlier run): reuse it.
    final earlier = await service.readyApk(version);
    if (earlier != null) return _setReady(version, earlier);
    // An earlier run's download still going: [resumePending] watches it.
    final pending = await service.pendingDownload();
    if (pending != null && pending['version'] == version) return;
    if (isDownloading(version)) return;
    _downloadingVersions.add(version);
    downloading.value =
        (version: version, received: 0, total: info.apkSizeBytes);
    var failed = false;
    try {
      await for (final progress
          in service.downloadInBackground(info, silent: true)) {
        if (progress.status == DownloadStatus.successful &&
            progress.localPath != null) {
          _clearDownloading(version);
          _setReady(version, progress.localPath!);
        } else if (progress.status == DownloadStatus.failed) {
          failed = true;
        } else {
          downloading.value = (
            version: version,
            received: progress.bytesDownloaded,
            total: progress.bytesTotal ?? info.apkSizeBytes,
          );
        }
      }
    } catch (_) {
      failed = true;
    } finally {
      _clearDownloading(version);
    }
    if (failed) _downloadFailed(info);
  }

  void _clearDownloading(String version) {
    _downloadingVersions.remove(version);
    if (downloading.value?.version == version) downloading.value = null;
  }

  /// Picks up a background download an earlier run didn't see finish; if it
  /// completed while the app was closed, it is installed like any other.
  Future<void> resumePending() async {
    final pending = await service.pendingDownload();
    if (pending == null) return;
    final id = pending['downloadId'];
    final version = pending['version'] as String?;
    if (id is! int || version == null) {
      await service.clearPendingDownload();
      return;
    }
    _downloadingVersions.add(version);
    downloading.value = (version: version, received: 0, total: null);
    try {
      await for (final progress in service.watchDownload(id)) {
        if (progress.status == DownloadStatus.successful &&
            progress.localPath != null) {
          _clearDownloading(version);
          await service.markVersionDownloaded(version,
              path: progress.localPath);
          await service.clearPendingDownload();
          // Only if it is still newer than the running app.
          if (UpdateService.isNewerBuild(
              version, await service.currentVersionWithBuild())) {
            _setReady(version, progress.localPath!);
          }
        } else if (progress.status == DownloadStatus.failed) {
          await service.clearPendingDownload();
        } else {
          downloading.value = (
            version: version,
            received: progress.bytesDownloaded,
            total: progress.bytesTotal,
          );
        }
      }
    } catch (_) {
      // The next poll starts a fresh download if one is still needed.
    } finally {
      _clearDownloading(version);
    }
  }

  void _setReady(String version, String path) {
    _ready = (version: version, path: path);
    ready.value = version;
    if (_failedVersion == version) _failedVersion = null;
    installWhenReady();
  }

  /// Install on the Changelog status card or the About page (also an older
  /// build to go back to): opens Android's confirm right away when [info]'s
  /// APK is downloaded (also by an earlier run); otherwise downloads it
  /// silently — one SnackBar says so — and opens the confirm as soon as it
  /// is complete.
  Future<void> install(UpdateInfo info) async {
    _requestedVersion = info.version;
    if (_ready?.version != info.version) {
      final earlier = await service.readyApk(info.version);
      if (earlier == null) {
        _failedVersion = null; // asked for: try the download again
        _hideBanner();
        _snack(updateDownloadingSnack);
        await _downloadSilently(info);
        return;
      }
      _ready = (version: info.version, path: earlier);
      ready.value = info.version;
    }
    installWhenReady();
  }

  /// Opens Android's confirm for the downloaded build while the app is in
  /// the foreground: once per version and start on its own, or whenever the
  /// user asked for that build. Otherwise (cancelled before) the banner
  /// stays.
  void installWhenReady() {
    final ready = _ready;
    if (ready == null || !_inForeground || !_canAsk()) return;
    final requested = _requestedVersion == ready.version;
    if (!requested && _promptedVersions.contains(ready.version)) {
      _showReadyBanner(ready.version);
      return;
    }
    if (requested) _requestedVersion = null;
    _promptedVersions.add(ready.version);
    unawaited(installReady());
  }

  void _snack(String message) {
    final context = _context;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _hideBanner() {
    _banner = null;
    final context = _context;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentMaterialBanner();
  }

  void _showBanner(String id, MaterialBanner banner) {
    if (_banner == id) return;
    final context = _context;
    if (context == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    _banner = id;
    messenger
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(banner);
  }

  void _showReadyBanner(String version) => _showBanner('ready:$version',
      updateReadyBanner(version, () => unawaited(installReady())));

  void _downloadFailed(UpdateInfo info) {
    _failedVersion = info.version;
    if (_requestedVersion == info.version) _requestedVersion = null;
    _showBanner('failed:${info.version}',
        updateFailedBanner(info.version, () => unawaited(install(info))));
  }

  /// Hands the downloaded APK to Android: its "Update this app?" is the one
  /// confirmation. Whatever happens there (installed → the app restarts;
  /// cancelled or failed), the slim banner stays to reopen it.
  Future<void> installReady() async {
    final ready = _ready;
    if (ready == null) return;
    try {
      final outcome = await service.installApk(ready.path);
      if (outcome == 'needs-permission') {
        _installOnResume = true;
        _snack('Allow installs from ${service.appDisplayName} in the '
            'settings screen that just opened — the update installs when '
            'you come back.');
      }
    } catch (e) {
      _snack('Install failed: $e');
    }
    _showReadyBanner(ready.version);
  }
}

/// The slim bar that stays after Android's confirm was cancelled (or not
/// answered) until [version] is installed; Install reopens the confirm.
MaterialBanner updateReadyBanner(String version, VoidCallback onInstall) {
  return MaterialBanner(
    key: const Key('update.banner.ready'),
    leading: const Icon(Icons.system_update_outlined),
    content: Text('Update ready · v$version'),
    actions: [
      TextButton(
        key: const Key('update.banner.install'),
        onPressed: onInstall,
        child: const Text('Install'),
      ),
    ],
  );
}

/// The banner when the silent download of [version] failed: Retry
/// downloads it silently again, then opens Android's confirm.
MaterialBanner updateFailedBanner(String version, VoidCallback onRetry) {
  return MaterialBanner(
    key: const Key('update.banner.failed'),
    leading: const Icon(Icons.system_update_outlined),
    content: Text("v$version is available (the background download didn't "
        'finish)'),
    actions: [
      TextButton(
        key: const Key('update.banner.retry'),
        onPressed: onRetry,
        child: const Text('Retry'),
      ),
    ],
  );
}
