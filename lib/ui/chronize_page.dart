import 'package:flutter/material.dart';

import '../models/task.dart';
import 'subpage_app_bar.dart';
import 'task_detail_page.dart';

/// Experimental "Chronize" tool.
///
/// Shows every task on a vertical 24-hour calendar for a single focused day.
/// Three vertical rollers on the right navigate the focus point at different
/// granularities:
///   * hour roller  -> spans 3 days  (72 hours) top to bottom
///   * day roller   -> spans 15 days top to bottom
///   * month roller -> spans 12 months top to bottom
///
/// The focused day/time is the sum of all three offsets measured from the
/// start of today, so the rollers combine to reach a wide range of dates.
class ChronizePage extends StatefulWidget {
  final List<Task> tasks;

  const ChronizePage({Key? key, required this.tasks}) : super(key: key);

  @override
  State<ChronizePage> createState() => _ChronizePageState();
}

class _ChronizePageState extends State<ChronizePage> {
  static const double _hourRowHeight = 64;

  static const List<String> _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const List<String> _months = [
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

  // Roller spans.
  static const int _hourSpan = 72; // 3 days
  static const int _daySpan = 15; // 15 days
  static const int _monthSpan = 12; // 12 months

  late final DateTime _base; // start of today
  final ScrollController _scrollController = ScrollController();

  double _hourOffset = 0;
  double _dayOffset = 0;
  double _monthOffset = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _base = DateTime(now.year, now.month, now.day);
    // Seed the hour roller so we open near the current hour for context.
    _hourOffset = now.hour.toDouble();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocusHour());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// The focused moment, derived from all three rollers.
  DateTime get _focus {
    final monthShifted = DateTime(
      _base.year,
      _base.month + _monthOffset.round(),
      _base.day,
    );
    return monthShifted.add(
      Duration(days: _dayOffset.round(), hours: _hourOffset.round()),
    );
  }

  DateTime get _focusDay =>
      DateTime(_focus.year, _focus.month, _focus.day);

  void _scrollToFocusHour() {
    if (!_scrollController.hasClients) return;
    final target = (_focus.hour * _hourRowHeight)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  List<Task> _tasksForHour(int hour) {
    final day = _focusDay;
    final list = widget.tasks.where((task) {
      final due = task.dueDate;
      if (due == null) return false;
      return due.year == day.year &&
          due.month == day.month &&
          due.day == day.day &&
          due.hour == hour;
    }).toList();
    list.sort((a, b) {
      final ra = a.listRanking ?? 1 << 31;
      final rb = b.listRanking ?? 1 << 31;
      return ra.compareTo(rb);
    });
    return list;
  }

  int get _taskCountForFocusDay {
    final day = _focusDay;
    return widget.tasks.where((task) {
      final due = task.dueDate;
      if (due == null) return false;
      return due.year == day.year &&
          due.month == day.month &&
          due.day == day.day;
    }).length;
  }

  String _formatFocusDate() {
    final f = _focus;
    final weekday = _weekdays[(f.weekday - 1) % 7];
    final month = _months[f.month - 1];
    return '$weekday ${f.day} $month ${f.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayCount = _taskCountForFocusDay;
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Chronize'),
      body: Column(
        children: [
          _buildHeader(theme, dayCount),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildCalendar(theme)),
                const VerticalDivider(width: 1),
                _buildRollers(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, int dayCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatFocusDate(),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 2),
          Text(
            dayCount == 0
                ? 'No tasks on this day'
                : '$dayCount task${dayCount == 1 ? '' : 's'} on this day',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(ThemeData theme) {
    final focusHour = _focus.hour;
    return ListView.builder(
      controller: _scrollController,
      itemCount: 24,
      itemBuilder: (context, hour) {
        final tasks = _tasksForHour(hour);
        final isFocusHour = hour == focusHour;
        return Container(
          height: _hourRowHeight,
          decoration: BoxDecoration(
            color: isFocusHour
                ? theme.colorScheme.primary.withOpacity(0.08)
                : null,
            border: Border(
              top: BorderSide(
                color: theme.dividerColor.withOpacity(0.5),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 56,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, right: 8),
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight:
                          isFocusHour ? FontWeight.bold : FontWeight.normal,
                      color: theme.colorScheme.onSurface
                          .withOpacity(isFocusHour ? 1 : 0.6),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final task in tasks) _buildTaskChip(theme, task),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTaskChip(ThemeData theme, Task task) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, right: 8),
      child: Material(
        color: task.isDone
            ? theme.colorScheme.surfaceVariant
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => TaskDetailPage(task: task),
              ),
            );
          },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration:
                    task.isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRollers(ThemeData theme) {
    final f = _focus;
    return SizedBox(
      width: 132,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _buildRoller(
              theme,
              label: 'Hour',
              valueLabel: '${f.hour.toString().padLeft(2, '0')}:00',
              value: _hourOffset,
              max: (_hourSpan - 1).toDouble(),
              divisions: _hourSpan - 1,
              onChanged: (v) => setState(() {
                _hourOffset = v;
              }),
              onChangeEnd: (_) => _scrollToFocusHour(),
            ),
            _buildRoller(
              theme,
              label: 'Day',
              valueLabel: '+${_dayOffset.round()}d',
              value: _dayOffset,
              max: (_daySpan - 1).toDouble(),
              divisions: _daySpan - 1,
              onChanged: (v) => setState(() {
                _dayOffset = v;
              }),
              onChangeEnd: (_) => _scrollToFocusHour(),
            ),
            _buildRoller(
              theme,
              label: 'Month',
              valueLabel: _months[f.month - 1],
              value: _monthOffset,
              max: (_monthSpan - 1).toDouble(),
              divisions: _monthSpan - 1,
              onChanged: (v) => setState(() {
                _monthOffset = v;
              }),
              onChangeEnd: (_) => _scrollToFocusHour(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoller(
    ThemeData theme, {
    required String label,
    required String valueLabel,
    required double value,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 4),
          Expanded(
            // Rotate so the slider runs vertically: bottom = later in time,
            // matching a top-to-bottom scroll moving forward.
            child: RotatedBox(
              quarterTurns: 1,
              child: Slider(
                value: value,
                min: 0,
                max: max,
                divisions: divisions > 0 ? divisions : null,
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            valueLabel,
            style: theme.textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
