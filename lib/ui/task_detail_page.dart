import 'package:flutter/material.dart';
import '../models/task.dart';
import '../l10n/app_localizations.dart';

class TaskDetailPage extends StatelessWidget {
  final Task task;
  const TaskDetailPage({Key? key, required this.task}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.taskDetails)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(task.description),
            ],
            if (task.note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${l10n.note}: ${task.note}'),
            ],
            if (task.label.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${l10n.label}: ${task.label}'),
            ],
            if (task.dueDate != null) ...[
              const SizedBox(height: 8),
              Text('${l10n.due}: ${task.dueDate!.toLocal().toString().split(' ')[0]}'),
            ],
            const SizedBox(height: 8),
            Text('${l10n.completed}: ${task.isDone ? l10n.yes : l10n.no}'),
          ],
        ),
      ),
    );
  }
}
