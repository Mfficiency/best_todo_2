import 'dart:async';

import 'package:flutter/material.dart';

import 'subpage_app_bar.dart';

class CountdownTimerPage extends StatefulWidget {
  const CountdownTimerPage({Key? key}) : super(key: key);

  @override
  State<CountdownTimerPage> createState() => _CountdownTimerPageState();
}

class _CountdownTimerPageState extends State<CountdownTimerPage> {
  DateTime? _targetDateTime;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initial = _targetDateTime ?? now.add(const Duration(days: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 100),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    setState(() {
      _targetDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });

    // Tick once a second so the countdown stays live.
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  /// Breaks the duration until [_targetDateTime] into calendar months,
  /// weeks, days, hours and minutes.
  _Countdown _computeCountdown() {
    final target = _targetDateTime!;
    final now = DateTime.now();

    if (!target.isAfter(now)) {
      return const _Countdown(
        months: 0,
        weeks: 0,
        days: 0,
        hours: 0,
        minutes: 0,
        isPast: true,
      );
    }

    // Count whole calendar months between now and target.
    var months = 0;
    var cursor = now;
    while (true) {
      final next = _addMonth(cursor);
      if (next.isAfter(target)) break;
      cursor = next;
      months++;
    }

    // The remainder, expressed as a plain duration.
    var remainder = target.difference(cursor);

    final weeks = remainder.inDays ~/ 7;
    remainder -= Duration(days: weeks * 7);

    final days = remainder.inDays;
    remainder -= Duration(days: days);

    final hours = remainder.inHours;
    remainder -= Duration(hours: hours);

    final minutes = remainder.inMinutes;

    return _Countdown(
      months: months,
      weeks: weeks,
      days: days,
      hours: hours,
      minutes: minutes,
      isPast: false,
    );
  }

  /// Adds one calendar month to [d], clamping the day for shorter months.
  DateTime _addMonth(DateTime d) {
    var year = d.year;
    var month = d.month + 1;
    if (month > 12) {
      month = 1;
      year++;
    }
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = d.day > lastDay ? lastDay : d.day;
    return DateTime(year, month, day, d.hour, d.minute, d.second);
  }

  String _formatTarget(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Countdown Timer'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(
                _targetDateTime == null
                    ? 'Pick a date and time'
                    : 'Change date and time',
              ),
              onPressed: _pickDateTime,
            ),
            const SizedBox(height: 8),
            if (_targetDateTime != null)
              Text(
                'Counting down to ${_formatTarget(_targetDateTime!)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 24),
            Expanded(
              child: Center(
                child: _targetDateTime == null
                    ? const Text(
                        'Pick a date and time to start the countdown.',
                        textAlign: TextAlign.center,
                      )
                    : _buildCountdown(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdown(BuildContext context) {
    final c = _computeCountdown();

    if (c.isPast) {
      return Text(
        'This date and time has already passed.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 16,
      children: [
        _unit(context, c.months, c.months == 1 ? 'Month' : 'Months'),
        _unit(context, c.weeks, c.weeks == 1 ? 'Week' : 'Weeks'),
        _unit(context, c.days, c.days == 1 ? 'Day' : 'Days'),
        _unit(context, c.hours, c.hours == 1 ? 'Hour' : 'Hours'),
        _unit(context, c.minutes, c.minutes == 1 ? 'Minute' : 'Minutes'),
      ],
    );
  }

  Widget _unit(BuildContext context, int value, String label) {
    return SizedBox(
      width: 96,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _Countdown {
  final int months;
  final int weeks;
  final int days;
  final int hours;
  final int minutes;
  final bool isPast;

  const _Countdown({
    required this.months,
    required this.weeks,
    required this.days,
    required this.hours,
    required this.minutes,
    required this.isPast,
  });
}
