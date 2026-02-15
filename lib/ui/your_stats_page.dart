import 'package:flutter/material.dart';

import '../config.dart';
import '../models/task.dart';

class YourStatsPage extends StatefulWidget {
  final List<Task> deletedItems;

  const YourStatsPage({Key? key, required this.deletedItems}) : super(key: key);

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

  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  DateTime _currentDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _scheduleScrollToRight();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
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
      if (!_scrollController.hasClients) {
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) {
        _scrollController.jumpTo(max);
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
      if (deletedAt == null) {
        continue;
      }
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
    if (count <= 0) {
      return colors[0];
    }
    if (count == 1) {
      return colors[1];
    }
    if (count == 2) {
      return colors[2];
    }
    if (count == 3) {
      return colors[3];
    }
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
            'Deleted items over the last 52 weeks',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: Padding(
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
                        final showLabel = dayIndex == 0 || dayIndex == 2 || dayIndex == 4;
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
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: List.generate(_weeks, (weekIndex) {
                            final weekStart = weeksStart[weekIndex];
                            final previousMonth =
                                weekIndex == 0 ? -1 : weeksStart[weekIndex - 1].month;
                            final label = weekIndex == 0 || weekStart.month != previousMonth
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
                                      child: Container(
                                        width: _cellSize,
                                        height: _cellSize,
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: BorderRadius.circular(2),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Stats'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(Config.isDev ? 72 : 48),
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
              TabBar(
                controller: _tabController,
                tabs: const [Tab(text: 'Deleted Heatmap')],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildHeatmapTab()],
      ),
    );
  }
}
