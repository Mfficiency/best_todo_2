import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/task.dart';
import '../models/view_filter_rules.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../utils/description_disclosure.dart';
import 'label_picker.dart';
import 'speech_input_button.dart';
import 'subpage_app_bar.dart';
import 'task_detail_page.dart';

/// Tools → Research: a pre-filtered view over the one task list — like
/// opening the Food Diary — showing only tasks flagged [Task.isResearch].
/// Items land here either added directly with the FAB, or approved into it
/// from the Waiting for Approval page's "Research" quick tag. Entries never
/// appear on the home tabs, the schedule view, projects or Todoist — see
/// [ItemViews.research] — and swiping one away moves it to the Archived
/// Items list, exactly like deleting a wishlist item.
class ResearchPage extends StatefulWidget {
  const ResearchPage({Key? key}) : super(key: key);

  @override
  State<ResearchPage> createState() => _ResearchPageState();
}

class _ResearchPageState extends State<ResearchPage> {
  final ItemRepository _repository = ItemRepository.instance;

  /// The full task list; the page shows and mutates only the research
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
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await _repository.saveItems(_tasks);
  }

  /// Entries newest-created-first, undated ones (shouldn't normally happen)
  /// last.
  List<Task> _entries() {
    final entries = ItemViews.research(
      _tasks,
      rules: Config.viewFilterRules[ViewFilterRules.research],
    );
    entries.sort((a, b) {
      final aTime = a.createdAt;
      final bTime = b.createdAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    return entries;
  }

  Future<void> _addEntry() async {
    final result = await showDialog<_ResearchEditResult>(
      context: context,
      builder: (context) => const _ResearchEditDialog(),
    );
    if (result == null) return;
    setState(() {
      _tasks.insert(
        0,
        Task(
          title: result.title,
          description: result.description,
          label: result.label,
          createdAt: DateTime.now(),
          isResearch: true,
        ),
      );
    });
    await _save();
  }

  void _openEntry(Task entry) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TaskDetailPage(task: entry)))
        .then((_) {
      if (!mounted) return;
      _load();
    });
  }

  /// Moves [entry] to the Archived Items list, with an undo snackbar —
  /// exactly like deleting a wishlist/food diary item.
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
      appBar: buildSubpageAppBar(context, title: 'Research'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add research item',
        onPressed: _addEntry,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No research items yet. Things worth digging into '
                      'land here — typed directly, or approved from '
                      'Waiting for Approval.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _ResearchTile(
                      key: ValueKey(entry.uid),
                      entry: entry,
                      onTap: () => _openEntry(entry),
                      onDelete: () => _deleteEntry(entry),
                    );
                  },
                ),
    );
  }
}

class _ResearchEditResult {
  final String title;
  final String description;
  final String label;

  const _ResearchEditResult(this.title, this.description, this.label);
}

/// Add dialog owning its own text controllers, so the dialog's exit
/// animation never touches a disposed one (see task_detail's rule).
class _ResearchEditDialog extends StatefulWidget {
  const _ResearchEditDialog();

  @override
  State<_ResearchEditDialog> createState() => _ResearchEditDialogState();
}

class _ResearchEditDialogState extends State<_ResearchEditDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController =
      TextEditingController();
  String _label = '';

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add research item'),
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
            LabelPickerField(
              value: _label,
              fieldLabel: 'Tags',
              onChanged: (v) => setState(() => _label = v),
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
            Navigator.of(context).pop(_ResearchEditResult(
              title,
              _descriptionController.text.trim(),
              _label.trim(),
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// One research entry: title, tags and description — no checkbox, no due
/// date, just a log line. Swipe (either direction) opens a confirm-free
/// delete, matching the app's general swipe-to-delete feel; tapping opens
/// the full [TaskDetailPage] for note/attachments/reminders.
class _ResearchTile extends StatelessWidget {
  final Task entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ResearchTile({
    Key? key,
    required this.entry,
    required this.onTap,
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
          onTap: onTap,
        ),
      ),
    );
  }
}
