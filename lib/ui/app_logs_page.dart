import 'dart:io' show File, Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/sync_log_entry.dart';
import '../services/device_log_service.dart';
import '../services/log_service.dart';
import '../services/sync_service.dart';
import 'subpage_app_bar.dart';

/// Displays logs collected during app interactions and widget updates, the
/// Android-side breadcrumbs (Device), and the history of background syncs
/// (Sync). Opening the page acknowledges a failed sync, clearing the red dot
/// on the drawer's App Logs entry.
///
/// The copy button hands over both logs at once — that is the bundle to paste
/// into a bug report, and the reason both are written to files: the widget
/// black screen is only recoverable with a force-close, which takes anything
/// kept in memory with it. The export button writes the same bundle to a
/// `.txt` file, untrimmed: a paste has to survive a chat box, a file does
/// not, so exporting is what to reach for when the interesting entry might be
/// further back than the copy's tail.
class AppLogsPage extends StatefulWidget {
  const AppLogsPage({Key? key}) : super(key: key);

  @override
  State<AppLogsPage> createState() => _AppLogsPageState();
}

class _AppLogsPageState extends State<AppLogsPage> {
  String? _deviceLog;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    SyncService.instance.ensureLoaded().then((_) {
      SyncService.instance.markErrorSeen();
    });
    // The copy header names the build the logs came from.
    Config.ensureVersionLoaded();
    _loadDeviceLog();
  }

  Future<void> _loadDeviceLog() async {
    final content = await DeviceLogService.read();
    if (!mounted) return;
    setState(() => _deviceLog = content);
  }

  /// How many trailing lines of each log the report carries. A pasted report
  /// gets truncated somewhere, and what matters is always the end.
  static const int _deviceLines = 250;
  static const int _appLines = 150;

  /// Everything worth sharing, in one block: app version, then the **device
  /// log first**. The app log used to lead, and the first field report of a
  /// black screen was cut off exactly at the device half — which is the only
  /// half that records the failure, because the Dart side logs nothing at all
  /// while the screen is black. Both are trimmed to their newest lines for the
  /// same reason — unless [full] is set, which is the export: a file has no
  /// paste limit to survive, so it carries every line there is.
  ///
  /// Always re-reads the device log from disk instead of reusing [_deviceLog]
  /// (which is only loaded once, in `initState`): two reports pulled minutes
  /// apart during the same page visit were coming back with byte-identical
  /// device halves — every native breadcrumb written after the page opened
  /// was silently missing, which is exactly the "device log went silent"
  /// shape earlier field reports blamed on the engine.
  Future<String> _report({bool full = false}) async {
    final appLog = await LogService.readFile();
    final device = await DeviceLogService.read();
    if (mounted) setState(() => _deviceLog = device);
    return 'BestToDo ${Config.versionWithBuild} — app logs\n'
        'exported ${DateTime.now().toIso8601String()}\n\n'
        '===== DEVICE LOG (Android) =====\n'
        '${_tail(device, full ? null : _deviceLines)}\n\n'
        '===== APP LOG =====\n'
        '${_tail(appLog, full ? null : _appLines)}\n';
  }

  /// The last [maxLines] lines, saying so when anything was left out. A null
  /// [maxLines] keeps everything.
  static String _tail(String content, int? maxLines) {
    final lines =
        content.trim().split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return '(empty)';
    if (maxLines == null || lines.length <= maxLines) return lines.join('\n');
    final kept = lines.sublist(lines.length - maxLines);
    return '(showing the last $maxLines of ${lines.length} lines)\n'
        '${kept.join('\n')}';
  }

  Future<void> _copyAll() async {
    final report = await _report();
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logs copied — paste them into your report'),
      ),
    );
  }

  /// Writes the whole bundle to a `.txt` in a folder the user picks. Same
  /// shape as the other exports in the app (SMS history, usage data): offer
  /// Downloads as the starting point where the platform has one, timestamp
  /// the filename so repeated exports never overwrite each other.
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
      final report = await _report(full: true);
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

  Future<void> _clearAll() async {
    LogService.clear();
    await DeviceLogService.clear();
    if (!mounted) return;
    setState(() => _deviceLog = '');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
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
              Tab(text: 'Device'),
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
            _DeviceLogView(content: _deviceLog, onRefresh: _loadDeviceLog),
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
          onPressed: _clearAll,
          tooltip: 'Clear logs',
          child: const Icon(Icons.delete),
        ),
      ),
    );
  }
}

/// The Android-side breadcrumb file: activity lifecycle, the intent behind
/// each launch, and whether the window actually drew anything after a resume.
class _DeviceLogView extends StatelessWidget {
  const _DeviceLogView({required this.content, required this.onRefresh});

  final String? content;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final text = content;
    if (text == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            text.trim().isEmpty ? 'No device entries yet' : text.trim(),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
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
