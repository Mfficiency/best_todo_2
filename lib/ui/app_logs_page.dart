import 'dart:io' show File, Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/sync_log_entry.dart';
import '../services/log_service.dart';
import '../services/sync_service.dart';
import 'subpage_app_bar.dart';

/// Displays logs collected during app interactions and widget updates, plus
/// the history of background syncs (Sync tab). Opening the page acknowledges
/// a failed sync, clearing the red dot on the drawer's App Logs entry.
///
/// The copy button puts the current logs on the clipboard, versioned and
/// timestamped, for pasting into a bug report. The export button writes the
/// same content to a `.txt` file instead: handy when the log is too long for
/// a paste to survive a chat box.
class AppLogsPage extends StatefulWidget {
  const AppLogsPage({Key? key}) : super(key: key);

  @override
  State<AppLogsPage> createState() => _AppLogsPageState();
}

class _AppLogsPageState extends State<AppLogsPage> {
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    SyncService.instance.ensureLoaded().then((_) {
      SyncService.instance.markErrorSeen();
    });
    // The copy/export header names the build the logs came from.
    Config.ensureVersionLoaded();
  }

  String _report() {
    final lines = LogService.logs.value;
    final body = lines.isEmpty ? '(empty)' : lines.join('\n');
    return 'BestToDo ${Config.versionWithBuild} — app logs\n'
        'exported ${DateTime.now().toIso8601String()}\n\n'
        '$body\n';
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _report()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copied — paste them into your report'),
      ),
    );
  }

  /// Writes the log to a `.txt` in a folder the user picks. Same shape as the
  /// other exports in the app (SMS history, usage data): offer Downloads as
  /// the starting point where the platform has one, timestamp the filename so
  /// repeated exports never overwrite each other.
  Future<void> _export() async {
    if (_exporting) return;
    final messenger = ScaffoldMessenger.of(context);
    String? downloads;
    try {
      downloads = (await getDownloadsDirectory())?.path;
    } catch (_) {
      // Android has no downloads directory to suggest — the picker opens
      // wherever it likes instead.
    }
    final directory = await getDirectoryPath(initialDirectory: downloads);
    if (directory == null) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Export canceled')));
      return;
    }
    setState(() => _exporting = true);
    try {
      final report = _report();
      final sep = Platform.pathSeparator;
      final path = '$directory${directory.endsWith(sep) ? '' : sep}'
          'besttodo_logs_${_timestampForFilename()}.txt';
      await File(path).writeAsString(report, flush: true);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Exported to $path')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static String _timestampForFilename() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: buildSubpageAppBar(
          context,
          title: 'App Logs',
          actions: [
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy logs',
              onPressed: _copyAll,
            ),
            IconButton(
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt),
              tooltip: 'Export logs to a file',
              onPressed: _exporting ? null : _export,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Logs'),
              Tab(text: 'Sync'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ValueListenableBuilder<List<String>>(
              valueListenable: LogService.logs,
              builder: (context, logs, _) {
                if (logs.isEmpty) {
                  return const Center(child: Text('No logs yet'));
                }
                return ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    title: Text(logs[index]),
                  ),
                );
              },
            ),
            ValueListenableBuilder<List<SyncLogEntry>>(
              valueListenable: SyncService.instance.entries,
              builder: (context, entries, _) {
                if (entries.isEmpty) {
                  return const Center(child: Text('No syncs yet'));
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _SyncEntryTile(entry: entries[index]),
                );
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: LogService.clear,
          tooltip: 'Clear logs',
          child: const Icon(Icons.delete),
        ),
      ),
    );
  }
}

class _SyncEntryTile extends StatelessWidget {
  final SyncLogEntry entry;
  const _SyncEntryTile({required this.entry});

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = entry.at;
    final stamp = '${_two(at.day)}.${_two(at.month)}.${at.year % 100} '
        '${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}';
    return ListTile(
      dense: true,
      leading: Icon(
        entry.success ? Icons.check_circle : Icons.error,
        color: entry.success ? Colors.green : theme.colorScheme.error,
      ),
      title: Text(
        entry.success
            ? 'Synced ${entry.itemCount} '
                '${entry.itemCount == 1 ? 'item' : 'items'} '
                'in ${entry.durationMs} ms'
            : 'Sync failed: ${entry.message}',
      ),
      subtitle: Text('$stamp · ${entry.trigger}'),
    );
  }
}
