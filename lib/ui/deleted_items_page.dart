import 'package:flutter/material.dart';
import '../models/task.dart';
import 'task_detail_page.dart';
import '../l10n/app_localizations.dart';

class DeletedItemsPage extends StatelessWidget {
  final List<Task> items;
  final void Function(Task task) onRestore;
  const DeletedItemsPage({
    Key? key,
    required this.items,
    required this.onRestore,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.deletedItems)),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final task = items[index];
          return ListTile(
            leading: IconButton(
              icon: const Icon(Icons.restore),
              tooltip: l10n.restore,
              onPressed: () => onRestore(task),
            ),
            title: Text(task.title),
            subtitle: task.description.isNotEmpty ? Text(task.description) : null,
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
