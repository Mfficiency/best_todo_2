import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/task.dart';
import '../services/storage_service.dart';
import 'subpage_app_bar.dart';

/// Tools → Wishlist: a separate task-shaped list for ideas and future wants.
///
/// Wishlist items intentionally show only the title, description, labels, and
/// quick priority tags.
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

  static const List<String> _priorityLabels = <String>[
    'priority-low',
    'priority-medium',
    'priority-high',
  ];

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
    await _exportItems(_items, 'wishlist_${_timestampForFilename()}.json');
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
        .where((label) => !_priorityLabels.contains(label.toLowerCase()))
        .toList();
    labels.insert(0, priorityLabel);
    return labels.join(', ');
  }

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
                  for (final priority in _priorityLabels)
                    OutlinedButton(
                      onPressed: () {
                        labelController.text = _labelTextWithPriority(
                          labelController.text,
                          priority,
                        );
                      },
                      child: Text(priority.replaceFirst('priority-', '')),
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
        final index = _items.indexWhere(
          (candidate) => candidate.uid == item.uid,
        );
        if (index >= 0) _items[index] = result;
      }
    });
    await _save();
  }

  Future<void> _deleteItem(Task item) async {
    setState(
        () => _items.removeWhere((candidate) => candidate.uid == item.uid));
    await _save();
  }

  List<String> _labelsFor(Task item) => _labelsFromText(item.label);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Wishlist',
        actions: [
          IconButton(
            tooltip: 'Export wishlist',
            onPressed: _items.isEmpty ? null : _exportAllItems,
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
                  itemBuilder: (context, index) =>
                      _buildItemCard(_items[index]),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Export wishlist item',
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: () => _exportItem(item),
            ),
            IconButton(
              tooltip: 'Delete wishlist item',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteItem(item),
            ),
          ],
        ),
      ),
    );
  }
}
