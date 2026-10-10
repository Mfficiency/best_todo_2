import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/streak_goal.dart';
import '../models/streak_kind.dart';
import '../models/task.dart';
import '../services/project_service.dart';
import '../services/storage_service.dart';
import '../services/streak_service.dart';

/// Lets the user set, change or clear the goal behind one of the
/// customizable flames ([StreakKind.create] or [StreakKind.plan]): either a
/// specific recurring task, or any task filed under a project. Owns its own
/// [TextEditingController] so it survives the dialog's exit animation (see
/// CLAUDE.md's note on `_ProjectEditDialog`).
class StreakGoalDialog extends StatefulWidget {
  final StreakKind kind;

  const StreakGoalDialog({super.key, required this.kind});

  @override
  State<StreakGoalDialog> createState() => _StreakGoalDialogState();
}

class _StreakGoalDialogState extends State<StreakGoalDialog> {
  late StreakGoalTarget _target;
  String? _selectedId;
  late final TextEditingController _titleController;
  String _lastAutoTitle = '';
  List<Task> _recurringTasks = [];
  bool _loadingTasks = true;

  StreakGoal? get _existing => Config.streakGoals[widget.kind.id];

  @override
  void initState() {
    super.initState();
    final existing = _existing;
    _target = existing?.target ?? StreakGoalTarget.task;
    _selectedId = existing?.targetId;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _lastAutoTitle = existing?.title ?? '';
    _titleController.addListener(() => setState(() {}));
    _loadRecurringTasks();
  }

  Future<void> _loadRecurringTasks() async {
    final tasks = await StorageService().readTaskListRaw();
    if (!mounted) return;
    setState(() {
      _recurringTasks = tasks
          .where((t) => t.isRecurring && t.recurrenceParentUid == null)
          .toList();
      _loadingTasks = false;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _applyAutoTitle(String name) {
    // Only overwrite the title while it still matches the last automatic
    // fill, so a title the user typed themselves is never clobbered.
    if (_titleController.text == _lastAutoTitle) {
      _titleController.text = name;
    }
    _lastAutoTitle = name;
  }

  List<DropdownMenuItem<String>> get _options => _target == StreakGoalTarget.task
      ? [
          for (final task in _recurringTasks)
            DropdownMenuItem(value: task.uid, child: Text(task.title)),
        ]
      : [
          for (final project in ProjectService.instance.list)
            DropdownMenuItem(value: project.id, child: Text(project.name)),
        ];

  String? get _validSelectedId =>
      _options.any((item) => item.value == _selectedId) ? _selectedId : null;

  void _save() {
    final id = _selectedId;
    final title = _titleController.text.trim();
    if (id == null || title.isEmpty) return;
    Config.streakGoals[widget.kind.id] =
        StreakGoal(target: _target, targetId: id, title: title);
    unawaited(Config.save());
    StreakService.instance.settingsChanged();
    Navigator.pop(context, true);
  }

  void _clear() {
    Config.streakGoals.remove(widget.kind.id);
    unawaited(Config.save());
    StreakService.instance.settingsChanged();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final slotName = widget.kind == StreakKind.create ? 'green' : 'blue';
    return AlertDialog(
      title: Text('${widget.kind.short} flame goal ($slotName)'),
      content: SizedBox(
        width: 360,
        child: _loadingTasks
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Light this flame by completing a recurring task, or any '
                    'task filed under a project.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<StreakGoalTarget>(
                    segments: const [
                      ButtonSegment(
                        value: StreakGoalTarget.task,
                        label: Text('Recurring task'),
                      ),
                      ButtonSegment(
                        value: StreakGoalTarget.project,
                        label: Text('Project'),
                      ),
                    ],
                    selected: {_target},
                    onSelectionChanged: (selection) => setState(() {
                      _target = selection.first;
                      _selectedId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (_target == StreakGoalTarget.task && _recurringTasks.isEmpty)
                    const Text(
                        'No recurring tasks yet — make one recurring first.')
                  else
                    Row(
                      children: [
                        Text(
                          _target == StreakGoalTarget.task
                              ? 'Recurring task:'
                              : 'Project:',
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _validSelectedId,
                            hint: const Text('Choose one'),
                            items: _options,
                            onChanged: (value) {
                              if (value == null) return;
                              final name = _target == StreakGoalTarget.task
                                  ? _recurringTasks
                                      .firstWhere((t) => t.uid == value)
                                      .title
                                  : ProjectService.instance.nameOf(value);
                              setState(() {
                                _selectedId = value;
                                _applyAutoTitle(name);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Flame title',
                      helperText: 'Shown on the flame and the streak page',
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (_existing != null)
          TextButton(
            onPressed: _clear,
            child: const Text('Remove goal'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selectedId == null || _titleController.text.trim().isEmpty
              ? null
              : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
