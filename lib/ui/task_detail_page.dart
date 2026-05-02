import 'package:flutter/material.dart';
import '../models/task.dart';
import 'subpage_app_bar.dart';

class TaskDetailPage extends StatelessWidget {
  final Task task;
  const TaskDetailPage({Key? key, required this.task}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Task Details'),
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
              Text('Note: ${task.note}'),
            ],
            if (task.label.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Label: ${task.label}'),
            ],
            if (task.dueDate != null) ...[
              const SizedBox(height: 8),
              Text('Due: ${task.dueDate!.toLocal().toString().split(' ')[0]}'),
            ],
            const SizedBox(height: 8),
            Text('Completed: ${task.isDone ? 'Yes' : 'No'}'),
          ],
        ),
      ),
    );
  }
}
