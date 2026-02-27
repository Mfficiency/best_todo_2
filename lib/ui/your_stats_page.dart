import 'package:flutter/material.dart';

import '../config.dart';
import '../models/daily_task_stats.dart';
import '../models/task.dart';
import 'subpage_app_bar.dart';

class YourStatsPage extends StatefulWidget {
  final List<Task> deletedItems;
  final Map<String, DailyTaskStats> dailyStatsByDay;

  const YourStatsPage({
    Key? key,
    required this.deletedItems,
    required this.dailyStatsByDay,
  }) : super(key: key);

  @override
  State<YourStatsPage> createState() => _YourStatsPageState();
}

class _YourStatsPageState extends State<YourStatsPage> {
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
  DateTime _currentDate = DateTime.now();
  bool _didAutoScrollDailyBars = false;

  @override
  void initState() {
    super.initState();
    _scheduleScrollToRight();
  }

  @override
  void dispose() {
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
      Theme.of(context).colorScheme.surfaceVariant,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Your Stats',
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
        ],
      ),
    );
  }
}
