import 'package:flutter/material.dart';

import '../models/approval_quick_tag.dart';
import '../services/approval_quick_tag_service.dart';
import 'subpage_app_bar.dart';

/// Settings > Tasks > Approval quick tags. Lets the user view/add/edit/
/// delete the tag -> tool dictionary [ApprovalQuickTagService] shows as
/// buttons at the top of a Waiting for Approval item's expanded details
/// panel (`waiting_approval_page.dart`) — e.g. tapping "Research" there
/// approves the item and sends it straight to the Research tool.
class ApprovalQuickTagsPage extends StatefulWidget {
  const ApprovalQuickTagsPage({Key? key}) : super(key: key);

  @override
  State<ApprovalQuickTagsPage> createState() => _ApprovalQuickTagsPageState();
}

class _ApprovalQuickTagsPageState extends State<ApprovalQuickTagsPage> {
  Future<void> _addOrEditTag([int? index]) async {
    final list = ApprovalQuickTagService.instance.list;
    final result = await showDialog<ApprovalQuickTag>(
      context: context,
      builder: (context) => _ApprovalQuickTagDialog(
        tag: index == null ? null : list[index],
      ),
    );
    if (result == null) return;
    final next = [...list];
    if (index == null) {
      next.add(result);
    } else {
      next[index] = result;
    }
    await ApprovalQuickTagService.instance.save(next);
    if (mounted) setState(() {});
  }

  Future<void> _deleteTag(int index) async {
    final next = [...ApprovalQuickTagService.instance.list]..removeAt(index);
    await ApprovalQuickTagService.instance.save(next);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Approval quick tags'),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add quick tag',
        onPressed: () => _addOrEditTag(),
        child: const Icon(Icons.add),
      ),
      body: ValueListenableBuilder<List<ApprovalQuickTag>>(
        valueListenable: ApprovalQuickTagService.instance.tags,
        builder: (context, tags, _) {
          if (tags.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No quick tags yet. Tap + to add one: a button that '
                  'approves a pending item straight into a tool, shown at '
                  'the top of its expanded details in Waiting for Approval.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: tags.length,
            itemBuilder: (context, index) {
              final tag = tags[index];
              return ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: Text(tag.label),
                subtitle: Text(
                  'Approves into ${ApprovalQuickTag.targetLabels[tag.target] ?? tag.target}',
                ),
                onTap: () => _addOrEditTag(index),
                trailing: IconButton(
                  tooltip: 'Delete quick tag',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteTag(index),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ApprovalQuickTagDialog extends StatefulWidget {
  final ApprovalQuickTag? tag;

  const _ApprovalQuickTagDialog({this.tag});

  @override
  State<_ApprovalQuickTagDialog> createState() =>
      _ApprovalQuickTagDialogState();
}

class _ApprovalQuickTagDialogState extends State<_ApprovalQuickTagDialog> {
  late final TextEditingController _labelController =
      TextEditingController(text: widget.tag?.label ?? '');
  late String _target =
      widget.tag?.target ?? ApprovalQuickTag.targets.first;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _save() {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context)
        .pop(ApprovalQuickTag(label: label, target: _target));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.tag == null ? 'Add quick tag' : 'Edit quick tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _labelController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Button label'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _target,
            decoration: const InputDecoration(labelText: 'Approves into'),
            items: [
              for (final target in ApprovalQuickTag.targets)
                DropdownMenuItem<String>(
                  value: target,
                  child: Text(ApprovalQuickTag.targetLabels[target]!),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _target = value);
            },
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
