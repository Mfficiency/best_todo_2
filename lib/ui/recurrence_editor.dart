import 'package:flutter/material.dart';

import '../models/recurrence_config.dart';

const _weekdayLabels = <int, String>{
  DateTime.monday: 'M',
  DateTime.tuesday: 'T',
  DateTime.wednesday: 'W',
  DateTime.thursday: 'T',
  DateTime.friday: 'F',
  DateTime.saturday: 'S',
  DateTime.sunday: 'S',
};

const _frequencyLabels = <String, String>{
  'daily': 'day',
  'weekly': 'week',
  'monthly': 'month',
  'yearly': 'year',
};

/// The full "how does this repeat" editor — frequency, step interval, which
/// weekdays (for weekly), and when it ends (never / on a date / after N
/// occurrences). Used both by the creation-time "Repeat" sheet and by the
/// inline task-tile editor for an existing series, so the two never drift
/// apart in what they offer.
class RecurrenceEditor extends StatelessWidget {
  final RecurrenceConfig config;
  final DateTime anchorDate;
  final ValueChanged<RecurrenceConfig> onChanged;

  const RecurrenceEditor({
    super.key,
    required this.config,
    required this.anchorDate,
    required this.onChanged,
  });

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Every'),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: TextFormField(
                initialValue: '${config.interval}',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(isDense: true),
                onChanged: (value) {
                  final n = int.tryParse(value);
                  if (n == null || n < 1) return;
                  onChanged(config.copyWith(interval: n));
                },
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: config.frequency,
              items: RecurrenceConfig.frequencies
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(
                          '${_frequencyLabels[f]}${config.interval == 1 ? '' : 's'}',
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                final weekdays = value == 'weekly' && config.weekdays.isEmpty
                    ? [anchorDate.weekday]
                    : config.weekdays;
                onChanged(
                    config.copyWith(frequency: value, weekdays: weekdays));
              },
            ),
          ],
        ),
        if (config.frequency == 'weekly') ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              for (final weekday in _weekdayLabels.keys)
                _WeekdayChip(
                  label: _weekdayLabels[weekday]!,
                  selected: config.weekdays.contains(weekday),
                  onTap: () {
                    final updated = List<int>.of(config.weekdays);
                    if (updated.contains(weekday)) {
                      if (updated.length > 1) updated.remove(weekday);
                    } else {
                      updated.add(weekday);
                    }
                    onChanged(config.copyWith(weekdays: updated));
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        const Text('Ends', style: TextStyle(fontWeight: FontWeight.bold)),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Never'),
          value: 'never',
          groupValue: config.endType,
          onChanged: (value) => onChanged(config.copyWith(endType: value)),
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Row(
            children: [
              const Text('On '),
              TextButton(
                onPressed: () async {
                  final base = _dateOnly(config.endDate ?? anchorDate);
                  final minDate = _dateOnly(anchorDate);
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: base.isBefore(minDate) ? minDate : base,
                    firstDate: minDate,
                    lastDate: minDate.add(const Duration(days: 365 * 10)),
                  );
                  if (picked == null) return;
                  onChanged(
                    config.copyWith(endType: 'date', endDate: picked),
                  );
                },
                child: Text(
                  config.endDate == null
                      ? 'pick a date'
                      : config.endDate!.toLocal().toString().split(' ')[0],
                ),
              ),
            ],
          ),
          value: 'date',
          groupValue: config.endType,
          onChanged: (value) => onChanged(config.copyWith(
            endType: value,
            endDate: config.endDate ?? anchorDate.add(const Duration(days: 30)),
          )),
        ),
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Row(
            children: [
              const Text('After '),
              SizedBox(
                width: 48,
                child: TextFormField(
                  initialValue: '${config.occurrenceCount ?? 10}',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (value) {
                    final n = int.tryParse(value);
                    if (n == null || n < 1) return;
                    onChanged(
                      config.copyWith(endType: 'count', occurrenceCount: n),
                    );
                  },
                ),
              ),
              const Text(' occurrences'),
            ],
          ),
          value: 'count',
          groupValue: config.endType,
          onChanged: (value) => onChanged(config.copyWith(
            endType: value,
            occurrenceCount: config.occurrenceCount ?? 10,
          )),
        ),
      ],
    );
  }
}

class _WeekdayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _WeekdayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: CircleAvatar(
        radius: 16,
        backgroundColor:
            selected ? scheme.primary : scheme.surfaceContainerHighest,
        foregroundColor: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
