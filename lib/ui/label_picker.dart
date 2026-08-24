import 'package:flutter/material.dart';

import '../models/label.dart';
import '../services/label_service.dart';
import '../utils/label_utils.dart';

/// Chip-based label editor: current labels render as removable chips, and an
/// "Add label" chip opens a searchable selection list (every known label,
/// checkbox-toggled) that also accepts a typed name to create a custom one —
/// the click-to-select-or-type pattern from Google Sheets/ClickUp/SharePoint
/// tag fields, replacing a bare comma-separated text field.
class LabelPickerField extends StatefulWidget {
  /// The task's label token string ([Task.label]).
  final String value;
  final ValueChanged<String> onChanged;
  final String fieldLabel;

  const LabelPickerField({
    Key? key,
    required this.value,
    required this.onChanged,
    this.fieldLabel = 'Labels',
  }) : super(key: key);

  @override
  State<LabelPickerField> createState() => _LabelPickerFieldState();
}

class _LabelPickerFieldState extends State<LabelPickerField> {
  late List<String> _tokens;

  @override
  void initState() {
    super.initState();
    _tokens = splitLabelTokens(widget.value);
    // registerTokens() no-ops on an empty list, so a task with no labels yet
    // would never trigger the lazy load of the registry — force it here.
    LabelService.instance.ensureLoaded();
    LabelService.instance.registerTokens(_tokens);
  }

  @override
  void didUpdateWidget(covariant LabelPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _tokens = splitLabelTokens(widget.value);
    }
  }

  void _commit(List<String> tokens) {
    setState(() => _tokens = tokens);
    LabelService.instance.registerTokens(tokens);
    widget.onChanged(joinLabelTokens(tokens));
  }

  void _removeAt(int index) {
    final next = [..._tokens]..removeAt(index);
    _commit(next);
  }

  Future<void> _openPicker() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => _LabelPickerDialog(initialSelected: _tokens),
    );
    if (result != null) _commit(result);
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.fieldLabel,
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < _tokens.length; i++)
                  InputChip(
                    label: Text(_tokens[i]),
                    onDeleted: () => _removeAt(i),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add label'),
                  onPressed: _openPicker,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The selection-list dialog: a search/create field on top, then every known
/// label as a checkable row (filtered by the search text), with an "Add"
/// row offered whenever the typed text isn't an existing label. Owns its own
/// controller so the exit animation never touches a disposed one.
class _LabelPickerDialog extends StatefulWidget {
  final List<String> initialSelected;

  const _LabelPickerDialog({required this.initialSelected});

  @override
  State<_LabelPickerDialog> createState() => _LabelPickerDialogState();
}

class _LabelPickerDialogState extends State<_LabelPickerDialog> {
  late final TextEditingController _searchController;
  late List<String> _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selected = [...widget.initialSelected];
    _searchController = TextEditingController()
      ..addListener(() => setState(() => _query = _searchController.text));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isSelected(String name) =>
      _selected.any((t) => t.toLowerCase() == name.toLowerCase());

  void _toggle(String name) {
    setState(() {
      final idx = _selected.indexWhere((t) => t.toLowerCase() == name.toLowerCase());
      if (idx >= 0) {
        _selected.removeAt(idx);
      } else {
        _selected.add(name);
      }
    });
  }

  void _addCustom() {
    final text = _searchController.text.trim();
    if (text.isEmpty) return;
    if (!_isSelected(text)) _toggle(text);
    _searchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Labels'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search or add a label',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (_) => _addCustom(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: ValueListenableBuilder<List<Label>>(
                valueListenable: LabelService.instance.labels,
                builder: (context, allLabels, _) {
                  final names = <String>{
                    for (final l in allLabels) l.name,
                    ..._selected,
                  }.toList()
                    ..sort((a, b) =>
                        a.toLowerCase().compareTo(b.toLowerCase()));
                  final query = _query.trim();
                  final filtered = query.isEmpty
                      ? names
                      : names
                          .where((n) =>
                              n.toLowerCase().contains(query.toLowerCase()))
                          .toList();
                  final exactMatch = names
                      .any((n) => n.toLowerCase() == query.toLowerCase());

                  return ListView(
                    shrinkWrap: true,
                    children: [
                      if (query.isNotEmpty && !exactMatch)
                        ListTile(
                          leading: const Icon(Icons.add),
                          title: Text('Add "$query"'),
                          onTap: _addCustom,
                        ),
                      for (final name in filtered)
                        CheckboxListTile(
                          value: _isSelected(name),
                          title: Text(name),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (_) => _toggle(name),
                        ),
                      if (filtered.isEmpty && query.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No labels yet — type to add one.'),
                        ),
                    ],
                  );
                },
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
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
