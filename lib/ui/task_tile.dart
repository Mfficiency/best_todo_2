import 'package:flutter/material.dart';
import '../models/task.dart';

class TaskTile extends StatelessWidget {
  final Task task;
  final VoidCallback onChanged;
  final VoidCallback onSwiped;

  const TaskTile({
    Key? key,
    required this.task,
    required this.onChanged,
    required this.onSwiped,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: task.isDone,
        onChanged: (_) => onChanged(),
      ),
      title: Text(
        task.title,
        style: TextStyle(
          decoration: task.isDone ? TextDecoration.lineThrough : null,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.swipe),
        tooltip: 'Move to next page',
        onPressed: onSwiped,
      ),
    );
  }
}
