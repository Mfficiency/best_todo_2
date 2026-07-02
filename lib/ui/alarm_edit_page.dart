import 'package:flutter/material.dart';

import '../models/alarm.dart';
import 'subpage_app_bar.dart';

/// Full screen editor for creating or editing an [Alarm].
///
/// Returns one of:
///  * an [Alarm] when the user saves,
///  * the string `'delete'` when the user deletes an existing alarm,
///  * `null` when the user backs out without saving.
class AlarmEditPage extends StatefulWidget {
  /// The alarm to edit, or null to create a new one.
  final Alarm? alarm;

  const AlarmEditPage({Key? key, this.alarm}) : super(key: key);

  @override
  State<AlarmEditPage> createState() => _AlarmEditPageState();
}

class _AlarmEditPageState extends State<AlarmEditPage> {
  late final bool _isNew;
  late Alarm _draft;
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  static const List<String> _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  void initState() {
    super.initState();
    _isNew = widget.alarm == null;
    _draft = widget.alarm?.copy() ?? Alarm(name: '');
    _nameController = TextEditingController(text: _draft.name);
    _descriptionController = TextEditingController(text: _draft.description);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _draft.hour, minute: _draft.minute),
    );
    if (picked != null) {
      setState(() {
        _draft.hour = picked.hour;
        _draft.minute = picked.minute;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _draft.date ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _draft.date = picked);
    }
  }

  void _toggleWeekday(int weekday) {
    setState(() {
      if (_draft.repeatDays.contains(weekday)) {
        _draft.repeatDays.remove(weekday);
      } else {
        _draft.repeatDays.add(weekday);
      }
    });
  }

  void _save() {
    _draft.name = _nameController.text.trim();
    _draft.description = _descriptionController.text.trim();
    if (_draft.name.isEmpty) {
      _draft.name = 'Alarm';
    }
    Navigator.of(context).pop(_draft);
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete alarm?'),
        content: Text('"${_draft.name}" will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop('delete');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: _isNew ? 'New Alarm' : 'Edit Alarm',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Time + on/off
          Center(
            child: TextButton(
              onPressed: _pickTime,
              child: Text(
                _draft.timeLabel,
                style: theme.textTheme.displayMedium
                    ?.copyWith(fontWeight: FontWeight.w300),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enabled'),
            subtitle: const Text('Turn this alarm on or off'),
            value: _draft.enabled,
            onChanged: (v) => setState(() => _draft.enabled = v),
          ),
          const Divider(),

          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Wake up',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'Optional note shown when the alarm rings',
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),

          // Repeating
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Repeat'),
            subtitle: Text(_draft.isRepeating
                ? 'Repeats on selected days'
                : 'Rings once'),
            value: _draft.isRepeating,
            onChanged: (v) => setState(() => _draft.isRepeating = v),
          ),
          if (_draft.isRepeating)
            Wrap(
              spacing: 8,
              children: [
                for (var weekday = 1; weekday <= 7; weekday++)
                  FilterChip(
                    label: Text(_weekdayNames[weekday - 1]),
                    selected: _draft.repeatDays.contains(weekday),
                    onSelected: (_) => _toggleWeekday(weekday),
                  ),
              ],
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Date'),
              subtitle: Text(_draft.date == null
                  ? 'Next time ${_draft.timeLabel} occurs'
                  : _draft.scheduleLabel),
              trailing: _draft.date == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _draft.date = null),
                    ),
              onTap: _pickDate,
            ),
          const Divider(),

          // Sound / melody
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.music_note),
                const SizedBox(width: 16),
                const Text('Melody'),
                const Spacer(),
                DropdownButton<String>(
                  value: kAlarmMelodies.contains(_draft.melody)
                      ? _draft.melody
                      : kAlarmMelodies.first,
                  items: [
                    for (final melody in kAlarmMelodies)
                      DropdownMenuItem(value: melody, child: Text(melody)),
                  ],
                  onChanged: (v) =>
                      setState(() => _draft.melody = v ?? _draft.melody),
                ),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(Icons.volume_up),
              const SizedBox(width: 16),
              Expanded(
                child: Slider(
                  value: _draft.volume.clamp(0.0, 1.0),
                  onChanged: (v) => setState(() => _draft.volume = v),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('${(_draft.volume * 100).round()}%',
                    textAlign: TextAlign.end),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibrate'),
            value: _draft.vibrate,
            onChanged: (v) => setState(() => _draft.vibrate = v),
          ),
          const Divider(),

          // Colour
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Colour'),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final color in kAlarmColors)
                GestureDetector(
                  onTap: () => setState(() => _draft.color = color),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _draft.color == color
                            ? theme.colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: _draft.color == color
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                ),
            ],
          ),
          const Divider(),

          // Snooze
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.snooze),
            title: const Text('Snooze'),
            value: _draft.snoozeEnabled,
            onChanged: (v) => setState(() => _draft.snoozeEnabled = v),
          ),
          if (_draft.snoozeEnabled) ...[
            _StepperRow(
              label: 'Snooze length',
              value: '${_draft.snoozeDurationMinutes} min',
              onMinus: _draft.snoozeDurationMinutes > 1
                  ? () => setState(() => _draft.snoozeDurationMinutes--)
                  : null,
              onPlus: _draft.snoozeDurationMinutes < 60
                  ? () => setState(() => _draft.snoozeDurationMinutes++)
                  : null,
            ),
            _StepperRow(
              label: 'Max snoozes',
              value: '${_draft.snoozeMaxCount}',
              onMinus: _draft.snoozeMaxCount > 0
                  ? () => setState(() => _draft.snoozeMaxCount--)
                  : null,
              onPlus: _draft.snoozeMaxCount < 10
                  ? () => setState(() => _draft.snoozeMaxCount++)
                  : null,
            ),
          ],
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
          if (!_isNew) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete alarm'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _StepperRow({
    required this.label,
    required this.value,
    this.onMinus,
    this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: onMinus,
          ),
          SizedBox(
            width: 56,
            child: Text(value, textAlign: TextAlign.center),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: onPlus,
          ),
        ],
      ),
    );
  }
}
