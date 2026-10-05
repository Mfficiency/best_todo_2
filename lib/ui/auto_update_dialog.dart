import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Starts [info]'s download on Android's `DownloadManager` and installs it
/// the moment it finishes — no blocking dialog, since the transfer itself now
/// runs as a system service independent of the app (see
/// [UpdateService.downloadInBackground]): it keeps going if the app is
/// backgrounded and rides out a Wi-Fi/mobile handover mid-download. Progress
/// and failures surface as brief snackbars instead of a modal that would
/// otherwise sit in front of the app for the whole download.
///
/// Called straight from the background auto-update check (`AutoUpdateChecker`
/// in `main.dart`/`main_music.dart`) with no "Download?" question first —
/// Android's own install prompt is the only gate. Returns true once the APK
/// was downloaded and handed to the installer, false on failure.
Future<bool> downloadUpdateInBackground(
    BuildContext context, UpdateInfo info, {UpdateService? service}) async {
  final updateService = service ?? UpdateService.instance;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(SnackBar(
    content: Text('Downloading v${info.version} in the background…'),
  ));
  try {
    await for (final progress in updateService.downloadInBackground(info)) {
      if (progress.status == DownloadStatus.successful &&
          progress.localPath != null) {
        await updateService.installApk(progress.localPath!);
        return true;
      } else if (progress.status == DownloadStatus.failed) {
        messenger?.showSnackBar(SnackBar(
          content: Text('Update download failed${progress.reason != null ? ' (${progress.reason})' : ''}.'),
        ));
        return false;
      }
    }
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Update download failed: $e')));
  }
  return false;
}
