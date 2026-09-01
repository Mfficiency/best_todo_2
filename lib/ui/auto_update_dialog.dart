import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// "New version available" prompt shown by the background auto-update check
/// (`AutoUpdateChecker` in `main.dart`). Yes goes straight into download +
/// install with no further confirmation — Android's own install prompt is
/// the only gate left, same as the About page's "Download & install".
Future<bool?> showUpdateAvailableDialog(
    BuildContext context, UpdateInfo info) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('New version available'),
      content: Text(
          'Version ${info.version} is available. Do you want to download '
          'and install it?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('No'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );
}

/// Starts [info]'s download on Android's `DownloadManager` and installs it
/// the moment it finishes — no blocking dialog, since the transfer itself now
/// runs as a system service independent of the app (see
/// [UpdateService.downloadInBackground]): it keeps going if the app is
/// backgrounded and rides out a Wi-Fi/mobile handover mid-download. Progress
/// and failures surface as brief snackbars instead of a modal that would
/// otherwise sit in front of the app for the whole download.
Future<void> downloadUpdateInBackground(
    BuildContext context, UpdateInfo info) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(SnackBar(
    content: Text('Downloading v${info.version} in the background…'),
  ));
  try {
    await for (final progress
        in UpdateService.instance.downloadInBackground(info)) {
      if (progress.status == DownloadStatus.successful &&
          progress.localPath != null) {
        await UpdateService.instance.installApk(progress.localPath!);
      } else if (progress.status == DownloadStatus.failed) {
        messenger?.showSnackBar(SnackBar(
          content: Text('Update download failed${progress.reason != null ? ' (${progress.reason})' : ''}.'),
        ));
      }
    }
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text('Update download failed: $e')));
  }
}
