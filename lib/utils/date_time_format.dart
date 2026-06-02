import 'dart:async';
import 'dart:math' as math;

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
  final yy = (d.year % 100).toString().padLeft(2, '0');
  switch (Config.dateFormat) {
    case 'dd.MM.yy':
      return '$dd.$mm.$yy';
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

/// Shows a calendar date picker that closes as soon as a *day* is tapped —
/// no separate OK/Cancel step. Selecting a year or navigating months does not
/// close it. Returns null if dismissed without a selection.
Future<DateTime?> pickDateInstantly(BuildContext context, DateTime initial) {
  final firstDate = DateTime(2000);
  final lastDate = DateTime(DateTime.now().year + 100);
  // Clamp the initial date into range so CalendarDatePicker never asserts.
  var initialDate = initial;
  if (initialDate.isBefore(firstDate)) initialDate = firstDate;
  if (initialDate.isAfter(lastDate)) initialDate = lastDate;

  return showDialog<DateTime>(
    context: context,
    builder: (_) => _InstantDatePicker(
      initial: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

class _InstantDatePicker extends StatefulWidget {
  final DateTime initial;
  final DateTime firstDate;
  final DateTime lastDate;

  const _InstantDatePicker({
    required this.initial,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_InstantDatePicker> createState() => _InstantDatePickerState();
}

class _InstantDatePickerState extends State<_InstantDatePicker> {
  // A year selection (or month navigation) fires onDisplayedMonthChanged right
  // before onDateChanged within the same synchronous turn; a real day tap only
  // fires onDateChanged. So we suppress closing for the remainder of any turn
  // in which the displayed month changed.
  bool _suppressClose = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 24),
      child: SizedBox(
        height: 360,
        child: CalendarDatePicker(
          initialDate: widget.initial,
          firstDate: widget.firstDate,
          lastDate: widget.lastDate,
          onDisplayedMonthChanged: (_) {
            _suppressClose = true;
            scheduleMicrotask(() => _suppressClose = false);
          },
          onDateChanged: (date) {
            if (_suppressClose) return;
            Navigator.of(context).pop(date);
          },
        ),
      ),
    );
  }
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
  static const double _dialSize = 220;

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

  /// Advances hour -> minute, or returns the chosen time once a minute is set.
  void _commitStep() {
    if (_step == _TimePickStep.hour) {
      setState(() => _step = _TimePickStep.minute);
    } else {
      Navigator.of(context).pop(TimeOfDay(hour: _hour, minute: _minute));
    }
  }

  /// Maps a touch point on the dial to an hour or minute value.
  void _updateFromPosition(Offset p) {
    const center = Offset(_dialSize / 2, _dialSize / 2);
    final v = p - center;
    var ang = math.atan2(v.dy, v.dx) + math.pi / 2; // 0 at top, clockwise
    if (ang < 0) ang += 2 * math.pi;

    if (_step == _TimePickStep.minute) {
      final m = (ang / (2 * math.pi) * 60).round() % 60;
      if (m != _minute) setState(() => _minute = m);
      return;
    }

    final pos = (ang / (2 * math.pi) * 12).round() % 12; // 0..11, 0 = top
    int h;
    if (_use24) {
      final inner = v.distance < _dialSize / 2 * 0.66;
      if (inner) {
        h = pos == 0 ? 0 : pos + 12; // 00, 13..23
      } else {
        h = pos == 0 ? 12 : pos; // 12, 1..11
      }
    } else {
      final h12 = pos == 0 ? 12 : pos;
      h = (h12 % 12) + (_hour >= 12 ? 12 : 0);
    }
    if (h != _hour) setState(() => _hour = h);
  }

  String _hourLabel() {
    if (_use24) return _hour.toString().padLeft(2, '0');
    return (_hour % 12 == 0 ? 12 : _hour % 12).toString();
  }

  Widget _headerSegment(String text, bool active, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: active ? scheme.onPrimaryContainer : null,
          ),
        ),
      ),
    );
  }

  Widget _amPmToggle() {
    final isPm = _hour >= 12;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ChoiceChip(
          label: const Text('AM'),
          selected: !isPm,
          onSelected: (_) => setState(() {
            if (isPm) _hour -= 12;
          }),
        ),
        const SizedBox(height: 4),
        ChoiceChip(
          label: const Text('PM'),
          selected: isPm,
          onSelected: (_) => setState(() {
            if (!isPm) _hour += 12;
          }),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hourActive = _step == _TimePickStep.hour;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      title: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _headerSegment(_hourLabel(), hourActive,
                () => setState(() => _step = _TimePickStep.hour)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(':', style: TextStyle(fontSize: 30)),
            ),
            _headerSegment(_minute.toString().padLeft(2, '0'), !hourActive,
                () => setState(() => _step = _TimePickStep.minute)),
            if (!_use24) ...[
              const SizedBox(width: 12),
              _amPmToggle(),
            ],
          ],
        ),
      ),
      content: SizedBox(
        width: _dialSize,
        height: _dialSize,
        child: GestureDetector(
          onTapDown: (d) => _updateFromPosition(d.localPosition),
          onTapUp: (d) {
            _updateFromPosition(d.localPosition);
            _commitStep();
          },
          onPanStart: (d) => _updateFromPosition(d.localPosition),
          onPanUpdate: (d) => _updateFromPosition(d.localPosition),
          onPanEnd: (_) => _commitStep(),
          child: CustomPaint(
            painter: _ClockPainter(
              step: _step,
              hour: _hour,
              minute: _minute,
              use24: _use24,
              scheme: theme.colorScheme,
              textStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (hourActive)
          FilledButton(
            onPressed: () => setState(() => _step = _TimePickStep.minute),
            child: const Text('Minutes'),
          ),
      ],
    );
  }
}

class _ClockPainter extends CustomPainter {
  final _TimePickStep step;
  final int hour;
  final int minute;
  final bool use24;
  final ColorScheme scheme;
  final TextStyle textStyle;

  _ClockPainter({
    required this.step,
    required this.hour,
    required this.minute,
    required this.use24,
    required this.scheme,
    required this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final outerR = radius - 18;
    final innerR = radius - 54;

    canvas.drawCircle(
        center, radius, Paint()..color = scheme.surfaceContainerHighest);

    // Selected hand + knob.
    final sel = _selectedAngleRadius(radius);
    final knob = center +
        Offset(math.sin(sel.angle) * sel.radius,
            -math.cos(sel.angle) * sel.radius);
    final accent = Paint()..color = scheme.primary;
    canvas.drawLine(
        center, knob, Paint()
      ..color = scheme.primary
      ..strokeWidth = 2);
    canvas.drawCircle(center, 4, accent);
    canvas.drawCircle(knob, 17, accent);

    if (step == _TimePickStep.minute) {
      _drawRing(canvas, center, outerR, 12, (i) => (i * 5).toString().padLeft(2, '0'),
          (i) => minute % 5 == 0 && minute ~/ 5 == i);
    } else if (use24) {
      _drawRing(canvas, center, outerR, 12, (i) => (i == 0 ? 12 : i).toString(),
          (i) {
        final val = i == 0 ? 12 : i;
        final outer = !(hour == 0 || hour >= 13);
        return outer && val == hour;
      });
      _drawRing(canvas, center, innerR, 12,
          (i) => (i == 0 ? '00' : (i + 12).toString()), (i) {
        final val = i == 0 ? 0 : i + 12;
        final inner = hour == 0 || hour >= 13;
        return inner && val == hour;
      });
    } else {
      final curH12 = hour % 12 == 0 ? 12 : hour % 12;
      _drawRing(canvas, center, outerR, 12, (i) => (i == 0 ? 12 : i).toString(),
          (i) => (i == 0 ? 12 : i) == curH12);
    }
  }

  ({double angle, double radius}) _selectedAngleRadius(double radius) {
    final outerR = radius - 18;
    final innerR = radius - 54;
    if (step == _TimePickStep.minute) {
      return (angle: minute / 60 * 2 * math.pi, radius: outerR);
    }
    if (use24) {
      final inner = hour == 0 || hour >= 13;
      final pos = inner ? (hour == 0 ? 0 : hour - 12) : (hour == 12 ? 0 : hour);
      return (angle: pos / 12 * 2 * math.pi, radius: inner ? innerR : outerR);
    }
    final curH12 = hour % 12 == 0 ? 12 : hour % 12;
    final pos = curH12 == 12 ? 0 : curH12;
    return (angle: pos / 12 * 2 * math.pi, radius: outerR);
  }

  void _drawRing(Canvas canvas, Offset center, double r, int count,
      String Function(int) labelFor, bool Function(int) isSelected) {
    for (var i = 0; i < count; i++) {
      final ang = i / count * 2 * math.pi;
      final pos =
          center + Offset(math.sin(ang) * r, -math.cos(ang) * r);
      final selected = isSelected(i);
      final tp = TextPainter(
        text: TextSpan(
          text: labelFor(i),
          style: textStyle.copyWith(
            color: selected ? scheme.onPrimary : scheme.onSurface,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _ClockPainter old) =>
      old.step != step ||
      old.hour != hour ||
      old.minute != minute ||
      old.use24 != use24 ||
      old.scheme != scheme;
}
