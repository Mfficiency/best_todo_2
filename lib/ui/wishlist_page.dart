import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/task.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../utils/linkified_text.dart';
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

/// Tools → Wishlist: a pre-filtered view over the one task list — like
/// opening a project — showing only tasks flagged [Task.isWish]. The full
/// item overview (the home page) shows the same tasks with all their
/// properties and tags; here they render as plain to-do tiles with no due
/// dates. Swiping works like the home list, except the options swipe raises
/// the item's priority (default: one step up, with High/Medium/Low
/// shortcuts) instead of rescheduling it, and the delete swipe moves the
/// item to the deleted list.
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

  @override
  void initState() {
    super.initState();
    _load();
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
    final wishes = ItemViews.wishlist(_tasks);
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
            label: result.label,
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

  void _setPriority(Task item, String priorityLabel) {
    setState(() => setWishPriority(item, priorityLabel));
    _save();
  }

  void _bumpPriority(Task item) {
    setState(() => bumpWishPriority(item));
    _save();
  }

  /// Moves [item] to the deleted list, with the same undo window as deleting
  /// a task on the home page.
  void _deleteItem(Task item) {
    final originalIndex = _tasks.indexOf(item);
    if (originalIndex < 0) return;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _tasks.removeAt(originalIndex));
    _save();

    late Timer timer;
    timer = Timer(Config.delayDuration, () async {
      item.deletedAt = DateTime.now();
      final deleted = await _repository.loadDeletedItems();
      deleted.insert(0, item);
      await _repository.saveDeletedItems(deleted);
      messenger.hideCurrentSnackBar();
    });

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted "${item.title}"'),
          duration: Config.delayDuration,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              timer.cancel();
              messenger.hideCurrentSnackBar();
              if (!mounted) return;
              setState(() => _tasks.insert(originalIndex, item));
              _save();
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final wishes = _wishes();
    return Scaffold(
      appBar: buildSubpageAppBar(
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
            onPressed: wishes.isEmpty ? null : _exportAllItems,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
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
                      'No wishlist items yet. Add ideas here; swipe to '
                      'prioritize or delete them.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                  itemCount: wishes.length,
                  itemBuilder: (context, index) {
                    final item = wishes[index];
                    return _WishTile(
                      key: ValueKey(item.uid),
                      item: item,
                      onToggle: () => _toggleDone(item),
                      onEdit: () => _editItem(item),
                      onExport: () => _exportItem(item),
                      onDelete: () => _deleteItem(item),
                      onBumpPriority: () => _bumpPriority(item),
                      onSetPriority: (label) => _setPriority(item, label),
                    );
                  },
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
  late final TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item?.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.item?.description ?? '');
    _labelController = TextEditingController(text: widget.item?.label ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _labelController.dispose();
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
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(
                labelText: 'Labels / tags',
                hintText: 'priority-high, gift, someday',
              ),
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
                    onPressed: () {
                      _labelController.text = widget.labelTextWithPriority(
                        _labelController.text,
                        priority,
                      );
                    },
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
              _labelController.text.trim(),
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
/// toward the options side opens priority shortcuts and raises the priority
/// one step when the countdown runs out; swiping toward the delete side
/// moves the item to the deleted list. Directions follow
/// [Config.swipeLeftDelete] like the home list.
class _WishTile extends StatefulWidget {
  final Task item;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onBumpPriority;
  final void Function(String priorityLabel) onSetPriority;

  const _WishTile({
    Key? key,
    required this.item,
    required this.onToggle,
    required this.onEdit,
    required this.onExport,
    required this.onDelete,
    required this.onBumpPriority,
    required this.onSetPriority,
  }) : super(key: key);

  @override
  State<_WishTile> createState() => _WishTileState();
}

class _WishTileState extends State<_WishTile>
    with SingleTickerProviderStateMixin {
  bool _optionsOpen = false;
  bool _isEmulator = false;
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

  @override
  void dispose() {
    _timer?.cancel();
    _progressController.dispose();
    super.dispose();
  }

  void _startPriorityOptions() {
    setState(() => _optionsOpen = true);
    _timer?.cancel();
    _progressController.reset();
    _progressController.forward();
    _timer = Timer(Config.delayDuration, () {
      if (!mounted || !_optionsOpen) return;
      _progressController.stop();
      setState(() => _optionsOpen = false);
      widget.onBumpPriority();
    });
  }

  void _closeOptions() {
    _timer?.cancel();
    _progressController.stop();
    if (mounted) setState(() => _optionsOpen = false);
  }

  void _selectPriority(String label) {
    _closeOptions();
    widget.onSetPriority(label);
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
      leading: Checkbox(
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
                if (widget.item.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  LinkifiedText(widget.item.description),
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
      onTap: widget.onEdit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isEmulator) ...[
            IconButton(
              icon: const Icon(Icons.swipe),
              tooltip: 'Prioritize',
              onPressed: _startPriorityOptions,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Delete wishlist item',
              onPressed: widget.onDelete,
            ),
          ],
          IconButton(
            tooltip: 'Export wishlist item',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: widget.onExport,
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
                      for (final priority in wishPriorityLabels.reversed)
                        TextButton(
                          onPressed: () => _selectPriority(priority),
                          child: Text(priority.replaceFirst('priority-', '')),
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
      final dragToDelete =
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
      } else if (dragToDelete) {
        final alignment = Config.swipeLeftDelete
            ? Alignment.centerRight
            : Alignment.centerLeft;
        background = Positioned.fill(
          child: Container(
            color: Colors.red.withValues(alpha: 0.5),
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: const Icon(Icons.delete, color: Colors.white),
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
            child: Icon(Icons.keyboard_double_arrow_up,
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
          final optionsSwipe =
              Config.swipeLeftDelete ? swipedRight : swipedLeft;
          final deleteSwipe = Config.swipeLeftDelete ? swipedLeft : swipedRight;
          if (_optionsOpen) {
            // Swiping back toward the delete side cancels the pending
            // priority change, mirroring the home list's cancel gesture.
            if (deleteSwipe) _closeOptions();
          } else if (optionsSwipe) {
            _startPriorityOptions();
          } else if (deleteSwipe) {
            widget.onDelete();
          }
          setState(() {
            _dragging = false;
            _dragOffset = 0;
          });
        },
        child: content,
      );
    }

    return Card(child: content);
  }
}
