import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/task.dart';
import '../models/task_change_source.dart';
import '../models/view_filter_rules.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../services/recurrence_service.dart';
import '../services/voice_inbox_service.dart';
import '../utils/date_utils.dart';
import '../utils/voice_inbox.dart';
import 'label_picker.dart';
import 'research_questions_page.dart';
import 'recurrence_scope_dialog.dart';
import 'speech_input_button.dart';
import 'subpage_app_bar.dart';
import 'task_tile.dart';

/// Tools → Research: a pre-filtered view over the one task list — like
/// opening the Food Diary — showing only tasks flagged [Task.isResearch].
/// Items land here either added directly with the FAB, or approved into it
/// from the Waiting for Approval page's "Research" quick tag. Entries never
/// appear on the home tabs, the schedule view, projects or Todoist — see
/// [ItemViews.research].
///
/// Entries are grouped by state — **Active**, **Next**, **Someday** (stored
/// as the wishlist's release tokens, see [backlogStateOf]) and **Done** for
/// checked-off ones — newest first within a section. Each card's "Move to"
/// button changes the state. The due date is kept but not shown.
///
/// Each entry is rendered with the very same [TaskTile] the home tabs use,
/// so a research item has every field a normal item has — done checkbox,
/// title, description, note, labels, attachments, due date, recurrence,
/// Notify and Send to Claude — editable in place by tapping it. Swiping
/// reschedules (sets the due date, the item stays in Research) or deletes
/// (moves it to Archived Items), exactly like on the home tabs.
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

  /// Archived Items + Deleted bin, passed to [RecurrenceService.refresh] so
  /// an already-deleted occurrence of a recurring research item is never
  /// regenerated (same as the home page does).
  List<Task> _archivedOrBinned = <Task>[];
  bool _loading = true;

  /// Mirrors the home page's tab day offsets (`HomePageState._offsetDays`);
  /// the last tab (Future) resolves to [Task.futureBucketMarker].
  static const List<int> _tabOffsetDays = [0, 1, 2, 7, 30];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await _repository.loadItems();
    final deleted = await _repository.loadDeletedItems();
    final bin = await _repository.loadBinItems();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _archivedOrBinned = [...deleted, ...bin];
      _loading = false;
    });
    unawaited(_checkReplies());
  }

  /// Whether a reply check is running (app-bar spinner).
  bool _checking = false;

  /// Reads the Todoist comments of every item waiting for the research
  /// routine ([VoiceInboxService.isWaiting]) — questions, or the finished
  /// page's link — and saves what changed.
  Future<void> _checkReplies({bool manual = false}) async {
    if (!VoiceInboxService.isConfigured || _checking) return;
    final waiting =
        ItemViews.research(_tasks).where(VoiceInboxService.isWaiting).toList();
    if (waiting.isEmpty) {
      if (manual && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nothing is waiting for Claude')));
      }
      return;
    }
    setState(() => _checking = true);
    var changed = false;
    for (final task in waiting) {
      try {
        changed = await VoiceInboxService.instance.refresh(task) || changed;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _checking = false);
    if (changed) await _save();
  }

  /// Starts the Claude research round for [entry] (Active, configured).
  Future<void> _startResearch(Task entry) async {
    setState(() => VoiceInboxService.markResearchRequested(entry));
    await _save();
    final service = VoiceInboxService.instance;
    final error = await service.runFire(entry,
        () => service.fireResearchQuestions(entry),
        (t) => t.researchStage = null);
    if (!mounted) return;
    await _reloadKeepingUi();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error ?? 'Asked Claude — its questions will show here')));
  }

  /// Re-reads the list after a fire (its sync may have pulled changes).
  Future<void> _reloadKeepingUi() async {
    final tasks = await _repository.loadItems();
    if (!mounted) return;
    setState(() => _tasks = tasks);
  }

  Future<void> _answerQuestions(Task entry) async {
    final answers = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => ResearchQuestionsPage(task: entry)),
    );
    if (answers == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await VoiceInboxService.instance.sendAnswers(entry, answers);
    } catch (e) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Couldn\'t send the answers — try again')));
      return;
    }
    await _reloadKeepingUi();
    final stored = _findTaskByUid(entry.uid);
    if (stored != null) {
      setState(() => stored.researchStage = ResearchStages.answered);
      await _save();
    }
    messenger.showSnackBar(const SnackBar(
        content: Text('Answers sent — Claude is writing the research page')));
  }

  /// The research-round line under an Active item's tile.
  Widget? _buildResearchStatus(Task entry) {
    if (entry.isDone || backlogStateOf(entry) != BacklogStates.active) {
      return null;
    }
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget line(IconData icon, String text) => Row(children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: style)),
        ]);
    switch (entry.researchStage) {
      case ResearchStages.requested:
        return line(Icons.hourglass_top, 'Claude is preparing questions…');
      case ResearchStages.questions:
        return Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: () => _answerQuestions(entry),
            icon: const Icon(Icons.question_answer_outlined),
            label: Text(entry.researchQuestions.length == 1
                ? 'Answer 1 question'
                : 'Answer ${entry.researchQuestions.length} questions'),
          ),
        );
      case ResearchStages.answered:
        return line(Icons.auto_awesome, 'Claude is writing the research page…');
      case ResearchStages.ready:
        return null; // the tile's "Open in Obsidian" says it all
    }
    if (!VoiceInboxService.isConfigured || entry.obsidianLink != null) {
      return null;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _startResearch(entry),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Start research with Claude'),
      ),
    );
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

  /// Moves [entry] to [state] (Active / Next / Someday).
  ///
  /// Moving an item to Active starts its Claude research round when the
  /// voice-inbox routine is set up and the item has none yet.
  void _setState(Task entry, String state) {
    setState(() => setBacklogState(entry, state));
    if (state == BacklogStates.active &&
        VoiceInboxService.isConfigured &&
        entry.researchStage == null &&
        entry.obsidianLink == null) {
      _startResearch(entry);
      return;
    }
    _save();
  }

  /// [_entries] split into the page's sections, in display order; empty
  /// sections are left out.
  List<MapEntry<String, List<Task>>> _sections() {
    final entries = _entries();
    final done = entries.where((t) => t.isDone).toList();
    return [
      for (final state in BacklogStates.all)
        MapEntry(
          BacklogStates.title(state),
          entries
              .where((t) => !t.isDone && backlogStateOf(t) == state)
              .toList(),
        ),
      MapEntry('Done', done),
    ].where((e) => e.value.isNotEmpty).toList();
  }

  Widget _buildCard(Task entry) {
    return Card(
      key: ValueKey('research-${entry.uid}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTile(entry),
                if (_buildResearchStatus(entry) case final status?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                    child: status,
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Move to',
            icon: const Icon(Icons.swap_vert),
            onSelected: (state) => _setState(entry, state),
            itemBuilder: (context) => [
              for (final state in BacklogStates.all)
                CheckedPopupMenuItem(
                  value: state,
                  checked: backlogStateOf(entry) == state,
                  child: Text(BacklogStates.title(state)),
                ),
            ],
          ),
        ],
      ),
    );
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
          note: result.note,
          label: result.label,
          dueDate: result.dueDate,
          createdAt: DateTime.now(),
          origin: TaskChangeSource.user,
          isResearch: true,
        ),
      );
    });
    await _save();
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _dueDateForTab(int tabIndex) {
    if (tabIndex >= _tabOffsetDays.length) return Task.futureBucketMarker;
    return _today().add(Duration(days: _tabOffsetDays[tabIndex]));
  }

  /// The home tab [due] would bucket into — [TaskTile] uses it to leave the
  /// item's own "tab" out of its swipe-to-reschedule choices.
  int _tabIndexForDueDate(DateTime? due) {
    final futureTab = Config.tabs.length - 1;
    if (Task.isFutureBucketDue(due)) return futureTab;
    final diff = dateDiffInDays(due!, _today());
    if (diff <= 0) return 0;
    if (diff == 1) return 1;
    if (diff == 2) return 2;
    if (diff < 30) return 3;
    return 4;
  }

  DateTime _nextWeekdayDate(int weekday) {
    final start = _today();
    var daysUntil = (weekday - start.weekday) % 7;
    if (daysUntil == 0) daysUntil = 7;
    return start.add(Duration(days: daysUntil));
  }

  Task? _findTaskByUid(String uid) {
    for (final t in _tasks) {
      if (t.uid == uid) return t;
    }
    return null;
  }

  void _refreshRecurring(Task task) {
    RecurrenceService.refresh(
      task,
      _tasks,
      now: _today(),
      archivedOrBinned: _archivedOrBinned,
    );
  }

  void _toggleEntry(Task entry) {
    setState(() {
      entry.toggleDone();
      entry.completedAt = entry.isDone ? DateTime.now() : null;
    });
    _save();
  }

  /// Swipe-to-reschedule: same as moving a task between home tabs, except
  /// the item stays in Research — only its due date changes.
  void _rescheduleEntry(Task entry, DateTime newDueDate) {
    if (entry.recurrenceParentUid != null) {
      entry.recurrenceOverride = true;
    }
    setState(() {
      entry.dueDate = newDueDate;
      final now = DateTime.now();
      entry.movedAt = now;
      entry.rescheduledAt = now;
      final master = entry.recurrenceParentUid != null
          ? _findTaskByUid(entry.recurrenceParentUid!)
          : entry;
      if (master != null) _refreshRecurring(master);
    });
    _save();
  }

  /// The expanded tile's "Pick due date", with the same recurring-series
  /// handling as the home page.
  void _changeDueDate(
    Task entry,
    DateTime newDueDate,
    RecurrenceEditScope scope,
  ) {
    setState(() {
      final parentUid = entry.recurrenceParentUid;
      if (parentUid != null) {
        final master = _findTaskByUid(parentUid);
        if (master == null) {
          entry.dueDate = newDueDate;
        } else if (scope == RecurrenceEditScope.thisAndFollowing) {
          final newMaster = RecurrenceService.reanchorSeriesFrom(
              master, _tasks, entry, newDueDate);
          _refreshRecurring(master);
          _refreshRecurring(newMaster);
        } else {
          entry.dueDate = newDueDate;
          entry.recurrenceOverride = true;
        }
      } else {
        entry.dueDate = newDueDate;
        if (entry.isRecurring) _refreshRecurring(entry);
      }
      final now = DateTime.now();
      entry.movedAt = now;
      entry.rescheduledAt = now;
    });
    _save();
  }

  /// Deletes [entry], asking — like the home tabs — whether a recurring
  /// item's delete covers just this event, this and following, or the
  /// whole series.
  Future<void> _requestDelete(Task entry) async {
    final isChild = entry.recurrenceParentUid != null;
    final master = isChild
        ? _findTaskByUid(entry.recurrenceParentUid!)
        : (entry.isRecurring ? entry : null);
    final hasOtherOccurrences = master != null &&
        (isChild || _tasks.any((t) => t.recurrenceParentUid == master.uid));
    if (master == null || !hasOtherOccurrences) {
      _deleteBatch([entry]);
      return;
    }

    final scope = await showRecurrenceScopeDialog(context, isDelete: true);
    if (scope == null || !mounted) return;

    final endType = master.recurrenceEndType;
    final endDate = master.recurrenceEndDate;
    final occurrenceCount = master.recurrenceOccurrenceCount;
    final exceptionDates = List.of(master.recurrenceExceptionDates);
    void restoreRule() {
      master.recurrenceEndType = endType;
      master.recurrenceEndDate = endDate;
      master.recurrenceOccurrenceCount = occurrenceCount;
      master.recurrenceExceptionDates = List.of(exceptionDates);
    }

    switch (scope) {
      case RecurrenceEditScope.allEvents:
        _deleteBatch(
          RecurrenceService.truncateSeriesBefore(
              master, _tasks, master.dueDate!),
          onUndo: restoreRule,
        );
        break;
      case RecurrenceEditScope.thisAndFollowing:
        _deleteBatch(
          RecurrenceService.truncateSeriesBefore(
              master, _tasks, entry.dueDate!),
          onUndo: restoreRule,
        );
        break;
      case RecurrenceEditScope.thisEvent:
        if (identical(entry, master)) {
          setState(() {
            RecurrenceService.promoteNextOccurrenceAsMaster(master, _tasks);
          });
          _deleteBatch([entry]);
        } else {
          final key = entry.recurrenceInstanceKey ??
              RecurrenceService.dayKey(entry.dueDate!);
          master.recurrenceExceptionDates.add(key);
          _deleteBatch(
            [entry],
            onUndo: () => master.recurrenceExceptionDates.remove(key),
          );
        }
        break;
    }
  }

  /// Moves [toDelete] to the Archived Items list, with an undo snackbar —
  /// exactly like deleting a task from the home tabs.
  void _deleteBatch(List<Task> toDelete, {VoidCallback? onUndo}) {
    if (toDelete.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final originalIndexes = <Task, int>{
      for (final t in toDelete) t: _tasks.indexOf(t),
    };

    setState(() {
      for (final t in toDelete) {
        _tasks.remove(t);
      }
    });
    _save();

    late Timer timer;
    timer = Timer(Config.delayDuration, () async {
      final deleted = await _repository.loadDeletedItems();
      final now = DateTime.now();
      for (final t in toDelete) {
        t.deletedAt = now;
        deleted.insert(0, t);
      }
      await _repository.saveDeletedItems(deleted);
      _archivedOrBinned = [..._archivedOrBinned, ...toDelete];
      messenger.hideCurrentSnackBar();
    });

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(toDelete.length == 1
              ? 'Deleted "${toDelete.first.title}"'
              : 'Deleted ${toDelete.length} events'),
          duration: Config.delayDuration,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              timer.cancel();
              messenger.hideCurrentSnackBar();
              if (!mounted) return;
              setState(() {
                onUndo?.call();
                final ordered = toDelete.toList()
                  ..sort((a, b) => (originalIndexes[a] ?? 0)
                      .compareTo(originalIndexes[b] ?? 0));
                for (final t in ordered) {
                  final at = (originalIndexes[t] ?? 0).clamp(0, _tasks.length);
                  _tasks.insert(at, t);
                }
              });
              _save();
            },
          ),
        ),
      );
  }

  Widget _buildTile(Task entry) {
    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    final usesCustomSwipe = isAndroid || kIsWeb;
    final tile = TaskTile(
      key: usesCustomSwipe ? ValueKey(entry.uid) : null,
      task: entry,
      pageIndex: _tabIndexForDueDate(entry.dueDate),
      onChanged: _save,
      onToggle: () => _toggleEntry(entry),
      onMove: (dest) => _rescheduleEntry(entry, _dueDateForTab(dest)),
      onMoveToWeekday: (weekday) =>
          _rescheduleEntry(entry, _nextWeekdayDate(weekday)),
      onMoveNext: () => _rescheduleEntry(
        entry,
        _dueDateForTab(
            (_tabIndexForDueDate(entry.dueDate) + 1) % Config.tabs.length),
      ),
      onDelete: () => _requestDelete(entry),
      onDueDateChanged: (_, newDueDate, scope) =>
          _changeDueDate(entry, newDueDate, scope),
      onRecurringChanged: () {
        setState(() => _refreshRecurring(entry));
        _save();
      },
      showSwipeButton: !isAndroid,
      swipeLeftDelete: Config.swipeLeftDelete,
    );
    if (usesCustomSwipe) return tile;
    return Dismissible(
      key: ValueKey(entry.uid),
      background: Container(
        color: Colors.red.withValues(alpha: 0.5),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _requestDelete(entry),
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Research',
        actions: [
          if (VoiceInboxService.isConfigured)
            IconButton(
              tooltip: "Check Claude's replies",
              icon: _checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.mark_chat_read_outlined),
              onPressed: () => _checkReplies(manual: true),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add research item',
        onPressed: _addEntry,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : sections.isEmpty
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
              : ListView(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                  children: [
                    for (final section in sections) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                        child: Text(
                          '${section.key} (${section.value.length})',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      for (final entry in section.value) _buildCard(entry),
                    ],
                  ],
                ),
    );
  }
}

class _ResearchEditResult {
  final String title;
  final String description;
  final String note;
  final String label;
  final DateTime? dueDate;

  const _ResearchEditResult({
    required this.title,
    required this.description,
    required this.note,
    required this.label,
    required this.dueDate,
  });
}

/// Add dialog owning its own text controllers, so the dialog's exit
/// animation never touches a disposed one (see task_detail's rule). Offers
/// the same fields a normal task's expanded tile does at creation time —
/// title, labels, description, note and an optional due date; everything
/// else (attachments, recurrence, ...) is edited on the tile afterwards.
class _ResearchEditDialog extends StatefulWidget {
  const _ResearchEditDialog();

  @override
  State<_ResearchEditDialog> createState() => _ResearchEditDialogState();
}

class _ResearchEditDialogState extends State<_ResearchEditDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String _label = '';
  DateTime? _dueDate;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked == null || !mounted) return;
    setState(() => _dueDate = picked);
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
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Note'),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(_dueDate == null
                      ? 'No due date'
                      : 'Due: ${_dueDate!.toLocal().toString().split(' ')[0]}'),
                ),
                if (_dueDate != null)
                  IconButton(
                    tooltip: 'Clear due date',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _dueDate = null),
                  ),
                TextButton(
                  onPressed: _pickDueDate,
                  child: const Text('Pick due date'),
                ),
              ],
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
              title: title,
              description: _descriptionController.text.trim(),
              note: _noteController.text.trim(),
              label: _label.trim(),
              dueDate: _dueDate,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
