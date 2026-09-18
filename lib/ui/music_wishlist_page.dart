import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/task.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../services/shared_wishlist_store.dart';
import '../utils/wish_priority.dart';
import 'label_picker.dart';
import 'subpage_app_bar.dart';
import 'wishlist_sync_banner.dart';

/// Tools → Wishlist for Best Music: the same wishlist BestToDo has, reduced
/// to its plainest form. Items are ordinary [Task] records flagged
/// [Task.isWish] — the identical JSON shape BestToDo's own Wishlist tool
/// (`wishlist_page.dart`) writes to `tasks.json`, and — once connected via
/// [SharedWishlistStore] — genuinely the same records, synced through one
/// shared external-storage file rather than each app's own sandboxed
/// storage (see that file's doc). Unlike BestToDo's Wishlist, this page
/// carries none of that tool's build-tracking chrome (release-group
/// sections, GitHub "Send to build", swipe menus): the list itself shows
/// nothing but each item's title, no icons at all, and tapping a title
/// opens every field — done, priority, tags, description — in one editor.
class MusicWishlistPage extends StatefulWidget {
  const MusicWishlistPage({super.key});

  @override
  State<MusicWishlistPage> createState() => _MusicWishlistPageState();
}

class _MusicWishlistPageState extends State<MusicWishlistPage> {
  final ItemRepository _repository = ItemRepository.instance;
  final SharedWishlistStore _sharedStore = SharedWishlistStore.instance;

  /// The full item list; the page shows and mutates only the isWish subset
  /// but always persists the whole list, exactly like BestToDo's Wishlist.
  List<Task> _tasks = <Task>[];
  bool _loading = true;

  /// Whether this app currently holds the permission [SharedWishlistStore]
  /// needs, i.e. whether wishlist items are actually shared with BestToDo
  /// right now — checked on load, never auto-requested.
  bool _syncConnected = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await _repository.loadItems();
    // Only touch the shared store (and re-persist locally) when actually
    // connected — an app that never connects behaves exactly as before.
    final connected = await _sharedStore.isConnected();
    if (connected) {
      final shared = await _sharedStore.load();
      final localWishes = tasks.where((t) => t.isWish).toList();
      final canonicalWishes = reconcileWishlist(localWishes, shared);
      tasks.removeWhere((t) => t.isWish);
      tasks.addAll(canonicalWishes);
      if (shared.fileExisted) {
        await _repository.saveItems(tasks);
      } else {
        unawaited(_sharedStore.save(canonicalWishes));
      }
    }
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
      _syncConnected = connected;
    });
  }

  Future<void> _save() async {
    await _repository.saveItems(_tasks);
    if (_syncConnected) {
      unawaited(_sharedStore.save(_tasks.where((t) => t.isWish).toList()));
    }
  }

  Future<bool> _connectSync() async {
    final granted = await _sharedStore.requestConnection();
    if (granted && mounted) {
      setState(() => _syncConnected = true);
      await _load();
    }
    return granted;
  }

  void _dismissSyncBanner() {
    setState(() => Config.wishlistSyncBannerDismissed = true);
    unawaited(Config.save());
  }

  /// Wishlist items sorted like BestToDo's: open items before done ones,
  /// then by priority, otherwise keeping list order.
  List<Task> _wishes() {
    final wishes = ItemViews.wishlist(_tasks);
    final order = <String, int>{
      for (var i = 0; i < wishes.length; i++) wishes[i].uid: i,
    };
    wishes.sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      final byPriority = wishPriorityRank(b) - wishPriorityRank(a);
      if (byPriority != 0) return byPriority;
      return order[a.uid]!.compareTo(order[b.uid]!);
    });
    return wishes;
  }

  Future<void> _openItem([Task? item]) async {
    final result = await Navigator.of(context).push<_MusicWishItemResult>(
      MaterialPageRoute(builder: (_) => _MusicWishItemPage(item: item)),
    );
    if (result == null) return;
    setState(() {
      if (result.deleted) {
        if (item != null) _tasks.remove(item);
      } else if (item == null) {
        _tasks.insert(
          0,
          Task(
            title: result.title,
            description: result.description,
            label: result.label,
            createdAt: DateTime.now(),
            isDone: result.isDone,
            isWish: true,
          ),
        );
      } else {
        item
          ..title = result.title
          ..description = result.description
          ..label = result.label
          ..isDone = result.isDone
          ..completedAt =
              result.isDone ? (item.completedAt ?? DateTime.now()) : null;
      }
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final wishes = _wishes();
    final showSyncBanner = !_loading &&
        !_syncConnected &&
        !Config.wishlistSyncBannerDismissed &&
        _sharedStore.isSupported;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Wishlist'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add wishlist item',
        onPressed: () => _openItem(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (showSyncBanner)
            WishlistSyncBanner(
              otherAppName: 'BestToDo',
              onConnect: _connectSync,
              onDismiss: _dismissSyncBanner,
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : wishes.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No wishlist items yet. Add ideas here; tap one to see '
                            'its description, priority and tags.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
                        itemCount: wishes.length,
                        itemBuilder: (context, index) {
                          final item = wishes[index];
                          return ListTile(
                            title: Text(
                              item.title,
                              style: TextStyle(
                                decoration: item.isDone
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            onTap: () => _openItem(item),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _MusicWishItemResult {
  final String title;
  final String description;
  final String label;
  final bool isDone;
  final bool deleted;

  const _MusicWishItemResult({
    this.title = '',
    this.description = '',
    this.label = '',
    this.isDone = false,
    this.deleted = false,
  });
}

/// Full-page editor for one wishlist item — every field the list itself
/// hides: title, done, priority (the same `priority-low/medium/high` tokens
/// as BestToDo's Wishlist), tags and description. Owns its own text
/// controllers so the page's exit transition never touches a disposed one.
class _MusicWishItemPage extends StatefulWidget {
  final Task? item;

  const _MusicWishItemPage({this.item});

  @override
  State<_MusicWishItemPage> createState() => _MusicWishItemPageState();
}

class _MusicWishItemPageState extends State<_MusicWishItemPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _label;
  late bool _isDone;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item?.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.item?.description ?? '');
    _label = widget.item?.label ?? '';
    _isDone = widget.item?.isDone ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  List<String> _labelsFromText(String text) => text
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toList();

  void _setPriority(String priorityLabel) {
    final labels = _labelsFromText(_label)
        .where((label) => !wishPriorityLabels.contains(label.toLowerCase()))
        .toList();
    labels.insert(0, priorityLabel);
    setState(() => _label = labels.join(', '));
  }

  int get _priorityRank {
    final labels = _labelsFromText(_label).map((l) => l.toLowerCase()).toSet();
    for (var i = wishPriorityLabels.length - 1; i >= 0; i--) {
      if (labels.contains(wishPriorityLabels[i])) return i + 1;
    }
    return 0;
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(_MusicWishItemResult(
      title: title,
      description: _descriptionController.text.trim(),
      label: _label.trim(),
      isDone: _isDone,
    ));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete wishlist item?'),
        content: Text('"${widget.item!.title}" will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(const _MusicWishItemResult(deleted: true));
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.item == null;
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: isNew ? 'Add wishlist item' : 'Edit wishlist item',
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              autofocus: isNew,
              decoration: const InputDecoration(labelText: 'Title'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Done'),
              value: _isDone,
              onChanged: (v) => setState(() => _isDone = v),
            ),
            const SizedBox(height: 4),
            Text('Priority', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < wishPriorityLabels.length; i++)
                  ChoiceChip(
                    label: Text(
                        wishPriorityLabels[i].replaceFirst('priority-', '')),
                    selected: _priorityRank == i + 1,
                    onSelected: (_) => _setPriority(wishPriorityLabels[i]),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LabelPickerField(
              value: _label,
              fieldLabel: 'Tags',
              onChanged: (v) => setState(() => _label = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 5,
            ),
          ],
        ),
      ),
    );
  }
}
