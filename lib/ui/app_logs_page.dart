import 'package:flutter/material.dart';

import '../models/sync_log_entry.dart';
import '../services/log_service.dart';
import '../services/sync_service.dart';
import '../services/todoist_sync_service.dart';
import 'subpage_app_bar.dart';

/// Displays logs collected during app interactions and widget updates, plus
/// the history of background syncs (Sync tab) and Todoist syncs (Todoist
/// tab). Opening the page acknowledges a failed sync on either, clearing the
/// red dot on the drawer's App Logs entry.
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
    TodoistSyncService.instance.ensureLoaded().then((_) {
      TodoistSyncService.instance.markErrorSeen();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: buildSubpageAppBar(
          context,
          title: 'App Logs',
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Logs'),
              Tab(text: 'Sync'),
              Tab(text: 'Todoist'),
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
            ValueListenableBuilder<List<SyncLogEntry>>(
              valueListenable: TodoistSyncService.instance.entries,
              builder: (context, entries, _) {
                if (entries.isEmpty) {
                  return const Center(child: Text('No Todoist syncs yet'));
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) =>
                      _SyncEntryTile(entry: entries[index], isTodoist: true),
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
  final bool isTodoist;
  const _SyncEntryTile({required this.entry, this.isTodoist = false});

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = entry.at;
    final stamp = '${_two(at.day)}.${_two(at.month)}.${at.year % 100} '
        '${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}';
    final noun = isTodoist ? 'change' : 'item';
    return ListTile(
      dense: true,
      leading: Icon(
        entry.success ? Icons.check_circle : Icons.error,
        color: entry.success ? Colors.green : theme.colorScheme.error,
      ),
      title: Text(
        entry.success
            ? 'Synced ${entry.itemCount} '
                '$noun${entry.itemCount == 1 ? '' : 's'} '
                'in ${entry.durationMs} ms'
            : 'Sync failed: ${entry.message}',
      ),
      subtitle: Text('$stamp · ${entry.trigger}'),
    );
  }
}
