import 'package:flutter/material.dart';
import '../config.dart';
import '../models/task.dart';
import '../models/view_filter_rules.dart';
import '../utils/linkified_text.dart';
import 'subpage_app_bar.dart';
import 'task_detail_page.dart';

/// The real Deleted bin: tasks denied from Waiting for Approval, or sent on
/// from Archived Items. Unlike the archive, entries here age out on their
/// own — [Config.deletedItemsRetentionDays] days after landing here, they are
/// purged for good (see `StorageService.loadBinTaskList`).
class DeletedBinPage extends StatelessWidget {
  final List<Task> items;
  final void Function(Task task) onRestore;
  final void Function(Task task) onDeletePermanently;
  const DeletedBinPage({
    Key? key,
    required this.items,
    required this.onRestore,
    required this.onDeletePermanently,
  }) : super(key: key);

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final retentionDays = Config.deletedItemsRetentionDays;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Deleted Items'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Items here are purged for good $retentionDays days after '
                'landing in the bin (Settings → Tasks).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final task = items[index];
                final deletedText = task.deletedAt != null
                    ? 'Deleted: ${_formatDate(task.deletedAt!)}'
                    : 'Deleted: Unknown date';
                final subtitle = task.description.isNotEmpty
                    ? '${task.description}\n$deletedText'
                    : deletedText;
                return ListTile(
                  leading: IconButton(
                    icon: const Icon(Icons.restore),
                    tooltip: 'Restore',
                    onPressed: () => onRestore(task),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_forever),
                    tooltip: 'Delete permanently',
                    onPressed: () => onDeletePermanently(task),
                  ),
                  title: LinkifiedText(task.title),
                  subtitle: LinkifiedText(subtitle),
                  isThreeLine: task.description.isNotEmpty,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TaskDetailPage(
                          task: task,
                          viewId: ViewFilterRules.bin,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
