import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/task.dart';
import '../models/view_filter_rules.dart';
import '../services/food_diary_widget_service.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../utils/date_time_format.dart';
import '../utils/description_disclosure.dart';
import 'label_picker.dart';
import 'speech_input_button.dart';
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
  /// Opens the "add entry" dialog automatically on first build, used when
  /// arriving from the home-screen widget's "+" (`besttodofood://add`).
  final bool autoAddEntry;

  const FoodDiaryPage({Key? key, this.autoAddEntry = false}) : super(key: key);

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
    // The dev/demo starter tasks (see home_page._loadTasks) mean the overall
    // list is essentially never empty, so the seed condition has to check
    // for existing food-diary entries specifically, not list emptiness —
    // otherwise it never fires. Dev builds seed a few entries spread across
    // the day so the tool is testable in Chrome and its screenshots always
    // show a populated log.
    if (!tasks.any((t) => t.isEatingHabit) && Config.isDev) {
      tasks.addAll(_buildDevSeed());
    }
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
    if (widget.autoAddEntry) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _editEntry());
    }
  }

  List<Task> _buildDevSeed() {
    final now = DateTime.now();
    DateTime at(int hour, int minute) =>
        DateTime(now.year, now.month, now.day, hour, minute);
    return [
      Task(
        title: 'Oatmeal with banana',
        description: 'Dev seed: a food diary entry',
        label: 'gluten',
        createdAt: now,
        dueDate: at(8, 0),
        hasExplicitTime: true,
        isEatingHabit: true,
      ),
      Task(
        title: 'Grilled chicken salad',
        description: 'Dev seed: a food diary entry',
        label: 'dairy-free',
        createdAt: now,
        dueDate: at(13, 0),
        hasExplicitTime: true,
        isEatingHabit: true,
      ),
      Task(
        title: 'Greek yogurt with honey',
        description: 'Dev seed: a food diary entry',
        label: 'sugar, lactose',
        createdAt: now,
        dueDate: at(19, 30),
        hasExplicitTime: true,
        isEatingHabit: true,
      ),
    ];
  }

  Future<void> _save() async {
    await _repository.saveItems(_tasks);
    await FoodDiaryWidgetService.sync(_tasks);
  }

  /// Entries sorted newest-eaten-first, undated ones (shouldn't normally
  /// happen) last.
  List<Task> _entries() {
    final entries = ItemViews.foodDiary(
      _tasks,
      rules: Config.viewFilterRules[ViewFilterRules.foodDiary],
    );
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

  /// Groups entries by the calendar day on which they were eaten. Historical
  /// days are rendered as collapsed sections so an established diary stays
  /// quick to scan, while today (and any future/undated entries) remains
  /// immediately visible.
  List<_FoodDiaryDay> _days(List<Task> entries) {
    final grouped = <DateTime?, List<Task>>{};
    for (final entry in entries) {
      final time = entry.dueDate;
      final day = time == null
          ? null
          : DateTime(time.year, time.month, time.day);
      grouped.putIfAbsent(day, () => <Task>[]).add(entry);
    }
    return [
      for (final group in grouped.entries)
        _FoodDiaryDay(day: group.key, entries: group.value),
    ];
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

  /// Creates a fresh log entry from [entry], preserving the food details but
  /// recording it at the current time. This makes recurring meals quick to
  /// log without changing the historical entry they came from.
  Future<void> _copyEntryToNow(Task entry) async {
    final now = DateTime.now();
    final copy = Task(
      title: entry.title,
      description: entry.description,
      label: entry.label,
      createdAt: now,
      dueDate: now,
      hasExplicitTime: true,
      isEatingHabit: true,
    );
    setState(() => _tasks.insert(0, copy));
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Copied "${entry.title}" to now')),
      );
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
    final days = _days(entries);
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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                  children: [
                    for (final day in days)
                      _FoodDiaryDaySection(
                        key: ValueKey(day.day),
                        day: day,
                        onEdit: _editEntry,
                        onCopyToNow: _copyEntryToNow,
                        onDelete: _deleteEntry,
                      ),
                  ],
                ),
    );
  }
}

class _FoodDiaryDay {
  final DateTime? day;
  final List<Task> entries;

  const _FoodDiaryDay({required this.day, required this.entries});
}

class _FoodDiaryDaySection extends StatelessWidget {
  final _FoodDiaryDay day;
  final ValueChanged<Task> onEdit;
  final ValueChanged<Task> onCopyToNow;
  final ValueChanged<Task> onDelete;

  const _FoodDiaryDaySection({
    super.key,
    required this.day,
    required this.onEdit,
    required this.onCopyToNow,
    required this.onDelete,
  });

  String _title(DateTime today) {
    if (day.day == null) return 'No date';
    if (day.day == today) return 'Today';
    return formatTimerDate(day.day!);
  }

  List<Widget> _tiles() => [
        for (final entry in day.entries)
          _FoodDiaryTile(
            key: ValueKey(entry.uid),
            entry: entry,
            onEdit: () => onEdit(entry),
            onCopyToNow: () => onCopyToNow(entry),
            onDelete: () => onDelete(entry),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isPast = day.day != null && day.day!.isBefore(today);
    final title = _title(today);

    if (isPast) {
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          key: PageStorageKey<String>('food-diary-day-$title'),
          initiallyExpanded: false,
          title: Text(title),
          subtitle: Text(
            '${day.entries.length} ${day.entries.length == 1 ? 'entry' : 'entries'}',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          children: _tiles(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ..._tiles(),
        const SizedBox(height: 8),
      ],
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Title'),
                    textInputAction: TextInputAction.next,
                  ),
                ),
                SpeechInputButton(controller: _titleController),
              ],
            ),
            // Tags sit right under the title, same as the wishlist dialog —
            // they're what a diary entry is glanced at for; the description
            // is the exception and lives at the bottom.
            LabelPickerField(
              value: _label,
              fieldLabel: 'Tags (e.g. sugar, lactose)',
              onChanged: (v) => setState(() => _label = v),
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
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
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
  final VoidCallback onCopyToNow;
  final VoidCallback onDelete;

  const _FoodDiaryTile({
    Key? key,
    required this.entry,
    required this.onEdit,
    required this.onCopyToNow,
    required this.onDelete,
  }) : super(key: key);

  List<String> _labels() => entry.label
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toList();

  /// Gives the diary a quick visual rhythm without making the card content
  /// harder to read. Morning runs until noon, the daytime/noon tint continues
  /// until 18:00, and the Bordeaux tint marks the evening.
  Color _cardColor(BuildContext context, DateTime? time) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hour = time?.hour ?? 12;
    if (hour < 12) {
      return isDark ? const Color(0xFF17324A) : const Color(0xFFE3F2FD);
    }
    if (hour < 18) {
      return isDark ? const Color(0xFF403817) : const Color(0xFFFFF8D6);
    }
    return isDark ? const Color(0xFF451E2D) : const Color(0xFFF3E1E6);
  }

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
        color: _cardColor(context, time),
        child: ListTile(
          title: Text(entry.title),
          trailing: IconButton(
            tooltip: 'Copy entry to now',
            onPressed: onCopyToNow,
            icon: const Icon(Icons.content_copy),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (time != null) ...[
                const SizedBox(height: 4),
                Text(formatTimerDateTime(time)),
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
              if (entry.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                DescriptionDisclosure(description: entry.description),
              ],
            ],
          ),
          onTap: onEdit,
        ),
      ),
    );
  }
}
