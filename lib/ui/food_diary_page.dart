import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/task.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../utils/date_time_format.dart';
import '../utils/linkified_text.dart';
import 'label_picker.dart';
import 'subpage_app_bar.dart';

/// Tools → Food Diary: a pre-filtered view over the one task list — like
/// opening the wishlist — showing only tasks flagged [Task.isEatingHabit].
/// Phase 1 is deliberately small: a title, an optional description, the time
/// the item was eaten, and free-form tags (e.g. "sugar", "lactose") reusing
/// the same label picker every other task uses. Entries never appear on the
/// home tabs, the schedule view, projects or Todoist — see
/// [ItemViews.foodDiary] — and swiping one away moves it to the Archived
/// Items list, exactly like deleting a wishlist item.
class FoodDiaryPage extends StatefulWidget {
  const FoodDiaryPage({Key? key}) : super(key: key);

  @override
  State<FoodDiaryPage> createState() => _FoodDiaryPageState();
}

class _FoodDiaryPageState extends State<FoodDiaryPage> {
  final ItemRepository _repository = ItemRepository.instance;

  /// The full task list; the page shows and mutates only the eating-habit
  /// subset but always persists the whole list.
  List<Task> _tasks = <Task>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await _repository.loadItems();
    // Platforms without storage (web) load an empty list; dev builds seed one
    // entry so the tool is testable in Chrome.
    if (tasks.isEmpty && Config.isDev) {
      tasks.add(Task(
        title: 'Greek yogurt with honey',
        description: 'Dev seed: a food diary entry',
        label: 'sugar, lactose',
        createdAt: DateTime.now(),
        dueDate: DateTime.now(),
        hasExplicitTime: true,
        isEatingHabit: true,
      ));
    }
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _save() => _repository.saveItems(_tasks);

  /// Entries sorted newest-eaten-first, undated ones (shouldn't normally
  /// happen) last.
  List<Task> _entries() {
    final entries = ItemViews.foodDiary(_tasks);
    entries.sort((a, b) {
      final aTime = a.dueDate;
      final bTime = b.dueDate;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return entries;
  }

  Future<void> _editEntry([Task? entry]) async {
    final result = await showDialog<_FoodDiaryEditResult>(
      context: context,
      builder: (context) => _FoodDiaryEditDialog(entry: entry),
    );
    if (result == null) return;
    setState(() {
      if (entry == null) {
        _tasks.insert(
          0,
          Task(
            title: result.title,
            description: result.description,
            label: result.label,
            createdAt: DateTime.now(),
            dueDate: result.time,
            hasExplicitTime: true,
            isEatingHabit: true,
          ),
        );
      } else {
        entry
          ..title = result.title
          ..description = result.description
          ..label = result.label
          ..dueDate = result.time
          ..hasExplicitTime = true;
      }
    });
    await _save();
  }

  /// Moves [entry] to the Archived Items list, with an undo snackbar —
  /// exactly like deleting a wishlist item.
  void _deleteEntry(Task entry) {
    final originalIndex = _tasks.indexOf(entry);
    if (originalIndex < 0) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _tasks.remove(entry));
    _save();

    late Timer timer;
    timer = Timer(Config.delayDuration, () async {
      final deleted = await _repository.loadDeletedItems();
      entry.deletedAt = DateTime.now();
      deleted.insert(0, entry);
      await _repository.saveDeletedItems(deleted);
      messenger.hideCurrentSnackBar();
    });

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${entry.title}"'),
          duration: Config.delayDuration,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              timer.cancel();
              messenger.hideCurrentSnackBar();
              if (!mounted) return;
              setState(() {
                final index = originalIndex.clamp(0, _tasks.length);
                _tasks.insert(index, entry);
              });
              _save();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Food Diary'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add food diary entry',
        onPressed: () => _editEntry(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No food diary entries yet. Log what you eat here — it '
                      'stays out of your task lists.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _FoodDiaryTile(
                      key: ValueKey(entry.uid),
                      entry: entry,
                      onEdit: () => _editEntry(entry),
                      onDelete: () => _deleteEntry(entry),
                    );
                  },
                ),
    );
  }
}

class _FoodDiaryEditResult {
  final String title;
  final String description;
  final String label;
  final DateTime time;

  const _FoodDiaryEditResult(
      this.title, this.description, this.label, this.time);
}

/// Add/edit dialog owning its text controllers, so the dialog's exit
/// animation never touches a disposed one (see task_detail's rule).
class _FoodDiaryEditDialog extends StatefulWidget {
  final Task? entry;

  const _FoodDiaryEditDialog({required this.entry});

  @override
  State<_FoodDiaryEditDialog> createState() => _FoodDiaryEditDialogState();
}

class _FoodDiaryEditDialogState extends State<_FoodDiaryEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _label;
  late DateTime _time;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.entry?.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.entry?.description ?? '');
    _label = widget.entry?.label ?? '';
    _time = widget.entry?.dueDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await pickDateInstantly(context, _time);
    if (date == null || !mounted) return;
    setState(() {
      _time = DateTime(
          date.year, date.month, date.day, _time.hour, _time.minute);
    });
  }

  Future<void> _pickTime() async {
    final time = await pickTimeOfDay(context, TimeOfDay.fromDateTime(_time));
    if (time == null || !mounted) return;
    setState(() {
      _time = DateTime(
          _time.year, _time.month, _time.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.entry == null ? 'Add food diary entry' : 'Edit entry'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Time', style: Theme.of(context).textTheme.labelLarge),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(formatTimerDate(_time)),
                ),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time, size: 16),
                  label: Text(formatTimerTime(_time)),
                ),
              ],
            ),
            LabelPickerField(
              value: _label,
              fieldLabel: 'Tags (e.g. sugar, lactose)',
              onChanged: (v) => setState(() => _label = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isEmpty) return;
            Navigator.of(context).pop(_FoodDiaryEditResult(
              title,
              _descriptionController.text.trim(),
              _label.trim(),
              _time,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// One food diary entry: title, time, description and tags — no checkbox,
/// no due-date semantics, just a log line. Swipe (either direction) opens a
/// confirm-free delete, matching the app's general swipe-to-delete feel.
class _FoodDiaryTile extends StatelessWidget {
  final Task entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _FoodDiaryTile({
    Key? key,
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  }) : super(key: key);

  List<String> _labels() => entry.label
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final labels = _labels();
    final time = entry.dueDate;
    return Dismissible(
      key: ValueKey(entry.uid),
      background: Container(
        color: Colors.red.withValues(alpha: 0.5),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red.withValues(alpha: 0.5),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        child: ListTile(
          title: Text(entry.title),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (time != null) ...[
                const SizedBox(height: 4),
                Text(formatTimerDateTime(time)),
              ],
              if (entry.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                LinkifiedText(entry.description),
              ],
              if (labels.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final label in labels)
                      Chip(
                        label: Text(label),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ],
            ],
          ),
          onTap: onEdit,
        ),
      ),
    );
  }
}
