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

/// Downloads [info]'s APK and hands it to the installer as soon as it opens,
/// showing progress while it works. Pops itself on success; on failure it
/// swaps to an error message with a dismiss button instead of closing on its
/// own, so the failure is not missed.
class UpdateDownloadDialog extends StatefulWidget {
  const UpdateDownloadDialog({super.key, required this.info});

  final UpdateInfo info;

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  int _received = 0;
  int? _total;
  String? _error;

  @override
  void initState() {
    super.initState();
    _total = widget.info.apkSizeBytes;
    _run();
  }

  Future<void> _run() async {
    try {
      final file = await UpdateService.instance.downloadApk(
        widget.info,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total ?? _total;
          });
        },
      );
      await UpdateService.instance.installApk(file.path);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return AlertDialog(
        title: const Text('Update failed'),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    }
    final total = _total;
    final progress = (total != null && total > 0) ? _received / total : null;
    return AlertDialog(
      title: Text('Downloading v${widget.info.version}…'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 12),
          Text(progress != null
              ? '${(progress * 100).toStringAsFixed(0)}%'
              : ''),
        ],
      ),
    );
  }
}
