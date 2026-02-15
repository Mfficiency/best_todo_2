import 'package:flutter/material.dart';
import '../models/task.dart';
import 'task_detail_page.dart';

class DeletedItemsPage extends StatelessWidget {
  final List<Task> items;
  final void Function(Task task) onRestore;
  final void Function(Task task) onDeletePermanently;
  const DeletedItemsPage({
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
    return Scaffold(
      appBar: AppBar(title: const Text('Deleted Items')),
      body: ListView.builder(
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
            title: Text(task.title),
            subtitle: Text(subtitle),
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
