import 'dart:async' show unawaited;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/music_library_service.dart';
import 'subpage_app_bar.dart';

/// Best Music's Settings page: just the music folder and its excluded
/// subfolders — the same `Config.musicFolder`/`musicExcludedSubfolders`
/// fields and `MusicLibraryService` calls as BestToDo's Settings → Music
/// Player section (`lib/ui/settings_page.dart`), reimplemented standalone
/// since that page is a single monolithic widget tightly coupled to
/// BestToDo's full settings list.
class MusicSettingsPage extends StatefulWidget {
  const MusicSettingsPage({super.key});

  @override
  State<MusicSettingsPage> createState() => _MusicSettingsPageState();
}

class _MusicSettingsPageState extends State<MusicSettingsPage> {
  Future<void> _pickFolder() async {
    await MusicLibraryService.instance.ensureFolderPermission();
    final directory = await getDirectoryPath(
      initialDirectory:
          Config.musicFolder.isNotEmpty ? Config.musicFolder : null,
    );
    if (directory == null) return;
    setState(() {
      Config.musicFolder = directory;
      Config.musicExcludedSubfolders = [];
    });
    await Config.save();
    unawaited(MusicLibraryService.instance.rescan());
  }

  Future<void> _clearFolder() async {
    setState(() {
      Config.musicFolder = '';
      Config.musicExcludedSubfolders = [];
    });
    await Config.save();
    unawaited(MusicLibraryService.instance.rescan());
  }

  Future<void> _openExclusionsDialog() async {
    final subfolders = await MusicLibraryService.instance.listSubfolders();
    if (!mounted) return;
    if (subfolders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No subfolders found under the music folder'),
      ));
      return;
    }
    final excluded = {...Config.musicExcludedSubfolders};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Excluded subfolders'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final folder in subfolders)
                      CheckboxListTile(
                        value: excluded.contains(folder),
                        title: Text(folder),
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              excluded.add(folder);
                            } else {
                              excluded.remove(folder);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    setState(() {
                      Config.musicExcludedSubfolders = excluded.toList();
                    });
                    await Config.save();
                    unawaited(MusicLibraryService.instance.rescan());
                    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chosen = Config.musicFolder.isNotEmpty;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Settings'),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Music folder'),
            subtitle: Text(chosen
                ? Config.musicFolder
                : 'Not set — choose the folder your music lives in'),
            trailing: const Icon(Icons.folder_open),
            onTap: _pickFolder,
          ),
          if (chosen) ...[
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('Forget this folder'),
              onTap: _clearFolder,
            ),
            ListTile(
              leading: const Icon(Icons.rule_folder_outlined),
              title: const Text('Excluded subfolders'),
              subtitle: Text(Config.musicExcludedSubfolders.isEmpty
                  ? 'None — every subfolder is included'
                  : Config.musicExcludedSubfolders.join(', ')),
              onTap: _openExclusionsDialog,
            ),
          ],
        ],
      ),
    );
  }
}
