import 'package:flutter/material.dart';

import '../models/task.dart';

/// Schedule-style body for the home page. Renders one long scrollable list
/// where tasks are grouped under per-day headers. The tab bar above
/// continues to drive [tabAnchorKeys] so tapping a tab scrolls this list
/// to the corresponding day section.
///
/// Tile construction is delegated back to the home page via [buildTile]
/// so swipe / move / delete / toggle behavior stays identical to the
/// list-mode tabs.
class ScheduleView extends StatelessWidget {
  final List<Task> tasks;
  final DateTime currentDate;
  final ScrollController scrollController;

  /// GlobalKeys for the section headers that each tab should scroll to.
  /// Keys: 0 = today, 1 = tomorrow, 2 = day after tomorrow,
  /// 3 = first next-week day section, 4 = first next-month day section,
  /// 5 = "Someday" section. The home page reuses these to scroll.
  final Map<int, GlobalKey> tabAnchorKeys;

  /// Builds the row for a single task. The home page passes a fully wired
  /// TaskTile here so all interactions match list mode.
  final Widget Function(Task task) buildTile;

  /// Add-task input row (same widget the list mode shows above each tab).
  final Widget addTaskRow;

  /// Sentinel due date used for the "future / no specific date" bucket.
  static final DateTime futureBucketDate = DateTime(2300, 1, 1);

  const ScheduleView({
    Key? key,
    required this.tasks,
    required this.currentDate,
    required this.scrollController,
    required this.tabAnchorKeys,
    required this.buildTile,
    required this.addTaskRow,
  }) : super(key: key);

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _isSameDay(DateTime a, DateTime b) => _dateOnly(a) == _dateOnly(b);
  String _dayKey(DateTime d) {
    final dd = _dateOnly(d);
    final m = dd.month.toString().padLeft(2, '0');
    final day = dd.day.toString().padLeft(2, '0');
    return '${dd.year}-$m-$day';
  }

  static const List<String> _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatHeader(DateTime date, DateTime today) {
    final d = _dateOnly(date);
    final t = _dateOnly(today);
    final diff = d.difference(t).inDays;
    final base =
        '${_weekdayNames[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}';
    if (diff == 0) return 'Today  ·  $base';
    if (diff == 1) return 'Tomorrow  ·  $base';
    if (diff == 2) return 'Day after tomorrow  ·  $base';
    if (d.year != t.year) return '$base, ${d.year}';
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(currentDate);

    // Split tasks into dated vs future-bucket / undated.
    final dated = <Task>[];
    final someday = <Task>[];
    for (final t in tasks) {
      final due = t.dueDate;
      if (due == null || _isSameDay(due, futureBucketDate)) {
        someday.add(t);
      } else {
        dated.add(t);
      }
    }

    // Group dated tasks by day. Overdue items roll up under today, matching
    // how the Today tab surfaces them.
    final grouped = <String, List<Task>>{};
    final keyToDate = <String, DateTime>{};
    for (final task in dated) {
      final due = _dateOnly(task.dueDate!);
      final groupDate = due.isBefore(today) ? today : due;
      final key = _dayKey(groupDate);
      grouped.putIfAbsent(key, () {
        keyToDate[key] = groupDate;
        return [];
      }).add(task);
    }

    // Ensure today / tomorrow / day-after sections always exist as scroll
    // anchors, even when empty.
    for (final offset in const [0, 1, 2]) {
      final d = today.add(Duration(days: offset));
      final key = _dayKey(d);
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
        keyToDate[key] = d;
      }
    }

    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => keyToDate[a]!.compareTo(keyToDate[b]!));

    // Stable per-day sort within each section.
    for (final list in grouped.values) {
      list.sort((a, b) {
        if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
        final ar = a.listRanking ?? 1 << 30;
        final br = b.listRanking ?? 1 << 30;
        return ar.compareTo(br);
      });
    }

    // Resolve anchor keys: today/tomorrow/day-after attach to their exact
    // day section; tabs 3/4 attach to the first qualifying day section;
    // tab 5 attaches to the Someday header (created below).
    final anchorKeyForKey = <String, GlobalKey>{};
    final todayKey = _dayKey(today);
    final tomorrowKey = _dayKey(today.add(const Duration(days: 1)));
    final dayAfterKey = _dayKey(today.add(const Duration(days: 2)));
    if (tabAnchorKeys[0] != null) anchorKeyForKey[todayKey] = tabAnchorKeys[0]!;
    if (tabAnchorKeys[1] != null) {
      anchorKeyForKey[tomorrowKey] = tabAnchorKeys[1]!;
    }
    if (tabAnchorKeys[2] != null) {
      anchorKeyForKey[dayAfterKey] = tabAnchorKeys[2]!;
    }
    // First day with diff >= 3 (next week range).
    if (tabAnchorKeys[3] != null) {
      for (final k in sortedKeys) {
        final diff = keyToDate[k]!.difference(today).inDays;
        if (diff >= 3 && diff < 30 && !anchorKeyForKey.containsKey(k)) {
          anchorKeyForKey[k] = tabAnchorKeys[3]!;
          break;
        }
      }
    }
    // First day with diff >= 30 (next month range).
    if (tabAnchorKeys[4] != null) {
      for (final k in sortedKeys) {
        final diff = keyToDate[k]!.difference(today).inDays;
        if (diff >= 30 && !anchorKeyForKey.containsKey(k)) {
          anchorKeyForKey[k] = tabAnchorKeys[4]!;
          break;
        }
      }
    }

    final children = <Widget>[];
    for (final key in sortedKeys) {
      final date = keyToDate[key]!;
      final dayTasks = grouped[key]!;
      children.add(
        _DayHeader(
          key: anchorKeyForKey[key],
          text: _formatHeader(date, today),
          isToday: _isSameDay(date, today),
        ),
      );
      if (dayTasks.isEmpty) {
        children.add(const _EmptyDayPlaceholder());
      } else {
        for (final t in dayTasks) {
          children.add(buildTile(t));
        }
      }
    }

    // Someday section. Always render the header so tab 5 has a scroll
    // anchor; show a placeholder when empty.
    children.add(
      _DayHeader(
        key: tabAnchorKeys[5],
        text: 'Someday',
        isToday: false,
      ),
    );
    if (someday.isEmpty) {
      children.add(const _EmptyDayPlaceholder());
    } else {
      for (final t in someday) {
        children.add(buildTile(t));
      }
    }

    return Column(
      children: [
        addTaskRow,
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: 32),
            children: children,
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String text;
  final bool isToday;

  const _DayHeader({Key? key, required this.text, required this.isToday})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: isToday ? theme.colorScheme.primary : null,
        ),
      ),
    );
  }
}

class _EmptyDayPlaceholder extends StatelessWidget {
  const _EmptyDayPlaceholder({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 16, 12),
      child: Text(
        'No tasks',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).disabledColor,
              fontStyle: FontStyle.italic,
            ),
      ),
    );
  }
}
