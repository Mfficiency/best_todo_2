import 'package:flutter/material.dart';

import '../config.dart';
import '../models/project.dart';
import '../services/project_service.dart';
import 'label_picker.dart';
import 'subpage_app_bar.dart';

/// One batch submitted from the Bulk Add tool: the item titles plus what they
/// all share — the label token string, the project (null = none) and the
/// home tab ([Config.tabs] index) whose due date they get.
class BulkAddRequest {
  final List<String> titles;
  final String label;
  final String? projectId;
  final int tabIndex;

  const BulkAddRequest({
    required this.titles,
    required this.label,
    required this.projectId,
    required this.tabIndex,
  });
}

/// Leading list markers a pasted line may carry ("- ", "* ", "• ", "1. ",
/// "2) ", "[ ] ", "- [x] "), stripped so a list copied from a note or chat
/// turns into clean titles.
final RegExp _listMarker =
    RegExp(r'^\s*(?:[-*•+]\s+|\d+[.)]\s+)?(?:\[[ xX]?\]\s*)?');

/// Splits the text area into item titles: one per non-blank line, list
/// markers stripped, surrounding whitespace trimmed.
List<String> parseBulkTitles(String text) => text
    .split(RegExp(r'\r?\n'))
    .map((line) => line.replaceFirst(_listMarker, '').trim())
    .where((line) => line.isNotEmpty)
    .toList();

/// Bulk Add tool: type or paste many items (one per line) and add them all
/// at once with the same tags, project and home tab. The tags, project and
/// tab stay selected after an add, so several batches can share them.
class BulkAddPage extends StatefulWidget {
  /// Adds the batch; returns how many items were added.
  final int Function(BulkAddRequest request) onAdd;

  const BulkAddPage({Key? key, required this.onAdd}) : super(key: key);

  @override
  State<BulkAddPage> createState() => _BulkAddPageState();
}

class _BulkAddPageState extends State<BulkAddPage> {
  final TextEditingController _itemsController = TextEditingController();
  String _label = '';
  String? _projectId;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _itemsController.addListener(() => setState(() {}));
    ProjectService.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _itemsController.dispose();
    super.dispose();
  }

  void _submit() {
    final titles = parseBulkTitles(_itemsController.text);
    if (titles.isEmpty) return;
    final added = widget.onAdd(BulkAddRequest(
      titles: titles,
      label: _label,
      projectId: _projectId,
      tabIndex: _tabIndex,
    ));
    _itemsController.clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Added $added item${added == 1 ? '' : 's'}'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final count = parseBulkTitles(_itemsController.text).length;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Bulk Add'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('bulk-add-items'),
            controller: _itemsController,
            minLines: 6,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Items',
              hintText: 'One item per line',
              helperText: 'List markers like "- " or "1. " are removed',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          LabelPickerField(
            value: _label,
            fieldLabel: 'Tags for every item',
            onChanged: (value) => setState(() => _label = value),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<List<Project>>(
            valueListenable: ProjectService.instance.projects,
            builder: (context, projects, _) {
              final selected = projects.any((p) => p.id == _projectId)
                  ? _projectId
                  : null;
              return DropdownButtonFormField<String?>(
                key: const Key('bulk-add-project'),
                value: selected,
                decoration: const InputDecoration(
                  labelText: 'Project',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No project'),
                  ),
                  for (final project in projects)
                    DropdownMenuItem<String?>(
                      value: project.id,
                      child: Text(project.name),
                    ),
                ],
                onChanged: (value) => setState(() => _projectId = value),
              );
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            key: const Key('bulk-add-tab'),
            value: _tabIndex,
            decoration: const InputDecoration(
              labelText: 'Add to',
              border: OutlineInputBorder(),
            ),
            items: [
              for (var i = 0; i < Config.tabs.length; i++)
                DropdownMenuItem<int>(
                  value: i,
                  child: Text(
                    Config.tabs[i].replaceAll('\n', ' ').trim(),
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _tabIndex = value ?? 0),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: count == 0 ? null : _submit,
            icon: const Icon(Icons.playlist_add),
            label: Text(count == 0
                ? 'Add items'
                : 'Add $count item${count == 1 ? '' : 's'}'),
          ),
        ],
      ),
    );
  }
}
