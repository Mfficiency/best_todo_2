import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:async';

import '../models/project.dart';
import '../models/recurrence_config.dart';
import '../models/task.dart';
import '../models/todoist_sync_map_entry.dart';
import '../config.dart';
import '../services/notification_service.dart';
import '../services/project_service.dart';
import '../services/todoist_sync_service.dart';
import '../utils/description_disclosure.dart';
import '../utils/label_style.dart';
import '../utils/label_utils.dart';
import '../utils/linkified_text.dart';
import 'attachments_field.dart';
import 'label_picker.dart';
import 'recurrence_editor.dart';
import 'recurrence_scope_dialog.dart';

enum _SwipeOptionMode { move, delete }

class _WeekdaySwipeOption {
  final String label;
  final int weekday;

  const _WeekdaySwipeOption(this.label, this.weekday);
}

/// One entry of the Notify bell's delay sheet. [label] doubles as the "in …"
/// part of the confirmation snackbar.
class _NotifyDelayOption {
  final String label;
  final int seconds;

  const _NotifyDelayOption(this.label, this.seconds);
}

/// Quick delays offered by the Notify bell, next to the configured default.
const _notifyDelayOptions = <_NotifyDelayOption>[
  _NotifyDelayOption('5 minutes', 5 * 60),
  _NotifyDelayOption('20 minutes', 20 * 60),
  _NotifyDelayOption('1 hour', 60 * 60),
];

/// Snooze-style delays offered by the double-tap menu — the "not now, but
/// don't let me forget" answer, without expanding the tile for the bell.
const _doubleTapReminderOptions = <_NotifyDelayOption>[
  _NotifyDelayOption('5 minutes', 5 * 60),
  _NotifyDelayOption('10 minutes', 10 * 60),
  _NotifyDelayOption('20 minutes', 20 * 60),
];

/// What the double-tap menu was asked for: the egg timer, or a reminder in
/// [reminder]'s time from now.
class _DoubleTapAction {
  final _NotifyDelayOption? reminder;

  const _DoubleTapAction.startTimer() : reminder = null;
  const _DoubleTapAction.remindIn(_NotifyDelayOption option)
      : reminder = option;

  bool get isTimer => reminder == null;
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
  final void Function(
    DateTime? oldDueDate,
    DateTime newDueDate,
    RecurrenceEditScope scope,
  )? onDueDateChanged;
  final VoidCallback? onRecurringChanged;

  /// Called when "Start timer" is picked from the double-tap menu. When null
  /// double taps do nothing (each tap just toggles the expansion).
  final VoidCallback? onStartTimer;
  final int pageIndex;
  final bool showSwipeButton;
  final bool swipeLeftDelete;
  final TaskTileController? controller;
  final bool keyboardFocused;
  final VoidCallback? onFocusRequested;
  final VoidCallback? onKeyboardActionCommitted;

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
    this.controller,
    this.keyboardFocused = false,
    this.onFocusRequested,
    this.onKeyboardActionCommitted,
  }) : super(key: key);

  @override
  State<TaskTile> createState() => _TaskTileState();
}

class TaskTileController {
  _TaskTileState? _state;

  bool get hasOptions => _state?._optionMode != null;
  bool get hasMoveOptions => _state?._optionMode == _SwipeOptionMode.move;
  bool get hasDeleteOptions => _state?._optionMode == _SwipeOptionMode.delete;

  void _attach(_TaskTileState state) {
    _state = state;
  }

  void _detach(_TaskTileState state) {
    if (_state == state) _state = null;
  }

  void open() => _state?._openExpanded();
  void startMoveOptions() => _state?._startMoveOptions(fromKeyboard: true);
  void startDeleteOptions() => _state?._startDeleteOptions(fromKeyboard: true);
  void stepOptions() => _state?._stepOptionSelection(fromKeyboard: true);
  void confirmOptions() => _state?._commitSelectedOption(advanceFocus: true);
  void closeOptions() => _state?._closeOptions();
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
  late final List<int> _destinations;
  double _dragOffset = 0;
  bool _dragging = false;
  int _optionSelectionIndex = 0;
  bool _optionStartedFromKeyboard = false;

  /// A generated occurrence that's been hand-edited stops being an
  /// interchangeable copy of the master: flagging it as an override keeps
  /// the series' regeneration from ever touching or discarding it, even if
  /// the schedule later shrinks past its slot.
  void _markOverrideIfChild() {
    if (widget.task.recurrenceParentUid != null) {
      widget.task.recurrenceOverride = true;
    }
  }

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descController = TextEditingController(text: widget.task.description);
    _noteController = TextEditingController(text: widget.task.note);
    _progressController = AnimationController(
      vsync: this,
      duration: Config.delayDuration,
    );
    _destinations = List<int>.generate(Config.tabs.length, (i) => i)
      ..remove(widget.pageIndex);
    widget.controller?._attach(this);
    _checkEmulator();
  }

  @override
  void didUpdateWidget(covariant TaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
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

  /// A small info button shown next to the Note field for a task linked to
  /// Todoist, so the sync id/date live in one tap-away place instead of
  /// cluttering the free-text description. Null (no icon) for a task that
  /// has never been synced.
  Widget? _todoistSyncInfoIcon() {
    final entry =
        TodoistSyncService.instance.entryForLocalUid(widget.task.uid);
    if (entry == null) return null;
    return IconButton(
      icon: const Icon(Icons.info_outline),
      tooltip: 'Todoist sync info',
      onPressed: () => _showTodoistSyncInfo(entry),
    );
  }

  void _showTodoistSyncInfo(TodoistSyncMapEntry entry) {
    final synced = entry.syncedAt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final syncedLabel =
        '${synced.year}-${two(synced.month)}-${two(synced.day)} '
        '${two(synced.hour)}:${two(synced.minute)}';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Todoist sync info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Source: Todoist'),
            Text('Synced: $syncedLabel'),
            Text('Todoist ID: ${entry.todoistId}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _startOptions(_SwipeOptionMode mode, {bool fromKeyboard = false}) {
    setState(() {
      _optionMode = mode;
      _optionSelectionIndex = 0;
      _optionStartedFromKeyboard = fromKeyboard;
    });
    _restartOptionTimer(mode);
  }

  void _restartOptionTimer(_SwipeOptionMode mode) {
    _timer?.cancel();
    _progressController.reset();
    _progressController.forward();
    _timer = Timer(Config.delayDuration, () {
      if (!mounted || _optionMode != mode) return;
      _commitSelectedOption();
    });
  }

  void _startMoveOptions({bool fromKeyboard = false}) {
    _startOptions(_SwipeOptionMode.move, fromKeyboard: fromKeyboard);
  }

  void _startDeleteOptions({bool fromKeyboard = false}) {
    _startOptions(_SwipeOptionMode.delete, fromKeyboard: fromKeyboard);
  }

  void _closeOptions() {
    _timer?.cancel();
    _progressController.stop();
    if (mounted) {
      setState(() {
        _optionMode = null;
        _optionStartedFromKeyboard = false;
      });
    }
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

  int get _optionCount {
    if (_optionMode == _SwipeOptionMode.move) return _destinations.length;
    if (_optionMode == _SwipeOptionMode.delete) {
      return 1 + _deleteSwipeWeekdayOptions.length;
    }
    return 0;
  }

  void _stepOptionSelection({bool fromKeyboard = false}) {
    final mode = _optionMode;
    final count = _optionCount;
    if (mode == null || count == 0) return;
    setState(() {
      _optionSelectionIndex = (_optionSelectionIndex + 1) % count;
      _optionStartedFromKeyboard = _optionStartedFromKeyboard || fromKeyboard;
    });
    _restartOptionTimer(mode);
  }

  void _commitSelectedOption({bool advanceFocus = false}) {
    final mode = _optionMode;
    if (mode == null) return;
    final shouldAdvanceFocus = advanceFocus || _optionStartedFromKeyboard;
    final selectedIndex = _optionSelectionIndex;
    _closeOptions();
    if (mode == _SwipeOptionMode.move) {
      final dest = _destinations[
          selectedIndex.clamp(0, _destinations.length - 1).toInt()];
      widget.onMove(dest);
    } else if (selectedIndex == 0) {
      widget.onDelete();
    } else {
      final option = _deleteSwipeWeekdayOptions[(selectedIndex - 1)
          .clamp(0, _deleteSwipeWeekdayOptions.length - 1)
          .toInt()];
      widget.onMoveToWeekday?.call(option.weekday);
    }
    if (shouldAdvanceFocus) widget.onKeyboardActionCommitted?.call();
  }

  void _openExpanded() {
    if (_expanded) return;
    setState(() => _expanded = true);
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
    widget.onFocusRequested?.call();
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

  /// Little menu shown on a double tap: start the egg timer (the dice one)
  /// for this task, or be reminded about it in a few minutes.
  Future<void> _showDoubleTapMenu() async {
    final minutes = Config.diceTimerDefaultMinutes.clamp(1, 60);
    final action = await showModalBottomSheet<_DoubleTapAction>(
      context: context,
      showDragHandle: true,
      // Five rows do not fit the default 9/16-of-the-screen sheet on a short
      // screen: let it size to its content (and scroll if even that is too
      // much) instead of overflowing.
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
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
                onTap: () => Navigator.of(sheetContext)
                    .pop(const _DoubleTapAction.startTimer()),
              ),
              const Divider(height: 1),
              for (final option in _doubleTapReminderOptions)
                ListTile(
                  leading: const Icon(Icons.notifications_none),
                  title: Text('Remind me in ${option.label}'),
                  onTap: () => Navigator.of(sheetContext)
                      .pop(_DoubleTapAction.remindIn(option)),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action.isTimer) {
      widget.onStartTimer?.call();
      return;
    }
    await _scheduleReminder(action.reminder!);
  }

  /// "in 05:00" for the configured default delay, so the sheet's last entry
  /// shows what tapping it will do.
  String _clockDelay(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  /// The Notify bell: asks *when* first. Picking 5 / 20 / 60 minutes reminds
  /// about this task later without touching its due date; the last entry keeps
  /// the one-tap behaviour of the configured default delay.
  Future<void> _sendTaskNotification() async {
    if (!Config.enableNotifications) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable notifications in Settings first')),
      );
      return;
    }
    final defaultSeconds = Config.defaultNotificationDelaySeconds;
    final picked = await showModalBottomSheet<_NotifyDelayOption>(
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
                'Notify me about "${widget.task.title}"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            for (final option in _notifyDelayOptions)
              ListTile(
                leading: const Icon(Icons.notifications_none),
                title: Text('In ${option.label}'),
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Default delay'),
              subtitle: Text(defaultSeconds == 0
                  ? 'Right away'
                  : 'In ${_clockDelay(defaultSeconds)} — set in Settings'),
              onTap: () => Navigator.of(sheetContext).pop(
                _NotifyDelayOption(_clockDelay(defaultSeconds), defaultSeconds),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _scheduleReminder(picked);
  }

  /// Schedules [option]'s reminder for this task and reports back in a
  /// snackbar. Shared by the Notify bell and the double-tap menu.
  Future<void> _scheduleReminder(_NotifyDelayOption option) async {
    if (!Config.enableNotifications) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable notifications in Settings first')),
      );
      return;
    }
    final sent = await NotificationService.showTaskNotification(
      widget.task.title,
      delaySeconds: option.seconds,
    );
    if (!mounted) return;
    if (sent) {
      final when = option.seconds == 0 ? 'now' : 'in ${option.label}';
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
    widget.controller?._detach(this);
    _titleController.dispose();
    _descController.dispose();
    _noteController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  /// [protected] tints the pill [protectedTagColor] — used for a chip that
  /// names one of the app's reserved states (e.g. "wish") so it reads
  /// consistently with how a manually typed reserved word renders in
  /// [LabelPickerField].
  Widget _tag(String text, {bool protected = false}) {
    final scheme = Theme.of(context).colorScheme;
    final color = protected ? protectedTagColor : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.16) ?? scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: color == null ? null : Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color ?? scheme.onSecondaryContainer,
          fontWeight: color == null ? null : FontWeight.w600,
        ),
      ),
    );
  }

  /// Small tags shown under the title: "Project 1" / "To-Do" for a task
  /// assigned to a project (listens to the project list so renames update
  /// everywhere), "wish" for wishlist items, plus every label the task
  /// carries — so the main list shows the task's properties whatever kind of
  /// task it is. Returns null when there is nothing to show.
  Widget? _buildSubtitle() {
    final task = widget.task;
    final labels = task.label
        .split(RegExp(r'[,\s]+'))
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();
    if (task.projectId == null && !task.isWish && labels.isEmpty) return null;
    return ValueListenableBuilder<List<Project>>(
      valueListenable: ProjectService.instance.projects,
      builder: (context, _, __) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                if (task.projectId != null) ...[
                  _tag(ProjectService.instance.nameOf(task.projectId)),
                  _tag(ProjectService.stageLabel(task.kanbanStatus)),
                ],
                if (task.isWish) _tag('wish', protected: true),
                for (final label in labels)
                  _tag(label, protected: isProtectedToken(label)),
              ],
            ),
            if (task.isWish && task.description.isNotEmpty)
              DescriptionDisclosure(description: task.description),
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

    final scheme = Theme.of(context).colorScheme;

    ButtonStyle? optionStyle(int index) {
      if (index != _optionSelectionIndex) return null;
      return TextButton.styleFrom(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      );
    }

    final listTile = ListTile(
      contentPadding: isAndroid
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16.0),
      minLeadingWidth: isAndroid ? 0 : null,
      leading: Checkbox(
        value: widget.task.isDone,
        onChanged: (_) => setState(() => widget.onToggle()),
      ),
      title: LinkifiedText(
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
                        for (var i = 0; i < _destinations.length; i++)
                          TextButton(
                            style: optionStyle(i),
                            onPressed: () => _selectMove(_destinations[i]),
                            child: Text(Config.tabs[_destinations[i]]),
                          ),
                      if (_optionMode == _SwipeOptionMode.delete) ...[
                        TextButton(
                          style: optionStyle(0),
                          onPressed: _selectDelete,
                          child: const Text('Delete'),
                        ),
                        for (var i = 0;
                            i < _deleteSwipeWeekdayOptions.length;
                            i++)
                          TextButton(
                            style: optionStyle(i + 1),
                            onPressed: () => _selectWeekday(
                                _deleteSwipeWeekdayOptions[i].weekday),
                            child: Text(_deleteSwipeWeekdayOptions[i].label),
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
                      onChanged: (v) => setState(() {
                        widget.task.title = v;
                        _markOverrideIfChild();
                      }),
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
                      onChanged: (v) => setState(() {
                        widget.task.description = v;
                        _markOverrideIfChild();
                      }),
                    ),
                  ),
                  Focus(
                    onFocusChange: (hasFocus) {
                      if (!hasFocus) widget.onChanged();
                    },
                    child: TextField(
                      controller: _noteController,
                      decoration: InputDecoration(
                        labelText: 'Note',
                        suffixIcon: _todoistSyncInfoIcon(),
                      ),
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                      onChanged: (v) => setState(() {
                        widget.task.note = v;
                        _markOverrideIfChild();
                      }),
                    ),
                  ),
                  LabelPickerField(
                    value: widget.task.label,
                    onChanged: (v) {
                      setState(() {
                        widget.task.label = v;
                        _markOverrideIfChild();
                      });
                      widget.onChanged();
                    },
                  ),
                  AttachmentsField(
                    taskUid: widget.task.uid,
                    attachments: widget.task.attachments,
                    onChanged: (v) {
                      widget.task.attachments = v;
                      widget.onChanged();
                    },
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
                          if (picked == null || !mounted) return;
                          final oldDueDate = widget.task.dueDate;
                          RecurrenceEditScope scope;
                          if (isRecurringChild) {
                            final chosen = await showRecurrenceScopeDialog(
                              context,
                              isDelete: false,
                              allowAllEvents: false,
                            );
                            if (chosen == null || !mounted) return;
                            scope = chosen;
                          } else {
                            // A standalone task, or the master of a series
                            // (whose own date is the series anchor — moving
                            // it always re-anchors the whole series).
                            scope = RecurrenceEditScope.thisAndFollowing;
                          }
                          widget.onDueDateChanged
                              ?.call(oldDueDate, picked, scope);
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
                      child: Text(
                        'Part of a recurring series. Editing this occurrence '
                        'only changes this one.',
                      ),
                    ),
                  if (widget.task.isRecurring && !isRecurringChild)
                    RecurrenceEditor(
                      config: RecurrenceConfig.fromTask(widget.task),
                      anchorDate: widget.task.dueDate ?? DateTime.now(),
                      onChanged: (config) {
                        setState(() => config.applyTo(widget.task));
                        widget.onRecurringChanged?.call();
                      },
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
            final originalWasRight = widget.swipeLeftDelete ==
                (_optionMode == _SwipeOptionMode.move);
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

    if (widget.keyboardFocused) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.primary, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: content,
      );
    }

    return content;
  }
}
