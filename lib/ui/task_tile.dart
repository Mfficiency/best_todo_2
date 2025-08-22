import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:async';
import 'dart:io' show Platform;

import '../models/task.dart';
import '../config.dart';

class TaskTile extends StatefulWidget {
  final Task task;
  final Future<void> Function() onChanged;
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
  bool _isEmulator = false;
  Timer? _timer;
  late final AnimationController _progressController;
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _noteController;
  late final TextEditingController _labelController;
  late final List<int> _destinations;
  double _dragOffset = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descController = TextEditingController(text: widget.task.description);
    _noteController = TextEditingController(text: widget.task.note);
    _labelController = TextEditingController(text: widget.task.label);
    _progressController = AnimationController(
      vsync: this,
      duration: Config.delayDuration,
    );
    _destinations = List<int>.generate(Config.tabs.length, (i) => i)
      ..remove(widget.pageIndex);
    _checkEmulator();
  }

  Future<void> _checkEmulator() async {
    final plugin = DeviceInfoPlugin();
    var isEmulator = true;
    try {
      if (kIsWeb) {
        isEmulator = true;
      } else if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        isEmulator = !info.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        isEmulator = !info.isPhysicalDevice;
      }
    } catch (_) {
      isEmulator = true;
    }
    if (mounted) setState(() => _isEmulator = isEmulator);
  }

  void _startOptions() {
    setState(() => _showOptions = true);
    _timer?.cancel();
    _progressController.reset();
    _progressController.forward();
    _timer = Timer(Config.delayDuration, () {
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
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_expanded)
          IconButton(
            icon: const Icon(Icons.expand_less),
            tooltip: 'Collapse',
            onPressed: _toggleExpanded,
          ),
        if (_isEmulator) ...[
          if (widget.showSwipeButton)
            IconButton(
              icon: const Icon(Icons.swipe),
              tooltip: 'Reschedule',
              onPressed: _startOptions,
            ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete',
            onPressed: widget.onDelete,
          ),
        ],
      ],
    );

    final listTile = ListTile(
      contentPadding:
          isAndroid ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16.0),
      minLeadingWidth: isAndroid ? 0 : null,
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
      trailing: trailing,
    );

    final stackTile = Stack(
      children: [
        listTile,
        if (_showOptions)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).cardColor.withOpacity(0.9),
              alignment: Alignment.centerRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
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
              ),
            ),
          ),
      ],
    );

    Widget content = InkWell(
      onTap: _toggleExpanded,
      child: Column(
        children: [
          stackTile,
          if (_expanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Focus(
                    onFocusChange: (hasFocus) {
                      if (!hasFocus) widget.onChanged();
                    },
                    child: TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                      onChanged: (v) => widget.task.title = v,
                    ),
                  ),
                  Focus(
                    onFocusChange: (hasFocus) {
                      if (!hasFocus) widget.onChanged();
                    },
                    child: TextField(
                      controller: _descController,
                      decoration: const InputDecoration(labelText: 'Description'),
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                      onChanged: (v) => widget.task.description = v,
                    ),
                  ),
                  Focus(
                    onFocusChange: (hasFocus) {
                      if (!hasFocus) widget.onChanged();
                    },
                    child: TextField(
                      controller: _noteController,
                      decoration: const InputDecoration(labelText: 'Note'),
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                      onChanged: (v) => widget.task.note = v,
                    ),
                  ),
                  Focus(
                    onFocusChange: (hasFocus) {
                      if (!hasFocus) widget.onChanged();
                    },
                    child: TextField(
                      controller: _labelController,
                      decoration: const InputDecoration(labelText: 'Label'),
                      onChanged: (v) => widget.task.label = v,
                    ),
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
                            widget.onChanged();
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

    
    content = AnimatedSlide(
      offset: Offset(_dragOffset / MediaQuery.of(context).size.width, 0),
      duration:
          _dragging ? Duration.zero : const Duration(milliseconds: 200),
      child: content,
    );

    if (isAndroid) {
      content = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          setState(() => _dragging = true);
        },
        onHorizontalDragUpdate: (details) {
          setState(() => _dragOffset += details.delta.dx);
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          const threshold = 100;
          if (widget.swipeLeftDelete) {
            if (_dragOffset > threshold || velocity > 500) {
              _startOptions();
            } else if (_dragOffset < -threshold || velocity < -500) {
              widget.onDelete();
            }
          } else {
            if (_dragOffset > threshold || velocity > 500) {
              widget.onDelete();
            } else if (_dragOffset < -threshold || velocity < -500) {
              _startOptions();
            }
          }
          setState(() {
            _dragging = false;
            _dragOffset = 0;
          });
        },
        child: content,
      );
    }

    return content;
  }
}
