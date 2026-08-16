import 'package:flutter/material.dart';

import '../models/streak_kind.dart';
import '../services/streak_service.dart';
import '../utils/date_time_format.dart';
import 'subpage_app_bar.dart';

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Yearly calendar for the streak: highlights the longest streak ever
/// (including grace days it survived) plus every other active day, with a
/// header naming the streak's exact first and last day.
class StreakCalendarPage extends StatefulWidget {
  /// Which of the three streak challenges the calendar draws.
  final StreakKind kind;

  const StreakCalendarPage({super.key, this.kind = StreakKind.complete});

  @override
  State<StreakCalendarPage> createState() => _StreakCalendarPageState();
}

class _StreakCalendarPageState extends State<StreakCalendarPage> {
  StreakService get _streak => StreakService.instance;

  late int _year;
  ({DateTime start, DateTime end})? _range;

  @override
  void initState() {
    super.initState();
    _range = _streak.longestStreakRange(kind: widget.kind);
    // Open on the year the longest streak started (it is what the user came
    // to see); fall back to the current year without any history.
    _year = _range?.start.year ?? DateTime.now().year;
  }

  bool _inLongestStreak(DateTime day) {
    final range = _range;
    if (range == null) return false;
    return !day.isBefore(range.start) && !day.isAfter(range.end);
  }

  Widget _legendDot(Color color, String label, {Border? border}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            border: border,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final range = _range;
    final longest = _streak.longestStreak(kind: widget.kind);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: range == null
            ? Text(
                'No streak yet — ${widget.kind.callToAction}',
                style: theme.textTheme.bodyMedium,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.emoji_events,
                          color: widget.kind.warm, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        'Longest streak: $longest days',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'From ${formatTimerDate(range.start)} '
                    'to ${formatTimerDate(range.end)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildYearSelector(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous year',
          onPressed: () => setState(() => _year--),
        ),
        Text(
          '$_year',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next year',
          onPressed: () => setState(() => _year++),
        ),
      ],
    );
  }

  Widget _buildMonth(ThemeData theme, int month) {
    final daysInMonth = DateTime(_year, month + 1, 0).day;
    final firstWeekday = DateTime(_year, month, 1).weekday; // 1 = Monday
    final cells = <Widget>[];
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_year, month, day);
      final active = _streak.isDayDone(date, kind: widget.kind);
      final inStreak = _inLongestStreak(date);
      Color? fill;
      Border? border;
      Color textColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
      if (inStreak && active) {
        fill = widget.kind.warm;
        textColor = Colors.white;
      } else if (inStreak) {
        // A day the streak survived thanks to the 48h grace period.
        border = Border.all(color: widget.kind.warm, width: 1.5);
        textColor = widget.kind.warm;
      } else if (active) {
        fill = widget.kind.cold.withValues(alpha: 0.35);
        textColor = theme.colorScheme.onSurface;
      }
      cells.add(Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          border: border,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 9,
            fontWeight:
                inStreak && active ? FontWeight.bold : FontWeight.normal,
            color: textColor,
          ),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _monthNames[month - 1],
          style: theme.textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          children: cells,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Streak calendar'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(theme),
          const SizedBox(height: 4),
          _buildYearSelector(theme),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _legendDot(widget.kind.warm, 'Longest streak'),
              _legendDot(Colors.transparent, 'Grace day',
                  border: Border.all(color: widget.kind.warm, width: 1.5)),
              _legendDot(
                  widget.kind.cold.withValues(alpha: 0.35), 'Active day'),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  (constraints.maxWidth / 170).floor().clamp(2, 4);
              final width =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (var month = 1; month <= 12; month++)
                    SizedBox(width: width, child: _buildMonth(theme, month)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
