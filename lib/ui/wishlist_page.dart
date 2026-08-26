import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../models/task.dart';
import '../models/view_filter_rules.dart';
import '../services/auto_tag_service.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../services/wishlist_shipped.dart';
import '../utils/description_disclosure.dart';
import '../utils/label_utils.dart';
import 'label_picker.dart';
import 'subpage_app_bar.dart';

enum _WishlistSortOrder { priority, newest, oldest, title }

/// Priority labels a wishlist item can carry inside [Task.label], ordered
/// from lowest to highest.
const List<String> wishPriorityLabels = <String>[
  'priority-low',
  'priority-medium',
  'priority-high',
];

/// 0 for no priority label, 1..3 for low..high.
int wishPriorityRank(Task task) {
  final labels = task.label
      .toLowerCase()
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .toSet();
  for (var i = wishPriorityLabels.length - 1; i >= 0; i--) {
    if (labels.contains(wishPriorityLabels[i])) return i + 1;
  }
  return 0;
}

/// Rewrites [task]'s label so [priorityLabel] is its only priority label;
/// all other labels are kept.
void setWishPriority(Task task, String priorityLabel) {
  final labels = task.label
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .where((label) => !wishPriorityLabels.contains(label.toLowerCase()))
      .toList();
  labels.insert(0, priorityLabel);
  task.label = labels.join(', ');
}

/// Raises [task]'s priority one step: none → low → medium → high (capped).
void bumpWishPriority(Task task) {
  final rank = wishPriorityRank(task);
  final next =
      rank >= wishPriorityLabels.length ? wishPriorityLabels.length - 1 : rank;
  setWishPriority(task, wishPriorityLabels[next]);
}

/// The release-tracking group a wishlist item is sorted into — rendered as
/// the wishlist's sections, top to bottom, exactly like the home page's
/// due-date tabs. Membership is decided entirely by tags: [newlyImplemented]
/// is automatic (the shipped-wish registry, restricted to the running app's
/// own version), [nextRelease] and [soon] follow the `release-next` /
/// `release-soon` label tokens, and anything left over is [backlog].
enum WishReleaseGroup { newlyImplemented, nextRelease, soon, backlog }

/// Which [WishReleaseGroup] a wishlist item currently belongs to.
/// [currentVersion] is the running app's version (`Config.version`): an item
/// the shipped-wish registry says was delivered by exactly that version is
/// "Newly implemented" regardless of any release-* tag it also carries, so
/// the group empties out again once the next version ships.
WishReleaseGroup wishReleaseGroupOf(Task task, String currentVersion) {
  final shipped = shippedWishesByUid[task.uid];
  if (shipped != null &&
      currentVersion.isNotEmpty &&
      shipped.version == currentVersion) {
    return WishReleaseGroup.newlyImplemented;
  }
  final labels =
      splitLabelTokens(task.label).map((label) => label.toLowerCase()).toSet();
  if (labels.contains(releaseNextToken)) return WishReleaseGroup.nextRelease;
  if (labels.contains(releaseSoonToken)) return WishReleaseGroup.soon;
  return WishReleaseGroup.backlog;
}

/// Moves [task] into [group] by rewriting its release tag, keeping every
/// other label. [WishReleaseGroup.backlog] and [WishReleaseGroup.
/// newlyImplemented] carry no tag of their own — moving into either just
/// strips `release-next`/`release-soon`.
void setWishReleaseGroup(Task task, WishReleaseGroup group) {
  final labels = splitLabelTokens(task.label)
      .where((label) => !releaseGroupTokens.contains(label.toLowerCase()))
      .toList();
  switch (group) {
    case WishReleaseGroup.nextRelease:
      labels.add(releaseNextToken);
      break;
    case WishReleaseGroup.soon:
      labels.add(releaseSoonToken);
      break;
    case WishReleaseGroup.newlyImplemented:
    case WishReleaseGroup.backlog:
      break;
  }
  task.label = joinLabelTokens(labels);
}

/// Moves [task] back one release step — the swipe-right default action:
/// nextRelease → soon → backlog (capped). No-op for [WishReleaseGroup.
/// backlog] (nothing further back to go) and [WishReleaseGroup.
/// newlyImplemented] (that group is automatic, not tag-driven — see
/// [wishReleaseGroupOf]).
void regressWishReleaseGroup(Task task, String currentVersion) {
  switch (wishReleaseGroupOf(task, currentVersion)) {
    case WishReleaseGroup.nextRelease:
      setWishReleaseGroup(task, WishReleaseGroup.soon);
      break;
    case WishReleaseGroup.soon:
      setWishReleaseGroup(task, WishReleaseGroup.backlog);
      break;
    case WishReleaseGroup.backlog:
    case WishReleaseGroup.newlyImplemented:
      break;
  }
}

/// Countdown before the options-swipe panel's progress bar "sweeps" across
/// and applies its default action ([regressWishReleaseGroup]). Deliberately
/// longer than the app-wide swipe-delete undo delay ([Config.delayDuration]):
/// misreading one of four buttons here costs more than misreading a single
/// undo action.
const Duration wishlistSweepDelay = Duration(seconds: 8);

/// Section title shown above a group's items.
String wishReleaseGroupTitle(WishReleaseGroup group) {
  switch (group) {
    case WishReleaseGroup.newlyImplemented:
      return 'Newly implemented';
    case WishReleaseGroup.nextRelease:
      return 'Next release';
    case WishReleaseGroup.soon:
      return 'Soon';
    case WishReleaseGroup.backlog:
      return 'Backlog';
  }
}

/// The plain-text prompt "Propose for next" puts on the clipboard: an
/// instruction for Claude to tag the user's Todoist backlog with
/// `release-next`/`release-soon` (aiming for ~3 items in the next release),
/// plus a snapshot of the current backlog/soon items so Claude has the exact
/// titles and tags without needing to cross-reference anything first. Pure
/// and deterministic, like [WishlistPage.clipboardText], so it's unit
/// testable without pumping a widget.
String proposeForNextPrompt(List<Task> backlogAndSoonItems) {
  final lines = <String>[
    'Check my BestToDo wishlist backlog in Todoist and decide what ships '
        'next.',
    'Tag about 3 items "release-next" (the next release) and a handful more '
        '"release-soon" (after that); leave everything else untagged so it '
        'stays in the backlog. Remove either tag from an item that no '
        'longer belongs there. BestToDo groups the wishlist by these tags, '
        'so the change takes effect there next time it syncs with Todoist.',
  ];
  if (backlogAndSoonItems.isNotEmpty) {
    lines.add('');
    lines.add('Current backlog / soon items:');
    for (final item in backlogAndSoonItems) {
      final tags = item.label.trim();
      lines.add('- ${item.title}${tags.isEmpty ? '' : ' [$tags]'}');
    }
  }
  return lines.join('\n');
}

/// The plain-text prompt "Copy selected as prompt" (multi-select mode) puts
/// on the clipboard: an instruction for Claude to build the given wishlist
/// items, followed by each item's title, description and labels. Pure and
/// deterministic, like [WishlistPage.clipboardText], so it's unit testable
/// without pumping a widget.
String buildSelectedWishesPrompt(List<Task> items) {
  final lines = <String>[
    'Build the following items from my BestToDo wishlist:',
    '',
  ];
  for (final item in items) {
    lines.add('- ${item.title}');
    final description = item.description.trim();
    if (description.isNotEmpty) lines.add('  $description');
    final tags = item.label.trim();
    if (tags.isNotEmpty) lines.add('  [$tags]');
  }
  return lines.join('\n');
}

/// Tools → Wishlist: a pre-filtered view over the one task list — like
/// opening a project — showing only tasks flagged [Task.isWish]. The full
/// item overview (the home page) shows the same tasks with all their
/// properties and tags; here they render as plain to-do tiles with no due
/// dates. Swiping right opens Share/Copy/Export/Delete shortcuts, with the
/// [wishlistSweepDelay] countdown defaulting to moving the item back one
/// release step ([regressWishReleaseGroup]); swiping left enters multi-select
/// mode, where the app bar's "Copy selected as prompt" action puts a
/// build-these-items prompt on the clipboard for pasting into Claude.
class WishlistPage extends StatefulWidget {
  const WishlistPage({Key? key}) : super(key: key);

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  final ItemRepository _repository = ItemRepository.instance;

  /// The full task list; the page shows and mutates only the isWish subset
  /// but always persists the whole list.
  List<Task> _tasks = <Task>[];
  bool _loading = true;
  _WishlistSortOrder _sortOrder = _WishlistSortOrder.priority;

  /// The running app's version, for [wishReleaseGroupOf]. Empty until
  /// loaded, which no shipped-wish version ever matches, so every item
  /// sorts by its tags alone until then.
  String _currentVersion = '';

  @override
  void initState() {
    super.initState();
    _load();
    Config.ensureVersionLoaded().then((_) {
      if (mounted) setState(() => _currentVersion = Config.version);
    });
  }

  Future<void> _load() async {
    // Also merges legacy wishlist.json items into the task list.
    final tasks = await _repository.loadItems();
    // Platforms without storage (web) load an empty list; dev builds seed
    // the same wish item the home page seeds so the tool is testable in
    // Chrome. On devices with data the list is never empty here.
    if (tasks.isEmpty && Config.isDev) {
      tasks.add(Task(
        title: 'Learn to sail',
        description: 'Dev seed: a wishlist item',
        label: 'priority-medium',
        createdAt: DateTime.now(),
        isWish: true,
      ));
    }
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _save() => _repository.saveItems(_tasks);

  int _compareCreatedAt(Task a, Task b, {required bool newestFirst}) {
    final aCreated = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bCreated = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return newestFirst
        ? bCreated.compareTo(aCreated)
        : aCreated.compareTo(bCreated);
  }

  int _compareBySortOrder(Task a, Task b) {
    switch (_sortOrder) {
      case _WishlistSortOrder.priority:
        final byPriority = wishPriorityRank(b) - wishPriorityRank(a);
        if (byPriority != 0) return byPriority;
        return 0;
      case _WishlistSortOrder.newest:
        return _compareCreatedAt(a, b, newestFirst: true);
      case _WishlistSortOrder.oldest:
        return _compareCreatedAt(a, b, newestFirst: false);
      case _WishlistSortOrder.title:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    }
  }

  String _sortLabel(_WishlistSortOrder order) {
    switch (order) {
      case _WishlistSortOrder.priority:
        return 'Priority';
      case _WishlistSortOrder.newest:
        return 'Newest';
      case _WishlistSortOrder.oldest:
        return 'Oldest';
      case _WishlistSortOrder.title:
        return 'Title';
    }
  }

  /// Wishlist items sorted like a to-do list: open items before done ones,
  /// then by the selected helper sort, otherwise keeping their list order.
  List<Task> _wishes() {
    final wishes = ItemViews.wishlist(
      _tasks,
      rules: Config.viewFilterRules[ViewFilterRules.wishlist],
    );
    final order = <String, int>{
      for (var i = 0; i < wishes.length; i++) wishes[i].uid: i,
    };
    wishes.sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      final bySelectedSort = _compareBySortOrder(a, b);
      if (bySelectedSort != 0) return bySelectedSort;
      return order[a.uid]!.compareTo(order[b.uid]!);
    });
    return wishes;
  }

  String _timestampForFilename() {
    final now = DateTime.now();
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  Future<String?> _pickExportPath(String filename) async {
    final downloads = await getDownloadsDirectory();
    final directory = await getDirectoryPath(initialDirectory: downloads?.path);
    if (directory == null) return null;
    final sep = Platform.pathSeparator;
    return '$directory${directory.endsWith(sep) ? '' : sep}$filename';
  }

  Map<String, dynamic> _exportPayload(List<Task> items) => <String, dynamic>{
        'export_version': 1,
        'exported_at': DateTime.now().toIso8601String(),
        'wishlist_items': items.map((item) => item.toJson()).toList(),
      };

  Future<void> _exportItems(List<Task> items, String filename) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No wishlist items to export')),
      );
      return;
    }

    final path = await _pickExportPath(filename);
    if (!mounted) return;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export canceled')),
      );
      return;
    }

    try {
      final file = File(path);
      await file.writeAsString(jsonEncode(_exportPayload(items)), flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to ${file.path}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export wishlist')),
      );
    }
  }

  Future<void> _exportAllItems() async {
    await _exportItems(_wishes(), 'wishlist_${_timestampForFilename()}.json');
  }

  Future<void> _exportItem(Task item) async {
    final safeTitle = item.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final filenameBase = safeTitle.isEmpty ? 'wishlist_item' : safeTitle;
    await _exportItems(
      <Task>[item],
      '${filenameBase}_${_timestampForFilename()}.json',
    );
  }

  /// The plain-text form of a wishlist item put on the clipboard: the title,
  /// then its description and labels on their own lines when it has any.
  static String clipboardText(Task item) {
    final lines = <String>[item.title];
    if (item.description.trim().isNotEmpty) lines.add(item.description.trim());
    if (item.label.trim().isNotEmpty) lines.add(item.label.trim());
    return lines.join('\n');
  }

  Future<void> _copyItem(Task item) async {
    await Clipboard.setData(ClipboardData(text: clipboardText(item)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Copied "${item.title}"')));
  }

  Future<void> _shareItem(Task item) async {
    await SharePlus.instance.share(
      ShareParams(text: clipboardText(item), subject: item.title),
    );
  }

  List<String> _labelsFromText(String text) => text
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toList();

  String _labelTextWithPriority(String text, String priorityLabel) {
    final labels = _labelsFromText(text)
        .where((label) => !wishPriorityLabels.contains(label.toLowerCase()))
        .toList();
    labels.insert(0, priorityLabel);
    return labels.join(', ');
  }

  Future<void> _editItem([Task? item]) async {
    final result = await showDialog<_WishEditResult>(
      context: context,
      builder: (context) => _WishEditDialog(
        item: item,
        labelTextWithPriority: _labelTextWithPriority,
      ),
    );

    if (result == null) return;
    setState(() {
      if (item == null) {
        _tasks.insert(
          0,
          Task(
            title: result.title,
            description: result.description,
            label: AutoTagService.instance.withAutoTags(
                result.title, result.label),
            createdAt: DateTime.now(),
            isWish: true,
          ),
        );
      } else {
        item
          ..title = result.title
          ..description = result.description
          ..label = result.label;
      }
    });
    await _save();
  }

  void _toggleDone(Task item) {
    setState(() {
      item.toggleDone();
      item.completedAt = item.isDone ? DateTime.now() : null;
    });
    _save();
  }

  /// Swipe-right's default (countdown-timeout) action: move [item] back one
  /// release step.
  void _regressRelease(Task item) {
    setState(() => regressWishReleaseGroup(item, _currentVersion));
    _save();
  }

  /// [wishes] partitioned into release groups, in section order. Membership
  /// is decided by [wishReleaseGroupOf]; each group keeps [wishes]'s own
  /// (already sorted) relative order.
  Map<WishReleaseGroup, List<Task>> _groupedWishes(List<Task> wishes) {
    final grouped = <WishReleaseGroup, List<Task>>{
      for (final group in WishReleaseGroup.values) group: <Task>[],
    };
    for (final wish in wishes) {
      grouped[wishReleaseGroupOf(wish, _currentVersion)]!.add(wish);
    }
    return grouped;
  }

  void _setReleaseGroup(Task item, WishReleaseGroup group) {
    setState(() => setWishReleaseGroup(item, group));
    _save();
  }

  /// Copies the "Propose for next" prompt for every open backlog/soon item
  /// (newly-implemented and already-scheduled items are the app's own
  /// bookkeeping, not candidates to re-tag).
  Future<void> _proposeForNext() async {
    final candidates = _wishes().where((wish) {
      if (wish.isDone) return false;
      final group = wishReleaseGroupOf(wish, _currentVersion);
      return group == WishReleaseGroup.backlog || group == WishReleaseGroup.soon;
    }).toList();
    await Clipboard.setData(
        ClipboardData(text: proposeForNextPrompt(candidates)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text(
            'Prompt copied — paste it to Claude, then sync Todoist to '
            'update the groups.'),
      ));
  }

  /// Moves every item in [items] to the deleted list in one go, with a
  /// single undo snackbar covering all of them.
  void _deleteItems(List<Task> items) {
    if (items.isEmpty) return;
    final originalIndices = <Task, int>{
      for (final item in items) item: _tasks.indexOf(item),
    }..removeWhere((_, index) => index < 0);
    if (originalIndices.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      for (final item in originalIndices.keys) {
        _tasks.remove(item);
      }
    });
    _save();

    late Timer timer;
    timer = Timer(Config.delayDuration, () async {
      final deleted = await _repository.loadDeletedItems();
      for (final item in originalIndices.keys) {
        item.deletedAt = DateTime.now();
        deleted.insert(0, item);
      }
      await _repository.saveDeletedItems(deleted);
      messenger.hideCurrentSnackBar();
    });

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(originalIndices.length == 1
              ? 'Deleted "${originalIndices.keys.first.title}"'
              : 'Deleted ${originalIndices.length} items'),
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

  /// The uids currently selected in multi-select mode; empty means the page
  /// isn't in selection mode. Swiping a tile left starts a selection with
  /// just that item; tapping other tiles toggles them in and out.
  final Set<String> _selectedUids = <String>{};

  bool get _selecting => _selectedUids.isNotEmpty;

  void _startSelection(Task item) {
    setState(() => _selectedUids.add(item.uid));
  }

  void _toggleSelected(Task item) {
    setState(() {
      if (!_selectedUids.remove(item.uid)) _selectedUids.add(item.uid);
    });
  }

  void _cancelSelection() => setState(_selectedUids.clear);

  /// Copies [buildSelectedWishesPrompt] for the selected items and exits
  /// selection mode.
  Future<void> _copySelectionAsPrompt() async {
    final items =
        _wishes().where((wish) => _selectedUids.contains(wish.uid)).toList();
    if (items.isEmpty) return;
    await Clipboard.setData(
        ClipboardData(text: buildSelectedWishesPrompt(items)));
    if (!mounted) return;
    setState(_selectedUids.clear);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(items.length == 1
            ? 'Copied "${items.first.title}" as a prompt'
            : 'Copied ${items.length} items as a prompt'),
      ));
  }

  void _deleteSelection() {
    final items =
        _wishes().where((wish) => _selectedUids.contains(wish.uid)).toList();
    setState(_selectedUids.clear);
    _deleteItems(items);
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
            tooltip: 'Copy selected as prompt',
            icon: const Icon(Icons.content_copy),
            onPressed: _copySelectionAsPrompt,
          ),
          IconButton(
            tooltip: 'Delete selected',
            icon: const Icon(Icons.delete),
            onPressed: _deleteSelection,
          ),
        ],
      );
    }
    return buildSubpageAppBar(
      context,
      title: 'Wishlist',
      actions: [
        PopupMenuButton<_WishlistSortOrder>(
          tooltip: 'Sort wishlist',
          icon: const Icon(Icons.sort),
          initialValue: _sortOrder,
          onSelected: (value) => setState(() => _sortOrder = value),
          itemBuilder: (context) => [
            for (final order in _WishlistSortOrder.values)
              PopupMenuItem(
                value: order,
                child: Row(
                  children: [
                    if (order == _sortOrder)
                      const Icon(Icons.check, size: 18)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 8),
                    Text(_sortLabel(order)),
                  ],
                ),
              ),
          ],
        ),
        IconButton(
          tooltip: 'Export wishlist',
          onPressed: _wishes().isEmpty ? null : _exportAllItems,
          icon: const Icon(Icons.download_outlined),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final wishes = _wishes();
    final grouped = _groupedWishes(wishes);
    return Scaffold(
      appBar: _buildAppBar(context),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
              tooltip: 'Add wishlist item',
              onPressed: () => _editItem(),
              child: const Icon(Icons.add),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : wishes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No wishlist items yet. Add ideas here; swipe right to '
                      'share/copy/export, swipe left to select.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                  children: [
                    for (final group in WishReleaseGroup.values)
                      // "Next release" always shows — it's where "Propose for
                      // next" lives, and that button should stay reachable
                      // even before anything has been tagged into it.
                      if (grouped[group]!.isNotEmpty ||
                          group == WishReleaseGroup.nextRelease) ...[
                        _WishReleaseSectionHeader(
                          group: group,
                          count: grouped[group]!.length,
                          onProposeForNext:
                              group == WishReleaseGroup.nextRelease
                                  ? _proposeForNext
                                  : null,
                        ),
                        for (final item in grouped[group]!)
                          _WishTile(
                            key: ValueKey(item.uid),
                            item: item,
                            releaseGroup: group,
                            selecting: _selecting,
                            selected: _selectedUids.contains(item.uid),
                            onToggle: () => _toggleDone(item),
                            onToggleSelected: () => _toggleSelected(item),
                            onStartSelection: () => _startSelection(item),
                            onEdit: () => _editItem(item),
                            onCopy: () => _copyItem(item),
                            onShare: () => _shareItem(item),
                            onExport: () => _exportItem(item),
                            onDelete: () => _deleteItems([item]),
                            onRegressRelease: () => _regressRelease(item),
                            onSetReleaseGroup: (newGroup) =>
                                _setReleaseGroup(item, newGroup),
                          ),
                      ],
                  ],
                ),
    );
  }
}

/// Header row above a release group's items: the group's title, its item
/// count, and — only above "Next release" — the "Propose for next" button
/// that copies [proposeForNextPrompt] to the clipboard.
class _WishReleaseSectionHeader extends StatelessWidget {
  final WishReleaseGroup group;
  final int count;
  final VoidCallback? onProposeForNext;

  const _WishReleaseSectionHeader({
    required this.group,
    required this.count,
    required this.onProposeForNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${wishReleaseGroupTitle(group)} ($count)',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (onProposeForNext != null)
            TextButton.icon(
              onPressed: onProposeForNext,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Propose for next'),
            ),
        ],
      ),
    );
  }
}

class _WishEditResult {
  final String title;
  final String description;
  final String label;

  const _WishEditResult(this.title, this.description, this.label);
}

/// Add/edit dialog owning its text controllers, so the dialog's exit
/// animation never builds fields with disposed controllers.
class _WishEditDialog extends StatefulWidget {
  final Task? item;
  final String Function(String text, String priorityLabel)
      labelTextWithPriority;

  const _WishEditDialog({
    required this.item,
    required this.labelTextWithPriority,
  });

  @override
  State<_WishEditDialog> createState() => _WishEditDialogState();
}

class _WishEditDialogState extends State<_WishEditDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _label;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item?.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.item?.description ?? '');
    _label = widget.item?.label ?? '';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
          widget.item == null ? 'Add wishlist item' : 'Edit wishlist item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              textInputAction: TextInputAction.next,
            ),
            // Labels and their priority shortcuts sit right under the title —
            // most wishes are a title plus a priority; the description is the
            // exception and lives at the bottom.
            LabelPickerField(
              value: _label,
              fieldLabel: 'Labels / tags',
              onChanged: (v) => setState(() => _label = v),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Quick priority',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final priority in wishPriorityLabels)
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _label = widget.labelTextWithPriority(_label, priority);
                    }),
                    child: Text(priority.replaceFirst('priority-', '')),
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
            Navigator.of(context).pop(_WishEditResult(
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

/// A wishlist item rendered like a home-page task tile (checkbox, title,
/// labels — never a due date) with the wishlist swipe actions: swiping
/// toward the options side opens Share/Copy/Export/Delete shortcuts and moves
/// the item back one release step ([WishlistPage]'s [regressWishReleaseGroup])
/// when the countdown runs out; swiping toward the other side starts
/// multi-select ([onStartSelection])/toggles it ([onToggleSelected]) instead
/// of deleting — deleting a single item now lives in the options panel
/// above, and the selection app bar still deletes several at once. Directions
/// follow [Config.swipeLeftDelete] like the home list.
class _WishTile extends StatefulWidget {
  final Task item;
  final WishReleaseGroup releaseGroup;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onToggleSelected;
  final VoidCallback onStartSelection;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onRegressRelease;
  final void Function(WishReleaseGroup group) onSetReleaseGroup;

  const _WishTile({
    Key? key,
    required this.item,
    required this.releaseGroup,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onToggleSelected,
    required this.onStartSelection,
    required this.onEdit,
    required this.onCopy,
    required this.onShare,
    required this.onExport,
    required this.onDelete,
    required this.onRegressRelease,
    required this.onSetReleaseGroup,
  }) : super(key: key);

  @override
  State<_WishTile> createState() => _WishTileState();
}

class _WishTileState extends State<_WishTile>
    with SingleTickerProviderStateMixin {
  bool _optionsOpen = false;
  Timer? _timer;
  late final AnimationController _progressController;
  double _dragOffset = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: wishlistSweepDelay,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  void _startSwipeOptions() {
    setState(() => _optionsOpen = true);
    _timer?.cancel();
    _progressController.reset();
    _progressController.forward();
    _timer = Timer(wishlistSweepDelay, () {
      if (!mounted || !_optionsOpen) return;
      _progressController.stop();
      setState(() => _optionsOpen = false);
      widget.onRegressRelease();
    });
  }

  void _closeOptions() {
    _timer?.cancel();
    _progressController.stop();
    if (mounted) setState(() => _optionsOpen = false);
  }

  void _share() {
    _closeOptions();
    widget.onShare();
  }

  void _copy() {
    _closeOptions();
    widget.onCopy();
  }

  void _export() {
    _closeOptions();
    widget.onExport();
  }

  void _delete() {
    _closeOptions();
    widget.onDelete();
  }

  List<String> _labels() => widget.item.label
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final labels = _labels();

    final listTile = ListTile(
      contentPadding: isAndroid
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16.0),
      minLeadingWidth: isAndroid ? 0 : null,
      leading: widget.selecting
          ? Checkbox(
              value: widget.selected,
              onChanged: (_) => widget.onToggleSelected(),
            )
          : Checkbox(
              value: widget.item.isDone,
              onChanged: (_) => widget.onToggle(),
            ),
      title: Text(
        widget.item.title,
        style: TextStyle(
          decoration: widget.item.isDone ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: widget.item.description.isEmpty && labels.isEmpty
          ? null
          : Column(
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
                if (widget.item.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  DescriptionDisclosure(description: widget.item.description),
                ],
              ],
            ),
      onTap: widget.selecting ? widget.onToggleSelected : widget.onEdit,
      // No per-item action icons: share/copy/export live behind the swipe
      // options overlay and selection starts with a swipe, so the only
      // trailing control left is the release-group picker (which has no
      // swipe equivalent — swiping only steps an item back one group).
      trailing: widget.selecting ||
              widget.releaseGroup == WishReleaseGroup.newlyImplemented
          ? null
          : PopupMenuButton<WishReleaseGroup>(
              tooltip: 'Move to release group',
              icon: const Icon(Icons.drive_file_move_outline),
              initialValue: widget.releaseGroup,
              onSelected: widget.onSetReleaseGroup,
              itemBuilder: (context) => [
                for (final group in const [
                  WishReleaseGroup.nextRelease,
                  WishReleaseGroup.soon,
                  WishReleaseGroup.backlog,
                ])
                  PopupMenuItem(
                    value: group,
                    child: Row(
                      children: [
                        if (group == widget.releaseGroup)
                          const Icon(Icons.check, size: 18)
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Text(wishReleaseGroupTitle(group)),
                      ],
                    ),
                  ),
              ],
            ),
    );

    final stackTile = Stack(
      children: [
        listTile,
        if (_optionsOpen)
          Positioned.fill(
            child: Container(
              color: Theme.of(context).cardColor.withValues(alpha: 0.9),
              alignment: Alignment.centerRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Share'),
                      ),
                      TextButton.icon(
                        onPressed: _copy,
                        icon: const Icon(Icons.content_copy, size: 18),
                        label: const Text('Copy'),
                      ),
                      TextButton.icon(
                        onPressed: _export,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: const Text('Export'),
                      ),
                      TextButton.icon(
                        onPressed: _delete,
                        icon: const Icon(Icons.delete, size: 18),
                        label: const Text('Delete'),
                      ),
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

    final slide = AnimatedSlide(
      offset: Offset(_dragOffset / MediaQuery.of(context).size.width, 0),
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 200),
      child: stackTile,
    );

    Widget? background;
    if (_dragOffset != 0) {
      final isCancelDrag = _optionsOpen &&
          (Config.swipeLeftDelete ? _dragOffset < 0 : _dragOffset > 0);
      final dragToSelect =
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
      } else if (dragToSelect) {
        final alignment = Config.swipeLeftDelete
            ? Alignment.centerRight
            : Alignment.centerLeft;
        background = Positioned.fill(
          child: Container(
            color: Colors.blue.withValues(alpha: 0.5),
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: const Icon(Icons.checklist, color: Colors.white),
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
            child: Icon(Icons.undo,
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
          final optionsSwipe =
              Config.swipeLeftDelete ? swipedRight : swipedLeft;
          final selectSwipe = Config.swipeLeftDelete ? swipedLeft : swipedRight;
          if (_optionsOpen) {
            // Swiping back toward the select side cancels the pending
            // release change, mirroring the home list's cancel gesture.
            if (selectSwipe) _closeOptions();
          } else if (optionsSwipe) {
            _startSwipeOptions();
          } else if (selectSwipe) {
            widget.onStartSelection();
          }
          setState(() {
            _dragging = false;
            _dragOffset = 0;
          });
        },
        child: content,
      );
    }

    return Card(
      color: widget.selected
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      child: content,
    );
  }
}
