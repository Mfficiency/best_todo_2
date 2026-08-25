import 'package:flutter/material.dart';

import '../models/auto_tag_group.dart';
import '../services/auto_tag_service.dart';
import '../utils/label_utils.dart';
import 'subpage_app_bar.dart';

/// Settings > Tasks > Auto-tag rules. Lets the user view/add/edit/delete the
/// tag -> group-of-words dictionary [AutoTagService] matches new item titles
/// against — e.g. the "fitness" tag firing on "gym", "workout" or "cardio".
class AutoTagRulesPage extends StatefulWidget {
  const AutoTagRulesPage({Key? key}) : super(key: key);

  @override
  State<AutoTagRulesPage> createState() => _AutoTagRulesPageState();
}

class _AutoTagRulesPageState extends State<AutoTagRulesPage> {
  Future<void> _addOrEditGroup([int? index]) async {
    final groups = AutoTagService.instance.list;
    final result = await showDialog<AutoTagGroup>(
      context: context,
      builder: (context) => _AutoTagGroupDialog(
        group: index == null ? null : groups[index],
      ),
    );
    if (result == null) return;
    final next = [...groups];
    if (index == null) {
      next.add(result);
    } else {
      next[index] = result;
    }
    await AutoTagService.instance.save(next);
    if (mounted) setState(() {});
  }

  Future<void> _deleteGroup(int index) async {
    final next = [...AutoTagService.instance.list]..removeAt(index);
    await AutoTagService.instance.save(next);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Auto-tag rules'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add tag',
        onPressed: () => _addOrEditGroup(),
        child: const Icon(Icons.add),
      ),
      body: ValueListenableBuilder<List<AutoTagGroup>>(
        valueListenable: AutoTagService.instance.groups,
        builder: (context, groups, _) {
          if (groups.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No auto-tag rules yet. Tap + to add one: a tag and the '
                  'group of words that should add it to a new task\'s title.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: Text(group.tag),
                subtitle: Text(group.keywords.join(', ')),
                onTap: () => _addOrEditGroup(index),
                trailing: IconButton(
                  tooltip: 'Delete tag',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteGroup(index),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AutoTagGroupDialog extends StatefulWidget {
  final AutoTagGroup? group;

  const _AutoTagGroupDialog({this.group});

  @override
  State<_AutoTagGroupDialog> createState() => _AutoTagGroupDialogState();
}

class _AutoTagGroupDialogState extends State<_AutoTagGroupDialog> {
  late final TextEditingController _tagController =
      TextEditingController(text: widget.group?.tag ?? '');
  late final TextEditingController _keywordsController =
      TextEditingController(text: (widget.group?.keywords ?? []).join(', '));

  @override
  void dispose() {
    _tagController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  void _save() {
    final tag = _tagController.text.trim();
    final keywords = splitLabelTokens(_keywordsController.text);
    if (tag.isEmpty || keywords.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(AutoTagGroup(tag: tag, keywords: keywords));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.group == null ? 'Add auto-tag rule' : 'Edit rule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _tagController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tag to add'),
          ),
          TextField(
            controller: _keywordsController,
            decoration: const InputDecoration(
              labelText: 'Words',
              helperText: 'Comma or space separated; any one of them '
                  'matches as a whole word in the title',
            ),
            keyboardType: TextInputType.multiline,
            maxLines: null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
