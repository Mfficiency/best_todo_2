import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/daily_task_stats.dart';
import '../models/task.dart';
import 'subpage_app_bar.dart';

class YourStatsPage extends StatefulWidget {
  final List<Task> tasks;
  final List<Task> deletedItems;
  final Map<String, DailyTaskStats> dailyStatsByDay;

  const YourStatsPage({
    Key? key,
    required this.tasks,
    required this.deletedItems,
    required this.dailyStatsByDay,
  }) : super(key: key);

  @override
  State<YourStatsPage> createState() => _YourStatsPageState();
}

class _YourStatsPageState extends State<YourStatsPage>
    with SingleTickerProviderStateMixin {
  static const int _weeks = 52;
  static const int _daysPerWeek = 7;
  static const double _cellSize = 11;
  static const double _cellGap = 3;
  static const double _weekGap = 3;
  static const double _monthLabelHeight = 16;
  static const double _leftLabelsWidth = 32;
  static const double _barMaxHeight = 180;
  static const double _barWidth = 16;
  static const double _barGap = 6;

  static const Color _movedColor = Color(0xFFD84343);
  static const Color _openingDoneColor = Color(0xFF1B5E20);
  static const Color _openingOpenColor = Color(0xFF424242);
  static const Color _createdDoneColor = Color(0xFF66BB6A);
  static const Color _createdOpenColor = Color(0xFFBDBDBD);
  static const Color _weekendTint = Color.fromARGB(29, 0, 96, 221);
  static const Color _weekendAccent = Color.fromARGB(255, 0, 95, 221);

  final ScrollController _heatmapScrollController = ScrollController();
  final ScrollController _dailyBarsScrollController = ScrollController();
  late final TabController _activityTabController;
  DateTime _currentDate = DateTime.now();
  bool _didAutoScrollDailyBars = false;

  @override
  void initState() {
    super.initState();
    _activityTabController = TabController(length: 5, vsync: this);
    _scheduleScrollToRight();
  }

  @override
  void dispose() {
    _activityTabController.dispose();
    _heatmapScrollController.dispose();
    _dailyBarsScrollController.dispose();
    super.dispose();
  }

  void _changeDate(int deltaDays) {
    setState(() {
      _currentDate = _currentDate.add(Duration(days: deltaDays));
    });
    _scheduleScrollToRight();
  }

  void _scheduleScrollToRight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_heatmapScrollController.hasClients) {
      } else {
        final max = _heatmapScrollController.position.maxScrollExtent;
        if (max > 0) {
          _heatmapScrollController.jumpTo(max);
        }
      }
      if (_dailyBarsScrollController.hasClients) {
        final max = _dailyBarsScrollController.position.maxScrollExtent;
        if (max > 0) {
          _dailyBarsScrollController.jumpTo(max);
        }
      }
    });
  }

  DateTime _dateOnly(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  Map<DateTime, int> _deletedCountByDay() {
    final counts = <DateTime, int>{};
    for (final task in widget.deletedItems) {
      final deletedAt = task.deletedAt;
      if (deletedAt == null) continue;
      final day = _dateOnly(deletedAt);
      counts[day] = (counts[day] ?? 0) + 1;
    }
    return counts;
  }

  List<Color> _legendColors(BuildContext context) {
    return [
      Theme.of(context).colorScheme.surfaceContainerHighest,
      Colors.blue.shade300,
      Colors.blue.shade500,
      Colors.blue.shade700,
      Colors.blue.shade900,
    ];
  }

  Color _colorForCount(
    int count,
    BuildContext context,
  ) {
    final colors = _legendColors(context);
    if (count <= 0) return colors[0];
    if (count == 1) return colors[1];
    if (count == 2) return colors[2];
    if (count == 3) return colors[3];
    return colors[4];
  }

  String _shortMonthName(int month) {
    const names = [
      '',
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
    return names[month];
  }

  String _formatDate(DateTime date) {
    final d = _dateOnly(date);
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  void _showHeatmapDayDetails(DateTime date, int count) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${_formatDate(date)}: $count completed'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildHeatmapTab() {
    final endDate = _dateOnly(_currentDate);
    final currentWeekStart =
        endDate.subtract(Duration(days: endDate.weekday - 1));
    final startDate = currentWeekStart.subtract(
      const Duration(days: (_weeks - 1) * _daysPerWeek),
    );
    final countsByDay = _deletedCountByDay();
    final weeksStart = List<DateTime>.generate(
      _weeks,
      (index) => startDate.add(Duration(days: index * _daysPerWeek)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Completed items over the last 52 weeks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _leftLabelsWidth,
                child: Padding(
                  padding: const EdgeInsets.only(top: _monthLabelHeight + 4),
                  child: Column(
                    children: List.generate(_daysPerWeek, (dayIndex) {
                      final showLabel =
                          dayIndex == 0 || dayIndex == 2 || dayIndex == 4;
                      return SizedBox(
                        height: _cellSize + _cellGap,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            showLabel
                                ? (dayIndex == 0
                                    ? 'Mon'
                                    : dayIndex == 2
                                        ? 'Wed'
                                        : 'Fri')
                                : '',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _heatmapScrollController,
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(_weeks, (weekIndex) {
                          final weekStart = weeksStart[weekIndex];
                          final previousMonth = weekIndex == 0
                              ? -1
                              : weeksStart[weekIndex - 1].month;
                          final label =
                              weekIndex == 0 || weekStart.month != previousMonth
                                  ? _shortMonthName(weekStart.month)
                                  : '';
                          return Padding(
                            padding: const EdgeInsets.only(right: _weekGap),
                            child: SizedBox(
                              width: _cellSize,
                              height: _monthLabelHeight,
                              child: Text(
                                label,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: List.generate(_weeks, (weekIndex) {
                          return Padding(
                            padding: const EdgeInsets.only(right: _weekGap),
                            child: Column(
                              children: List.generate(_daysPerWeek, (dayIndex) {
                                final date = weeksStart[weekIndex].add(
                                  Duration(days: dayIndex),
                                );
                                final count = countsByDay[date] ?? 0;
                                final color = _colorForCount(count, context);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: _cellGap),
                                  child: Tooltip(
                                    message:
                                        '${date.toIso8601String().split('T').first}: $count deleted',
                                    child: GestureDetector(
                                      onTap: () => _showHeatmapDayDetails(date, count),
                                      child: Container(
                                        width: _cellSize,
                                        height: _cellSize,
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: BorderRadius.circular(2),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text('Legend', style: Theme.of(context).textTheme.bodySmall),
              ...[
                MapEntry('0', _colorForCount(0, context)),
                MapEntry('1', _colorForCount(1, context)),
                MapEntry('2', _colorForCount(2, context)),
                MapEntry('3', _colorForCount(3, context)),
                MapEntry('+4', _colorForCount(4, context)),
              ].map((entry) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: _cellSize,
                      height: _cellSize,
                      decoration: BoxDecoration(
                        color: entry.value,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(entry.key, style: Theme.of(context).textTheme.bodySmall),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  int _intersectionCount(Set<String> first, Set<String> second) {
    return first.where(second.contains).length;
  }

  bool _isWeekend(DateTime date) {
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildDailyBarsTab() {
    if (!_didAutoScrollDailyBars) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_dailyBarsScrollController.hasClients) {
          final max = _dailyBarsScrollController.position.maxScrollExtent;
          if (max > 0) {
            _dailyBarsScrollController.jumpTo(max);
          }
        }
        _didAutoScrollDailyBars = true;
      });
    }

    final endDate = _dateOnly(_currentDate);
    final startDate = endDate.subtract(const Duration(days: 364));
    final dates = List<DateTime>.generate(
      365,
      (index) => startDate.add(Duration(days: index)),
    );

    final bars = <Widget>[];
    final monthLabels = <Widget>[];
    DateTime? previousDate;
    for (final date in dates) {
      final isWeekend = _isWeekend(date);
      final stats = widget.dailyStatsByDay[_dayKeyFromDate(date)] ??
          DailyTaskStats(dayKey: _dayKeyFromDate(date));
      final openingCount = stats.openingTaskIds.length;
      final movedCount =
          _intersectionCount(stats.movedFromOpeningTaskIds, stats.openingTaskIds);
      final completedFromOpeningCount = stats.completedFromOpeningTaskIds
          .where((id) =>
              stats.openingTaskIds.contains(id) &&
              !stats.movedFromOpeningTaskIds.contains(id))
          .length;
      final openingNotCompletedCount = (openingCount -
              movedCount -
              completedFromOpeningCount)
          .clamp(0, 1 << 31)
          .toInt();
      final createdCount = stats.createdDuringDayTaskIds.length;
      final completedFromCreatedCount = _intersectionCount(
        stats.completedFromCreatedTaskIds,
        stats.createdDuringDayTaskIds,
      );
      final createdNotCompletedCount =
          (createdCount - completedFromCreatedCount).clamp(0, 1 << 31).toInt();

      final total = movedCount +
          completedFromOpeningCount +
          openingNotCompletedCount +
          completedFromCreatedCount +
          createdNotCompletedCount;
      final unitHeight = total <= 0 ? 10.0 : (_barMaxHeight / total).clamp(3.0, 16.0);
      final monthChanged = previousDate == null ||
          previousDate.month != date.month ||
          previousDate.year != date.year;
      final monthLabel = monthChanged
          ? (previousDate == null || previousDate.year != date.year
              ? '${_shortMonthName(date.month)} ${date.year}'
              : _shortMonthName(date.month))
          : '';
      monthLabels.add(
        SizedBox(
          width: _barWidth + (_barGap * 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              monthLabel,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.visible,
            ),
          ),
        ),
      );

      final stackBlocks = <Widget>[
        for (var i = 0; i < createdNotCompletedCount; i++)
          _stackBlock(_createdOpenColor, unitHeight),
        for (var i = 0; i < completedFromCreatedCount; i++)
          _stackBlock(_createdDoneColor, unitHeight),
        for (var i = 0; i < openingNotCompletedCount; i++)
          _stackBlock(_openingOpenColor, unitHeight),
        for (var i = 0; i < completedFromOpeningCount; i++)
          _stackBlock(_openingDoneColor, unitHeight),
        for (var i = 0; i < movedCount; i++) _stackBlock(_movedColor, unitHeight),
      ];

      bars.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _barGap),
          child: Tooltip(
            message:
                '${date.toIso8601String().split('T').first}\nOpening: $openingCount\nCreated: $createdCount\nCompleted: ${completedFromOpeningCount + completedFromCreatedCount}',
            child: SizedBox(
              width: _barWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: _barMaxHeight + 12,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        if (isWeekend)
                          Positioned.fill(
                            child: Container(
                              margin: const EdgeInsets.only(top: 10),
                              decoration: BoxDecoration(
                                color: _weekendTint,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: stackBlocks,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${date.day}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight:
                              isWeekend ? FontWeight.w700 : FontWeight.w400,
                          color: isWeekend ? _weekendAccent : null,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      previousDate = date;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'Daily task composition',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SingleChildScrollView(
          controller: _dailyBarsScrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: bars,
              ),
              const SizedBox(height: 6),
              Row(children: monthLabels),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _legendItem('Moved (start day)', _movedColor),
              _legendItem('Completed (start day)', _openingDoneColor),
              _legendItem('Not completed (start day)', _openingOpenColor),
              _legendItem('Completed (created/day)', _createdDoneColor),
              _legendItem('Not completed (created/day)', _createdOpenColor),
            ],
          ),
        ),
      ],
    );
  }

  String _dayKeyFromDate(DateTime date) {
    final d = _dateOnly(date);
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  Widget _stackBlock(Color color, double height) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      width: 26,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  List<Task> _allTasksForActivity() {
    final byId = <String, Task>{};
    for (final task in widget.tasks) {
      byId[task.uid] = task;
    }
    for (final task in widget.deletedItems) {
      byId[task.uid] = task;
    }
    return byId.values.toList();
  }

  DateTime _startOfWindow() => _dateOnly(_currentDate).subtract(const Duration(days: 30));

  bool _isInWindow(DateTime localDateTime) {
    final day = _dateOnly(localDateTime);
    final start = _startOfWindow();
    final end = _dateOnly(_currentDate);
    return !day.isBefore(start) && !day.isAfter(end);
  }

  List<DateTime> _eventsForType(Task task, String type) {
    if (type == 'Created') return task.createdAt == null ? <DateTime>[] : [task.createdAt!];
    if (type == 'Completed') return task.completedAt == null ? <DateTime>[] : [task.completedAt!];
    if (type == 'Moved') {
      final events = <DateTime>[];
      if (task.movedAt != null) events.add(task.movedAt!);
      if (task.rescheduledAt != null && task.rescheduledAt != task.movedAt) {
        events.add(task.rescheduledAt!);
      }
      return events;
    }
    if (type == 'Deleted') return task.deletedAt == null ? <DateTime>[] : [task.deletedAt!];
    return <DateTime>[
      ..._eventsForType(task, 'Created'),
      ..._eventsForType(task, 'Completed'),
      ..._eventsForType(task, 'Moved'),
      ..._eventsForType(task, 'Deleted'),
    ];
  }

  List<List<int>> _hourWeekdayCounts(String type) {
    final grid = List<List<int>>.generate(24, (_) => List<int>.filled(7, 0));
    for (final task in _allTasksForActivity()) {
      for (final event in _eventsForType(task, type)) {
        final local = event.toLocal();
        if (!_isInWindow(local)) continue;
        final dayCol = local.weekday - 1;
        final hour = local.hour;
        grid[hour][dayCol] += 1;
      }
    }
    return grid;
  }

  Color _activityCellColor(int count, _ActivityScale scale, BuildContext context) {
    final base = Theme.of(context).colorScheme.primary;
    if (count <= 0 || scale.cap <= 0) {
      return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
    final t = scale.intensity(count);
    return Color.lerp(
      base.withValues(alpha: 0.18),
      base.withValues(alpha: 0.92),
      t,
    )!;
  }

  Widget _buildActivityLegend(_ActivityScale scale) {
    final caption = scale.cap <= 0
        ? 'No activity yet.'
        : scale.maxCount > scale.cap
            ? 'Log scale, saturating at ${scale.cap}/h (busiest slot: ${scale.maxCount}).'
            : 'Log scale.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text('Legend', style: Theme.of(context).textTheme.bodySmall),
              ...scale.legendStops().map((stop) {
                final isTop = stop == scale.cap && scale.maxCount > scale.cap;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _activityCellColor(stop, scale, context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isTop ? '$stop+' : '$stop',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                );
              }),
            ],
          ),
          const SizedBox(height: 4),
          Text(caption, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  String _weekdayName(int dayIndex) {
    const names = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return names[dayIndex];
  }

  String _hourRangeLabel(int hour) {
    final next = (hour + 1) % 24;
    return '${hour.toString().padLeft(2, '0')}:00-${next.toString().padLeft(2, '0')}:00';
  }

  String _peakSummary(String type, List<List<int>> counts) {
    var bestCount = 0;
    var bestHour = 0;
    var bestDay = 0;
    for (var h = 0; h < 24; h++) {
      for (var d = 0; d < 7; d++) {
        if (counts[h][d] > bestCount) {
          bestCount = counts[h][d];
          bestHour = h;
          bestDay = d;
        }
      }
    }
    if (bestCount == 0) {
      return 'No $type activity in the last 31 days.';
    }
    return 'Most items are ${type.toLowerCase()} on ${_weekdayName(bestDay)} between ${_hourRangeLabel(bestHour)}.';
  }

  Widget _buildItemActivityHeatmapSection() {
    final tabs = <String>['Created', 'Completed', 'Moved', 'Deleted', 'Combined'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Item Activity Heatmap (Last 31 days)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _activityTabController,
            isScrollable: true,
            tabs: tabs.map((t) => Tab(text: t)).toList(),
          ),
          SizedBox(
            height: 520,
            child: TabBarView(
              controller: _activityTabController,
              children: tabs.map((type) {
                final counts = _hourWeekdayCounts(type);
                final scale = _ActivityScale.fromCounts(counts);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 52,
                            child: Column(
                              children: [
                                const SizedBox(height: 22),
                                for (var hour = 0; hour < 24; hour++)
                                  SizedBox(
                                    height: 16,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        hour.toString().padLeft(2, '0'),
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              Row(
                                children: [
                                  for (var day = 0; day < 7; day++)
                                    SizedBox(
                                      width: 26,
                                      child: Center(
                                        child: Text(
                                          _weekdayName(day).substring(0, 3),
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              for (var hour = 0; hour < 24; hour++)
                                Row(
                                  children: [
                                    for (var day = 0; day < 7; day++)
                                      Padding(
                                        padding: const EdgeInsets.all(1),
                                        child: Tooltip(
                                          message:
                                              '${_weekdayName(day)}\n${_hourRangeLabel(hour)}\n$type\nCount: ${counts[hour][day]}',
                                          child: Container(
                                            width: 24,
                                            height: 14,
                                            decoration: BoxDecoration(
                                              color: _activityCellColor(
                                                counts[hour][day],
                                                scale,
                                                context,
                                              ),
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildActivityLegend(scale),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        _peakSummary(type, counts),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// One line of the fun-stats list: icon, what it is, the number. When
  /// [details] is non-empty the tile is tappable and opens a sheet listing
  /// which items (and when) made that number up.
  Widget _funStatTile(
    IconData icon,
    String title,
    String value, {
    String? subtitle,
    List<_StatDetailEntry> details = const <_StatDetailEntry>[],
  }) {
    final tappable = details.isNotEmpty;
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: tappable ? () => _showStatDetails(title, details) : null,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (tappable) ...[
              const SizedBox(width: 2),
              Icon(Icons.chevron_right,
                  size: 18, color: Theme.of(context).colorScheme.outline),
            ],
          ],
        ),
      ),
    );
  }

  /// "Mon, 2026-08-10 · 14:32" — used inside the fun-stats detail sheets so
  /// tapping a number shows the day of week/month it happened on.
  String _weekdayDateTime(DateTime date) {
    final local = date.toLocal();
    final weekday = _weekdayName(local.weekday - 1).substring(0, 3);
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return '$weekday, ${_formatDate(local)} · $time';
  }

  /// Bottom sheet listing the items (or days) behind a fun-stat number.
  void _showStatDetails(String title, List<_StatDetailEntry> entries) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (sheetContext, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(title,
                      style: Theme.of(sheetContext).textTheme.titleLarge),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: entries.length,
                    itemBuilder: (itemContext, index) {
                      final entry = entries[index];
                      return ListTile(
                        dense: true,
                        title: Text(entry.label),
                        trailing: Text(
                          entry.detail,
                          style: Theme.of(itemContext).textTheme.bodySmall,
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Tasks with a `completedAt`, newest first, labelled with when they
  /// finished — the "which item made this number" list for done-based stats.
  List<_StatDetailEntry> _completedEntries(Iterable<Task> tasks) {
    final sorted = tasks.toList()
      ..sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
    return sorted
        .map((t) => _StatDetailEntry(t.title, _weekdayDateTime(t.completedAt!)))
        .toList();
  }

  /// Same idea but keyed off `createdAt`, for planning-side stats.
  List<_StatDetailEntry> _createdEntries(Iterable<Task> tasks) {
    final sorted = tasks.toList()
      ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    return sorted
        .map((t) => _StatDetailEntry(t.title, _weekdayDateTime(t.createdAt!)))
        .toList();
  }

  /// Day-bucketed counts (busiest day, postponed-by-day) as detail rows,
  /// busiest first.
  List<_StatDetailEntry> _dayCountEntries(
      Map<DateTime, int> byDay, String suffix) {
    final entries = byDay.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : b.key.compareTo(a.key);
      });
    return entries
        .map((e) => _StatDetailEntry(
              '${_weekdayName(_dateOnly(e.key).weekday - 1)}, '
                  '${_formatDate(e.key)}',
              '${e.value} $suffix',
            ))
        .toList();
  }

  /// "3 min", "5 h", "2 days" — rough is the point, these are for fun.
  String _roughDuration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} s';
    if (d.inHours < 1) return '${d.inMinutes} min';
    if (d.inDays < 1) return '${d.inHours} h';
    if (d.inDays < 14) return '${d.inDays} days';
    return '${(d.inDays / 7).round()} weeks';
  }

  /// Index of the biggest entry in [counts], or null when they are all zero.
  int? _peakIndex(List<int> counts) {
    var best = 0;
    int? index;
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] > best) {
        best = counts[i];
        index = i;
      }
    }
    return index;
  }

  /// All-time trivia about your items: the numbers that are fun rather than
  /// actionable, which is why they sit at the very bottom of the page.
  Widget _buildFunStatsSection() {
    final tasks = _allTasksForActivity();
    final completed = tasks.where((t) => t.completedAt != null).toList();
    final createdCount = tasks.where((t) => t.createdAt != null).length;

    final completionsByDay = <DateTime, int>{};
    final byHour = List<int>.filled(24, 0);
    final byWeekday = List<int>.filled(7, 0);
    var earlyBird = 0;
    var nightOwl = 0;
    var weekendDone = 0;
    for (final task in completed) {
      final at = task.completedAt!.toLocal();
      final day = _dateOnly(at);
      completionsByDay[day] = (completionsByDay[day] ?? 0) + 1;
      byHour[at.hour] += 1;
      byWeekday[at.weekday - 1] += 1;
      if (at.hour < 8) earlyBird += 1;
      if (at.hour >= 22 || at.hour < 5) nightOwl += 1;
      if (_isWeekend(at)) weekendDone += 1;
    }

    // Turnaround: how long an item waited between being written down and
    // being ticked off. Only items that carry both timestamps can play.
    MapEntry<Duration, Task>? fastest;
    MapEntry<Duration, Task>? slowest;
    for (final task in completed) {
      final createdAt = task.createdAt;
      if (createdAt == null) continue;
      final waited = task.completedAt!.difference(createdAt);
      if (waited.isNegative) continue;
      if (fastest == null || waited < fastest.key) {
        fastest = MapEntry(waited, task);
      }
      if (slowest == null || waited > slowest.key) {
        slowest = MapEntry(waited, task);
      }
    }

    // The item that has been waiting the longest and is still not done.
    Task? oldestOpen;
    for (final task in widget.tasks) {
      if (task.isDone || task.deletedAt != null || task.createdAt == null) {
        continue;
      }
      if (oldestOpen == null ||
          task.createdAt!.isBefore(oldestOpen.createdAt!)) {
        oldestOpen = task;
      }
    }

    // When things get written down — the planning half of the day.
    final createdByHour = List<int>.filled(24, 0);
    for (final task in tasks) {
      final at = task.createdAt?.toLocal();
      if (at != null) createdByHour[at.hour] += 1;
    }

    // Every time an item due that day was pushed to another one, and the
    // weekday that happens on most.
    var postponed = 0;
    final postponedByWeekday = List<int>.filled(7, 0);
    final postponedByDay = <DateTime, int>{};
    for (final entry in widget.dailyStatsByDay.entries) {
      final stats = entry.value;
      final moved = _intersectionCount(
          stats.movedFromOpeningTaskIds, stats.openingTaskIds);
      if (moved == 0) continue;
      postponed += moved;
      final day = DateTime.tryParse(entry.key);
      if (day != null) {
        postponedByWeekday[day.weekday - 1] += moved;
        postponedByDay[day] = (postponedByDay[day] ?? 0) + moved;
      }
    }

    final openNow = widget.tasks.where((t) => !t.isDone).length;
    final activeDays = completionsByDay.length;
    final busiest = completionsByDay.entries.isEmpty
        ? null
        : completionsByDay.entries
            .reduce((a, b) => b.value > a.value ? b : a);
    final peakHour = _peakIndex(byHour);
    final peakWeekday = _peakIndex(byWeekday);
    final peakPlanningHour = _peakIndex(createdByHour);
    final peakPostponeDay = _peakIndex(postponedByWeekday);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Text(
              'Fun stats',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (completed.isEmpty && createdCount == 0)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Text('Complete a few items and the trivia shows up here.'),
            )
          else ...[
            _funStatTile(
              Icons.check_circle_outline,
              'Items completed',
              '${completed.length}',
              details: _completedEntries(completed),
            ),
            _funStatTile(
                Icons.edit_note, 'Items ever created', '$createdCount'),
            if (createdCount > 0)
              _funStatTile(
                Icons.percent,
                'Completion rate',
                '${(completed.length * 100 / createdCount).round()}%',
                subtitle: 'Of everything you wrote down',
              ),
            if (busiest != null)
              _funStatTile(
                Icons.local_fire_department,
                'Busiest day',
                '${busiest.value}',
                subtitle: _formatDate(busiest.key),
                details: _completedEntries(completed.where(
                    (t) => _dateOnly(t.completedAt!) == busiest.key)),
              ),
            if (activeDays > 0)
              _funStatTile(
                Icons.calendar_month,
                'Days with something done',
                '$activeDays',
                subtitle: 'Averaging '
                    '${(completed.length / activeDays).toStringAsFixed(1)} '
                    'per day',
                details: _dayCountEntries(completionsByDay, 'completed'),
              ),
            if (peakHour != null)
              _funStatTile(
                Icons.schedule,
                'Golden hour',
                '${byHour[peakHour]}',
                subtitle: 'Most items finish ${_hourRangeLabel(peakHour)}',
                details: _completedEntries(completed
                    .where((t) => t.completedAt!.toLocal().hour == peakHour)),
              ),
            if (peakWeekday != null)
              _funStatTile(
                Icons.event_available,
                'Favourite weekday',
                '${byWeekday[peakWeekday]}',
                subtitle: '${_weekdayName(peakWeekday)} is your best day',
                details: _completedEntries(completed.where((t) =>
                    t.completedAt!.toLocal().weekday - 1 == peakWeekday)),
              ),
            if (peakPlanningHour != null)
              _funStatTile(
                Icons.edit_calendar,
                'Planning hour',
                '${createdByHour[peakPlanningHour]}',
                subtitle: 'Most items get written down '
                    '${_hourRangeLabel(peakPlanningHour)}',
                details: _createdEntries(tasks.where((t) =>
                    t.createdAt != null &&
                    t.createdAt!.toLocal().hour == peakPlanningHour)),
              ),
            if (earlyBird > 0)
              _funStatTile(
                Icons.wb_twilight,
                'Early bird finishes',
                '$earlyBird',
                subtitle: 'Done before 08:00',
                details: _completedEntries(
                    completed.where((t) => t.completedAt!.toLocal().hour < 8)),
              ),
            if (nightOwl > 0)
              _funStatTile(
                Icons.nights_stay,
                'Night owl finishes',
                '$nightOwl',
                subtitle: 'Done after 22:00 or before 05:00',
                details: _completedEntries(completed.where((t) {
                  final hour = t.completedAt!.toLocal().hour;
                  return hour >= 22 || hour < 5;
                })),
              ),
            if (completed.isNotEmpty)
              _funStatTile(
                Icons.weekend,
                'Weekend share',
                '${(weekendDone * 100 / completed.length).round()}%',
                subtitle: '$weekendDone finished on a Saturday or Sunday',
                details: _completedEntries(
                    completed.where((t) => _isWeekend(t.completedAt!.toLocal()))),
              ),
            if (fastest != null)
              _funStatTile(
                Icons.bolt,
                'Fastest finish',
                _roughDuration(fastest.key),
                subtitle: fastest.value.title,
                details: [
                  _StatDetailEntry('Created', _weekdayDateTime(fastest.value.createdAt!)),
                  _StatDetailEntry(
                      'Completed', _weekdayDateTime(fastest.value.completedAt!)),
                ],
              ),
            if (slowest != null)
              _funStatTile(
                Icons.hourglass_bottom,
                'Longest wait',
                _roughDuration(slowest.key),
                subtitle: slowest.value.title,
                details: [
                  _StatDetailEntry('Created', _weekdayDateTime(slowest.value.createdAt!)),
                  _StatDetailEntry(
                      'Completed', _weekdayDateTime(slowest.value.completedAt!)),
                ],
              ),
            if (oldestOpen != null)
              _funStatTile(
                Icons.elderly,
                'Oldest open item',
                _roughDuration(
                    DateTime.now().difference(oldestOpen.createdAt!)),
                subtitle: oldestOpen.title,
                details: [
                  _StatDetailEntry(
                      'Created', _weekdayDateTime(oldestOpen.createdAt!)),
                ],
              ),
            if (postponed > 0)
              _funStatTile(
                Icons.next_plan,
                'Times postponed',
                '$postponed',
                subtitle: 'Items moved off the day they were due',
                details: _dayCountEntries(postponedByDay, 'postponed'),
              ),
            if (peakPostponeDay != null)
              _funStatTile(
                Icons.snooze,
                'Most postponed on',
                '${postponedByWeekday[peakPostponeDay]}',
                subtitle: '${_weekdayName(peakPostponeDay)} is when things '
                    'get pushed',
                details: _dayCountEntries(
                    Map.fromEntries(postponedByDay.entries.where(
                        (e) => e.key.weekday - 1 == peakPostponeDay)),
                    'postponed'),
              ),
            _funStatTile(Icons.inbox, 'Open right now', '$openNow'),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Productivity Stats',
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(Config.isDev ? 52 : 0),
          child: Column(
            children: [
              if (Config.isDev)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeDate(-1),
                    ),
                    Text(
                      _currentDate.toLocal().toString().split(' ')[0],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeDate(1),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      body: ListView(
        children: [
          _buildHeatmapTab(),
          const Divider(height: 1),
          _buildDailyBarsTab(),
          const Divider(height: 1),
          _buildItemActivityHeatmapSection(),
          const Divider(height: 1),
          _buildFunStatsSection(),
        ],
      ),
    );
  }
}

/// Colour scale for the hour x weekday activity heatmap.
///
/// Normalising against the raw maximum makes a single outlier slot (a bulk
/// import, one marathon session) push every other slot into the same faint
/// shade. Instead the scale saturates at the Tukey upper fence of the
/// non-empty cells and compresses counts logarithmically, so the ordinary
/// range keeps most of the colour ramp and outliers simply top out.
class _ActivityScale {
  /// Count that renders at full intensity; anything above saturates.
  final int cap;

  /// Raw busiest-cell count, used for the legend caption.
  final int maxCount;

  const _ActivityScale({required this.cap, required this.maxCount});

  factory _ActivityScale.fromCounts(List<List<int>> counts) {
    final values = <int>[];
    var maxCount = 0;
    for (final row in counts) {
      for (final value in row) {
        if (value > maxCount) maxCount = value;
        if (value > 0) values.add(value);
      }
    }
    if (values.isEmpty) {
      return const _ActivityScale(cap: 0, maxCount: 0);
    }
    values.sort();
    final q1 = _quantile(values, 0.25);
    final q3 = _quantile(values, 0.75);
    final fence = (q3 + 1.5 * (q3 - q1)).round();
    // One step above q3 keeps a busy-but-not-outlier slot distinguishable even
    // when the fence collapses (e.g. every ordinary cell holds the same count).
    final cap = math.min(maxCount, math.max(q3 + 1, math.max(1, fence)));
    return _ActivityScale(cap: math.max(1, cap), maxCount: maxCount);
  }

  /// Nearest-rank quantile of an ascending [sorted] list.
  static int _quantile(List<int> sorted, double fraction) {
    final index = ((sorted.length - 1) * fraction).round();
    return sorted[index];
  }

  /// 0..1 position on the colour ramp for [count].
  double intensity(int count) {
    if (count <= 0 || cap <= 0) return 0;
    if (cap == 1) return 1;
    final t = math.log(1 + count) / math.log(1 + cap);
    return t.clamp(0.0, 1.0);
  }

  /// Representative counts for the legend, spaced geometrically so the swatches
  /// are evenly spread along the ramp rather than bunched at the low end.
  List<int> legendStops() {
    if (cap <= 0) return const <int>[0];
    final stops = <int>{0, 1};
    for (var step = 1; step <= 3; step++) {
      stops.add(math.max(1, math.pow(cap, step / 3).round()));
    }
    stops.add(cap);
    return stops.toList()..sort();
  }
}

/// One row of a fun-stat detail sheet: what it was ([label], usually the
/// item's title or a day) and when/how much ([detail]).
class _StatDetailEntry {
  final String label;
  final String detail;

  const _StatDetailEntry(this.label, this.detail);
}
