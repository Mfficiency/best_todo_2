import 'package:flutter/cupertino.dart';
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

/// Which wheel originated a focus change, so we don't fight the wheel the user
/// is actively dragging when repositioning the others.
enum _Wheel { hour, day, month }

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

  late final DateTime _base; // start of today; item 0 on every wheel/timeline

  // The infinite vertical hour timeline on the left. A scroll offset of
  // `item * _hourRowHeight` puts hour `item` (relative to _base) at the top, so
  // it scrolls smoothly and endlessly across days and months.
  late final ScrollController _timeline;
  final Key _timelineCenter = const ValueKey('timeline-center');

  // Infinite scroll-wheel controllers. Item 0 on each wheel maps to [_base]:
  //   hour wheel  -> _base plus `item` hours  (24 items == one calendar day)
  //   day wheel   -> _base plus `item` days
  //   month wheel -> _base plus `item` months
  late final FixedExtentScrollController _hourWheel;
  late final FixedExtentScrollController _dayWheel;
  late final FixedExtentScrollController _monthWheel;

  // The focused moment (hour granularity): the single source of truth the
  // wheels and the timeline all read from. The focus hour sits at the top of
  // the timeline viewport.
  late DateTime _focus;

  // Per-wheel suppression: >0 while that wheel is being repositioned
  // programmatically, so its onSelectedItemChanged is ignored instead of
  // treated as user input (the wheel the user is dragging is never suppressed).
  final Map<_Wheel, int> _suppress = {
    _Wheel.hour: 0,
    _Wheel.day: 0,
    _Wheel.month: 0,
  };

  // True while the timeline is being scrolled programmatically, so its scroll
  // listener doesn't treat that motion as the user picking a new hour.
  bool _programmaticScroll = false;
  int _lastTopItem = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _base = DateTime(now.year, now.month, now.day);
    _focus = DateTime(now.year, now.month, now.day, now.hour);
    _lastTopItem = _hourItemFor(_focus);
    _timeline = ScrollController(
      initialScrollOffset: _lastTopItem * _hourRowHeight,
    )..addListener(_onTimelineScroll);
    _hourWheel = FixedExtentScrollController(initialItem: _hourItemFor(_focus));
    _dayWheel = FixedExtentScrollController(initialItem: _dayItemFor(_focus));
    _monthWheel =
        FixedExtentScrollController(initialItem: _monthItemFor(_focus));
  }

  @override
  void dispose() {
    _timeline.dispose();
    _hourWheel.dispose();
    _dayWheel.dispose();
    _monthWheel.dispose();
    super.dispose();
  }

  // ---- Item <-> moment mapping (item 0 == _base on every wheel) ----

  // Floor division for negative items (Dart's a % b is >= 0 for b > 0).
  int _floorDiv(int a, int b) => (a - (a % b)) ~/ b;

  int _dayItemFor(DateTime f) {
    final diff = DateTime(f.year, f.month, f.day).difference(_base);
    return (diff.inHours / 24).round(); // round so DST days don't drift
  }

  int _hourItemFor(DateTime f) => _dayItemFor(f) * 24 + f.hour;

  int _monthItemFor(DateTime f) =>
      (f.year - _base.year) * 12 + (f.month - _base.month);

  DateTime _dateForDayItem(int item) =>
      DateTime(_base.year, _base.month, _base.day + item);

  /// Moment for an hour-wheel item; crossing a 24-item boundary rolls into the
  /// adjacent day.
  DateTime _focusForHourItem(int item) {
    final date = _dateForDayItem(_floorDiv(item, 24));
    return DateTime(date.year, date.month, date.day, item % 24);
  }

  /// Moment for a day-wheel item, keeping the current hour-of-day.
  DateTime _focusForDayItem(int item) {
    final date = _dateForDayItem(item);
    return DateTime(date.year, date.month, date.day, _focus.hour);
  }

  /// Moment for a month-wheel item, keeping the hour and clamping the day so it
  /// stays valid (e.g. Jan 31 -> Feb 28).
  DateTime _focusForMonthItem(int item) {
    final first = DateTime(_base.year, _base.month + item, 1);
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final day = _focus.day < daysInMonth ? _focus.day : daysInMonth;
    return DateTime(first.year, first.month, day, _focus.hour);
  }

  /// Applies a focused moment chosen from [sourceWheel] (or the timeline, when
  /// [fromTimeline] is true): updates state and repositions every other surface
  /// so they all track the carry (hour past midnight -> day moves; day past
  /// month end -> month moves).
  void _setFocus(DateTime next, _Wheel sourceWheel) {
    if (_suppress[sourceWheel]! > 0) return; // programmatic move, not user input
    setState(() => _focus = next);
    _syncWheel(_Wheel.hour, _hourWheel, _hourItemFor(next), sourceWheel, false);
    _syncWheel(_Wheel.day, _dayWheel, _dayItemFor(next), sourceWheel, false);
    _syncWheel(
        _Wheel.month, _monthWheel, _monthItemFor(next), sourceWheel, false);
    _scrollTimelineToFocus();
  }

  /// Moves wheel [c] to [target] without it counting as user input. Small
  /// carries animate (so the neighbouring wheel is visibly nudged); large jumps
  /// (e.g. a whole-month change shifting the day wheel by ~30), or any move
  /// while [instant] is set, snap immediately.
  void _syncWheel(
    _Wheel wheel,
    FixedExtentScrollController c,
    int target,
    _Wheel? source,
    bool instant,
  ) {
    if (wheel == source || !c.hasClients || c.selectedItem == target) return;
    final animate = !instant && (target - c.selectedItem).abs() <= 3;
    _suppress[wheel] = _suppress[wheel]! + 1;
    void done() {
      final n = _suppress[wheel]!;
      if (n > 0) _suppress[wheel] = n - 1;
    }

    if (animate) {
      c
          .animateToItem(
            target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          )
          .whenComplete(done);
    } else {
      c.jumpToItem(target);
      WidgetsBinding.instance.addPostFrameCallback((_) => done());
    }
  }

  DateTime get _focusDay =>
      DateTime(_focus.year, _focus.month, _focus.day);

  // Distance the timeline visibly glides into place. Targets farther than this
  // are first jumped to within one glide of the destination so a far move (a
  // whole month) still reads as one smooth scroll instead of a hard snap.
  static const double _glideDistance = 8 * _hourRowHeight;

  /// Smoothly scrolls the timeline so the focus hour is at the top. For far
  /// targets it fakes the motion: jump to just shy of the target in the travel
  /// direction, then glide the rest, so it always looks like a smooth scroll.
  void _scrollTimelineToFocus() {
    if (!_timeline.hasClients) return;
    final target = _hourItemFor(_focus) * _hourRowHeight;
    final distance = (target - _timeline.offset).abs();
    if (distance < 0.5) return;
    _lastTopItem = _hourItemFor(_focus);
    _programmaticScroll = true;
    if (distance > _glideDistance) {
      final dir = target > _timeline.offset ? 1 : -1;
      _timeline.jumpTo(target - dir * _glideDistance);
    }
    _timeline
        .animateTo(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
        )
        .whenComplete(() => _programmaticScroll = false);
  }

  /// As the user scrolls the timeline, track the wheels live to the hour at the
  /// top of the viewport. Deliberately does NOT call setState: rebuilding the
  /// sliver tree mid-fling is what makes the scroll stutter and the focus
  /// highlight hop between hours. The header + highlight refresh on settle.
  void _onTimelineScroll() {
    if (_programmaticScroll || !_timeline.hasClients) return;
    final topItem = (_timeline.offset / _hourRowHeight).round();
    if (topItem == _lastTopItem) return;
    _lastTopItem = topItem;
    _focus = _focusForHourItem(topItem);
    _syncWheel(_Wheel.hour, _hourWheel, topItem, null, true);
    _syncWheel(_Wheel.day, _dayWheel, _dayItemFor(_focus), null, true);
    _syncWheel(_Wheel.month, _monthWheel, _monthItemFor(_focus), null, true);
  }

  /// Once the timeline stops, refresh the header and focus-hour highlight to the
  /// settled hour (a single rebuild, so it never affects scroll smoothness).
  void _onTimelineSettle() {
    // Ignore settles emitted while we're driving the scroll ourselves: the
    // focus is already correct (set by the wheel handler), and the intermediate
    // offset during a fake glide would otherwise refresh to the wrong hour.
    if (_programmaticScroll || !_timeline.hasClients) return;
    _lastTopItem = (_timeline.offset / _hourRowHeight).round();
    _focus = _focusForHourItem(_lastTopItem);
    setState(() {});
  }

  List<Task> _tasksForHourItem(int item) {
    final date = _dateForDayItem(_floorDiv(item, 24));
    final hour = item % 24;
    final list = widget.tasks.where((task) {
      final due = task.dueDate;
      if (due == null) return false;
      return due.year == date.year &&
          due.month == date.month &&
          due.day == date.day &&
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
    final focusItem = _hourItemFor(_focus);
    // A CustomScrollView with a centre key scrolls infinitely in both
    // directions: the forward sliver builds item 0, 1, 2, ... and the leading
    // sliver builds item -1, -2, -3, ... above it. Every row is exactly
    // [_hourRowHeight] tall so offset == item * height stays exact.
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        _onTimelineSettle();
        return false;
      },
      child: CustomScrollView(
        controller: _timeline,
        center: _timelineCenter,
        slivers: [
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _hourRow(theme, -index - 1, focusItem),
            ),
          ),
          SliverList(
            key: _timelineCenter,
            delegate: SliverChildBuilderDelegate(
              (context, index) => _hourRow(theme, index, focusItem),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hourRow(ThemeData theme, int item, int focusItem) {
    final tasks = _tasksForHourItem(item);
    final hour = item % 24;
    final isFocus = item == focusItem;
    final isMidnight = hour == 0;
    final date = _dateForDayItem(_floorDiv(item, 24));
    return Container(
      key: ValueKey('chronize-hour-$item'),
      height: _hourRowHeight,
      decoration: BoxDecoration(
        color: isFocus ? theme.colorScheme.primary.withOpacity(0.08) : null,
        border: Border(
          top: BorderSide(
            color: isMidnight
                ? theme.colorScheme.primary.withOpacity(0.5)
                : theme.dividerColor.withOpacity(0.5),
            width: isMidnight ? 1.5 : 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.0,
                      fontWeight:
                          isFocus ? FontWeight.bold : FontWeight.normal,
                      color: theme.colorScheme.onSurface
                          .withOpacity(isFocus ? 1 : 0.6),
                    ),
                  ),
                  // Date marker at the start of each day so the endless
                  // timeline stays legible while scrolling.
                  if (isMidnight)
                    Text(
                      '${date.day} ${_months[date.month - 1]}',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        height: 1.0,
                        fontSize: 10,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
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
    return SizedBox(
      width: 168,
      child: Row(
        children: [
          _buildWheel(
            theme,
            controller: _hourWheel,
            // Hour-of-day; crossing a 24-item boundary carries to the day wheel.
            labelFor: (i) => '${(i % 24).toString().padLeft(2, '0')}:00',
            onSelected: (i) => _setFocus(_focusForHourItem(i), _Wheel.hour),
          ),
          _buildWheel(
            theme,
            controller: _dayWheel,
            // Actual calendar date number for that day.
            labelFor: (i) => _dateForDayItem(i).day.toString(),
            onSelected: (i) => _setFocus(_focusForDayItem(i), _Wheel.day),
          ),
          _buildWheel(
            theme,
            controller: _monthWheel,
            labelFor: (i) =>
                _months[DateTime(_base.year, _base.month + i, 1).month - 1],
            onSelected: (i) => _setFocus(_focusForMonthItem(i), _Wheel.month),
          ),
        ],
      ),
    );
  }

  Widget _buildWheel(
    ThemeData theme, {
    required FixedExtentScrollController controller,
    required String Function(int) labelFor,
    required ValueChanged<int> onSelected,
  }) {
    return Expanded(
      // childCount: null makes the wheel scroll infinitely in both directions.
      child: CupertinoPicker.builder(
        scrollController: controller,
        itemExtent: 32,
        useMagnifier: true,
        magnification: 1.15,
        squeeze: 1.1,
        selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
          background: theme.colorScheme.primary.withOpacity(0.12),
        ),
        onSelectedItemChanged: onSelected,
        itemBuilder: (context, i) => Center(
          child: Text(
            labelFor(i),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}
