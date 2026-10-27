import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/approval_quick_tag.dart';
import '../models/task.dart';
import '../models/view_filter_rules.dart';
import '../services/approval_quick_tag_service.dart';
import '../services/food_diary_widget_service.dart';
import '../services/grocery_category_service.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../services/log_service.dart';
import '../services/task_widget_service.dart';
import '../services/todoist_sync_service.dart';
import '../services/voice_inbox_service.dart';
import '../utils/label_style.dart';
import '../utils/label_utils.dart';
import '../utils/linkified_text.dart';
import '../utils/voice_inbox.dart';
import 'subpage_app_bar.dart';
import 'task_detail_page.dart';

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

/// How the pending list (and, in grouped view, each group's items and the
/// groups themselves) is ordered. [newest] is the default — most recently
/// created items first.
enum _SortMode { newest, oldest, alphabetical }

/// How the pending list is sectioned: by voice-inbox category (the default —
/// see `docs/proposals/voice-inbox.md`), by the conversation it came from,
/// or not at all.
enum _Grouping { category, conversation, none }

/// The section a pending [task] is in when grouped by category.
String _categoryOf(Task task) => ApprovalGroups.of(task.approvalGroup);

/// Human label for a [Task.approvalSuggestion], e.g. "Tomorrow" or "Next";
/// null when there's nothing usable to show.
String? _suggestionLabel(Task task) {
  final group = _categoryOf(task);
  if (ApprovalGroups.isDated(group)) {
    final tab = suggestedTabIndex(task.approvalSuggestion);
    return tab == null ? null : Config.tabs[tab];
  }
  if (ApprovalGroups.isStateful(group)) {
    final state = suggestedState(task.approvalSuggestion);
    return state == null ? null : BacklogStates.title(state);
  }
  return null;
}

/// The state a Backlog/Research item is approved into when its swipe
/// countdown runs out: the routine's suggestion, else Next.
String _defaultStateFor(Task task) =>
    suggestedState(task.approvalSuggestion) ?? BacklogStates.next;

String _two(int v) => v.toString().padLeft(2, '0');

/// `yyyy-MM-dd` in local time — the date-only prefix shown first in every
/// group header, regardless of what the group's title is.
String _formatDateOnly(DateTime dt) {
  final d = dt.toLocal();
  return '${d.year}-${_two(d.month)}-${_two(d.day)}';
}

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

  /// How the list is sectioned. Picked from the app bar's "Group by" menu;
  /// not persisted — each visit starts grouped by category, the sections the
  /// per-group swipe options belong to.
  _Grouping _grouping = _Grouping.category;

  /// Current ordering of the pending list (and, in grouped view, each
  /// group's items and the groups themselves — see [_groupedPending]).
  /// Toggled from the app bar; not persisted, same as [_grouping].
  _SortMode _sortMode = _SortMode.newest;

  /// Which pending items are inline-expanded (creation date, source
  /// conversation, Todoist sync info). Several can be open at once.
  final Set<String> _expandedUids = <String>{};

  /// The uids currently selected in multi-select mode. The app bar's Select
  /// button (or long-pressing a group header) starts a selection; tapping
  /// tiles/headers toggles them in and out while selecting. Long-pressing a
  /// tile no longer selects — it drags the item to another category.
  final Set<String> _selectedUids = <String>{};

  /// True from the Select button until the selection is canceled or acted
  /// on, so the page stays in selection mode with nothing checked yet.
  bool _selectionMode = false;

  bool get _selecting => _selectionMode || _selectedUids.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await _repository.loadItems();
    // Self-contained like the task list load: the quick-tag buttons at the
    // top of the expanded details panel need this loaded before they can
    // render, and this page is the only place they're shown.
    await ApprovalQuickTagService.instance.load();
    await GroceryCategoryService.instance.load();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  /// Persists the list and redraws the home-screen widget from it — the
  /// widget is a view of the same list, so a denied task has to leave it
  /// too (the home page only pushes on its own saves).
  /// Set while "Approve selected" runs each item's own approve path, so the
  /// list is written once at the end instead of once per item.
  bool _batching = false;

  /// Routine fires queued by an approval, run once the approval is saved
  /// (each one syncs first, and the sync must see the saved approval).
  final List<Future<String?> Function()> _pendingFires = [];

  /// Saves, then runs [_pendingFires] one by one. A failed fire shows a
  /// SnackBar; afterwards the list is reloaded, since the syncs inside the
  /// fires may have pulled changes into tasks.json.
  Future<void> _saveThenFire() async {
    if (_batching) return;
    await _save();
    if (_pendingFires.isEmpty) return;
    final fires = List.of(_pendingFires);
    _pendingFires.clear();
    final messenger = ScaffoldMessenger.maybeOf(context);
    for (final fire in fires) {
      final error = await fire();
      if (error != null) {
        messenger?.showSnackBar(SnackBar(content: Text(error)));
      }
    }
    final reloaded = await _repository.loadItems();
    if (!mounted) return;
    setState(() => _tasks = reloaded);
  }

  Future<void> _save() async {
    if (_batching) return;
    await _repository.saveItems(_tasks);
    await TaskWidgetService.sync(_tasks);
    await FoodDiaryWidgetService.sync(_tasks);
  }

  List<Task> _pending() => ItemViews.waitingApproval(
        _tasks,
        rules: Config.viewFilterRules[ViewFilterRules.approval],
      );

  /// [Task.createdAt] for sort comparisons, with a fixed epoch fallback for
  /// items that predate the field — they sort as the oldest of the bunch
  /// either way.
  DateTime _sortDate(Task task) =>
      task.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// [pending] ordered per [_sortMode]. Groups (see [_groupedPending]) form
  /// from this order, so sorting also decides which group appears first —
  /// whichever group its first item (per the chosen order) belongs to.
  List<Task> _sortedPending(List<Task> pending) {
    final sorted = List<Task>.from(pending);
    switch (_sortMode) {
      case _SortMode.newest:
        sorted.sort((a, b) => _sortDate(b).compareTo(_sortDate(a)));
        break;
      case _SortMode.oldest:
        sorted.sort((a, b) => _sortDate(a).compareTo(_sortDate(b)));
        break;
      case _SortMode.alphabetical:
        sorted.sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
    }
    return sorted;
  }

  /// [pending] partitioned by [_groupKeyFor], in first-seen order.
  Map<String, List<Task>> _groupedPending(List<Task> pending) {
    final grouped = <String, List<Task>>{};
    for (final task in pending) {
      grouped.putIfAbsent(_groupKeyFor(task), () => <Task>[]).add(task);
    }
    return grouped;
  }

  /// Whether [key] is a real [Task.pendingSourceTitle] rather than one of
  /// [_groupKeyFor]'s date-based fallbacks (an hour label, or
  /// [_unspecifiedGroupTitle]) — those already show a date of their own, so
  /// the group header only needs the extra leading date for a title group.
  bool _groupNeedsLeadingDate(String key, Task sample) =>
      sample.pendingSourceTitle?.trim() == key;

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

  /// Lifts the approval gate on [task] — every approve path starts here.
  /// Removes [waitingApprovalToken] (and its legacy spellings); the next
  /// Todoist sync pushes the shortened label array, so the tag disappears on
  /// the Todoist side too. A Migros/Lemmon item also gets its work-context
  /// label, which is what routes it to Worklist/Lemmon (and the home list's
  /// MLR/Lemmon toggles).
  void _liftGate(Task task) {
    task.label = removeWaitingApprovalToken(task.label);
    task.approvedAt = DateTime.now();
    switch (_categoryOf(task)) {
      case ApprovalGroups.migros:
        task.label = addLabelToken(task.label, worklistToken);
        break;
      case ApprovalGroups.lemmon:
        task.label = addLabelToken(task.label, lemmonToken);
        break;
    }
  }

  /// The plain Approve button (and "Approve selected"): approves [task] into
  /// its category with the routine's suggestion when there is one — a dated
  /// item with no suggestion keeps its date untouched, exactly like before
  /// the voice inbox. An unsorted (Other) item is approved as a plain task.
  void _approve(Task task) {
    final group = _categoryOf(task);
    if (ApprovalGroups.isDated(group)) {
      final tab = suggestedTabIndex(task.approvalSuggestion);
      if (tab != null) return _approveWithDate(task, tab);
    } else if (ApprovalGroups.isStateful(group)) {
      return _approveToState(task, _defaultStateFor(task));
    } else if (group == ApprovalGroups.groceries) {
      return _approveToGroceries(task);
    } else if (group == ApprovalGroups.food) {
      return _approveToFoodDiary(task);
    }
    setState(() => _liftGate(task));
    _save();
    LogService.add('WaitingApprovalPage._approve', 'Approved "${task.title}"');
  }

  /// Approves [task] and schedules it: due on the date [tabIndex] (an index
  /// into [Config.tabs]) maps to — the swipe-side quick-select shortcuts.
  void _approveWithDate(Task task, int tabIndex) {
    setState(() {
      _liftGate(task);
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
      _liftGate(task);
      task.dueDate = _nextWeekdayDate(weekday);
      final now = DateTime.now();
      task.movedAt = now;
      task.rescheduledAt = now;
    });
    _save();
    LogService.add('WaitingApprovalPage._approve',
        'Approved "${task.title}", due ${task.dueDate}');
  }

  /// Approves a Backlog item into the Wishlist or a Research item into the
  /// Research tool, in [state] (Active / Next / Someday). Any other
  /// category approved this way (e.g. from "Approve selected") goes to the
  /// Wishlist.
  ///
  /// With the voice-inbox routine set up, a Backlog approval also asks it to
  /// write the item's Obsidian page, and a Research item approved straight
  /// into Active starts its research round — fired after the save (see
  /// [_saveThenFire]).
  void _approveToState(Task task, String state) {
    final research = _categoryOf(task) == ApprovalGroups.research;
    setState(() {
      _liftGate(task);
      if (research) {
        task.isResearch = true;
      } else {
        task.isWish = true;
      }
      setBacklogState(task, state);
    });
    if (VoiceInboxService.isConfigured) {
      final service = VoiceInboxService.instance;
      if (!research) {
        VoiceInboxService.markObsidianRequested(task);
        _pendingFires.add(() => service.runFire(task,
            () => service.fireWritePage(task),
            (t) => t.obsidianRequestedAt = null));
      } else if (state == BacklogStates.active) {
        VoiceInboxService.markResearchRequested(task);
        _pendingFires.add(() => service.runFire(task,
            () => service.fireResearchQuestions(task),
            (t) => t.researchStage = null));
      }
    }
    _saveThenFire();
    LogService.add('WaitingApprovalPage._approve',
        'Approved "${task.title}" as ${BacklogStates.title(state)}');
  }

  /// Approves [task] onto the grocery list. Something already on the list
  /// is unchecked instead of added twice (the pending item then just goes
  /// away) — see [GroceryList.add].
  void _approveToGroceries(Task task) {
    setState(() {
      _liftGate(task);
      final category = task.groceryCategory == null
          ? null
          : GroceryCategoryService.instance.resolve(task.groceryCategory);
      final kept = GroceryList.add(_tasks, task, category: category);
      if (!identical(kept, task)) _tasks.remove(task);
    });
    _save();
    LogService.add('WaitingApprovalPage._approve',
        'Approved "${task.title}" onto the grocery list');
  }

  /// Approves [task] into the Food Diary (only reachable for an item dragged
  /// into the Food diary group — routine-sorted food skips approval).
  void _approveToFoodDiary(Task task) {
    setState(() {
      _liftGate(task);
      task.isEatingHabit = true;
      if (task.dueDate == null || !task.hasExplicitTime) {
        task.dueDate = task.createdAt ?? DateTime.now();
        task.hasExplicitTime = true;
      }
    });
    _save();
    LogService.add('WaitingApprovalPage._approve',
        'Approved "${task.title}" into the Food Diary');
  }

  /// Moves a pending [task] into another category — a long-press drag onto
  /// a section, or the Other picker. The item stays waiting for approval;
  /// its suggested destination resets to the new group's default.
  void _moveToGroup(Task task, String group) {
    if (_categoryOf(task) == group) return;
    setState(() {
      task.approvalGroup = group;
      task.approvalSuggestion = null;
    });
    _save();
    LogService.add('WaitingApprovalPage._moveToGroup',
        'Moved "${task.title}" to ${ApprovalGroups.title(group)}');
  }

  /// Asks which category [task] belongs in (the Other group's swipe, and the
  /// long press outside the category view) and moves it there.
  Future<void> _pickGroup(Task task) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move "${task.title}" to'),
        children: [
          for (final group in ApprovalGroups.pickable)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(group),
              child: Text(ApprovalGroups.title(group)),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    _moveToGroup(task, picked);
  }

  /// Approves [task] and routes it straight into the tool [tag] names
  /// (Wishlist/Research today — see [ApprovalQuickTag.targets]) by flipping
  /// that tool's membership flag on the task, exactly like the plain
  /// Approve button plus a manual flag toggle would. Reached from the quick-
  /// tag buttons at the top of the expanded details panel — see
  /// [_PendingTaskTileState._buildQuickTags].
  void _approveWithQuickTag(Task task, ApprovalQuickTag tag) {
    setState(() {
      _liftGate(task);
      switch (tag.target) {
        case ApprovalQuickTag.wishlistTarget:
          task.isWish = true;
          break;
        case ApprovalQuickTag.researchTarget:
          task.isResearch = true;
          break;
      }
    });
    _save();
    LogService.add('WaitingApprovalPage._approve',
        'Approved "${task.title}" into ${tag.target}');
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

  void _setGrouping(_Grouping grouping) =>
      setState(() => _grouping = grouping);

  void _setSortMode(_SortMode mode) => setState(() => _sortMode = mode);

  void _toggleExpanded(Task task) {
    setState(() {
      if (!_expandedUids.remove(task.uid)) _expandedUids.add(task.uid);
    });
  }

  void _toggleSelected(Task task) {
    setState(() {
      if (!_selectedUids.remove(task.uid)) _selectedUids.add(task.uid);
    });
  }

  void _cancelSelection() => setState(() {
        _selectedUids.clear();
        _selectionMode = false;
      });

  void _enterSelectionMode() => setState(() => _selectionMode = true);

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

  /// Approves every selected item in one go, each exactly like its own plain
  /// Approve button (its category, with the routine's suggestion if any).
  void _approveSelection() {
    final targets =
        _pending().where((t) => _selectedUids.contains(t.uid)).toList();
    if (targets.isEmpty) return;
    _batching = true;
    try {
      for (final task in targets) {
        _approve(task);
      }
    } finally {
      _batching = false;
    }
    setState(() {
      _selectedUids.clear();
      _selectionMode = false;
    });
    _saveThenFire();
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
      _selectionMode = false;
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
          tooltip: 'Select',
          icon: const Icon(Icons.checklist),
          onPressed: _enterSelectionMode,
        ),
        PopupMenuButton<_SortMode>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort),
          initialValue: _sortMode,
          onSelected: _setSortMode,
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _SortMode.newest,
              child: Text('Newest first'),
            ),
            PopupMenuItem(
              value: _SortMode.oldest,
              child: Text('Oldest first'),
            ),
            PopupMenuItem(
              value: _SortMode.alphabetical,
              child: Text('Alphabetical'),
            ),
          ],
        ),
        PopupMenuButton<_Grouping>(
          tooltip: 'Group by',
          icon: const Icon(Icons.view_agenda_outlined),
          initialValue: _grouping,
          onSelected: _setGrouping,
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _Grouping.category,
              child: Text('By category'),
            ),
            PopupMenuItem(
              value: _Grouping.conversation,
              child: Text('By conversation'),
            ),
            PopupMenuItem(
              value: _Grouping.none,
              child: Text('One list'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTile(Task task) => _PendingTaskTile(
        key: ValueKey(task.uid),
        task: task,
        group: _categoryOf(task),
        draggable: _grouping == _Grouping.category,
        selecting: _selecting,
        selected: _selectedUids.contains(task.uid),
        expanded: _expandedUids.contains(task.uid),
        onApprove: () => _approve(task),
        onApproveWithDate: (tabIndex) => _approveWithDate(task, tabIndex),
        onApproveToWeekday: (weekday) => _approveToWeekday(task, weekday),
        onApproveToState: (state) => _approveToState(task, state),
        onApproveToGroceries: () => _approveToGroceries(task),
        onApproveToFoodDiary: () => _approveToFoodDiary(task),
        onPickGroup: () => _pickGroup(task),
        onApproveWithQuickTag: (tag) => _approveWithQuickTag(task, tag),
        onDeny: () => _deny(task),
        onToggleSelected: () => _toggleSelected(task),
        onToggleExpanded: () => _toggleExpanded(task),
      );

  /// The category view: one section per non-empty category, in
  /// [ApprovalGroups.all] order. Each section is a drop target, so a
  /// long-press drag of an item onto another section re-sorts it.
  Widget _buildCategoryList(List<Task> pending) {
    final byGroup = <String, List<Task>>{};
    for (final task in pending) {
      byGroup.putIfAbsent(_categoryOf(task), () => <Task>[]).add(task);
    }
    final groups =
        ApprovalGroups.all.where((g) => byGroup.containsKey(g)).toList();
    // While dragging, every pickable category is offered as a target — an
    // empty one shows as a slim header so an item can be moved into it.
    return ListView(
      children: [
        for (final group in {...groups, ...ApprovalGroups.pickable}
            .where((g) => byGroup.containsKey(g) || _dragging))
          DragTarget<String>(
            key: ValueKey('approval-group-$group'),
            onWillAcceptWithDetails: (details) => true,
            onAcceptWithDetails: (details) {
              final task = pending.cast<Task?>().firstWhere(
                  (t) => t?.uid == details.data,
                  orElse: () => null);
              if (task != null) _moveToGroup(task, group);
            },
            builder: (context, candidates, rejected) {
              final items = byGroup[group] ?? const <Task>[];
              final highlighted = candidates.isNotEmpty;
              return Container(
                color: highlighted
                    ? Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.5)
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ApprovalGroupHeader(
                      date: null,
                      title: ApprovalGroups.title(group),
                      count: items.length,
                      selecting: _selecting,
                      allSelected: items.isNotEmpty &&
                          items.every((t) => _selectedUids.contains(t.uid)),
                      onTap: _selecting && items.isNotEmpty
                          ? () => _toggleGroupSelected(items)
                          : null,
                      onLongPress: _selecting || items.isEmpty
                          ? null
                          : () => _startSelectionForGroup(items),
                    ),
                    for (final task in items) _buildTile(task),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  /// True while an item is being long-press dragged (category view), so the
  /// empty categories show up as drop targets too.
  bool _dragging = false;

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
            date: _groupNeedsLeadingDate(entry.key, entry.value.first)
                ? entry.value.first.createdAt
                : null,
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
    final pending = _loading ? <Task>[] : _sortedPending(_pending());
    return Scaffold(
      appBar: _buildAppBar(context),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : pending.isEmpty
              ? const Center(child: Text('Nothing waiting for approval'))
              : NotificationListener<_PendingDragNotification>(
                  onNotification: (n) {
                    if (_dragging != n.dragging) {
                      setState(() => _dragging = n.dragging);
                    }
                    return true;
                  },
                  child: switch (_grouping) {
                    _Grouping.category => _buildCategoryList(pending),
                    _Grouping.conversation => _buildGroupedList(pending),
                    _Grouping.none => _buildFlatList(pending),
                  },
                ),
    );
  }
}

/// Header row above a conversation group's items in the grouped view: the
/// group's title, its item count and, while selecting, a checkbox that
/// selects/deselects the whole group at once. Long-pressing it (outside
/// selection mode) starts a selection with the whole group already checked.
class _ApprovalGroupHeader extends StatelessWidget {
  /// The group's leading date — always shown ahead of [title], even though
  /// [title] (a [Task.pendingSourceTitle], usually) already gives the group
  /// a name of its own. Taken from whichever item currently sorts first
  /// within the group, so it tracks the active sort mode.
  final DateTime? date;
  final String title;
  final int count;
  final bool selecting;
  final bool allSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _ApprovalGroupHeader({
    required this.date,
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
                date != null
                    ? '${_formatDateOnly(date!)}  $title ($count)'
                    : '$title ($count)',
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

/// Bubbled up by a [_PendingTaskTile] when a long-press drag starts or ends,
/// so the page can offer the empty categories as drop targets meanwhile.
class _PendingDragNotification extends Notification {
  final bool dragging;
  const _PendingDragNotification(this.dragging);
}

/// A pending item rendered like a home-page task tile, with the home list's
/// swipe gestures — and options that depend on the item's voice-inbox
/// [group]:
///
/// * Todo / Migros / Lemmon (and food): the approve side offers Today/
///   Tomorrow/Day After Tomorrow/Next Week/Next Month/Future; the deny side
///   offers Deny plus Fri/Sat/Sun/Mon shortcuts (which approve the item onto
///   that day).
/// * Backlog / Research: the approve side offers Active / Next / Someday;
///   the deny side just Deny.
/// * Groceries: the approve side offers "Add to list"; the deny side Deny.
/// * Other: swiping toward approve opens the category picker instead (the
///   item stays waiting, in its new category); the deny side Deny.
///
/// Letting the countdown run out applies the routine's suggestion (shown as
/// a "→ …" chip on the row) or the group's default — Today, Next, "Add to
/// list" — on the approve side, Deny on the deny side. Directions follow
/// [Config.swipeLeftDelete] like the home list. The plain leading/trailing
/// Approve/Deny icon buttons stay as one-tap alternatives.
///
/// Tapping the tile toggles an inline details panel (creation date, source
/// conversation, Todoist sync info, Obsidian project/transcript) whose very
/// first row is a set of quick-tag buttons (Settings > Tasks > Approval quick
/// tags — Wishlist/Research by default). In the category view a long press
/// picks the item up to drag it onto another category's section ([draggable]);
/// in the other views a long press opens the category picker. While the page
/// is selecting, the leading icon becomes a checkbox, tapping toggles
/// selection instead of expanding, and the swipe gestures are disabled.
class _PendingTaskTile extends StatefulWidget {
  final Task task;
  final String group;
  final bool draggable;
  final bool selecting;
  final bool selected;
  final bool expanded;
  final VoidCallback onApprove;
  final void Function(int tabIndex) onApproveWithDate;
  final void Function(int weekday) onApproveToWeekday;
  final void Function(String state) onApproveToState;
  final VoidCallback onApproveToGroceries;
  final VoidCallback onApproveToFoodDiary;
  final VoidCallback onPickGroup;
  final void Function(ApprovalQuickTag tag) onApproveWithQuickTag;
  final VoidCallback onDeny;
  final VoidCallback onToggleSelected;
  final VoidCallback onToggleExpanded;

  const _PendingTaskTile({
    Key? key,
    required this.task,
    required this.group,
    required this.draggable,
    required this.selecting,
    required this.selected,
    required this.expanded,
    required this.onApprove,
    required this.onApproveWithDate,
    required this.onApproveToWeekday,
    required this.onApproveToState,
    required this.onApproveToGroceries,
    required this.onApproveToFoodDiary,
    required this.onPickGroup,
    required this.onApproveWithQuickTag,
    required this.onDeny,
    required this.onToggleSelected,
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

  /// Whether the deny side also offers the weekday shortcuts (which approve
  /// the item onto that day as a dated task).
  bool get _dated => ApprovalGroups.isDated(widget.group);

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

  /// What the approve side does when its countdown runs out.
  void _applyApproveDefault() {
    final group = widget.group;
    if (ApprovalGroups.isStateful(group)) {
      widget.onApproveToState(_defaultStateFor(widget.task));
    } else if (group == ApprovalGroups.groceries) {
      widget.onApproveToGroceries();
    } else if (group == ApprovalGroups.food) {
      widget.onApproveToFoodDiary();
    } else {
      widget
          .onApproveWithDate(suggestedTabIndex(widget.task.approvalSuggestion) ?? 0);
    }
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
        _applyApproveDefault();
      } else {
        widget.onDeny();
      }
    });
  }

  void _startApproveOptions() {
    // Other has no destination of its own yet: the approve swipe asks which
    // category the item belongs in instead of approving it.
    if (widget.group == ApprovalGroups.other) {
      widget.onPickGroup();
      return;
    }
    _startOptions(_PendingSwipeMode.approve);
  }

  void _startDenyOptions() => _startOptions(_PendingSwipeMode.deny);

  void _closeOptions() {
    _timer?.cancel();
    _progressController.stop();
    if (mounted) setState(() => _mode = null);
  }

  void _select(VoidCallback action) {
    _closeOptions();
    action();
  }

  void _handleTap() {
    if (widget.selecting) {
      widget.onToggleSelected();
    } else {
      widget.onToggleExpanded();
    }
  }

  /// Quick-tag buttons shown as the first row of the expanded details panel:
  /// one per configured [ApprovalQuickTag] (Settings > Tasks > Approval
  /// quick tags). Tapping one approves the item straight into the tool it
  /// names, without touching the plain Approve button.
  Widget _buildQuickTags(BuildContext context) {
    final tags = ApprovalQuickTagService.instance.list;
    if (tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in tags)
            OutlinedButton.icon(
              onPressed: () => widget.onApproveWithQuickTag(tag),
              icon: const Icon(Icons.sell_outlined, size: 16),
              label: Text(tag.label),
            ),
        ],
      ),
    );
  }

  /// One label chip, colored like every other tag chip in the app
  /// ([TaskTile._tag], [TaskLabelLine]) — the approval gate token itself
  /// included, since it's still one of the task's real labels.
  Widget _tag(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    final color = protectedChipColorFor(text);
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

  /// Every detail linked to the item, shown when [widget.expanded] is true:
  /// the quick-tag buttons ([_buildQuickTags]) first, then creation date,
  /// source conversation, Todoist sync info, the voice inbox's Obsidian
  /// project/transcript/grocery category, note, due date/time window and
  /// every label tag — plus a link to [TaskDetailPage] for the rest
  /// (attachments, reminder, full journal history) so nothing about the
  /// task is more than one tap away from this row.
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
    if (task.obsidianProject != null) {
      lines.add('Project: ${task.obsidianProject}');
    }
    if (task.groceryCategory != null &&
        widget.group == ApprovalGroups.groceries) {
      lines.add('Category: ${task.groceryCategory}');
    }
    if (task.transcriptPath != null) {
      lines.add('Transcript: ${task.transcriptPath}');
    }
    if (task.note.isNotEmpty) lines.add('Note: ${task.note}');
    if (task.dueDate != null) {
      lines.add('Due: ${task.dueDate!.toLocal().toString().split(' ')[0]}');
    }
    final duration = task.duration;
    if (task.startAt != null &&
        task.endAt != null &&
        duration != null &&
        duration > Duration.zero) {
      lines.add('Start: ${_formatDateTime(task.startAt!)}');
      lines.add('End: ${_formatDateTime(task.endAt!)}');
    }
    if (task.attachments.isNotEmpty) {
      lines.add('Attachments: ${task.attachments.length}');
    }
    final tags = splitLabelTokens(task.label);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQuickTags(context),
          for (final line in lines) Text(line, style: detailStyle),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [for (final tag in tags) _tag(context, tag)],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.drive_file_move_outline, size: 16),
                label: const Text('Move to category'),
                onPressed: widget.onPickGroup,
              ),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('View full details'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TaskDetailPage(task: task),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The swipe panel's option buttons for [_mode] and the item's group.
  List<Widget> _optionButtons() {
    final task = widget.task;
    Widget option(String label, VoidCallback onPressed,
            {bool suggested = false}) =>
        TextButton(
          onPressed: () => _select(onPressed),
          child: Text(
            label,
            style: suggested
                ? const TextStyle(fontWeight: FontWeight.bold)
                : null,
          ),
        );

    if (_mode == _PendingSwipeMode.deny) {
      return [
        option('Deny', widget.onDeny),
        if (_dated)
          for (final o in _pendingSwipeWeekdayOptions)
            option(o.label, () => widget.onApproveToWeekday(o.weekday)),
      ];
    }
    final group = widget.group;
    if (ApprovalGroups.isStateful(group)) {
      final suggested = _defaultStateFor(task);
      return [
        for (final state in BacklogStates.all)
          option(BacklogStates.title(state),
              () => widget.onApproveToState(state),
              suggested: state == suggested),
      ];
    }
    if (group == ApprovalGroups.groceries) {
      return [option('Add to list', widget.onApproveToGroceries)];
    }
    if (group == ApprovalGroups.food) {
      return [option('Add to diary', widget.onApproveToFoodDiary)];
    }
    final suggestedTab = suggestedTabIndex(task.approvalSuggestion) ?? 0;
    return [
      for (var i = 0; i < Config.tabs.length; i++)
        option(Config.tabs[i], () => widget.onApproveWithDate(i),
            suggested: i == suggestedTab &&
                task.approvalSuggestion != null),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final suggestion = _suggestionLabel(task);
    final theme = Theme.of(context);
    final hasSubtitle = task.description.isNotEmpty || suggestion != null;
    final listTile = ListTile(
      title: LinkifiedText(task.title),
      subtitle: hasSubtitle
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (task.description.isNotEmpty)
                  LinkifiedText(task.description),
                if (suggestion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '→ $suggestion',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            )
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
              color: theme.colorScheme.error,
              onPressed: widget.onDeny,
            ),
      onTap: _handleTap,
      // In the category view the long press belongs to the drag (see
      // below); elsewhere it opens the category picker.
      onLongPress:
          widget.selecting || widget.draggable ? null : widget.onPickGroup,
    );

    final stackTile = Stack(
      children: [
        listTile,
        if (_mode != null)
          Positioned.fill(
            child: Container(
              color: theme.cardColor.withValues(alpha: 0.9),
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
                      children: _optionButtons(),
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
            child: Icon(
                widget.group == ApprovalGroups.other
                    ? Icons.drive_file_move_outline
                    : Icons.check_circle_outline,
                color: theme.colorScheme.primary),
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

    if (widget.selected) {
      content = Container(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        child: content,
      );
    }

    if (!widget.draggable || widget.selecting) return content;
    // Long press picks the item up; dropping it on another category's
    // section moves it there (see _WaitingApprovalPageState._buildCategoryList).
    return LongPressDraggable<String>(
      data: task.uid,
      axis: Axis.vertical,
      onDragStarted: () => const _PendingDragNotification(true).dispatch(context),
      onDragEnd: (_) => const _PendingDragNotification(false).dispatch(context),
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 32),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(task.title, style: theme.textTheme.titleMedium),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: content),
      child: content,
    );
  }
}
