import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/task.dart';
import 'subpage_app_bar.dart';
import 'task_detail_page.dart';

/// Experimental "Chronize" tool.
///
/// The left side is an infinite, smoothly-scrolling vertical timeline. Each row
/// is a fixed height and represents [_unitMinutes] of time; pinching (or the
/// zoom buttons) changes that unit from 5-minute marks all the way out to a
/// multi-day overview. On the right, day/month (and optionally hour) scroll
/// wheels jump the focus to a chosen date.
class ChronizePage extends StatefulWidget {
  final List<Task> tasks;

  const ChronizePage({Key? key, required this.tasks}) : super(key: key);

  @override
  State<ChronizePage> createState() => _ChronizePageState();
}

/// Which wheel originated a focus change.
enum _Wheel { hour, day, month }

class _ChronizePageState extends State<ChronizePage> {
  static const double _rowHeight = 64;

  // How far the timeline visibly glides into place; farther targets jump to
  // within one glide of the destination first so they still read as a smooth
  // scroll rather than a hard snap.
  static const double _glideDistance = 8 * _rowHeight;

  // Minutes-per-row zoom levels, finest (5-minute marks) to a wide overview.
  static const List<int> _zoomUnits = [5, 15, 30, 60, 120, 240, 720, 1440];
  static const int _defaultZoomIndex = 3; // 60 minutes

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

  // The infinite vertical timeline. A scroll offset of `item * _rowHeight` puts
  // row `item` (= item * _unitMinutes from _base) at the top.
  late final ScrollController _timeline;
  final Key _timelineCenter = const ValueKey('timeline-center');

  // Infinite scroll-wheel controllers (item 0 maps to [_base]).
  late final FixedExtentScrollController _hourWheel;
  late final FixedExtentScrollController _dayWheel;
  late final FixedExtentScrollController _monthWheel;

  // The focused moment: the single source of truth the wheels and the timeline
  // all read from. The focus sits at the top of the timeline viewport.
  late DateTime _focus;

  // Current zoom: minutes represented by one row.
  int _zoomIndex = _defaultZoomIndex;
  int _unitMinutes = _zoomUnits[_defaultZoomIndex];

  // Per-wheel suppression: >0 while that wheel is being repositioned
  // programmatically, so its callback is ignored instead of treated as input.
  final Map<_Wheel, int> _suppress = {
    _Wheel.hour: 0,
    _Wheel.day: 0,
    _Wheel.month: 0,
  };

  // True while the timeline is scrolled programmatically (so its listener
  // ignores that motion); and while a pinch is in progress (so the timeline
  // doesn't scroll under the two fingers).
  bool _programmaticScroll = false;
  bool _pinching = false;
  int _lastTopItem = 0;

  // Debounce so spinning a wheel stays smooth: the heavy work (gliding the
  // timeline, refreshing the header) runs once, after the wheel settles.
  Timer? _settleTimer;

  // Active pointers, for pinch-to-zoom detection.
  final Map<int, Offset> _pointers = {};
  double _pinchStartDistance = 0;
  int _pinchStartZoom = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _base = DateTime(now.year, now.month, now.day);
    _focus = DateTime(now.year, now.month, now.day, now.hour);
    _lastTopItem = _itemForFocus();
    _timeline = ScrollController(
      initialScrollOffset: _lastTopItem * _rowHeight,
    )..addListener(_onTimelineScroll);
    _hourWheel = FixedExtentScrollController(initialItem: _hourItemFor(_focus));
    _dayWheel = FixedExtentScrollController(initialItem: _dayItemFor(_focus));
    _monthWheel =
        FixedExtentScrollController(initialItem: _monthItemFor(_focus));
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _timeline.dispose();
    _hourWheel.dispose();
    _dayWheel.dispose();
    _monthWheel.dispose();
    super.dispose();
  }

  // ---- Item <-> moment mapping (item 0 == _base) ----

  // Floor division for negative items (Dart's a % b is >= 0 for b > 0).
  int _floorDiv(int a, int b) => (a - (a % b)) ~/ b;

  int _dayItemFor(DateTime f) {
    final diff = DateTime(f.year, f.month, f.day).difference(_base);
    return (diff.inHours / 24).round(); // round so DST days don't drift
  }

  int _minutesFromBase(DateTime f) =>
      _dayItemFor(f) * 1440 + f.hour * 60 + f.minute;

  DateTime _momentForMinutes(int mins) {
    final dayPart = _floorDiv(mins, 1440);
    final within = mins - dayPart * 1440;
    final date = _dateForDayItem(dayPart);
    return DateTime(date.year, date.month, date.day, within ~/ 60, within % 60);
  }

  // Timeline (zoom-aware) mapping.
  int _itemForFocus() => (_minutesFromBase(_focus) / _unitMinutes).round();
  DateTime _focusForItem(int item) => _momentForMinutes(item * _unitMinutes);

  // Wheel mappings (independent of zoom).
  int _hourItemFor(DateTime f) => _dayItemFor(f) * 24 + f.hour;
  int _monthItemFor(DateTime f) =>
      (f.year - _base.year) * 12 + (f.month - _base.month);
  DateTime _dateForDayItem(int item) =>
      DateTime(_base.year, _base.month, _base.day + item);

  DateTime _focusForHourItem(int item) {
    final date = _dateForDayItem(_floorDiv(item, 24));
    return DateTime(date.year, date.month, date.day, item % 24);
  }

  DateTime _focusForDayItem(int item) {
    final date = _dateForDayItem(item);
    return DateTime(date.year, date.month, date.day, _focus.hour, _focus.minute);
  }

  DateTime _focusForMonthItem(int item) {
    final first = DateTime(_base.year, _base.month + item, 1);
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final day = _focus.day < daysInMonth ? _focus.day : daysInMonth;
    return DateTime(first.year, first.month, day, _focus.hour, _focus.minute);
  }

  DateTime get _focusDay =>
      DateTime(_focus.year, _focus.month, _focus.day);

  // ---- Wheel input (smooth: cheap while spinning, settle once on pause) ----

  void _onWheelInput(_Wheel wheel, DateTime next) {
    if (_suppress[wheel]! > 0) return; // programmatic reposition, not input
    // Cheap: only record the focus while the wheel spins, so the wheel itself
    // stays perfectly smooth. The timeline glide + refresh run on settle.
    _focus = next;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 120), _settleAfterWheel);
  }

  void _settleAfterWheel() {
    if (!mounted) return;
    // Carry the other wheels, glide the timeline, refresh — all at once, after
    // spinning has stopped.
    _syncWheel(_Wheel.hour, _hourWheel, _hourItemFor(_focus), false);
    _syncWheel(_Wheel.day, _dayWheel, _dayItemFor(_focus), false);
    _syncWheel(_Wheel.month, _monthWheel, _monthItemFor(_focus), false);
    _scrollTimelineToFocus();
    setState(() {});
  }

  /// Moves wheel [c] to [target] without it counting as user input. Already at
  /// target, or not currently shown? skip. Small carries animate; large jumps,
  /// or [instant], snap.
  void _syncWheel(
    _Wheel wheel,
    FixedExtentScrollController c,
    int target,
    bool instant,
  ) {
    if (!c.hasClients || c.selectedItem == target) return;
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

  // ---- Timeline scrolling ----

  /// Smoothly scrolls the timeline so the focus is at the top. For far targets
  /// it fakes the motion: jump to just shy of the target, then glide the rest,
  /// so it always looks like a smooth scroll instead of a hard snap.
  void _scrollTimelineToFocus() {
    if (!_timeline.hasClients) return;
    final target = _itemForFocus() * _rowHeight;
    final distance = (target - _timeline.offset).abs();
    if (distance < 0.5) return;
    _lastTopItem = _itemForFocus();
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

  /// As the user scrolls the timeline, track the wheels live to the row at the
  /// top. Deliberately no setState: rebuilding the sliver tree mid-fling is what
  /// makes scrolling stutter. The header refreshes on settle.
  void _onTimelineScroll() {
    if (_programmaticScroll || !_timeline.hasClients) return;
    final topItem = (_timeline.offset / _rowHeight).round();
    if (topItem == _lastTopItem) return;
    _lastTopItem = topItem;
    _focus = _focusForItem(topItem);
    _syncWheel(_Wheel.hour, _hourWheel, _hourItemFor(_focus), true);
    _syncWheel(_Wheel.day, _dayWheel, _dayItemFor(_focus), true);
    _syncWheel(_Wheel.month, _monthWheel, _monthItemFor(_focus), true);
  }

  /// Once the timeline stops, refresh the header + focus highlight (one rebuild,
  /// so it never affects scroll smoothness).
  void _onTimelineSettle() {
    if (_programmaticScroll || !_timeline.hasClients) return;
    _lastTopItem = (_timeline.offset / _rowHeight).round();
    _focus = _focusForItem(_lastTopItem);
    setState(() {});
  }

  void _returnToToday() {
    final now = DateTime.now();
    _focus = DateTime(now.year, now.month, now.day, now.hour);
    _syncWheel(_Wheel.hour, _hourWheel, _hourItemFor(_focus), false);
    _syncWheel(_Wheel.day, _dayWheel, _dayItemFor(_focus), false);
    _syncWheel(_Wheel.month, _monthWheel, _monthItemFor(_focus), false);
    _scrollTimelineToFocus();
    setState(() {});
  }

  // ---- Zoom ----

  bool get _canZoomIn => _zoomIndex > 0;
  bool get _canZoomOut => _zoomIndex < _zoomUnits.length - 1;

  void _setZoom(int newIndex) {
    newIndex = newIndex.clamp(0, _zoomUnits.length - 1);
    if (newIndex == _zoomIndex) return;
    setState(() {
      _zoomIndex = newIndex;
      _unitMinutes = _zoomUnits[newIndex];
    });
    // Keep the focus pinned to the top after the row unit changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_timeline.hasClients) return;
      _programmaticScroll = true;
      _lastTopItem = _itemForFocus();
      _timeline.jumpTo(_lastTopItem * _rowHeight);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _programmaticScroll = false);
    });
  }

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      final pts = _pointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartZoom = _zoomIndex;
      if (!_pinching) setState(() => _pinching = true);
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length != 2 || _pinchStartDistance <= 0) return;
    final pts = _pointers.values.toList();
    final scale = (pts[0] - pts[1]).distance / _pinchStartDistance;
    // Spreading the fingers (scale > 1) zooms in: one level finer per doubling.
    final steps = (math.log(scale) / math.ln2).round();
    _setZoom(_pinchStartZoom - steps);
  }

  void _onPointerEnd(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2 && _pinching) {
      setState(() => _pinching = false);
    }
  }

  // ---- Task lookups ----

  List<Task> _tasksForItem(int item) {
    final start = item * _unitMinutes;
    final end = start + _unitMinutes;
    final list = widget.tasks.where((task) {
      final due = task.dueDate;
      if (due == null) return false;
      final mins = _minutesFromBase(due);
      return mins >= start && mins < end;
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

  String _zoomLabel() {
    final m = _unitMinutes;
    if (m < 60) return '$m min';
    if (m < 1440) return '${m ~/ 60} h';
    return '${m ~/ 1440} d';
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
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_formatFocusDate(), style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  dayCount == 0
                      ? 'No tasks on this day'
                      : '$dayCount task${dayCount == 1 ? '' : 's'} on this day',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            tooltip: 'Zoom out',
            onPressed: _canZoomOut ? () => _setZoom(_zoomIndex + 1) : null,
          ),
          Text(_zoomLabel(), style: theme.textTheme.labelSmall),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: 'Zoom in',
            onPressed: _canZoomIn ? () => _setZoom(_zoomIndex - 1) : null,
          ),
          TextButton.icon(
            onPressed: _returnToToday,
            icon: const Icon(Icons.today, size: 18),
            label: const Text('Today'),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(ThemeData theme) {
    final focusItem = _itemForFocus();
    // A CustomScrollView with a centre key scrolls infinitely both ways: the
    // forward sliver builds item 0, 1, 2, ... and the leading sliver builds
    // item -1, -2, -3, ... above it. Listener handles pinch-to-zoom while the
    // scroll view handles single-finger scrolling.
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          _onTimelineSettle();
          return false;
        },
        child: CustomScrollView(
          controller: _timeline,
          center: _timelineCenter,
          physics: _pinching ? const NeverScrollableScrollPhysics() : null,
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _row(theme, -index - 1, focusItem),
              ),
            ),
            SliverList(
              key: _timelineCenter,
              delegate: SliverChildBuilderDelegate(
                (context, index) => _row(theme, index, focusItem),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, int item, int focusItem) {
    final tasks = _tasksForItem(item);
    final mins = item * _unitMinutes;
    final moment = _momentForMinutes(mins);
    final isFocus = item == focusItem;
    final isDayStart = mins % 1440 == 0;
    final daily = _unitMinutes >= 1440;
    final dateLabel = '${moment.day} ${_months[moment.month - 1]}';
    return Container(
      key: ValueKey('chronize-row-$item'),
      height: _rowHeight,
      decoration: BoxDecoration(
        color: isFocus ? theme.colorScheme.primary.withOpacity(0.08) : null,
        border: Border(
          top: BorderSide(
            color: isDayStart
                ? theme.colorScheme.primary.withOpacity(0.5)
                : theme.dividerColor.withOpacity(0.5),
            width: isDayStart ? 1.5 : 0.5,
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
                    daily
                        ? dateLabel
                        : '${moment.hour.toString().padLeft(2, '0')}:'
                            '${moment.minute.toString().padLeft(2, '0')}',
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
                  // Date marker at the start of each day keeps the endless
                  // timeline legible while scrolling.
                  if (isDayStart && !daily)
                    Text(
                      dateLabel,
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                decoration: task.isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRollers(ThemeData theme) {
    final showHour = Config.chronizeShowHourWheel;
    return SizedBox(
      width: showHour ? 168 : 112,
      child: Row(
        children: [
          if (showHour)
            _buildWheel(
              theme,
              controller: _hourWheel,
              labelFor: (i) => '${(i % 24).toString().padLeft(2, '0')}:00',
              onSelected: (i) =>
                  _onWheelInput(_Wheel.hour, _focusForHourItem(i)),
            ),
          _buildWheel(
            theme,
            controller: _dayWheel,
            labelFor: (i) => _dateForDayItem(i).day.toString(),
            onSelected: (i) => _onWheelInput(_Wheel.day, _focusForDayItem(i)),
          ),
          _buildWheel(
            theme,
            controller: _monthWheel,
            labelFor: (i) =>
                _months[DateTime(_base.year, _base.month + i, 1).month - 1],
            onSelected: (i) =>
                _onWheelInput(_Wheel.month, _focusForMonthItem(i)),
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
