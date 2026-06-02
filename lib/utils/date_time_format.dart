import 'package:flutter/material.dart';

import '../config.dart';

const List<String> _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats the time of [d] honoring [Config.use24HourFormat].
String formatTimerTime(DateTime d) {
  final mm = d.minute.toString().padLeft(2, '0');
  if (Config.use24HourFormat) {
    return '${d.hour.toString().padLeft(2, '0')}:$mm';
  }
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final period = d.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$mm $period';
}

/// Formats the date of [d] honoring the chosen [Config.dateFormat].
String formatTimerDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yyyy = d.year.toString();
  switch (Config.dateFormat) {
    case 'dd/MM/yyyy':
      return '$dd/$mm/$yyyy';
    case 'MM/dd/yyyy':
      return '$mm/$dd/$yyyy';
    case 'yyyy-MM-dd':
      return '$yyyy-$mm-$dd';
    case 'd MMM yyyy':
      return '${d.day} ${_monthsShort[d.month - 1]} $yyyy';
    case 'dd.MM.yyyy':
    default:
      return '$dd.$mm.$yyyy';
  }
}

/// Formats both date and time, e.g. "09.06.2026, 14:30".
String formatTimerDateTime(DateTime d) =>
    '${formatTimerDate(d)}, ${formatTimerTime(d)}';

/// Shows a calendar date picker that closes as soon as a day is tapped —
/// no separate OK/Cancel step. Returns null if dismissed without a selection.
Future<DateTime?> pickDateInstantly(BuildContext context, DateTime initial) {
  final firstDate = DateTime(2000);
  final lastDate = DateTime(DateTime.now().year + 100);
  // Clamp the initial date into range so CalendarDatePicker never asserts.
  var initialDate = initial;
  if (initialDate.isBefore(firstDate)) initialDate = firstDate;
  if (initialDate.isAfter(lastDate)) initialDate = lastDate;

  return showDialog<DateTime>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      child: SizedBox(
        height: 360,
        child: CalendarDatePicker(
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: lastDate,
          onDateChanged: (date) => Navigator.of(context).pop(date),
        ),
      ),
    ),
  );
}

/// Shows a quick two-step time picker (tap an hour, then tap a minute) that
/// closes the instant a minute is tapped — no separate OK step. Honors
/// [Config.use24HourFormat]. Returns null if dismissed without a selection.
Future<TimeOfDay?> pickTimeOfDay(BuildContext context, TimeOfDay initial) {
  return showDialog<TimeOfDay>(
    context: context,
    builder: (_) => _InstantTimePicker(initial: initial),
  );
}

enum _TimePickStep { hour, minute }

class _InstantTimePicker extends StatefulWidget {
  final TimeOfDay initial;

  const _InstantTimePicker({required this.initial});

  @override
  State<_InstantTimePicker> createState() => _InstantTimePickerState();
}

class _InstantTimePickerState extends State<_InstantTimePicker> {
  late int _hour; // 0-23
  late int _minute; // 0-59
  _TimePickStep _step = _TimePickStep.hour;

  bool get _use24 => Config.use24HourFormat;

  @override
  void initState() {
    super.initState();
    _hour = widget.initial.hour;
    _minute = widget.initial.minute;
  }

  void _selectHour(int hour24) {
    setState(() {
      _hour = hour24;
      _step = _TimePickStep.minute;
    });
  }

  void _selectMinute(int minute) {
    Navigator.of(context).pop(TimeOfDay(hour: _hour, minute: minute));
  }

  Widget _cell(String label, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? scheme.onPrimaryContainer : null,
          ),
        ),
      ),
    );
  }

  Widget _grid(List<Widget> cells) {
    return GridView.count(
      crossAxisCount: 6,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      childAspectRatio: 1.4,
      children: cells,
    );
  }

  Widget _buildHourStep() {
    if (_use24) {
      return _grid([
        for (var h = 0; h < 24; h++)
          _cell(h.toString().padLeft(2, '0'), h == _hour, () => _selectHour(h)),
      ]);
    }
    final isPm = _hour >= 12;
    final currentHour12 = _hour % 12 == 0 ? 12 : _hour % 12;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: const Text('AM'),
                selected: !isPm,
                onSelected: (_) => setState(() {
                  if (isPm) _hour -= 12;
                }),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('PM'),
                selected: isPm,
                onSelected: (_) => setState(() {
                  if (!isPm) _hour += 12;
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: _grid([
            for (var h = 1; h <= 12; h++)
              _cell(
                h.toString(),
                h == currentHour12,
                () => _selectHour((h % 12) + (isPm ? 12 : 0)),
              ),
          ]),
        ),
      ],
    );
  }

  Widget _buildMinuteStep() {
    return _grid([
      for (var m = 0; m < 60; m++)
        _cell(m.toString().padLeft(2, '0'), m == _minute, () => _selectMinute(m)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _step == _TimePickStep.hour ? 'Select hour' : 'Select minute',
      ),
      content: SizedBox(
        width: 320,
        height: 280,
        child: _step == _TimePickStep.hour
            ? _buildHourStep()
            : _buildMinuteStep(),
      ),
      actions: [
        if (_step == _TimePickStep.minute)
          TextButton(
            onPressed: () => setState(() => _step = _TimePickStep.hour),
            child: const Text('Back'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
