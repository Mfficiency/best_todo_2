import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/storage_service.dart';
import 'subpage_app_bar.dart';

/// Tools → Wishlist: a separate task-shaped list for ideas and future wants.
///
/// Wishlist items intentionally show only the title, description, and labels.
/// Priority is represented by labels/tags instead of a dedicated priority UI.
class WishlistPage extends StatefulWidget {
  const WishlistPage({Key? key}) : super(key: key);

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  final StorageService _storage = StorageService();
  List<Task> _items = <Task>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _storage.loadWishlist();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _save() => _storage.saveWishlist(_items);

  Future<void> _editItem([Task? item]) async {
    final titleController = TextEditingController(text: item?.title ?? '');
    final descriptionController =
        TextEditingController(text: item?.description ?? '');
    final labelController = TextEditingController(text: item?.label ?? '');

    final result = await showDialog<Task>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? 'Add wishlist item' : 'Edit wishlist item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
                textInputAction: TextInputAction.next,
              ),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Labels / tags',
                  hintText: 'priority-high, gift, someday',
                ),
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
              final title = titleController.text.trim();
              if (title.isEmpty) return;
              Navigator.of(context).pop(Task(
                uid: item?.uid,
                title: title,
                description: descriptionController.text.trim(),
                label: labelController.text.trim(),
                createdAt: item?.createdAt ?? DateTime.now(),
              ));
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    titleController.dispose();
    descriptionController.dispose();
    labelController.dispose();

    if (result == null) return;
    setState(() {
      if (item == null) {
        _items.insert(0, result);
      } else {
        final index = _items.indexWhere((candidate) => candidate.uid == item.uid);
        if (index >= 0) _items[index] = result;
      }
    });
    await _save();
  }

  Future<void> _deleteItem(Task item) async {
    setState(() => _items.removeWhere((candidate) => candidate.uid == item.uid));
    await _save();
  }

  List<String> _labelsFor(Task item) => item.label
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Wishlist'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add wishlist item',
        onPressed: () => _editItem(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No wishlist items yet. Add ideas here and use labels/tags for priority.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                  itemCount: _items.length,
                  itemBuilder: (context, index) => _buildItemCard(_items[index]),
                ),
    );
  }

  Widget _buildItemCard(Task item) {
    final labels = _labelsFor(item);
    return Card(
      child: ListTile(
        title: Text(item.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(item.description),
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
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
          ],
        ),
        onTap: () => _editItem(item),
        trailing: IconButton(
          tooltip: 'Delete wishlist item',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteItem(item),
        ),
      ),
    );
  }
}
