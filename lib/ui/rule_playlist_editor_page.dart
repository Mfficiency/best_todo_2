import 'package:flutter/material.dart';

import '../models/music_playlist.dart';
import '../models/playlist_rule.dart';
import '../services/music_playlist_service.dart';
import 'subpage_app_bar.dart';

/// Builds or edits a rule-based playlist: an AND/OR set of conditions over
/// title/artist/album/genre/year. NOT lives per-condition ("is not"/"does
/// not contain"/"is not one of") rather than as a separate operator — see
/// [RuleOperator]'s doc comment for how "genre X released last year,
/// excluding Artist C" becomes three rows: `genre is X` AND `year is 2025`
/// AND `artist is not one of [C]`.
class RulePlaylistEditorPage extends StatefulWidget {
  const RulePlaylistEditorPage({super.key, this.existing});

  /// When set, edits this playlist's name/rules in place instead of
  /// creating a new one.
  final MusicPlaylist? existing;

  @override
  State<RulePlaylistEditorPage> createState() =>
      _RulePlaylistEditorPageState();
}

class _ConditionRow {
  _ConditionRow({
    required this.field,
    required this.operator,
    String initialValue = '',
  }) : controller = TextEditingController(text: initialValue);

  RuleField field;
  RuleOperator operator;
  final TextEditingController controller;
}

class _RulePlaylistEditorPageState extends State<RulePlaylistEditorPage> {
  late final TextEditingController _nameController;
  RuleCombinator _combinator = RuleCombinator.all;
  final List<_ConditionRow> _rows = [];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    final ruleSet = existing?.ruleSet;
    if (ruleSet != null && ruleSet.conditions.isNotEmpty) {
      _combinator = ruleSet.combinator;
      for (final condition in ruleSet.conditions) {
        _rows.add(_ConditionRow(
          field: condition.field,
          operator: condition.operator,
          initialValue: condition.values.join(', '),
        ));
      }
    } else {
      _rows.add(
          _ConditionRow(field: RuleField.genre, operator: RuleOperator.equals));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final row in _rows) {
      row.controller.dispose();
    }
    super.dispose();
  }

  bool _isNumeric(RuleField field) => field == RuleField.year;

  List<RuleOperator> _operatorsFor(RuleField field) => _isNumeric(field)
      ? const [
          RuleOperator.equals,
          RuleOperator.notEquals,
          RuleOperator.greaterOrEqual,
          RuleOperator.lessOrEqual,
          RuleOperator.inList,
          RuleOperator.notInList,
        ]
      : const [
          RuleOperator.equals,
          RuleOperator.notEquals,
          RuleOperator.contains,
          RuleOperator.notContains,
          RuleOperator.inList,
          RuleOperator.notInList,
        ];

  String _fieldLabel(RuleField field) {
    switch (field) {
      case RuleField.title:
        return 'Title';
      case RuleField.artist:
        return 'Artist';
      case RuleField.album:
        return 'Album';
      case RuleField.genre:
        return 'Genre';
      case RuleField.year:
        return 'Year';
    }
  }

  String _operatorLabel(RuleOperator operator) {
    switch (operator) {
      case RuleOperator.equals:
        return 'is';
      case RuleOperator.notEquals:
        return 'is not';
      case RuleOperator.contains:
        return 'contains';
      case RuleOperator.notContains:
        return 'does not contain';
      case RuleOperator.inList:
        return 'is one of';
      case RuleOperator.notInList:
        return 'is not one of';
      case RuleOperator.greaterOrEqual:
        return 'is at least';
      case RuleOperator.lessOrEqual:
        return 'is at most';
    }
  }

  List<String> _parseValues(_ConditionRow row) {
    final raw = row.controller.text.trim();
    if (raw.isEmpty) return const [];
    if (row.operator == RuleOperator.inList ||
        row.operator == RuleOperator.notInList) {
      return raw
          .split(',')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList();
    }
    return [raw];
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Give the playlist a name')));
      return;
    }
    final conditions = _rows
        .map((row) => RuleCondition(
              field: row.field,
              operator: row.operator,
              values: _parseValues(row),
            ))
        .where((c) => c.values.isNotEmpty)
        .toList();
    if (conditions.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Add at least one rule with a value')));
      return;
    }
    final ruleSet = PlaylistRuleSet(combinator: _combinator, conditions: conditions);
    final existing = widget.existing;
    if (existing != null) {
      await MusicPlaylistService.instance
          .updateRulePlaylist(existing.id, name: name, ruleSet: ruleSet);
    } else {
      await MusicPlaylistService.instance.createRulePlaylist(name, ruleSet);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: widget.existing == null ? 'New rule playlist' : 'Edit rule playlist',
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _save,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Playlist name'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Match'),
              const SizedBox(width: 8),
              DropdownButton<RuleCombinator>(
                value: _combinator,
                items: const [
                  DropdownMenuItem(value: RuleCombinator.all, child: Text('all')),
                  DropdownMenuItem(value: RuleCombinator.any, child: Text('any')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _combinator = value);
                },
              ),
              const SizedBox(width: 8),
              const Flexible(child: Text('of the following rules:')),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _rows.length; i++) _buildRow(i),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _rows.add(_ConditionRow(
                field: RuleField.genre, operator: RuleOperator.equals))),
            icon: const Icon(Icons.add),
            label: const Text('Add rule'),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(int index) {
    final row = _rows[index];
    final isMulti = row.operator == RuleOperator.inList ||
        row.operator == RuleOperator.notInList;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<RuleField>(
              value: row.field,
              items: [
                for (final field in RuleField.values)
                  DropdownMenuItem(value: field, child: Text(_fieldLabel(field))),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  row.field = value;
                  if (!_operatorsFor(value).contains(row.operator)) {
                    row.operator = _operatorsFor(value).first;
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<RuleOperator>(
              value: row.operator,
              isExpanded: true,
              items: [
                for (final operator in _operatorsFor(row.field))
                  DropdownMenuItem(
                      value: operator, child: Text(_operatorLabel(operator))),
              ],
              onChanged: (value) {
                if (value != null) setState(() => row.operator = value);
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: TextField(
              controller: row.controller,
              decoration: InputDecoration(
                hintText: isMulti ? 'comma-separated' : null,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'Remove rule',
            onPressed: _rows.length <= 1
                ? null
                : () => setState(() => _rows.removeAt(index).controller.dispose()),
          ),
        ],
      ),
    );
  }
}
