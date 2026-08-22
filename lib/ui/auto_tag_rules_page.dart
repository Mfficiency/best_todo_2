import 'package:flutter/material.dart';

import '../models/auto_tag_rule.dart';
import '../services/auto_tag_service.dart';
import 'subpage_app_bar.dart';

/// Settings > Tasks > Auto-tag rules. Lets the user view/add/edit/delete the
/// keyword → tag dictionary [AutoTagService] matches new item titles against.
class AutoTagRulesPage extends StatefulWidget {
  const AutoTagRulesPage({Key? key}) : super(key: key);

  @override
  State<AutoTagRulesPage> createState() => _AutoTagRulesPageState();
}

class _AutoTagRulesPageState extends State<AutoTagRulesPage> {
  Future<void> _addOrEditRule([int? index]) async {
    final rules = AutoTagService.instance.list;
    final result = await showDialog<AutoTagRule>(
      context: context,
      builder: (context) => _AutoTagRuleDialog(
        rule: index == null ? null : rules[index],
      ),
    );
    if (result == null) return;
    final next = [...rules];
    if (index == null) {
      next.add(result);
    } else {
      next[index] = result;
    }
    await AutoTagService.instance.save(next);
    if (mounted) setState(() {});
  }

  Future<void> _deleteRule(int index) async {
    final next = [...AutoTagService.instance.list]..removeAt(index);
    await AutoTagService.instance.save(next);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Auto-tag rules'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add rule',
        onPressed: () => _addOrEditRule(),
        child: const Icon(Icons.add),
      ),
      body: ValueListenableBuilder<List<AutoTagRule>>(
        valueListenable: AutoTagService.instance.rules,
        builder: (context, rules, _) {
          if (rules.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No auto-tag rules yet. Tap + to add one: a keyword and '
                  'the tag it should add to a new task\'s title.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: rules.length,
            itemBuilder: (context, index) {
              final rule = rules[index];
              return ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: Text('"${rule.keyword}" → ${rule.tag}'),
                onTap: () => _addOrEditRule(index),
                trailing: IconButton(
                  tooltip: 'Delete rule',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteRule(index),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AutoTagRuleDialog extends StatefulWidget {
  final AutoTagRule? rule;

  const _AutoTagRuleDialog({this.rule});

  @override
  State<_AutoTagRuleDialog> createState() => _AutoTagRuleDialogState();
}

class _AutoTagRuleDialogState extends State<_AutoTagRuleDialog> {
  late final TextEditingController _keywordController =
      TextEditingController(text: widget.rule?.keyword ?? '');
  late final TextEditingController _tagController =
      TextEditingController(text: widget.rule?.tag ?? '');

  @override
  void dispose() {
    _keywordController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _save() {
    final keyword = _keywordController.text.trim();
    final tag = _tagController.text.trim();
    if (keyword.isEmpty || tag.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(AutoTagRule(keyword: keyword, tag: tag));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rule == null ? 'Add auto-tag rule' : 'Edit rule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _keywordController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Keyword',
              helperText: 'Matched as a whole word in the title',
            ),
          ),
          TextField(
            controller: _tagController,
            decoration: const InputDecoration(labelText: 'Tag to add'),
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
