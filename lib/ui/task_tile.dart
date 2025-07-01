import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/task.dart';
import '../config.dart';
import '../l10n/app_localizations.dart';

class TaskTile extends StatefulWidget {
  final Task task;
  final VoidCallback onChanged;
  final void Function(int destination) onMove;
  final VoidCallback onMoveNext;
  final VoidCallback onDelete;
  final int pageIndex;
  final bool showSwipeButton;
  final bool swipeLeftDelete;

  const TaskTile({
    Key? key,
    required this.task,
    required this.onChanged,
    required this.onMove,
    required this.onMoveNext,
    required this.onDelete,
    required this.pageIndex,
    this.showSwipeButton = true,
    this.swipeLeftDelete = true,
  }) : super(key: key);

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile>
    with SingleTickerProviderStateMixin {
  bool _showOptions = false;
  bool _expanded = false;
  Timer? _timer;
  late final AnimationController _progressController;
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _noteController;
  late final TextEditingController _labelController;
  late final List<int> _destinations;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descController = TextEditingController(text: widget.task.description);
    _noteController = TextEditingController(text: widget.task.note);
    _labelController = TextEditingController(text: widget.task.label);
    _progressController = AnimationController(
      vsync: this,
      duration: Duration(seconds: Config.defaultDelaySeconds),
    );
    _destinations = List<int>.generate(Config.tabs.length, (i) => i)
      ..remove(widget.pageIndex);
  }

  void _startOptions() {
    setState(() => _showOptions = true);
    _timer?.cancel();
    _progressController.reset();
    _progressController.forward();
    _timer = Timer(Duration(seconds: Config.defaultDelaySeconds), () {
      if (mounted && _showOptions) {
        widget.onMoveNext();
        _progressController.stop();
        setState(() => _showOptions = false);
      }
    });
  }

  void _select(int dest) {
    _timer?.cancel();
    _progressController.stop();
    widget.onMove(dest);
    setState(() => _showOptions = false);
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _titleController.dispose();
    _descController.dispose();
    _noteController.dispose();
    _labelController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    Widget content = InkWell(
      onTap: _toggleExpanded,
      child: Column(
        children: [
          ListTile(
            contentPadding:
                isAndroid ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16.0),
            minLeadingWidth: isAndroid ? 0 : null,
            leading: Checkbox(
              value: widget.task.isDone,
              onChanged: (_) => setState(() => widget.onChanged()),
            ),
            title: Text(
              widget.task.title,
              style: TextStyle(
                decoration: widget.task.isDone ? TextDecoration.lineThrough : null,
              ),
            ),
            trailing: _showOptions
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var dest in _destinations)
                            TextButton(
                              onPressed: () => _select(dest),
                              child: Text(Config.tabs[dest]),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 60,
                        child: AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, child) {
                            return LinearProgressIndicator(value: _progressController.value);
                          },
                        ),
                      ),
                    ],
                  )
                : (widget.showSwipeButton
                    ? IconButton(
                        icon: const Icon(Icons.swipe),
                        tooltip: AppLocalizations.of(context).reschedule,
                        onPressed: _startOptions,
                      )
                    : null),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Title'),
                    onChanged: (v) => widget.task.title = v,
                  ),
                  TextField(
                    controller: _descController,
                    decoration: const InputDecoration(labelText: 'Description'),
                    onChanged: (v) => widget.task.description = v,
                  ),
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(labelText: 'Note'),
                    onChanged: (v) => widget.task.note = v,
                  ),
                  TextField(
                    controller: _labelController,
                    decoration: const InputDecoration(labelText: 'Label'),
                    onChanged: (v) => widget.task.label = v,
                  ),
                  Row(
                    children: [
                      Text(widget.task.dueDate == null
                          ? 'No due date'
                          : 'Due: '
                              '${widget.task.dueDate!.toLocal().toString().split(' ')[0]}'),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: widget.task.dueDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                          );
                          if (picked != null) {
                            setState(() => widget.task.dueDate = picked);
                          }
                        },
                        child: const Text('Pick due date'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
        ],
      ),
    );

    if (isAndroid) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (widget.swipeLeftDelete) {
            if (velocity > 0) {
              _startOptions();
            } else if (velocity < 0) {
              widget.onDelete();
            }
          } else {
            if (velocity > 0) {
              widget.onDelete();
            } else if (velocity < 0) {
              _startOptions();
            }
          }
        },
        child: content,
      );
    }

    return content;
  }
}
