import 'dart:async';

import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// The automatic update of a running app (BestToDo in `main.dart`, Best
/// Music in `main_music.dart`; same flow as BestCollage and Hally Remote):
///
/// 1. A newer build found by the background poll ([onUpdateFound]) or a
///    pull-down on the changelog ([checkNow]) downloads **silently** with
///    Android's `DownloadManager` — no question, no notification.
/// 2. Only when the APK is complete does the app ask: an "Update ready"
///    dialog, once per version and start, while the app is in the
///    foreground. Later leaves a banner that stays until it is installed.
/// 3. Nothing installs without a tap: Install hands the APK to a
///    PackageInstaller session (`ApkInstaller.kt`), so Android's "Update
///    this app?" is the only step left. Without the one-time "install
///    unknown apps" switch, that opens first and the install starts when
///    the user comes back.
///
/// The finished APK is remembered ([UpdateService.readyApk]) and reused
/// after a restart. If the silent download fails, a banner offers Install,
/// which downloads it again in the foreground and installs it.
class AutoUpdateFlow {
  AutoUpdateFlow({
    required this.navigatorKey,
    UpdateService Function()? service,
    bool Function()? canAsk,
  })  : _service = service ?? (() => UpdateService.instance),
        _canAsk = canAsk ?? (() => true);

  /// The running app's flow, for the changelog's pull-down; null in tests
  /// and off Android.
  static AutoUpdateFlow? current;

  final GlobalKey<NavigatorState> navigatorKey;
  final UpdateService Function() _service;

  /// False while something else owns the screen (intro, pickers); the
  /// question waits until the next check or coming back to the app.
  final bool Function() _canAsk;

  UpdateService get service => _service();

  String? _downloadingVersion;
  String? _failedVersion;
  ({String version, String path})? _ready;
  String? _askedVersion;
  String? _bannerVersion;
  bool _installOnResume = false;
  bool _inForeground = true;

  /// The version that is downloaded and waiting for a tap, if any.
  String? get readyVersion => _ready?.version;

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

  /// App lifecycle: asks when coming back if a download finished meanwhile,
  /// and finishes an install that first needed the permission switch.
  void onLifecycleChanged(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    if (!_inForeground) return;
    if (_installOnResume) {
      _installOnResume = false;
      unawaited(installReady());
      return;
    }
    askWhenReady();
  }

  Future<void> _downloadSilently(UpdateInfo info) async {
    final version = info.version;
    if (version == _downloadingVersion || version == _failedVersion) return;
    if (_ready?.version == version) return askWhenReady();
    // Downloaded before (also by an earlier run): reuse it.
    final earlier = await service.readyApk(version);
    if (earlier != null) return _setReady(version, earlier);
    // An earlier run's download still going: [resumePending] watches it.
    final pending = await service.pendingDownload();
    if (pending != null && pending['version'] == version) return;
    if (_downloadingVersion == version) return;
    _downloadingVersion = version;
    try {
      await for (final progress
          in service.downloadInBackground(info, silent: true)) {
        if (progress.status == DownloadStatus.successful &&
            progress.localPath != null) {
          _setReady(version, progress.localPath!);
        } else if (progress.status == DownloadStatus.failed) {
          _downloadFailed(info);
        }
      }
    } catch (_) {
      _downloadFailed(info);
    } finally {
      if (_downloadingVersion == version) _downloadingVersion = null;
    }
  }

  /// Picks up a background download an earlier run didn't see finish; if it
  /// completed while the app was closed, the app asks to install it.
  Future<void> resumePending() async {
    final pending = await service.pendingDownload();
    if (pending == null) return;
    final id = pending['downloadId'];
    final version = pending['version'] as String?;
    if (id is! int || version == null) {
      await service.clearPendingDownload();
      return;
    }
    _downloadingVersion = version;
    try {
      await for (final progress in service.watchDownload(id)) {
        if (progress.status == DownloadStatus.successful &&
            progress.localPath != null) {
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
        }
      }
    } catch (_) {
      // The next poll starts a fresh download if one is still needed.
    } finally {
      if (_downloadingVersion == version) _downloadingVersion = null;
    }
  }

  void _setReady(String version, String path) {
    _ready = (version: version, path: path);
    askWhenReady();
  }

  /// Once per version and start, while the app is in the foreground: the
  /// download is complete, install now? Later leaves a banner.
  void askWhenReady() {
    final ready = _ready;
    final context = _context;
    if (ready == null || context == null || !_inForeground || !_canAsk()) {
      return;
    }
    if (_askedVersion == ready.version) return;
    _askedVersion = ready.version;
    unawaited(() async {
      final install = await showUpdateReadyDialog(
          context, service.appDisplayName, ready.version);
      if (install == true) {
        await installReady();
      } else {
        _showBanner(updateReadyBanner(
            ready.version, () => unawaited(installReady())));
        _bannerVersion = ready.version;
      }
    }());
  }

  void _showBanner(MaterialBanner banner) {
    final context = _context;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentMaterialBanner()
      ..showMaterialBanner(banner);
  }

  void _downloadFailed(UpdateInfo info) {
    _failedVersion = info.version;
    if (_bannerVersion == info.version) return;
    _bannerVersion = info.version;
    _showBanner(updateAvailableBanner(
        info.version, () => unawaited(_downloadAndInstall(info))));
  }

  /// The failed-download banner's Install: download in the foreground (with
  /// Android's download notification as progress), then install.
  Future<void> _downloadAndInstall(UpdateInfo info) async {
    if (_downloadingVersion == info.version) return;
    _downloadingVersion = info.version;
    final context = _context;
    if (context != null) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentMaterialBanner()
        ..showSnackBar(
            SnackBar(content: Text('Downloading v${info.version}…')));
    }
    String? path;
    try {
      await for (final progress in service.downloadInBackground(info)) {
        if (progress.status == DownloadStatus.successful) {
          path = progress.localPath;
        }
      }
    } catch (_) {
      // Shown as the banner again below.
    } finally {
      if (_downloadingVersion == info.version) _downloadingVersion = null;
    }
    if (path == null) {
      _bannerVersion = null;
      _downloadFailed(info);
      return;
    }
    _failedVersion = null;
    _ready = (version: info.version, path: path);
    _askedVersion = info.version; // Install was tapped already: no dialog
    await installReady();
  }

  /// Hands the downloaded APK to Android (only ever after a tap on Install).
  Future<void> installReady() async {
    final ready = _ready;
    if (ready == null) return;
    try {
      final outcome = await service.installApk(ready.path);
      if (outcome == 'needs-permission') _installOnResume = true;
    } catch (e) {
      final context = _context;
      if (context != null) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('Install failed: $e')));
      }
    }
    // Cancelled in Android's dialog or failed: the banner stays.
    _bannerVersion = ready.version;
    _showBanner(
        updateReadyBanner(ready.version, () => unawaited(installReady())));
  }
}

/// "Update ready" — shown once per start when the automatic background
/// download of [version] is complete.
Future<bool?> showUpdateReadyDialog(
    BuildContext context, String appName, String version) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.system_update_outlined),
      title: const Text('Update ready'),
      content: Text('$appName v$version was downloaded in the background. '
          'Install it now? The app restarts; your data stays.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
        FilledButton(
          key: const Key('update.ready.install'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Install'),
        ),
      ],
    ),
  );
}

/// The banner that stays after "Later" until [version] is installed.
MaterialBanner updateReadyBanner(String version, VoidCallback onInstall) {
  return MaterialBanner(
    leading: const Icon(Icons.system_update_outlined),
    content: Text('v$version is downloaded and ready to install'),
    actions: [
      TextButton(
        key: const Key('update.banner.install'),
        onPressed: onInstall,
        child: const Text('Install'),
      ),
    ],
  );
}

/// The banner when the background download of [version] failed: Install
/// downloads it again in the foreground, then installs it.
MaterialBanner updateAvailableBanner(String version, VoidCallback onInstall) {
  return MaterialBanner(
    leading: const Icon(Icons.system_update_outlined),
    content: Text("v$version is available (the background download didn't "
        'finish)'),
    actions: [
      TextButton(
        key: const Key('update.banner.download'),
        onPressed: onInstall,
        child: const Text('Install'),
      ),
    ],
  );
}
