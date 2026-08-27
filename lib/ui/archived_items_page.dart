import 'package:flutter/material.dart';
import '../models/task.dart';
import '../utils/linkified_text.dart';
import 'subpage_app_bar.dart';
import 'task_detail_page.dart';

/// Where a task lands after a normal delete (swipe, Chronize, wishlist) or an
/// end-of-day auto-clear of a finished task — a soft archive, not a real
/// deletion. Restorable here, or sent on to the real [Icons.delete_forever]
/// bin (see the app bar action), where [Task.deletedAt] finally ages out.
class ArchivedItemsPage extends StatelessWidget {
  final List<Task> items;
  final void Function(Task task) onRestore;
  final void Function(Task task) onMoveToBin;
  final VoidCallback onOpenBin;
  const ArchivedItemsPage({
    Key? key,
    required this.items,
    required this.onRestore,
    required this.onMoveToBin,
    required this.onOpenBin,
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
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Archived Items',
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: 'Deleted items (bin)',
            onPressed: onOpenBin,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final task = items[index];
          final archivedLabel =
              task.autoDeleted ? 'Automatically archived' : 'Archived';
          final archivedText = task.deletedAt != null
              ? '$archivedLabel: ${_formatDate(task.deletedAt!)}'
              : '$archivedLabel: Unknown date';
          final subtitle = task.description.isNotEmpty
              ? '${task.description}\n$archivedText'
              : archivedText;
          return ListTile(
            leading: IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'Restore',
              onPressed: () => onRestore(task),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Move to bin',
              onPressed: () => onMoveToBin(task),
            ),
            title: LinkifiedText(task.title),
            subtitle: LinkifiedText(subtitle),
            isThreeLine: task.description.isNotEmpty,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TaskDetailPage(task: task),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
