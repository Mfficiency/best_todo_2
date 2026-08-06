import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:async';

import '../models/project.dart';
import '../models/task.dart';
import '../config.dart';
import '../services/notification_service.dart';
import '../services/project_service.dart';

enum _SwipeOptionMode { move, delete }

class _WeekdaySwipeOption {
  final String label;
  final int weekday;

  const _WeekdaySwipeOption(this.label, this.weekday);
}

const _deleteSwipeWeekdayOptions = <_WeekdaySwipeOption>[
  _WeekdaySwipeOption('Fri', DateTime.friday),
  _WeekdaySwipeOption('Sat', DateTime.saturday),
  _WeekdaySwipeOption('Sun', DateTime.sunday),
  _WeekdaySwipeOption('Mon', DateTime.monday),
];

class TaskTile extends StatefulWidget {
  final Task task;
  final VoidCallback onChanged;
  final VoidCallback onToggle;
  final void Function(int destination) onMove;
  final void Function(int weekday)? onMoveToWeekday;
  final VoidCallback onMoveNext;
  final VoidCallback onDelete;
  final void Function(DateTime? oldDueDate, DateTime? newDueDate)?
      onDueDateChanged;
  final VoidCallback? onRecurringChanged;

  /// Called when "Start timer" is picked from the double-tap menu. When null
  /// double taps do nothing (each tap just toggles the expansion).
  final VoidCallback? onStartTimer;
  final int pageIndex;
  final bool showSwipeButton;
  final bool swipeLeftDelete;

  const TaskTile({
    Key? key,
    required this.task,
    required this.onChanged,
    required this.onToggle,
    required this.onMove,
    this.onMoveToWeekday,
    required this.onMoveNext,
    required this.onDelete,
    this.onDueDateChanged,
    this.onRecurringChanged,
    this.onStartTimer,
    required this.pageIndex,
    this.showSwipeButton = true,
    this.swipeLeftDelete = true,
  }) : super(key: key);

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<TaskTile>
    with SingleTickerProviderStateMixin {
  _SwipeOptionMode? _optionMode;
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

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await plugin.androidInfo;
        isEmulator = !androidInfo.isPhysicalDevice;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await plugin.iosInfo;
        isEmulator = !iosInfo.isPhysicalDevice;
      }
    } catch (_) {
      isEmulator = true;
    }
    if (mounted) setState(() => _isEmulator = isEmulator);
  }

  void _startOptions(_SwipeOptionMode mode) {
    setState(() => _optionMode = mode);
    _timer?.cancel();
    _progressController.reset();
    _progressController.forward();
    _timer = Timer(Config.delayDuration, () {
      if (!mounted || _optionMode != mode) return;
      _progressController.stop();
      setState(() => _optionMode = null);
      if (mode == _SwipeOptionMode.move) {
        widget.onMoveNext();
      } else {
        widget.onDelete();
      }
    });
  }

  void _startMoveOptions() {
    _startOptions(_SwipeOptionMode.move);
  }

  void _startDeleteOptions() {
    _startOptions(_SwipeOptionMode.delete);
  }

  void _closeOptions() {
    _timer?.cancel();
    _progressController.stop();
    if (mounted) setState(() => _optionMode = null);
  }

  void _selectMove(int dest) {
    _closeOptions();
    widget.onMove(dest);
  }

  void _selectDelete() {
    _closeOptions();
    widget.onDelete();
  }

  void _selectWeekday(int weekday) {
    _closeOptions();
    widget.onMoveToWeekday?.call(weekday);
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
  }

  /// Wall-clock moment of the previous tap, for the hand-rolled double-tap
  /// detection in [_handleTap]. A real `onDoubleTap` recognizer would hold
  /// the gesture arena for the double-tap timeout on EVERY tap in the tile —
  /// delaying the checkbox and the expand-on-tap by ~300 ms (and deadlocking
  /// fake-async widget tests, which don't advance that timer).
  DateTime? _lastTapAt;

  void _handleTap() {
    final now = DateTime.now();
    final last = _lastTapAt;
    _lastTapAt = now;
    if (widget.onStartTimer != null &&
        last != null &&
        now.difference(last) < kDoubleTapTimeout) {
      _lastTapAt = null;
      // Second tap of a double tap: take back the expansion toggle the first
      // tap made, then show the menu.
      _toggleExpanded();
      _showDoubleTapMenu();
      return;
    }
    _toggleExpanded();
  }

  /// Little menu shown on a double tap. For now it holds a single action:
  /// starting the egg timer (the dice one) for this task.
  Future<void> _showDoubleTapMenu() async {
    final minutes = Config.diceTimerDefaultMinutes.clamp(1, 60);
    final start = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                widget.task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Start timer'),
              subtitle: Text('Counts down $minutes min — '
                  'turn the dial to change it'),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (start == true) widget.onStartTimer?.call();
  }

  Future<void> _sendTaskNotification() async {
    if (!Config.enableNotifications) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable notifications in Settings first')),
      );
      return;
    }
    final delaySeconds = Config.defaultNotificationDelaySeconds;
    final sent = await NotificationService.showTaskNotification(
      widget.task.title,
      delaySeconds: delaySeconds,
    );
    if (!mounted) return;
    if (sent) {
      final minutes = (delaySeconds ~/ 60).toString().padLeft(2, '0');
      final seconds = (delaySeconds % 60).toString().padLeft(2, '0');
      final when = delaySeconds == 0 ? 'now' : 'in $minutes:$seconds';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Notification scheduled $when')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification permission is required')),
      );
    }
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

  Widget _tag(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: scheme.onSecondaryContainer),
      ),
    );
  }

  /// Small tags shown under the title: "Project 1" / "To-Do" for a task
  /// assigned to a project (listens to the project list so renames update
  /// everywhere), plus "wish" and the task's own labels for wishlist items —
  /// so the main list shows every property a wish carries. Returns null when
  /// there is nothing to show.
  Widget? _buildSubtitle() {
    final task = widget.task;
    if (task.projectId == null && !task.isWish) return null;
    final labels = task.label
        .split(RegExp(r'[,\s]+'))
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();
    return ValueListenableBuilder<List<Project>>(
      valueListenable: ProjectService.instance.projects,
      builder: (context, _, __) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.isWish && task.description.isNotEmpty)
              Text(task.description),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                if (task.projectId != null) ...[
                  _tag(ProjectService.instance.nameOf(task.projectId)),
                  _tag(ProjectService.stageLabel(task.kanbanStatus)),
                ],
                if (task.isWish) ...[
                  _tag('wish'),
                  for (final label in labels) _tag(label),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final isRecurringChild = widget.task.recurrenceParentUid != null;
    final trailing = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isEmulator) ...[
          if (widget.showSwipeButton)
            IconButton(
              icon: const Icon(Icons.swipe),
              tooltip: 'Reschedule',
              onPressed: _startMoveOptions,
            ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete',
            onPressed: _startDeleteOptions,
          ),
        ],
        if (_expanded)
          IconButton(
            icon: const Icon(Icons.notifications_none),
            tooltip: 'Notify',
            onPressed: _sendTaskNotification,
          ),
        if (_expanded)
          IconButton(
            icon: const Icon(Icons.expand_less),
            tooltip: 'Collapse',
            onPressed: _toggleExpanded,
          ),
      ],
    );

    final listTile = ListTile(
      contentPadding: isAndroid
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16.0),
      minLeadingWidth: isAndroid ? 0 : null,
      leading: Checkbox(
        value: widget.task.isDone,
        onChanged: (_) => setState(() => widget.onToggle()),
      ),
      title: Text(
        widget.task.title,
        style: TextStyle(
          decoration: widget.task.isDone ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: _buildSubtitle(),
      trailing: trailing,
    );

    final stackTile = Stack(
      children: [
        listTile,
        if (_optionMode != null)
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
                      if (_optionMode == _SwipeOptionMode.move)
                        for (var dest in _destinations)
                          TextButton(
                            onPressed: () => _selectMove(dest),
                            child: Text(Config.tabs[dest]),
                          ),
                      if (_optionMode == _SwipeOptionMode.delete) ...[
                        TextButton(
                          onPressed: _selectDelete,
                          child: const Text('Delete'),
                        ),
                        for (final option in _deleteSwipeWeekdayOptions)
                          TextButton(
                            onPressed: () => _selectWeekday(option.weekday),
                            child: Text(option.label),
                          ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 60,
                    child: AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, child) {
                        return LinearProgressIndicator(
                            value: _progressController.value);
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
      onTap: _handleTap,
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
                      decoration:
                          const InputDecoration(labelText: 'Description'),
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
                            firstDate: DateTime.now()
                                .subtract(const Duration(days: 365)),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 365 * 5)),
                          );
                          if (picked != null) {
                            final oldDueDate = widget.task.dueDate;
                            setState(() => widget.task.dueDate = picked);
                            widget.onDueDateChanged?.call(oldDueDate, picked);
                            widget.onRecurringChanged?.call();
                          }
                        },
                        child: const Text('Pick due date'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('Recurring'),
                      const Spacer(),
                      Switch(
                        value: widget.task.isRecurring,
                        onChanged: isRecurringChild
                            ? null
                            : (value) {
                                setState(() {
                                  widget.task.isRecurring = value;
                                  if (value &&
                                      widget.task.recurrenceEndDate == null) {
                                    final start = _dateOnly(
                                      widget.task.dueDate ?? DateTime.now(),
                                    );
                                    widget.task.recurrenceEndDate =
                                        start.add(const Duration(days: 7));
                                  }
                                  if (!value) {
                                    widget.task.recurrenceEndDate = null;
                                  }
                                });
                                widget.onRecurringChanged?.call();
                              },
                      ),
                    ],
                  ),
                  if (isRecurringChild)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('This is a generated recurring task.'),
                    ),
                  if (widget.task.isRecurring && !isRecurringChild)
                    Row(
                      children: [
                        const Text('Every'),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: widget.task.recurrenceIntervalDays,
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1 day')),
                            DropdownMenuItem(value: 2, child: Text('2 days')),
                            DropdownMenuItem(value: 7, child: Text('7 days')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              widget.task.recurrenceIntervalDays = value;
                            });
                            widget.onRecurringChanged?.call();
                          },
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            final base = _dateOnly(
                              widget.task.recurrenceEndDate ??
                                  widget.task.dueDate ??
                                  DateTime.now(),
                            );
                            final minDate = _dateOnly(
                              widget.task.dueDate ?? DateTime.now(),
                            );
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  base.isBefore(minDate) ? minDate : base,
                              firstDate: minDate,
                              lastDate:
                                  minDate.add(const Duration(days: 365 * 5)),
                            );
                            if (picked == null) return;
                            setState(() {
                              widget.task.recurrenceEndDate = picked;
                            });
                            widget.onRecurringChanged?.call();
                          },
                          child: Text(
                            widget.task.recurrenceEndDate == null
                                ? 'Pick end date'
                                : 'End: ${widget.task.recurrenceEndDate!.toLocal().toString().split(' ')[0]}',
                          ),
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

    final slide = AnimatedSlide(
      offset: Offset(_dragOffset / MediaQuery.of(context).size.width, 0),
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
      child: content,
    );

    Widget? background;
    if (_dragOffset != 0) {
      // Minimalist mode swaps the orange/red swipe backdrops for neutral ink.
      final scheme = Theme.of(context).colorScheme;
      final swipeForeground =
          Config.minimalistMode ? scheme.surface : Colors.white;
      final neutralBackdrop = scheme.onSurface.withValues(alpha: 0.45);
      final originalWasRight = _optionMode != null &&
          widget.swipeLeftDelete == (_optionMode == _SwipeOptionMode.move);
      final isCancelDrag = _optionMode != null &&
          ((originalWasRight && _dragOffset < 0) ||
              (!originalWasRight && _dragOffset > 0));
      final dragToDelete =
          widget.swipeLeftDelete ? _dragOffset < 0 : _dragOffset > 0;
      if (isCancelDrag) {
        final alignment =
            _dragOffset < 0 ? Alignment.centerRight : Alignment.centerLeft;
        background = Positioned.fill(
          child: Container(
            color: Config.minimalistMode
                ? neutralBackdrop
                : Colors.orange.withOpacity(0.5),
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: swipeForeground,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      } else if (dragToDelete) {
        final alignment = widget.swipeLeftDelete
            ? Alignment.centerRight
            : Alignment.centerLeft;
        background = Positioned.fill(
          child: Container(
            color: Config.minimalistMode
                ? neutralBackdrop
                : Colors.red.withOpacity(0.5),
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Icon(Icons.delete, color: swipeForeground),
          ),
        );
      } else {
        final alignment = widget.swipeLeftDelete
            ? Alignment.centerLeft
            : Alignment.centerRight;
        final icon =
            widget.swipeLeftDelete ? Icons.arrow_forward : Icons.arrow_back;
        background = Positioned.fill(
          child: Container(
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary),
          ),
        );
      }
    }

    content = Stack(
      children: [
        if (background != null) background,
        slide,
      ],
    );

    if (isAndroid || kIsWeb) {
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
          final swipedRight = _dragOffset > threshold || velocity > 500;
          final swipedLeft = _dragOffset < -threshold || velocity < -500;
          if (_optionMode != null) {
            final originalWasRight =
                widget.swipeLeftDelete == (_optionMode == _SwipeOptionMode.move);
            if ((originalWasRight && swipedLeft) ||
                (!originalWasRight && swipedRight)) {
              _closeOptions();
            }
          } else if (widget.swipeLeftDelete) {
            if (swipedRight) {
              _startMoveOptions();
            } else if (swipedLeft) {
              _startDeleteOptions();
            }
          } else {
            if (swipedRight) {
              _startDeleteOptions();
            } else if (swipedLeft) {
              _startMoveOptions();
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
