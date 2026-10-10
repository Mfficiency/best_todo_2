import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/countdown_milestone.dart';
import '../models/countdown_timer.dart';

/// What [showCountdownMilestonesDialog] hands back when the user saves.
class MilestonesResult {
  final bool enabled;
  final List<CountdownMilestone> milestones;

  const MilestonesResult({required this.enabled, required this.milestones});
}

/// Opens the per-timer milestone editor. Returns null when cancelled.
Future<MilestonesResult?> showCountdownMilestonesDialog(
  BuildContext context,
  CountdownTimerItem timer,
) {
  return showDialog<MilestonesResult>(
    context: context,
    builder: (_) => _MilestonesDialog(timer: timer),
  );
}

/// The dialog owns its own controllers (one per row) and disposes them itself —
/// disposing them from the caller right after `showDialog` returns would break
/// the exit animation, which still builds the fields.
class _MilestonesDialog extends StatefulWidget {
  final CountdownTimerItem timer;

  const _MilestonesDialog({required this.timer});

  @override
  State<_MilestonesDialog> createState() => _MilestonesDialogState();
}

/// One editable row: a text controller for the number plus the unit/direction
/// the dropdown and toggle write into.
class _Draft {
  final TextEditingController controller;
  MilestoneUnit unit;
  MilestoneDirection direction;

  _Draft(CountdownMilestone m)
      : controller = TextEditingController(text: m.value.toString()),
        unit = m.unit,
        direction = m.direction;
}

class _MilestonesDialogState extends State<_MilestonesDialog> {
  late bool _enabled;
  late List<_Draft> _drafts;

  @override
  void initState() {
    super.initState();
    _enabled = widget.timer.notifyRoundNumbers;
    _drafts =
        widget.timer.sortedMilestones.map((m) => _Draft(m.copy())).toList();
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.controller.dispose();
    }
    super.dispose();
  }

  void _add() {
    setState(() {
      _drafts.add(_Draft(
        CountdownMilestone(value: 1, unit: MilestoneUnit.days),
      ));
    });
  }

  void _removeAt(int index) {
    setState(() {
      _drafts.removeAt(index).controller.dispose();
    });
  }

  void _resetToDefaults() {
    setState(() {
      for (final d in _drafts) {
        d.controller.dispose();
      }
      _drafts = CountdownTimerItem.defaultMilestones()
          .map((m) => _Draft(m))
          .toList();
      _enabled = true;
    });
  }

  void _cycleDirection(_Draft draft) {
    setState(() {
      draft.direction = switch (draft.direction) {
        MilestoneDirection.both => MilestoneDirection.before,
        MilestoneDirection.before => MilestoneDirection.after,
        MilestoneDirection.after => MilestoneDirection.both,
      };
    });
  }

  /// Drafts turned back into milestones: blank/zero rows dropped, duplicates
  /// (same number and unit) collapsed, longest first.
  List<CountdownMilestone> _collect() {
    final result = <CountdownMilestone>[];
    for (final d in _drafts) {
      final value = int.tryParse(d.controller.text.trim()) ?? 0;
      if (value <= 0) continue;
      final milestone = CountdownMilestone(
        value: value,
        unit: d.unit,
        direction: d.direction,
      );
      if (result.any((m) => m.sameAs(milestone))) continue;
      result.add(milestone);
    }
    result.sort((a, b) => b.approximateSeconds.compareTo(a.approximateSeconds));
    return result;
  }

  void _save() {
    Navigator.of(context).pop(
      MilestonesResult(enabled: _enabled, milestones: _collect()),
    );
  }

  IconData _directionIcon(MilestoneDirection d) => switch (d) {
        MilestoneDirection.before => Icons.arrow_back,
        MilestoneDirection.after => Icons.arrow_forward,
        MilestoneDirection.both => Icons.compare_arrows,
      };

  String _directionTooltip(MilestoneDirection d) => switch (d) {
        MilestoneDirection.before => 'Notify before the event only',
        MilestoneDirection.after => 'Notify after the event only',
        MilestoneDirection.both => 'Notify before and after the event',
      };

  Widget _buildRow(int index) {
    final draft = _drafts[index];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: TextField(
              controller: draft.controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.end,
              decoration: const InputDecoration(isDense: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<MilestoneUnit>(
              value: draft.unit,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              onChanged: (unit) {
                if (unit == null) return;
                setState(() => draft.unit = unit);
              },
              items: [
                for (final unit in MilestoneUnit.values)
                  DropdownMenuItem(
                    value: unit,
                    child: Text(
                      CountdownMilestone.unitName(unit, plural: true),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(_directionIcon(draft.direction), size: 20),
            tooltip: _directionTooltip(draft.direction),
            visualDensity: VisualDensity.compact,
            onPressed: () => _cycleDirection(draft),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Remove milestone',
            visualDensity: VisualDensity.compact,
            onPressed: () => _removeAt(index),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.timer.label.trim().isEmpty
        ? 'Untitled timer'
        : widget.timer.label.trim();
    return AlertDialog(
      title: const Text('Milestone notifications'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              SwitchListTile(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('Notify at milestones'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const Divider(),
              if (_drafts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No milestones yet.'),
                )
              else
                for (var i = 0; i < _drafts.length; i++) _buildRow(i),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add milestone'),
                    onPressed: _add,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _resetToDefaults,
                    child: const Text('Defaults'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
