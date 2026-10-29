import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/task.dart';
import '../models/task_change_source.dart';
import '../services/grocery_category_service.dart';
import '../services/item_repository.dart';
import '../services/item_views.dart';
import '../services/log_service.dart';
import 'speech_input_button.dart';
import 'subpage_app_bar.dart';

/// Tools → Groceries: a reusable checklist over the one task list — items
/// flagged [Task.isGrocery], never shown anywhere else (see
/// [ItemViews.groceries]). Grouped into sections by [Task.groceryCategory]
/// in the order of [GroceryCategoryService]'s (editable) list; no dates.
/// Checked items stay until "Reset list" unchecks everything (the day
/// rollover sweep skips grocery items), and adding something already on the
/// list unchecks it instead of making a duplicate ([GroceryList.add]).
///
/// Items arrive typed here with the FAB, or approved from Waiting for
/// Approval's Groceries group (the voice inbox).
class GroceriesPage extends StatefulWidget {
  const GroceriesPage({Key? key}) : super(key: key);

  @override
  State<GroceriesPage> createState() => _GroceriesPageState();
}

class _GroceriesPageState extends State<GroceriesPage> {
  final ItemRepository _repository = ItemRepository.instance;
  final GroceryCategoryService _categories = GroceryCategoryService.instance;

  /// The full task list; the page shows and mutates only the grocery subset
  /// but always persists the whole list.
  List<Task> _tasks = <Task>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tasks = await _repository.loadItems();
    await _categories.load();
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _save() => _repository.saveItems(_tasks);

  List<Task> _items() => ItemViews.groceries(_tasks);

  /// [_items] by section, in the configured category order; empty sections
  /// are left out. Within a section: unchecked first, then by name.
  List<MapEntry<String, List<Task>>> _sections() {
    final bySection = <String, List<Task>>{};
    for (final item in _items()) {
      bySection
          .putIfAbsent(_categories.resolve(item.groceryCategory), () => [])
          .add(item);
    }
    return [
      for (final name in _categories.list)
        if (bySection[name] != null)
          MapEntry(
            name,
            bySection[name]!
              ..sort((a, b) {
                if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
                return a.title.toLowerCase().compareTo(b.title.toLowerCase());
              }),
          ),
    ];
  }

  void _toggle(Task item, bool checked) {
    setState(() {
      item.isDone = checked;
      item.completedAt = checked ? DateTime.now() : null;
    });
    _save();
  }

  void _setAll(bool checked) {
    final items = _items();
    if (items.isEmpty) return;
    setState(() {
      for (final item in items) {
        item.isDone = checked;
        item.completedAt = checked ? DateTime.now() : null;
      }
    });
    _save();
    LogService.add('GroceriesPage',
        checked ? 'Checked all ${items.length}' : 'Reset ${items.length}');
  }

  Future<void> _addItem() async {
    final result = await showDialog<_GroceryEditResult>(
      context: context,
      builder: (_) => _GroceryEditDialog(
        categories: _categories.list,
        rememberedCategory: (title) =>
            GroceryList.rememberedCategory(_tasks, title),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final item = Task(
        title: result.title,
        createdAt: DateTime.now(),
        origin: TaskChangeSource.user,
      );
      final kept = GroceryList.add(_tasks, item, category: result.category);
      if (identical(kept, item)) _tasks.insert(0, item);
    });
    await _save();
  }

  Future<void> _changeCategory(Task item) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Category'),
        children: [
          for (final name in _categories.list)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => item.groceryCategory = picked);
    _save();
  }

  /// Removes [item] from the list (to Archived Items after the undo window,
  /// like every other delete in the app).
  void _delete(Task item) {
    final index = _tasks.indexOf(item);
    if (index < 0) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _tasks.removeAt(index));
    _save();
    late Timer timer;
    timer = Timer(Config.delayDuration, () async {
      final deleted = await _repository.loadDeletedItems();
      item.deletedAt = DateTime.now();
      deleted.insert(0, item);
      await _repository.saveDeletedItems(deleted);
      messenger.hideCurrentSnackBar();
    });
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Removed "${item.title}"'),
        duration: Config.delayDuration,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            timer.cancel();
            messenger.hideCurrentSnackBar();
            if (!mounted) return;
            setState(() => _tasks.insert(index.clamp(0, _tasks.length), item));
            _save();
          },
        ),
      ));
  }

  Future<void> _editCategories() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GroceryCategoriesPage()),
    );
    if (mounted) setState(() {});
  }

  Widget _buildItem(Task item) {
    return Dismissible(
      key: ValueKey('grocery-${item.uid}'),
      background: Container(
        color: Colors.red.withValues(alpha: 0.5),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red.withValues(alpha: 0.5),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _delete(item),
      child: CheckboxListTile(
        controlAffinity: ListTileControlAffinity.leading,
        value: item.isDone,
        onChanged: (v) => _toggle(item, v ?? false),
        title: Text(
          item.title,
          style: item.isDone
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        secondary: IconButton(
          tooltip: 'Change category',
          icon: const Icon(Icons.drive_file_move_outline),
          onPressed: () => _changeCategory(item),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = _loading ? <MapEntry<String, List<Task>>>[] : _sections();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Groceries',
        actions: [
          IconButton(
            tooltip: 'Edit categories',
            icon: const Icon(Icons.category_outlined),
            onPressed: _editCategories,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add grocery item',
        onPressed: _loading ? null : _addItem,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: sections.isEmpty ? null : () => _setAll(true),
                        icon: const Icon(Icons.done_all),
                        label: const Text('Check all'),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            sections.isEmpty ? null : () => _setAll(false),
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset list'),
                      ),
                    ],
                  ),
                ),
                if (sections.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nothing on the list yet. Add items with +, or say '
                      'them to Pocket and approve them from Waiting for '
                      'Approval.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final section in sections) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(
                      '${section.key} (${section.value.where((t) => !t.isDone).length}/${section.value.length})',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final item in section.value) _buildItem(item),
                ],
              ],
            ),
    );
  }
}

class _GroceryEditResult {
  final String title;

  /// Null = let [GroceryList.add] use the remembered category.
  final String? category;

  const _GroceryEditResult(this.title, this.category);
}

/// Add dialog owning its own controller (see `_ProjectEditDialog`'s rule).
/// The category starts on "Automatic": the category the item had last time,
/// shown live as the name is typed, else Other.
class _GroceryEditDialog extends StatefulWidget {
  final List<String> categories;
  final String? Function(String title) rememberedCategory;

  const _GroceryEditDialog({
    required this.categories,
    required this.rememberedCategory,
  });

  @override
  State<_GroceryEditDialog> createState() => _GroceryEditDialogState();
}

class _GroceryEditDialogState extends State<_GroceryEditDialog> {
  final TextEditingController _controller = TextEditingController();

  /// Null = automatic.
  String? _category;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(_GroceryEditResult(title, _category));
  }

  @override
  Widget build(BuildContext context) {
    final remembered = widget.rememberedCategory(_controller.text);
    return AlertDialog(
      title: const Text('Add grocery item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Item'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              SpeechInputButton(controller: _controller),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(remembered == null
                    ? 'Automatic'
                    : 'Automatic ($remembered)'),
              ),
              for (final name in widget.categories)
                DropdownMenuItem<String?>(value: name, child: Text(name)),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

/// The Groceries tool's category list: reorder (drag), rename (tap), delete,
/// add. "Other" is fixed at the bottom; a deleted category's items fall back
/// into it.
class GroceryCategoriesPage extends StatefulWidget {
  const GroceryCategoriesPage({Key? key}) : super(key: key);

  @override
  State<GroceryCategoriesPage> createState() => _GroceryCategoriesPageState();
}

class _GroceryCategoriesPageState extends State<GroceryCategoriesPage> {
  final GroceryCategoryService _service = GroceryCategoryService.instance;
  late List<String> _names;

  @override
  void initState() {
    super.initState();
    _names = _service.list
        .where((n) => n != GroceryCategoryService.otherCategory)
        .toList();
    _service.load().then((_) {
      if (!mounted) return;
      setState(() {
        _names = _service.list
            .where((n) => n != GroceryCategoryService.otherCategory)
            .toList();
      });
    });
  }

  Future<void> _persist() async {
    await _service.save(_names);
    if (mounted) setState(() {});
  }

  Future<void> _edit({int? index}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryNameDialog(
        initial: index == null ? '' : _names[index],
        title: index == null ? 'Add category' : 'Rename category',
      ),
    );
    if (name == null || name.trim().isEmpty || !mounted) return;
    setState(() {
      if (index == null) {
        _names.add(name.trim());
      } else {
        _names[index] = name.trim();
      }
    });
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Grocery categories'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add category',
        onPressed: () => _edit(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Expanded(
            child: ReorderableListView(
              buildDefaultDragHandles: true,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  _names.insert(newIndex, _names.removeAt(oldIndex));
                });
                _persist();
              },
              children: [
                for (var i = 0; i < _names.length; i++)
                  ListTile(
                    key: ValueKey('category-${_names[i]}'),
                    title: Text(_names[i]),
                    onTap: () => _edit(index: i),
                    trailing: IconButton(
                      tooltip: 'Delete category',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        setState(() => _names.removeAt(i));
                        _persist();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const ListTile(
            title: Text(GroceryCategoryService.otherCategory),
            subtitle: Text('Always last; catches everything else'),
          ),
        ],
      ),
    );
  }
}

class _CategoryNameDialog extends StatefulWidget {
  final String initial;
  final String title;

  const _CategoryNameDialog({required this.initial, required this.title});

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
