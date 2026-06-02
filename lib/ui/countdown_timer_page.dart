import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/countdown_timer.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import 'subpage_app_bar.dart';

class CountdownTimerPage extends StatefulWidget {
  const CountdownTimerPage({Key? key}) : super(key: key);

  @override
  State<CountdownTimerPage> createState() => _CountdownTimerPageState();
}

class _CountdownTimerPageState extends State<CountdownTimerPage> {
  final StorageService _storage = StorageService();

  List<CountdownTimerItem> _timers = [];
  final Set<String> _expanded = {};

  /// Timer uids that should not fire a zero-notification: either they have
  /// already fired this session, or they were already past when the bell was
  /// switched on. Not persisted.
  final Set<String> _notifySuppressed = {};

  Timer? _ticker;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _checkZeroNotifications();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final loaded = await _storage.loadCountdownTimers();
    final List<CountdownTimerItem> timers;
    if (loaded == null) {
      // First run: seed a few example timers in development builds only.
      timers = Config.isDev ? _devSeedTimers() : <CountdownTimerItem>[];
      await _storage.saveCountdownTimers(timers);
    } else {
      timers = loaded;
    }
    // Past timers that have the bell on should not retroactively fire.
    final now = DateTime.now();
    for (final t in timers) {
      if (t.notifyOnZero && !t.target.isAfter(now)) {
        _notifySuppressed.add(t.uid);
      }
    }
    if (!mounted) return;
    setState(() {
      _timers = timers;
      _loading = false;
    });
  }

  List<CountdownTimerItem> _devSeedTimers() {
    final now = DateTime.now();
    return [
      CountdownTimerItem(
        label: 'New Year',
        target: DateTime(now.year + 1, 1, 1, 0, 0),
      ),
      CountdownTimerItem(
        label: 'Project deadline',
        target: now.add(const Duration(days: 30, hours: 6)),
        notifyOnZero: true,
      ),
      CountdownTimerItem(
        label: 'Coffee break',
        target: now.add(const Duration(minutes: 15)),
      ),
    ];
  }

  Future<void> _save() => _storage.saveCountdownTimers(_timers);

  void _checkZeroNotifications() {
    final now = DateTime.now();
    for (final t in _timers) {
      if (!t.notifyOnZero) continue;
      if (_notifySuppressed.contains(t.uid)) continue;
      if (!t.target.isAfter(now)) {
        _notifySuppressed.add(t.uid);
        final name = t.label.trim().isEmpty ? 'Countdown' : t.label.trim();
        NotificationService.showTaskNotification(
          '$name reached zero',
          delaySeconds: 0,
        );
      }
    }
  }

  Future<void> _addTimer() async {
    final result = await _showEditDialog();
    if (result == null) return;
    setState(() {
      _timers.add(result);
      if (result.notifyOnZero && !result.target.isAfter(DateTime.now())) {
        _notifySuppressed.add(result.uid);
      }
    });
    await _save();
  }

  Future<void> _editTimer(CountdownTimerItem timer) async {
    final result = await _showEditDialog(existing: timer);
    if (result == null) return;
    setState(() {
      timer.label = result.label;
      timer.target = result.target;
      // Re-evaluate suppression against the new target.
      _notifySuppressed.remove(timer.uid);
      if (timer.notifyOnZero && !timer.target.isAfter(DateTime.now())) {
        _notifySuppressed.add(timer.uid);
      }
    });
    await _save();
  }

  void _toggleNotify(CountdownTimerItem timer) {
    setState(() {
      timer.notifyOnZero = !timer.notifyOnZero;
      if (timer.notifyOnZero) {
        // Don't retroactively notify for an already-elapsed timer.
        if (!timer.target.isAfter(DateTime.now())) {
          _notifySuppressed.add(timer.uid);
        } else {
          _notifySuppressed.remove(timer.uid);
        }
      } else {
        _notifySuppressed.remove(timer.uid);
      }
    });
    _save();
  }

  void _deleteTimer(int index) {
    final removed = _timers[index];
    setState(() {
      _timers.removeAt(index);
      _expanded.remove(removed.uid);
    });
    _save();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${removed.label.trim().isEmpty ? 'Timer' : removed.label} deleted',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              setState(() {
                final insertAt = index <= _timers.length ? index : _timers.length;
                _timers.insert(insertAt, removed);
              });
              _save();
            },
          ),
        ),
      );
  }

  Future<CountdownTimerItem?> _showEditDialog({
    CountdownTimerItem? existing,
  }) {
    return showDialog<CountdownTimerItem>(
      context: context,
      builder: (_) => _TimerEditDialog(existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Countdown'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _timers.length + 1,
      itemBuilder: (context, index) {
        if (index == _timers.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('New Timer'),
                onPressed: _addTimer,
              ),
            ),
          );
        }

        final timer = _timers[index];
        return Dismissible(
          key: ValueKey(timer.uid),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => _deleteTimer(index),
          child: _buildTimerCard(context, timer),
        );
      },
    );
  }

  Widget _buildTimerCard(BuildContext context, CountdownTimerItem timer) {
    final now = DateTime.now();
    final isPast = !timer.target.isAfter(now);
    final isExpanded = _expanded.contains(timer.uid);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expanded.remove(timer.uid);
                } else {
                  _expanded.add(timer.uid);
                }
              });
            },
            title: Text(
              timer.label.trim().isEmpty ? 'Untitled timer' : timer.label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(_formatTarget(timer.target)),
                const SizedBox(height: 2),
                Text(
                  _relativeSummary(now, timer.target),
                  style: TextStyle(
                    color: isPast
                        ? Colors.orange.shade800
                        : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit',
                  onPressed: () => _editTimer(timer),
                ),
                IconButton(
                  icon: Icon(
                    timer.notifyOnZero
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    color: timer.notifyOnZero
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: timer.notifyOnZero
                      ? 'Notify at zero: on'
                      : 'Notify at zero: off',
                  onPressed: () => _toggleNotify(timer),
                ),
              ],
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildExpandedDetail(context, now, timer.target, isPast),
            ),
        ],
      ),
    );
  }

  Widget _buildExpandedDetail(
    BuildContext context,
    DateTime now,
    DateTime target,
    bool isPast,
  ) {
    final from = isPast ? target : now;
    final to = isPast ? now : target;
    final d = _Decimals(to.difference(from));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(
          isPast ? 'Time since the event' : 'Time until the event',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        _detailRow('Years', d.years.toStringAsFixed(1)),
        _detailRow('Months', d.months.toStringAsFixed(1)),
        _detailRow('Weeks', d.weeks.toStringAsFixed(1)),
        _detailRow('Days', d.days.toStringAsFixed(1)),
        _detailRow('Hours', d.hours.toStringAsFixed(1)),
        _detailRow('Minutes', d.minutes.toStringAsFixed(1)),
        _detailRow('Seconds', '${d.seconds}'),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  /// Compact whole-unit breakdown shown on the collapsed card, with a
  /// direction prefix/suffix. Counts up once the target has passed.
  String _relativeSummary(DateTime now, DateTime target) {
    final isPast = !target.isAfter(now);
    final from = isPast ? target : now;
    final to = isPast ? now : target;

    final b = _breakdown(from, to);
    final parts = <String>[];
    if (b.months > 0) parts.add('${b.months}mo');
    if (b.weeks > 0) parts.add('${b.weeks}w');
    if (b.days > 0) parts.add('${b.days}d');
    if (b.hours > 0) parts.add('${b.hours}h');
    if (b.minutes > 0) parts.add('${b.minutes}m');
    parts.add('${b.seconds}s');

    final body = parts.join(' ');
    return isPast ? '$body ago (counting up)' : 'in $body';
  }

  /// Whole-unit breakdown using calendar months for the collapsed summary.
  _Breakdown _breakdown(DateTime from, DateTime to) {
    var months = 0;
    var cursor = from;
    while (true) {
      final next = _addMonth(cursor);
      if (next.isAfter(to)) break;
      cursor = next;
      months++;
    }
    var remainder = to.difference(cursor);

    final weeks = remainder.inDays ~/ 7;
    remainder -= Duration(days: weeks * 7);
    final days = remainder.inDays;
    remainder -= Duration(days: days);
    final hours = remainder.inHours;
    remainder -= Duration(hours: hours);
    final minutes = remainder.inMinutes;
    remainder -= Duration(minutes: minutes);
    final seconds = remainder.inSeconds;

    return _Breakdown(
      months: months,
      weeks: weeks,
      days: days,
      hours: hours,
      minutes: minutes,
      seconds: seconds,
    );
  }

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
}

/// The same duration expressed in several units, all as decimals except
/// seconds. e.g. 1.1 years == 13.2 months == ~57 weeks.
class _Decimals {
  final double years;
  final double months;
  final double weeks;
  final double days;
  final double hours;
  final double minutes;
  final int seconds;

  factory _Decimals(Duration duration) {
    final us = duration.inMicroseconds.abs().toDouble();
    final totalSeconds = us / 1000000.0;
    final totalMinutes = totalSeconds / 60.0;
    final totalHours = totalMinutes / 60.0;
    final totalDays = totalHours / 24.0;
    return _Decimals._(
      years: totalDays / 365.25,
      months: totalDays / 30.4375,
      weeks: totalDays / 7.0,
      days: totalDays,
      hours: totalHours,
      minutes: totalMinutes,
      seconds: totalSeconds.floor(),
    );
  }

  const _Decimals._({
    required this.years,
    required this.months,
    required this.weeks,
    required this.days,
    required this.hours,
    required this.minutes,
    required this.seconds,
  });
}

class _Breakdown {
  final int months;
  final int weeks;
  final int days;
  final int hours;
  final int minutes;
  final int seconds;

  const _Breakdown({
    required this.months,
    required this.weeks,
    required this.days,
    required this.hours,
    required this.minutes,
    required this.seconds,
  });
}

/// Dialog used to create or edit a single timer (label + date + time).
class _TimerEditDialog extends StatefulWidget {
  final CountdownTimerItem? existing;

  const _TimerEditDialog({this.existing});

  @override
  State<_TimerEditDialog> createState() => _TimerEditDialogState();
}

class _TimerEditDialogState extends State<_TimerEditDialog> {
  late final TextEditingController _labelController;
  late DateTime _target;

  @override
  void initState() {
    super.initState();
    _labelController =
        TextEditingController(text: widget.existing?.label ?? '');
    _target = widget.existing?.target ??
        DateTime.now().add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _target,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 100),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_target),
    );
    if (time == null || !mounted) return;

    setState(() {
      _target = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
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
    return AlertDialog(
      title: Text(widget.existing == null ? 'New Timer' : 'Edit Timer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _labelController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Birthday',
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(_formatTarget(_target)),
            onPressed: _pickDateTime,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final result = CountdownTimerItem(
              uid: widget.existing?.uid,
              label: _labelController.text.trim(),
              target: _target,
              notifyOnZero: widget.existing?.notifyOnZero ?? false,
            );
            Navigator.of(context).pop(result);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
