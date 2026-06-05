import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../config.dart';
import '../models/task.dart';
import 'subpage_app_bar.dart';

/// A level's marks start fading in once they are at least [kMarkFadeStartPx]
/// apart on screen and are fully opaque by [kMarkFadeFullPx]. Because finer
/// levels sit closer together, they only reach these thresholds at higher zoom,
/// which is what staggers their appearance as the user zooms in (and, in
/// reverse, fades them away when zooming out).
const double kMarkFadeStartPx = 22;
const double kMarkFadeFullPx = 52;

/// Opacity (0..1) for a level of time marks spaced [intervalMinutes] apart,
/// shown at a zoom of [pixelsPerMinute] logical pixels per minute.
///
/// [alwaysVisible] keeps the coarsest level on screen so the ruler is never
/// empty when fully zoomed out. Exposed at the library level so the smooth
/// fade behaviour can be unit tested without a painter.
double markLevelOpacity({
  required double intervalMinutes,
  required double pixelsPerMinute,
  bool alwaysVisible = false,
}) {
  if (alwaysVisible) return 1.0;
  final spacingPx = intervalMinutes * pixelsPerMinute;
  return ((spacingPx - kMarkFadeStartPx) / (kMarkFadeFullPx - kMarkFadeStartPx))
      .clamp(0.0, 1.0);
}

/// A single granularity level of time marks on the [ChronizePage] ruler.
///
/// Coarser levels (a larger [intervalMinutes]) stay visible when zoomed out,
/// while finer levels only fade in as the user zooms further in. Every
/// interval is a divisor of all coarser intervals so the marks line up and a
/// mark shared with a coarser level is drawn only once (at the coarser level).
class _MarkLevel {
  const _MarkLevel(this.intervalMinutes, this.tickLength,
      {this.alwaysVisible = false});

  /// Spacing between marks of this level, in minutes.
  final int intervalMinutes;

  /// How far the tick line reaches into the gutter (longer for coarser levels).
  final double tickLength;

  /// The coarsest level stays on screen so the ruler is never empty.
  final bool alwaysVisible;
}

/// Experimental "Chronize" tool.
///
/// The left side is an infinite vertical timeline drawn on a *continuous* time
/// axis: zooming (pinch or the +/- buttons) smoothly scales the axis rather
/// than snapping between fixed row units. As you zoom in, finer time marks fade
/// in one granularity at a time — day/2h first, then the hour, half-hour,
/// 10-minute and 5-minute marks — and the lines spread apart. Zooming out
/// reverses it, fading the finer marks away until only the coarse marks remain.
///
/// On the right, day/month (and optionally hour) scroll wheels jump the focus
/// to a chosen date; the wheels and the timeline stay in sync.
class ChronizePage extends StatefulWidget {
  final List<Task> tasks;

  /// Create a task at the given deadline (date + time), tapped on the timeline.
  final void Function(String title, DateTime dueDate)? onCreateTask;

  /// Called after a task is edited in place so the host can persist the change.
  final VoidCallback? onTaskChanged;

  /// Delete a task chosen on the timeline.
  final void Function(Task task)? onDeleteTask;

  const ChronizePage({
    Key? key,
    required this.tasks,
    this.onCreateTask,
    this.onTaskChanged,
    this.onDeleteTask,
  }) : super(key: key);

  @override
  State<ChronizePage> createState() => _ChronizePageState();
}

/// Which wheel originated a focus change.
enum _Wheel { hour, day, month }

class _ChronizePageState extends State<ChronizePage>
    with TickerProviderStateMixin {
  /// Mark levels, coarsest to finest. The day level is always visible so the
  /// ruler never goes blank when fully zoomed out.
  static const List<_MarkLevel> _levels = [
    _MarkLevel(1440, 28, alwaysVisible: true), // 1 day
    _MarkLevel(720, 24), // 12 h
    _MarkLevel(360, 20), // 6 h
    _MarkLevel(120, 16), // 2 h
    _MarkLevel(60, 13), // 1 h
    _MarkLevel(30, 10), // 30 min
    _MarkLevel(10, 7), // 10 min
    _MarkLevel(5, 5), // 5 min
  ];

  // Continuous zoom bounds, in logical pixels per minute. At the minimum the
  // day marks sit ~43px apart (a multi-day overview); at the maximum the
  // 5-minute marks sit ~60px apart.
  static const double _minPixelsPerMinute = 0.03;
  static const double _maxPixelsPerMinute = 12.0;
  static const double _zoomButtonFactor = 1.6;

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

  late final DateTime _base; // start of today; minute 0 of the timeline

  // The continuous timeline state: how zoomed in we are, and which minute (from
  // _base; negative = before today) sits at the top edge of the viewport. The
  // top edge is the "focus" the header and wheels read from.
  double _pixelsPerMinute = 0.9;
  double _topMinute = 0;

  // Infinite scroll-wheel controllers (item 0 maps to [_base]).
  late final FixedExtentScrollController _hourWheel;
  late final FixedExtentScrollController _dayWheel;
  late final FixedExtentScrollController _monthWheel;

  // Per-wheel suppression: >0 while that wheel is being repositioned
  // programmatically, so its callback is ignored instead of treated as input.
  final Map<_Wheel, int> _suppress = {
    _Wheel.hour: 0,
    _Wheel.day: 0,
    _Wheel.month: 0,
  };

  // Glide animation shared by the Today button, wheel settle and zoom buttons:
  // it interpolates _topMinute and/or _pixelsPerMinute toward a target.
  late final AnimationController _glide;
  double _glideStartTop = 0;
  double _glideTargetTop = 0;
  double _glideStartPpm = 0;
  double _glideTargetPpm = 0;

  // Momentum (fling) after a pan: an unbounded controller driven by a friction
  // simulation so the timeline keeps gliding and slows to a stop on release.
  late final AnimationController _fling;
  double _flingPpm = 1;

  // Pinch / drag anchors captured at the start of a scale gesture.
  double _gestureStartPpm = 0.9;
  double _gestureStartTop = 0;
  double _gestureStartFocalY = 0;

  // Last measured viewport height, used to center the focus (e.g. "Today").
  double _viewportHeight = 0;

  // Debounce so spinning a wheel stays smooth: the glide runs once, after the
  // wheel settles.
  Timer? _settleTimer;
  DateTime? _pendingFocus;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _base = DateTime(now.year, now.month, now.day);
    final focus = DateTime(now.year, now.month, now.day, now.hour);
    _topMinute = _minutesFromBase(focus).toDouble();

    _hourWheel = FixedExtentScrollController(initialItem: _hourItemFor(focus));
    _dayWheel = FixedExtentScrollController(initialItem: _dayItemFor(focus));
    _monthWheel =
        FixedExtentScrollController(initialItem: _monthItemFor(focus));

    _glide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )
      ..addListener(_onGlideTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _syncWheelsToFocus();
      });

    _fling = AnimationController.unbounded(vsync: this)
      ..addListener(_onFlingTick);
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _glide.dispose();
    _fling.dispose();
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

  // The focused moment is whatever sits at the top edge of the viewport.
  DateTime get _focus => _momentForMinutes(_topMinute.round());

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
    final f = _focus;
    return DateTime(date.year, date.month, date.day, f.hour, f.minute);
  }

  DateTime _focusForMonthItem(int item) {
    final first = DateTime(_base.year, _base.month + item, 1);
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final f = _focus;
    final day = f.day < daysInMonth ? f.day : daysInMonth;
    return DateTime(first.year, first.month, day, f.hour, f.minute);
  }

  DateTime get _focusDay {
    final f = _focus;
    return DateTime(f.year, f.month, f.day);
  }

  // ---- Glide animation ----

  double _clampZoom(double v) =>
      v.clamp(_minPixelsPerMinute, _maxPixelsPerMinute);

  void _animateTo({double? topMinute, double? pixelsPerMinute}) {
    _fling.stop();
    _glideStartTop = _topMinute;
    _glideTargetTop = topMinute ?? _topMinute;
    _glideStartPpm = _pixelsPerMinute;
    _glideTargetPpm = pixelsPerMinute ?? _pixelsPerMinute;
    if ((_glideTargetTop - _glideStartTop).abs() < 0.01 &&
        (_glideTargetPpm - _glideStartPpm).abs() < 1e-6) {
      return;
    }
    _glide
      ..reset()
      ..forward();
  }

  void _onGlideTick() {
    final t = Curves.easeOut.transform(_glide.value);
    setState(() {
      _topMinute = _glideStartTop + (_glideTargetTop - _glideStartTop) * t;
      _pixelsPerMinute =
          _glideStartPpm + (_glideTargetPpm - _glideStartPpm) * t;
    });
  }

  // Friction-driven momentum: drive _topMinute from the unbounded controller
  // (position is in pixel space, so the deceleration feel is zoom-independent).
  void _onFlingTick() {
    setState(() => _topMinute = _fling.value / _flingPpm);
    _syncWheelsToFocus();
  }

  // ---- Direct manipulation (pinch zoom + single-finger pan) ----

  void _onScaleStart(ScaleStartDetails details) {
    _glide.stop();
    _fling.stop();
    _gestureStartPpm = _pixelsPerMinute;
    _gestureStartTop = _topMinute;
    _gestureStartFocalY = details.localFocalPoint.dy;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // The minute under the fingers when the gesture began.
    final anchorMinute = _gestureStartTop + _gestureStartFocalY / _gestureStartPpm;
    final newPpm = _clampZoom(_gestureStartPpm * details.scale);
    final focalY = details.localFocalPoint.dy;
    // Keep that minute under the current focal point: one expression covers
    // both single-finger panning (scale == 1, focal point moves) and pinch
    // zoom (scale changes).
    setState(() {
      _pixelsPerMinute = newPpm;
      _topMinute = anchorMinute - focalY / newPpm;
    });
    _syncWheelsToFocus();
  }

  /// On release, keep gliding with friction so the timeline slows to a stop
  /// instead of halting instantly.
  void _onScaleEnd(ScaleEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (velocity.abs() < 50) return; // ignore tiny residual motion
    _flingPpm = _pixelsPerMinute;
    // Work in pixel space: position = topMinute * ppm, which moves opposite to
    // the finger's vertical velocity.
    final simulation = FrictionSimulation(
      0.135,
      _topMinute * _flingPpm,
      -velocity,
    );
    _fling.animateWith(simulation);
  }

  /// Desktop / web: the mouse wheel or trackpad scrolls the timeline.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _glide.stop();
    _fling.stop();
    setState(() {
      _topMinute += event.scrollDelta.dy / _pixelsPerMinute;
    });
    _syncWheelsToFocus();
  }

  // ---- Zoom controls ----

  bool get _canZoomIn => _pixelsPerMinute < _maxPixelsPerMinute - 1e-6;
  bool get _canZoomOut => _pixelsPerMinute > _minPixelsPerMinute + 1e-6;

  // Zooming with the buttons keeps the top focus pinned (anchor at y == 0).
  // Rapid taps compound off the in-flight target rather than the mid-glide
  // value, so two quick taps move two steps.
  void _zoomBy(double factor) {
    final base = _glide.isAnimating ? _glideTargetPpm : _pixelsPerMinute;
    _animateTo(pixelsPerMinute: _clampZoom(base * factor));
  }

  void _returnToToday() {
    final nowMinute = _minutesFromBase(DateTime.now()).toDouble();
    // Center the current time in the viewport (rather than pinning it to the
    // top edge) so "Today" lands on the actual current hour.
    final target = _viewportHeight > 0
        ? nowMinute - _viewportHeight / (2 * _pixelsPerMinute)
        : nowMinute;
    _animateTo(topMinute: target);
  }

  // ---- Wheel <-> timeline sync ----

  void _onWheelInput(_Wheel wheel, DateTime next) {
    if (_suppress[wheel]! > 0) return; // programmatic reposition, not input
    // Cheap while the wheel spins: just remember the target. The timeline glide
    // and the carry of the other wheels run once, after it settles.
    _pendingFocus = next;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 120), _settleAfterWheel);
  }

  void _settleAfterWheel() {
    if (!mounted || _pendingFocus == null) return;
    final target = _pendingFocus!;
    _pendingFocus = null;
    _syncWheel(_Wheel.hour, _hourWheel, _hourItemFor(target), false);
    _syncWheel(_Wheel.day, _dayWheel, _dayItemFor(target), false);
    _syncWheel(_Wheel.month, _monthWheel, _monthItemFor(target), false);
    _animateTo(topMinute: _minutesFromBase(target).toDouble());
  }

  /// Jump every wheel to the current top focus without it counting as input.
  void _syncWheelsToFocus() {
    final f = _focus;
    _syncWheel(_Wheel.hour, _hourWheel, _hourItemFor(f), true);
    _syncWheel(_Wheel.day, _dayWheel, _dayItemFor(f), true);
    _syncWheel(_Wheel.month, _monthWheel, _monthItemFor(f), true);
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

  // ---- Task lookups ----

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

  /// Label for the finest mark level currently (at least half) visible.
  String _zoomLabel() {
    for (final level in _levels.reversed) {
      final opacity = markLevelOpacity(
        intervalMinutes: level.intervalMinutes.toDouble(),
        pixelsPerMinute: _pixelsPerMinute,
        alwaysVisible: level.alwaysVisible,
      );
      if (opacity >= 0.5) return _intervalLabel(level.intervalMinutes);
    }
    return _intervalLabel(_levels.first.intervalMinutes);
  }

  static String _intervalLabel(int minutes) {
    if (minutes < 60) return '$minutes min';
    if (minutes < 1440) return '${minutes ~/ 60} h';
    return '${minutes ~/ 1440} d';
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
            onPressed: _canZoomOut ? () => _zoomBy(1 / _zoomButtonFactor) : null,
          ),
          SizedBox(
            width: 44,
            child: Text(
              _zoomLabel(),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: 'Zoom in',
            onPressed: _canZoomIn ? () => _zoomBy(_zoomButtonFactor) : null,
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
    // Recomputed each build so the "now" line tracks the clock without needing
    // a periodic timer (it refreshes on any interaction / rebuild).
    final nowMinute = _minutesFromBase(DateTime.now()).toDouble();
    // Listener handles mouse-wheel / trackpad scrolling; GestureDetector handles
    // pinch-to-zoom and single-finger panning. The CustomPaint draws the
    // continuous ruler; tappable task chips are positioned on top.
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        _viewportHeight = height;
        final eventNav = _buildEventNav(theme, height);
        return Listener(
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: (details) => _onScaleUpdate(details),
            onScaleEnd: _onScaleEnd,
            onTapUp: _onBackgroundTapUp,
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TimeAxisPainter(
                        levels: _levels,
                        pixelsPerMinute: _pixelsPerMinute,
                        topMinute: _topMinute,
                        nowMinute: nowMinute,
                        base: _base,
                        months: _months,
                        onSurface: theme.colorScheme.onSurface,
                        surface: theme.colorScheme.surface,
                        primary: theme.colorScheme.primary,
                        nowColor: theme.colorScheme.error,
                      ),
                    ),
                  ),
                  ..._buildTaskChips(theme, height),
                  if (eventNav != null) eventNav,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Positions the visible task chips on the body by their time, cascading any
  /// that would overlap so they stay readable.
  List<Widget> _buildTaskChips(ThemeData theme, double height) {
    const chipHeight = 22.0;
    const gap = 2.0;
    final bodyLeft = _TimeAxisPainter.gutterWidth + 6;
    final topMin = _topMinute;
    final bottomMin = _topMinute + height / _pixelsPerMinute;

    final visible = widget.tasks.where((task) {
      final due = task.dueDate;
      if (due == null) return false;
      final m = _minutesFromBase(due).toDouble();
      return m >= topMin - 60 && m <= bottomMin + 1;
    }).toList()
      ..sort((a, b) => _minutesFromBase(a.dueDate!)
          .compareTo(_minutesFromBase(b.dueDate!)));

    final chips = <Widget>[];
    double lastBottom = double.negativeInfinity;
    for (final task in visible) {
      final m = _minutesFromBase(task.dueDate!).toDouble();
      var y = (m - _topMinute) * _pixelsPerMinute;
      if (y < lastBottom + gap) y = lastBottom + gap;
      lastBottom = y + chipHeight;
      if (y > height) break;
      chips.add(
        Positioned(
          left: bodyLeft,
          right: 6,
          top: y,
          height: chipHeight,
          child: _buildTaskChip(theme, task),
        ),
      );
    }
    return chips;
  }

  /// Tasks that sit on the timeline: have a due date and aren't the far-future
  /// "someday" bucket (year >= 2300).
  Iterable<Task> get _datedTasks => widget.tasks.where((t) {
        final d = t.dueDate;
        return d != null && d.year < 2300;
      });

  /// When no event is within the viewport, builds the two centered navigator
  /// cards pointing at the nearest past and future events. Returns null when an
  /// event is in view (so the cards hide) or there are no dated events at all.
  Widget? _buildEventNav(ThemeData theme, double height) {
    if (height <= 0 || _pixelsPerMinute <= 0) return null;
    final topMin = _topMinute;
    final bottomMin = _topMinute + height / _pixelsPerMinute;
    final centerMin = (topMin + bottomMin) / 2;

    double? prev; // nearest event above the viewport (in the past)
    double? next; // nearest event below the viewport (in the future)
    for (final task in _datedTasks) {
      final m = _minutesFromBase(task.dueDate!).toDouble();
      if (m >= topMin && m <= bottomMin) {
        return null; // an event is visible -> hide the cards
      } else if (m < topMin) {
        if (prev == null || m > prev) prev = m;
      } else {
        if (next == null || m < next) next = m;
      }
    }

    final prevMin = prev;
    final nextMin = next;
    if (prevMin == null && nextMin == null) return null;

    final cards = <Widget>[];
    if (prevMin != null) {
      cards.add(_eventNavCard(
        theme,
        icon: Icons.keyboard_arrow_up,
        title: 'Previous event',
        subtitle: '${_formatGap(centerMin - prevMin)} earlier',
        targetMinute: prevMin,
        height: height,
      ));
    }
    if (nextMin != null) {
      if (cards.isNotEmpty) cards.add(const SizedBox(height: 16));
      cards.add(_eventNavCard(
        theme,
        icon: Icons.keyboard_arrow_down,
        title: 'Next event',
        subtitle: 'in ${_formatGap(nextMin - centerMin)}',
        targetMinute: nextMin,
        height: height,
      ));
    }

    return Positioned(
      left: _TimeAxisPainter.gutterWidth,
      right: 0,
      top: 0,
      bottom: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: cards,
        ),
      ),
    );
  }

  /// One navigator card. Tapping it glides the timeline so [targetMinute] is
  /// centered in the viewport.
  Widget _eventNavCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String subtitle,
    required double targetMinute,
    required double height,
  }) {
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _animateTo(
          topMinute: targetMinute - height / (2 * _pixelsPerMinute),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: scheme.onSecondaryContainer),
              Text(
                title,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSecondaryContainer.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Formats a positive minute gap as a coarse "3 days" / "5 hours" / "20 min".
  static String _formatGap(double minutes) {
    final m = minutes.abs().round();
    if (m >= 1440) {
      final days = (m / 1440).round();
      return days == 1 ? '1 day' : '$days days';
    }
    if (m >= 60) {
      final hours = (m / 60).round();
      return hours == 1 ? '1 hour' : '$hours hours';
    }
    if (m >= 1) return m == 1 ? '1 min' : '$m min';
    return 'now';
  }

  /// Tapping empty timeline space opens the create-task dialog with the
  /// deadline set to the tapped position (rounded to 5 minutes).
  void _onBackgroundTapUp(TapUpDetails details) {
    if (widget.onCreateTask == null) return;
    final minute = _topMinute + details.localPosition.dy / _pixelsPerMinute;
    final rounded = (minute / 5).round() * 5;
    _openTaskEditor(initialDue: _momentForMinutes(rounded));
  }

  /// Shows the shared create/edit dialog. With [task] it edits in place; with
  /// [initialDue] it creates a new task at that deadline.
  Future<void> _openTaskEditor({Task? task, DateTime? initialDue}) async {
    final result = await showDialog<_TaskDialogResult>(
      context: context,
      builder: (_) => _TaskEditDialog(
        isEdit: task != null,
        initialTitle: task?.title ?? '',
        initialDue: task?.dueDate ?? initialDue ?? DateTime.now(),
        initialDone: task?.isDone ?? false,
      ),
    );
    if (result == null || !mounted) return;

    if (task == null) {
      if (result.action == _TaskDialogAction.save &&
          result.title.trim().isNotEmpty) {
        widget.onCreateTask?.call(result.title.trim(), result.due);
      }
    } else if (result.action == _TaskDialogAction.delete) {
      widget.onDeleteTask?.call(task);
    } else {
      final title = result.title.trim();
      if (title.isNotEmpty) task.title = title;
      task.dueDate = result.due;
      task.hasExplicitTime = true;
      task.isDone = result.isDone;
      widget.onTaskChanged?.call();
    }
    if (mounted) setState(() {});
  }

  Widget _buildTaskChip(ThemeData theme, Task task) {
    return Material(
      color: task.isDone
          ? theme.colorScheme.surfaceVariant
          : theme.colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _openTaskEditor(task: task),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
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

/// Paints the continuous time ruler: the left gutter ticks + time/date labels
/// and the faint gridlines that extend across the body. Each mark level's
/// opacity comes from how far apart its marks currently sit, which produces the
/// smooth fade as the user zooms.
class _TimeAxisPainter extends CustomPainter {
  _TimeAxisPainter({
    required this.levels,
    required this.pixelsPerMinute,
    required this.topMinute,
    required this.nowMinute,
    required this.base,
    required this.months,
    required this.onSurface,
    required this.surface,
    required this.primary,
    required this.nowColor,
  });

  final List<_MarkLevel> levels;
  final double pixelsPerMinute;
  final double topMinute;
  final double nowMinute;
  final DateTime base;
  final List<String> months;
  final Color onSurface;
  final Color surface;
  final Color primary;
  final Color nowColor;

  /// Width of the left gutter that holds the time / date labels and ticks.
  static const double gutterWidth = 56;

  /// Labels need a little more breathing room than bare tick lines.
  static const double _labelMinSpacingPx = 30;

  double _yForMinute(num minute) => (minute - topMinute) * pixelsPerMinute;

  double _levelOpacity(_MarkLevel level) => markLevelOpacity(
        intervalMinutes: level.intervalMinutes.toDouble(),
        pixelsPerMinute: pixelsPerMinute,
        alwaysVisible: level.alwaysVisible,
      );

  /// True when [minute] is also a mark of any coarser (earlier) level, so it
  /// shouldn't be drawn twice.
  bool _coveredByCoarser(int minute, int levelIndex) {
    for (var i = 0; i < levelIndex; i++) {
      if (minute % levels[i].intervalMinutes == 0) return true;
    }
    return false;
  }

  String _labelFor(_MarkLevel level, int minute) {
    if (level.intervalMinutes >= 1440) {
      final d = base.add(Duration(minutes: minute));
      return '${d.day} ${months[d.month - 1]}';
    }
    final wrapped = ((minute % 1440) + 1440) % 1440;
    final h = (wrapped ~/ 60).toString().padLeft(2, '0');
    final m = (wrapped % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = surface);

    // Coarsest to finest so finer ticks/labels render on top of coarser ones.
    for (var levelIndex = 0; levelIndex < levels.length; levelIndex++) {
      final level = levels[levelIndex];
      final opacity = _levelOpacity(level);
      if (opacity <= 0) continue;

      final interval = level.intervalMinutes;
      final isDay = interval >= 1440;
      final tickPaint = Paint()
        ..color = (isDay ? primary : onSurface).withOpacity(opacity)
        ..strokeWidth = isDay ? 1.5 : 1;
      final gridPaint = Paint()
        ..color = (isDay ? primary : onSurface)
            .withOpacity(opacity * (isDay ? 0.35 : 0.12))
        ..strokeWidth = isDay ? 1.2 : 1;

      final showLabel =
          interval * pixelsPerMinute >= _labelMinSpacingPx && opacity > 0.05;
      final labelColor = (isDay ? primary : onSurface).withOpacity(opacity);

      // First mark at or after the top of the viewport.
      final firstMark = (topMinute / interval).ceil() * interval;
      for (var minute = firstMark;; minute += interval) {
        final y = _yForMinute(minute);
        if (y > size.height) break;
        if (_coveredByCoarser(minute, levelIndex)) continue;

        canvas.drawLine(Offset(gutterWidth, y), Offset(size.width, y), gridPaint);
        canvas.drawLine(
          Offset(gutterWidth - level.tickLength, y),
          Offset(gutterWidth, y),
          tickPaint,
        );
        if (showLabel) {
          _paintLabel(canvas, _labelFor(level, minute), y, labelColor,
              bold: isDay);
        }
      }
    }

    // Vertical divider between the gutter and the body.
    canvas.drawLine(
      Offset(gutterWidth, 0),
      Offset(gutterWidth, size.height),
      Paint()
        ..color = onSurface.withOpacity(0.25)
        ..strokeWidth = 1,
    );

    _paintNowLine(canvas, size);
  }

  void _paintLabel(Canvas canvas, String text, double y, Color color,
      {bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: gutterWidth - 6);
    painter.paint(canvas, Offset(4, y - painter.height / 2));
  }

  void _paintNowLine(Canvas canvas, Size size) {
    final y = _yForMinute(nowMinute);
    if (y < 0 || y > size.height) return;
    canvas.drawLine(
      Offset(gutterWidth, y),
      Offset(size.width, y),
      Paint()
        ..color = nowColor.withOpacity(0.8)
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(Offset(gutterWidth, y), 3, Paint()..color = nowColor);
  }

  @override
  bool shouldRepaint(_TimeAxisPainter old) =>
      old.pixelsPerMinute != pixelsPerMinute ||
      old.topMinute != topMinute ||
      old.nowMinute != nowMinute ||
      old.onSurface != onSurface ||
      old.surface != surface ||
      old.primary != primary ||
      old.nowColor != nowColor;
}

/// What the user chose in the create/edit task dialog.
enum _TaskDialogAction { save, delete }

class _TaskDialogResult {
  const _TaskDialogResult(
    this.action, {
    this.title = '',
    required this.due,
    this.isDone = false,
  });

  final _TaskDialogAction action;
  final String title;
  final DateTime due;
  final bool isDone;
}

/// Shared dialog to create a task (with a preset deadline) or edit an existing
/// one. Lets the user set the title, the deadline date and time, and (when
/// editing) the done state, plus delete.
class _TaskEditDialog extends StatefulWidget {
  const _TaskEditDialog({
    required this.isEdit,
    required this.initialTitle,
    required this.initialDue,
    required this.initialDone,
  });

  final bool isEdit;
  final String initialTitle;
  final DateTime initialDue;
  final bool initialDone;

  @override
  State<_TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<_TaskEditDialog> {
  late final TextEditingController _titleController;
  late DateTime _due;
  late bool _done;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _due = widget.initialDue;
    _done = widget.initialDone;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _due =
          DateTime(picked.year, picked.month, picked.day, _due.hour, _due.minute));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due),
    );
    if (picked != null) {
      setState(() => _due = DateTime(
          _due.year, _due.month, _due.day, picked.hour, picked.minute));
    }
  }

  String get _dateLabel {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${_due.year}-${two(_due.month)}-${two(_due.day)}';
  }

  String get _timeLabel {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(_due.hour)}:${two(_due.minute)}';
  }

  void _save() {
    Navigator.of(context).pop(
      _TaskDialogResult(
        _TaskDialogAction.save,
        title: _titleController.text,
        due: _due,
        isDone: _done,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.isEdit ? 'Edit task' : 'New task'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            autofocus: !widget.isEdit,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Title'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(_dateLabel),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_timeLabel),
              ),
            ],
          ),
          if (widget.isEdit)
            CheckboxListTile(
              value: _done,
              onChanged: (v) => setState(() => _done = v ?? false),
              title: const Text('Done'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ),
      actions: [
        if (widget.isEdit)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              _TaskDialogResult(_TaskDialogAction.delete, due: _due),
            ),
            child: Text(
              'Delete',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
