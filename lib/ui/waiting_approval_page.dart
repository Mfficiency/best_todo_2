import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/task.dart';
import '../models/view_filter_rules.dart';
import '../services/food_diary_widget_service.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../services/log_service.dart';
import '../services/task_widget_service.dart';
import '../services/todoist_sync_service.dart';
import '../utils/label_utils.dart';
import '../utils/linkified_text.dart';
import 'subpage_app_bar.dart';

/// A pending item's swipe options: the approve side (lift the approval gate
/// and schedule it) or the deny side (drop it, or approve it onto one of a
/// few quick weekdays instead).
enum _PendingSwipeMode { approve, deny }

class _PendingWeekdayOption {
  final String label;
  final int weekday;

  const _PendingWeekdayOption(this.label, this.weekday);
}

/// Quick weekday shortcuts on the deny side — same set as the home list's
/// swipe-to-a-weekday shortcuts.
const _pendingSwipeWeekdayOptions = <_PendingWeekdayOption>[
  _PendingWeekdayOption('Fri', DateTime.friday),
  _PendingWeekdayOption('Sat', DateTime.saturday),
  _PendingWeekdayOption('Sun', DateTime.sunday),
  _PendingWeekdayOption('Mon', DateTime.monday),
];

/// Group title shown for a pending item with neither [Task.pendingSourceTitle]
/// nor [Task.createdAt] to fall back on — nothing left to group it by.
const String _unspecifiedGroupTitle = 'Unspecified';

String _two(int v) => v.toString().padLeft(2, '0');

/// `yyyy-MM-dd HH:mm` in local time — matches `TaskTile`'s sync-info dialog
/// formatting so date/time strings look the same everywhere in the app.
String _formatDateTime(DateTime dt) {
  final d = dt.toLocal();
  return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';
}

/// `yyyy-MM-dd HH:00` in local time — [createdAt] rounded down to the hour
/// it falls in, used to cluster pending items that predate
/// [Task.pendingSourceTitle]. A single sync run (or a batch typed/pasted in
/// one sitting) creates all its items within seconds of each other, so the
/// creation hour doubles as a proxy for "came from the same batch" — it also
/// naturally keeps different days apart, which covers the plain
/// group-by-date case.
String? _hourGroupLabel(DateTime? createdAt) {
  if (createdAt == null) return null;
  final d = createdAt.toLocal();
  return '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:00';
}

/// The group a pending [task] belongs to: its [Task.pendingSourceTitle] when
/// present (the normal case for items created since that field existed);
/// otherwise the hour it was created in ([_hourGroupLabel]); otherwise
/// [_unspecifiedGroupTitle] for items with no creation time to fall back on
/// either (created before [Task.createdAt] existed).
String _groupKeyFor(Task task) {
  final title = task.pendingSourceTitle?.trim();
  if (title != null && title.isNotEmpty) return title;
  return _hourGroupLabel(task.createdAt) ?? _unspecifiedGroupTitle;
}

/// Tasks pulled in via the Todoist workflow land here first — tagged with
/// [waitingApprovalToken] and hidden from every other list (home tabs,
/// wishlist, project boards; see `ItemViews`) — until approved or denied.
///
/// Self-contained like [WishlistPage]: loads and saves the whole task list
/// on its own, so the home page just reloads from storage when coming back
/// (see `HomePage._reloadTasksFromStorage`).
class WaitingApprovalPage extends StatefulWidget {
  const WaitingApprovalPage({Key? key}) : super(key: key);

  @override
  State<WaitingApprovalPage> createState() => _WaitingApprovalPageState();
}

class _WaitingApprovalPageState extends State<WaitingApprovalPage> {
  final ItemRepository _repository = ItemRepository.instance;

  /// The full task list; the page shows and mutates only the pending subset
  /// but always persists the whole list.
  List<Task> _tasks = <Task>[];
  bool _loading = true;

  /// Whether the list is shown grouped by [_groupKeyFor] instead of one flat
  /// list. Toggled from the app bar; not persisted — each visit starts on the
  /// flat list, matching the page's previous-only behavior.
  bool _groupByConversation = false;

  /// Which pending items are inline-expanded (creation date, source
  /// conversation, Todoist sync info). Several can be open at once.
  final Set<String> _expandedUids = <String>{};

  /// The uids currently selected in multi-select mode; empty means the page
  /// isn't in selection mode. Long-pressing a tile (or a group header)
  /// starts a selection; tapping other tiles/headers toggles them in and
  /// out while selecting.
  final Set<String> _selectedUids = <String>{};

  bool get _selecting => _selectedUids.isNotEmpty;

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

  /// Persists the list and redraws the home-screen widget from it — the
  /// widget is a view of the same list, so a denied task has to leave it
  /// too (the home page only pushes on its own saves).
  Future<void> _save() async {
    await _repository.saveItems(_tasks);
    await TaskWidgetService.sync(_tasks);
    await FoodDiaryWidgetService.sync(_tasks);
  }

  List<Task> _pending() => ItemViews.waitingApproval(
        _tasks,
        rules: Config.viewFilterRules[ViewFilterRules.approval],
      );

  /// [pending] partitioned by [_groupKeyFor], in first-seen order.
  Map<String, List<Task>> _groupedPending(List<Task> pending) {
    final grouped = <String, List<Task>>{};
    for (final task in pending) {
      grouped.putIfAbsent(_groupKeyFor(task), () => <Task>[]).add(task);
    }
    return grouped;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Day offsets for the [Config.tabs] destinations a pending item can be
  /// approved into, mirroring `HomePageState._offsetDays`. The last tab
  /// (Future) has no offset — it always resolves to the fixed far-future
  /// sentinel date.
  static const List<int> _tabOffsetDays = [0, 1, 2, 7, 30];

  DateTime _dueDateForTab(int tabIndex) {
    if (tabIndex >= _tabOffsetDays.length) return Task.futureBucketMarker;
    return _dateOnly(DateTime.now())
        .add(Duration(days: _tabOffsetDays[tabIndex]));
  }

  DateTime _nextWeekdayDate(int weekday) {
    final start = _dateOnly(DateTime.now());
    var daysUntil = (weekday - start.weekday) % 7;
    if (daysUntil == 0) daysUntil = 7;
    return start.add(Duration(days: daysUntil));
  }

  /// Removes [waitingApprovalToken] (and its legacy spellings), making the
  /// task visible wherever it belongs (today's list, a project, the
  /// wishlist, ...). The next Todoist sync pushes the shortened label array,
  /// so the tag disappears on the Todoist side too.
  void _approve(Task task) {
    setState(() {
      task.label = removeWaitingApprovalToken(task.label);
    });
    _save();
    LogService.add('WaitingApprovalPage._approve', 'Approved "${task.title}"');
  }

  /// Approves [task] and schedules it: due on the date [tabIndex] (an index
  /// into [Config.tabs]) maps to — the swipe-side quick-select shortcuts.
  void _approveWithDate(Task task, int tabIndex) {
    setState(() {
      task.label = removeWaitingApprovalToken(task.label);
      task.dueDate = _dueDateForTab(tabIndex);
      final now = DateTime.now();
      task.movedAt = now;
      task.rescheduledAt = now;
    });
    _save();
    LogService.add('WaitingApprovalPage._approve',
        'Approved "${task.title}", due ${task.dueDate}');
  }

  /// Approves [task], due on the next occurrence of [weekday].
  void _approveToWeekday(Task task, int weekday) {
    if (weekday < DateTime.monday || weekday > DateTime.sunday) return;
    setState(() {
      task.label = removeWaitingApprovalToken(task.label);
      task.dueDate = _nextWeekdayDate(weekday);
      final now = DateTime.now();
      task.movedAt = now;
      task.rescheduledAt = now;
    });
    _save();
    LogService.add('WaitingApprovalPage._approve',
        'Approved "${task.title}", due ${task.dueDate}');
  }

  /// Denies the task by sending it straight to the real Deleted bin — unlike
  /// a normal delete elsewhere in the app (which only archives), a denial was
  /// never wanted in the first place, so it skips the archive and starts
  /// aging toward permanent purge right away (recoverable from the bin until
  /// then). Same home-style undo window as the main list's delete swipe.
  void _deny(Task task) {
    final originalIndex = _tasks.indexOf(task);
    if (originalIndex < 0) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _tasks.removeAt(originalIndex));
    _save();
    LogService.add('WaitingApprovalPage._deny', 'Denied "${task.title}"');

    late Timer timer;
    timer = Timer(Config.delayDuration, () async {
      task.deletedAt = DateTime.now();
      task.autoDeleted = false;
      final binned = await _repository.loadBinItems();
      binned.insert(0, task);
      if (binned.length > 100) binned.removeLast();
      await _repository.saveBinItems(binned);
      messenger.hideCurrentSnackBar();
    });

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Denied "${task.title}"'),
          duration: Config.delayDuration,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              timer.cancel();
              messenger.hideCurrentSnackBar();
              if (!mounted) return;
              setState(() => _tasks.insert(originalIndex, task));
              _save();
            },
          ),
        ),
      );
  }

  void _toggleGrouping() =>
      setState(() => _groupByConversation = !_groupByConversation);

  void _toggleExpanded(Task task) {
    setState(() {
      if (!_expandedUids.remove(task.uid)) _expandedUids.add(task.uid);
    });
  }

  void _startSelection(Task task) => setState(() => _selectedUids.add(task.uid));

  void _toggleSelected(Task task) {
    setState(() {
      if (!_selectedUids.remove(task.uid)) _selectedUids.add(task.uid);
    });
  }

  void _cancelSelection() => setState(_selectedUids.clear);

  void _startSelectionForGroup(List<Task> tasks) {
    setState(() {
      for (final task in tasks) {
        _selectedUids.add(task.uid);
      }
    });
  }

  /// Tapping a group header while selecting toggles the whole group: fully
  /// selects it if any item was unselected, clears it if every item already
  /// was.
  void _toggleGroupSelected(List<Task> tasks) {
    setState(() {
      final allSelected = tasks.every((t) => _selectedUids.contains(t.uid));
      for (final task in tasks) {
        if (allSelected) {
          _selectedUids.remove(task.uid);
        } else {
          _selectedUids.add(task.uid);
        }
      }
    });
  }

  /// Approves every selected item in one go, exactly like the single plain
  /// Approve button (no due date is touched).
  void _approveSelection() {
    final targets =
        _pending().where((t) => _selectedUids.contains(t.uid)).toList();
    if (targets.isEmpty) return;
    setState(() {
      for (final task in targets) {
        task.label = removeWaitingApprovalToken(task.label);
      }
      _selectedUids.clear();
    });
    _save();
    LogService.add(
        'WaitingApprovalPage._approve', 'Approved ${targets.length} item(s)');
  }

  /// Denies every selected item in one go, with a single combined undo
  /// snackbar — the bulk equivalent of [_deny].
  void _denySelection() {
    final targets =
        _pending().where((t) => _selectedUids.contains(t.uid)).toList();
    if (targets.isEmpty) return;
    final originalIndices = <Task, int>{
      for (final task in targets) task: _tasks.indexOf(task),
    }..removeWhere((_, index) => index < 0);
    if (originalIndices.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      for (final task in originalIndices.keys) {
        _tasks.remove(task);
      }
      _selectedUids.clear();
    });
    _save();
    LogService.add('WaitingApprovalPage._deny',
        'Denied ${originalIndices.length} item(s)');

    late Timer timer;
    timer = Timer(Config.delayDuration, () async {
      final binned = await _repository.loadBinItems();
      for (final task in originalIndices.keys) {
        task.deletedAt = DateTime.now();
        task.autoDeleted = false;
        binned.insert(0, task);
      }
      while (binned.length > 100) {
        binned.removeLast();
      }
      await _repository.saveBinItems(binned);
      messenger.hideCurrentSnackBar();
    });

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(originalIndices.length == 1
              ? 'Denied "${originalIndices.keys.first.title}"'
              : 'Denied ${originalIndices.length} items'),
          duration: Config.delayDuration,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              timer.cancel();
              messenger.hideCurrentSnackBar();
              if (!mounted) return;
              setState(() {
                final byIndex = originalIndices.entries.toList()
                  ..sort((a, b) => a.value.compareTo(b.value));
                for (final entry in byIndex) {
                  final index = entry.value.clamp(0, _tasks.length);
                  _tasks.insert(index, entry.key);
                }
              });
              _save();
            },
          ),
        ),
      );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    if (_selecting) {
      return AppBar(
        leading: IconButton(
          tooltip: 'Cancel selection',
          icon: const Icon(Icons.close),
          onPressed: _cancelSelection,
        ),
        title: Text('${_selectedUids.length} selected'),
        actions: [
          IconButton(
            tooltip: 'Approve selected',
            icon: const Icon(Icons.check_circle_outline),
            onPressed: _approveSelection,
          ),
          IconButton(
            tooltip: 'Deny selected',
            icon: const Icon(Icons.cancel_outlined),
            onPressed: _denySelection,
          ),
        ],
      );
    }
    return buildSubpageAppBar(
      context,
      title: 'Waiting for Approval',
      actions: [
        IconButton(
          tooltip:
              _groupByConversation ? 'Show as one list' : 'Group by conversation',
          icon: Icon(
              _groupByConversation ? Icons.view_list : Icons.view_agenda_outlined),
          onPressed: _toggleGrouping,
        ),
      ],
    );
  }

  Widget _buildTile(Task task) => _PendingTaskTile(
        key: ValueKey(task.uid),
        task: task,
        selecting: _selecting,
        selected: _selectedUids.contains(task.uid),
        expanded: _expandedUids.contains(task.uid),
        onApprove: () => _approve(task),
        onApproveWithDate: (tabIndex) => _approveWithDate(task, tabIndex),
        onApproveToWeekday: (weekday) => _approveToWeekday(task, weekday),
        onDeny: () => _deny(task),
        onToggleSelected: () => _toggleSelected(task),
        onStartSelection: () => _startSelection(task),
        onToggleExpanded: () => _toggleExpanded(task),
      );

  Widget _buildFlatList(List<Task> pending) => ListView.builder(
        itemCount: pending.length,
        itemBuilder: (context, index) => _buildTile(pending[index]),
      );

  Widget _buildGroupedList(List<Task> pending) {
    final grouped = _groupedPending(pending);
    return ListView(
      children: [
        for (final entry in grouped.entries) ...[
          _ApprovalGroupHeader(
            title: entry.key,
            count: entry.value.length,
            selecting: _selecting,
            allSelected: entry.value.every((t) => _selectedUids.contains(t.uid)),
            onTap: _selecting
                ? () => _toggleGroupSelected(entry.value)
                : null,
            onLongPress: _selecting
                ? null
                : () => _startSelectionForGroup(entry.value),
          ),
          for (final task in entry.value) _buildTile(task),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _loading ? <Task>[] : _pending();
    return Scaffold(
      appBar: _buildAppBar(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : pending.isEmpty
              ? const Center(child: Text('Nothing waiting for approval'))
              : _groupByConversation
                  ? _buildGroupedList(pending)
                  : _buildFlatList(pending),
    );
  }
}

/// Header row above a conversation group's items in the grouped view: the
/// group's title, its item count and, while selecting, a checkbox that
/// selects/deselects the whole group at once. Long-pressing it (outside
/// selection mode) starts a selection with the whole group already checked.
class _ApprovalGroupHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool selecting;
  final bool allSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ApprovalGroupHeader({
    required this.title,
    required this.count,
    required this.selecting,
    required this.allSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
        child: Row(
          children: [
            if (selecting) ...[
              // A plain icon rather than a real Checkbox: a Checkbox owns
              // its own tap recognizer, which would compete with this row's
              // InkWell for the same tap and risk firing [onTap] twice.
              Icon(
                allSelected ? Icons.check_box : Icons.check_box_outline_blank,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                '$title ($count)',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pending item rendered like a home-page task tile, with exactly the home
/// list's swipe gestures: swiping toward the approve side offers Today/
/// Tomorrow/Day After Tomorrow/Next Week/Next Month/Future shortcuts and
/// approves the item onto today when the countdown runs out; swiping toward
/// the deny side offers Deny plus Fri/Sat/Sun/Mon shortcuts (which approve
/// the item onto that day) and denies it when the countdown runs out.
/// Directions follow [Config.swipeLeftDelete] like the home list. The plain
/// leading/trailing Approve/Deny icon buttons stay as one-tap alternatives
/// that don't touch the due date.
///
/// Tapping the tile toggles an inline details panel (creation date, source
/// conversation, Todoist sync info); long-pressing it starts multi-select,
/// during which the leading icon becomes a checkbox, tapping toggles
/// selection instead of expanding, and the swipe gestures are disabled.
class _PendingTaskTile extends StatefulWidget {
  final Task task;
  final bool selecting;
  final bool selected;
  final bool expanded;
  final VoidCallback onApprove;
  final void Function(int tabIndex) onApproveWithDate;
  final void Function(int weekday) onApproveToWeekday;
  final VoidCallback onDeny;
  final VoidCallback onToggleSelected;
  final VoidCallback onStartSelection;
  final VoidCallback onToggleExpanded;

  const _PendingTaskTile({
    Key? key,
    required this.task,
    required this.selecting,
    required this.selected,
    required this.expanded,
    required this.onApprove,
    required this.onApproveWithDate,
    required this.onApproveToWeekday,
    required this.onDeny,
    required this.onToggleSelected,
    required this.onStartSelection,
    required this.onToggleExpanded,
  }) : super(key: key);

  @override
  State<_PendingTaskTile> createState() => _PendingTaskTileState();
}

class _PendingTaskTileState extends State<_PendingTaskTile>
    with SingleTickerProviderStateMixin {
  _PendingSwipeMode? _mode;
  Timer? _timer;
  late final AnimationController _progressController;
  double _dragOffset = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: Config.delayDuration,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  void _startOptions(_PendingSwipeMode mode) {
    setState(() => _mode = mode);
    _timer?.cancel();
    _progressController.reset();
    _progressController.forward();
    _timer = Timer(Config.delayDuration, () {
      if (!mounted || _mode != mode) return;
      _progressController.stop();
      setState(() => _mode = null);
      if (mode == _PendingSwipeMode.approve) {
        widget.onApproveWithDate(0); // Today
      } else {
        widget.onDeny();
      }
    });
  }

  void _startApproveOptions() => _startOptions(_PendingSwipeMode.approve);
  void _startDenyOptions() => _startOptions(_PendingSwipeMode.deny);

  void _closeOptions() {
    _timer?.cancel();
    _progressController.stop();
    if (mounted) setState(() => _mode = null);
  }

  void _selectApprove(int tabIndex) {
    _closeOptions();
    widget.onApproveWithDate(tabIndex);
  }

  void _selectDeny() {
    _closeOptions();
    widget.onDeny();
  }

  void _selectWeekday(int weekday) {
    _closeOptions();
    widget.onApproveToWeekday(weekday);
  }

  /// Creation date, source conversation and Todoist sync info shown when
  /// [widget.expanded] is true.
  Widget _buildDetails(BuildContext context) {
    final task = widget.task;
    final theme = Theme.of(context);
    final detailStyle = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final entry = TodoistSyncService.instance.entryForLocalUid(task.uid);
    final lines = <String>[];
    if (task.createdAt != null) {
      lines.add('Created: ${_formatDateTime(task.createdAt!)}');
    }
    lines.add('From: ${_groupKeyFor(task)}');
    if (entry != null) {
      lines.add('Synced from Todoist: ${_formatDateTime(entry.syncedAt)}');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines) Text(line, style: detailStyle),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final listTile = ListTile(
      title: LinkifiedText(task.title),
      subtitle: task.description.isNotEmpty
          ? LinkifiedText(task.description)
          : null,
      isThreeLine: task.description.isNotEmpty,
      leading: widget.selecting
          ? Checkbox(
              value: widget.selected,
              onChanged: (_) => widget.onToggleSelected(),
            )
          : IconButton(
              icon: const Icon(Icons.check_circle_outline),
              tooltip: 'Approve',
              color: Colors.green,
              onPressed: widget.onApprove,
            ),
      trailing: widget.selecting
          ? null
          : IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Deny',
              color: Theme.of(context).colorScheme.error,
              onPressed: widget.onDeny,
            ),
      onTap: widget.selecting ? widget.onToggleSelected : widget.onToggleExpanded,
      onLongPress: widget.selecting ? null : widget.onStartSelection,
    );

    final stackTile = Stack(
      children: [
        listTile,
        if (_mode != null)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).cardColor.withValues(alpha: 0.9),
              alignment: Alignment.centerRight,
              // The ListTile's own single-line height (56) leaves the
              // button row + progress bar column no slack, so a slightly
              // taller TextButton tap target (theme/density dependent)
              // overflows it — scale the whole column down rather than
              // chase exact pixel budgets across themes.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_mode == _PendingSwipeMode.approve)
                          for (var i = 0; i < Config.tabs.length; i++)
                            TextButton(
                              onPressed: () => _selectApprove(i),
                              child: Text(Config.tabs[i]),
                            ),
                        if (_mode == _PendingSwipeMode.deny) ...[
                          TextButton(
                            onPressed: _selectDeny,
                            child: const Text('Deny'),
                          ),
                          for (final option in _pendingSwipeWeekdayOptions)
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
          ),
      ],
    );

    final tileWithDetails = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        stackTile,
        if (widget.expanded) _buildDetails(context),
      ],
    );

    final slide = AnimatedSlide(
      offset: Offset(_dragOffset / MediaQuery.of(context).size.width, 0),
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
      child: tileWithDetails,
    );

    Widget? background;
    if (_dragOffset != 0) {
      final originalWasRight = _mode != null &&
          Config.swipeLeftDelete == (_mode == _PendingSwipeMode.approve);
      final isCancelDrag = _mode != null &&
          ((originalWasRight && _dragOffset < 0) ||
              (!originalWasRight && _dragOffset > 0));
      final dragToDeny =
          Config.swipeLeftDelete ? _dragOffset < 0 : _dragOffset > 0;
      if (isCancelDrag) {
        final alignment =
            _dragOffset < 0 ? Alignment.centerRight : Alignment.centerLeft;
        background = Positioned.fill(
          child: Container(
            color: Colors.orange.withValues(alpha: 0.5),
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      } else if (dragToDeny) {
        final alignment = Config.swipeLeftDelete
            ? Alignment.centerRight
            : Alignment.centerLeft;
        background = Positioned.fill(
          child: Container(
            color: Colors.red.withValues(alpha: 0.5),
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: const Icon(Icons.cancel_outlined, color: Colors.white),
          ),
        );
      } else {
        final alignment = Config.swipeLeftDelete
            ? Alignment.centerLeft
            : Alignment.centerRight;
        background = Positioned.fill(
          child: Container(
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Icon(Icons.check_circle_outline,
                color: Theme.of(context).colorScheme.primary),
          ),
        );
      }
    }

    Widget content = Stack(
      children: [
        if (background != null) background,
        slide,
      ],
    );

    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    if ((isAndroid || kIsWeb) && !widget.selecting) {
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
          if (_mode != null) {
            final originalWasRight = Config.swipeLeftDelete ==
                (_mode == _PendingSwipeMode.approve);
            if ((originalWasRight && swipedLeft) ||
                (!originalWasRight && swipedRight)) {
              _closeOptions();
            }
          } else if (Config.swipeLeftDelete) {
            if (swipedRight) {
              _startApproveOptions();
            } else if (swipedLeft) {
              _startDenyOptions();
            }
          } else {
            if (swipedRight) {
              _startDenyOptions();
            } else if (swipedLeft) {
              _startApproveOptions();
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

    return widget.selected
        ? Container(
            color: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.4),
            child: content,
          )
        : content;
  }
}
