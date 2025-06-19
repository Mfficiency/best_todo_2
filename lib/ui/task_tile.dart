import 'package:flutter/material.dart';
import 'dart:async';
import '../models/task.dart';

class TaskTile extends StatefulWidget {
  final Task task;
  final VoidCallback onChanged;
  final void Function(int destination) onMove;

  const TaskTile({
    Key? key,
    required this.task,
    required this.onChanged,
    required this.onMove,
  }) : super(key: key);

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile> {
  bool _showOptions = false;
  Timer? _timer;

  void _startOptions() {
    setState(() => _showOptions = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted && _showOptions) {
        widget.onMove(1); // default to tomorrow
        setState(() => _showOptions = false);
      }
    });
  }

  void _select(int dest) {
    _timer?.cancel();
    widget.onMove(dest);
    setState(() => _showOptions = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: widget.task.isDone,
        onChanged: (_) => widget.onChanged(),
      ),
      title: Text(
        widget.task.title,
        style: TextStyle(
          decoration: widget.task.isDone ? TextDecoration.lineThrough : null,
        ),
      ),
      trailing: _showOptions
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => _select(1),
                  child: const Text('Tomorrow'),
                ),
                TextButton(
                  onPressed: () => _select(2),
                  child: const Text('Day After Tomorrow'),
                ),
                TextButton(
                  onPressed: () => _select(3),
                  child: const Text('Next Week'),
                ),
              ],
            )
          : IconButton(
              icon: const Icon(Icons.swipe),
              tooltip: 'Reschedule',
              onPressed: _startOptions,
            ),
    );
  }
}
