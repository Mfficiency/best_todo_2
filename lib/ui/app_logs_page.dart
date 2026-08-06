import 'package:flutter/material.dart';

import '../models/sync_log_entry.dart';
import '../services/log_service.dart';
import '../services/sync_service.dart';
import 'subpage_app_bar.dart';

/// Displays logs collected during app interactions and widget updates, plus
/// the history of background syncs (Sync tab). Opening the page acknowledges
/// a failed sync, clearing the red dot on the drawer's App Logs entry.
class AppLogsPage extends StatefulWidget {
  const AppLogsPage({Key? key}) : super(key: key);

  @override
  State<AppLogsPage> createState() => _AppLogsPageState();
}

class _AppLogsPageState extends State<AppLogsPage> {
  @override
  void initState() {
    super.initState();
    SyncService.instance.ensureLoaded().then((_) {
      SyncService.instance.markErrorSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: buildSubpageAppBar(
          context,
          title: 'App Logs',
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
