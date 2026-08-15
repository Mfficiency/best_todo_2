import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
/// kept in memory with it.
class AppLogsPage extends StatefulWidget {
  const AppLogsPage({Key? key}) : super(key: key);

  @override
  State<AppLogsPage> createState() => _AppLogsPageState();
}

class _AppLogsPageState extends State<AppLogsPage> {
  String? _deviceLog;

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

  /// Everything worth sharing, in one block: app version, the app log (from
  /// the file, so it includes the runs before the last force-close) and the
  /// Android breadcrumbs.
  Future<String> _report() async {
    final appLog = await LogService.readFile();
    final device = _deviceLog ?? await DeviceLogService.read();
    return 'BestToDo ${Config.versionWithBuild} — app logs\n'
        'exported ${DateTime.now().toIso8601String()}\n\n'
        '===== APP LOG =====\n'
        '${appLog.trim().isEmpty ? '(empty)' : appLog.trim()}\n\n'
        '===== DEVICE LOG (Android) =====\n'
        '${device.trim().isEmpty ? '(empty)' : device.trim()}\n';
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
