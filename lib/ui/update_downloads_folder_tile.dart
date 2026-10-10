import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/update_service.dart';

/// Settings row showing where in-app update APKs are downloaded to
/// ([UpdateService.updateDownloadsDirectory]), with a copy-path button.
/// Shared by BestToDo's Settings → Updates and Best Music's Settings, each
/// passing its own [UpdateService] instance.
class UpdateDownloadsFolderTile extends StatefulWidget {
  const UpdateDownloadsFolderTile({super.key, required this.updateService});

  final UpdateService updateService;

  @override
  State<UpdateDownloadsFolderTile> createState() =>
      _UpdateDownloadsFolderTileState();
}

class _UpdateDownloadsFolderTileState extends State<UpdateDownloadsFolderTile> {
  late final Future<String?> _path =
      widget.updateService.updateDownloadsDirectory();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _path,
      builder: (context, snapshot) {
        final path = snapshot.data;
        final String subtitle;
        if (snapshot.connectionState != ConnectionState.done) {
          subtitle = 'Loading…';
        } else if (path == null) {
          subtitle = 'Not available — updates are only downloaded in-app on '
              'Android';
        } else {
          subtitle = path;
        }
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Update downloads folder'),
          subtitle: Text(subtitle),
          trailing: path == null
              ? null
              : IconButton(
                  tooltip: 'Copy path',
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: path));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Folder path copied')),
                    );
                  },
                ),
        );
      },
    );
  }
}
