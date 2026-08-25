import 'package:flutter/material.dart';

import '../config.dart';
import '../models/gcal_event.dart';
import '../models/weekly_hours_plan.dart';
import '../services/google_calendar_service.dart';
import '../services/weekly_hours_service.dart';
import '../utils/date_time_format.dart';
import 'subpage_app_bar.dart';

/// Tools -> Weekly Hours Planner: a Monday-to-Friday template of two work
/// blocks per day (a fixed half-hour lunch break sits in whatever gap is
/// between them), each nominally totalling [WeeklyHoursPlan.targetMinutesPerDay]
/// (8:36) for a 43-hour week. Dragging a block's start or end away from that
/// default banks a surplus or deficit that Friday's dotted line shows as the
/// theoretical clock-out time needed to keep the week at 43 hours.
///
/// The five weekdays render as a vertical week grid — columns side by side,
/// time running top-to-bottom — sized to fill the available height so the
/// whole configured hour range (Settings → Weekly Hours Planner) is visible
/// without scrolling. A Google Calendar URL imported in Settings overlays
/// that day's real events, translucent, underneath the work blocks.
class WeeklyHoursPlannerPage extends StatefulWidget {
  const WeeklyHoursPlannerPage({Key? key}) : super(key: key);

  @override
  State<WeeklyHoursPlannerPage> createState() =>
      _WeeklyHoursPlannerPageState();
}

class _WeeklyHoursPlannerPageState extends State<WeeklyHoursPlannerPage> {
  final WeeklyHoursService _service = WeeklyHoursService.instance;
  late WeeklyHoursPlan _plan;
  bool _loading = true;

  List<GCalRawEvent> _gcalRaw = const [];
  String? _gcalError;

  @override
  void initState() {
    super.initState();
    _load();
    _loadGoogleCalendar();
  }

  Future<void> _load() async {
    await _service.load();
    if (!mounted) return;
    setState(() {
      _plan = _service.plan.value;
      _loading = false;
    });
  }

  Future<void> _loadGoogleCalendar() async {
    final cached = await GoogleCalendarService.loadCached();
    if (mounted && cached.isNotEmpty) setState(() => _gcalRaw = cached);
    final url = Config.googleCalendarUrl.trim();
    if (url.isEmpty) return;
    try {
      final fresh = await GoogleCalendarService.refresh(url);
      if (!mounted) return;
      setState(() {
        _gcalRaw = fresh;
        _gcalError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _gcalError = 'Could not refresh the imported calendar');
    }
  }

  /// Updates the in-memory plan immediately (so every day's block sizes and
  /// Friday's theoretical line react live while dragging); the file write
  /// only happens once the drag ends, via [_persist].
  void _onDayChanged(int index, DayPlan day) {
    setState(() => _plan = _plan.withDay(index, day));
  }

  Future<void> _persist() => _service.updatePlan(_plan);

  Future<void> _reset() async {
    setState(() => _plan = WeeklyHoursPlan.defaultPlan());
    await _persist();
  }

  /// Monday of the current calendar week, used only to resolve which real
  /// dates the Google Calendar overlay pulls events for — the plan itself
  /// stays a date-less Monday-to-Friday template.
  DateTime _mondayOfThisWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  /// Timed (non-all-day) Google Calendar events for the given weekday
  /// [index] (0 = Monday .. 4 = Friday) of the current week.
  List<GCalEvent> _gcalEventsForDay(int index) {
    if (_gcalRaw.isEmpty) return const [];
    final day = _mondayOfThisWeek().add(Duration(days: index));
    final dayEnd = day.add(const Duration(days: 1));
    return GoogleCalendarService.eventsInRange(_gcalRaw, day, dayEnd)
        .where((e) => !e.allDay)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Weekly Hours Planner',
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Reset to default week',
            onPressed: _loading ? null : _reset,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final planned = _plan.plannedWeeklyMinutes;
    final target = _plan.targetWeeklyMinutes;
    final diff = planned - target;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('This week', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatDuration(planned)} planned  ·  target '
                          '${_formatDuration(target)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  if (diff != 0)
                    Chip(
                      label: Text(
                        '${diff > 0 ? '+' : '-'}${_formatDuration(diff.abs())}',
                      ),
                      backgroundColor: diff > 0
                          ? theme.colorScheme.tertiaryContainer
                          : theme.colorScheme.errorContainer,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_gcalError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _gcalError!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildWeekGrid(theme),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekGrid(ThemeData theme) {
    final startHour = Config.weeklyHoursStartHour;
    final endHour = Config.weeklyHoursEndHour;
    final rangeMinutes = (endHour - startHour) * 60;

    return LayoutBuilder(
      builder: (context, constraints) {
        const headerHeight = 32.0;
        final trackHeight =
            (constraints.maxHeight - headerHeight).clamp(0.0, double.infinity);
        final pxPerMinute = rangeMinutes > 0 ? trackHeight / rangeMinutes : 0.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: headerHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(width: _gutterWidth),
                  for (var i = 0; i < _plan.days.length; i++)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            WeeklyHoursPlan.weekdayNames[i],
                            style: theme.textTheme.labelSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            _formatDuration(_plan.days[i].workedMinutes),
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.disabledColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _gutterWidth,
                    child: CustomPaint(
                      painter: _HourGutterPainter(
                        startHour: startHour,
                        endHour: endHour,
                        pxPerMinute: pxPerMinute,
                        color: theme.disabledColor,
                        use24Hour: Config.use24HourFormat,
                      ),
                    ),
                  ),
                  for (var i = 0; i < _plan.days.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: _DayColumn(
                          weekday: WeeklyHoursPlan.weekdayNames[i],
                          day: _plan.days[i],
                          isFriday: i == _plan.days.length - 1,
                          theoreticalEndMinutes:
                              i == _plan.days.length - 1
                                  ? _plan.theoreticalFridayEndMinutes
                                  : null,
                          startHour: startHour,
                          endHour: endHour,
                          pxPerMinute: pxPerMinute,
                          gcalEvents: _gcalEventsForDay(i),
                          onChanged: (day) => _onDayChanged(i, day),
                          onDragEnd: _persist,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

const double _gutterWidth = 28.0;

String _formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

String _formatMinutesOfDay(int minutes) {
  final clamped = minutes.clamp(0, 24 * 60 - 1);
  return formatTimerTime(DateTime(2000, 1, 1, clamped ~/ 60, clamped % 60));
}

/// One weekday's vertical timeline: a track spanning [startHour] to
/// [endHour] (top to bottom) with the morning and afternoon blocks drawn as
/// colored bars, four draggable handles at their top/bottom edges, any
/// imported Google Calendar events for the day rendered translucent behind
/// them, and (Friday only) a dashed horizontal line marking
/// [theoreticalEndMinutes].
class _DayColumn extends StatefulWidget {
  final String weekday;
  final DayPlan day;
  final bool isFriday;
  final int? theoreticalEndMinutes;
  final int startHour;
  final int endHour;
  final double pxPerMinute;
  final List<GCalEvent> gcalEvents;
  final ValueChanged<DayPlan> onChanged;
  final VoidCallback onDragEnd;

  const _DayColumn({
    required this.weekday,
    required this.day,
    required this.isFriday,
    required this.theoreticalEndMinutes,
    required this.startHour,
    required this.endHour,
    required this.pxPerMinute,
    required this.gcalEvents,
    required this.onChanged,
    required this.onDragEnd,
  });

  @override
  State<_DayColumn> createState() => _DayColumnState();
}

enum _Handle { morningStart, morningEnd, afternoonStart, afternoonEnd }

class _DayColumnState extends State<_DayColumn> {
  static const int minBlockMinutes = 30;
  static const int snapMinutes = 5;
  static const double handleTouchHeight = 22;

  /// Unsnapped running value for the handle currently being dragged, in
  /// minutes since midnight. Null when nothing is being dragged.
  double? _dragValue;
  _Handle? _draggingHandle;

  int get _trackStartMinutes => widget.startHour * 60;
  int get _trackEndMinutes => widget.endHour * 60;

  double _minutesToY(int minutes) =>
      (minutes - _trackStartMinutes) * widget.pxPerMinute;

  int _current(_Handle handle) {
    if (_draggingHandle == handle && _dragValue != null) {
      return _dragValue!.round();
    }
    switch (handle) {
      case _Handle.morningStart:
        return widget.day.morning.startMinutes;
      case _Handle.morningEnd:
        return widget.day.morning.endMinutes;
      case _Handle.afternoonStart:
        return widget.day.afternoon.startMinutes;
      case _Handle.afternoonEnd:
        return widget.day.afternoon.endMinutes;
    }
  }

  void _onDragStart(_Handle handle) {
    setState(() {
      _draggingHandle = handle;
      _dragValue = _current(handle).toDouble();
    });
  }

  void _onDragUpdate(_Handle handle, double deltaDy) {
    if (_draggingHandle != handle || _dragValue == null) return;
    if (widget.pxPerMinute <= 0) return;
    final deltaMinutes = deltaDy / widget.pxPerMinute;
    var next = _dragValue! + deltaMinutes;

    final morning = widget.day.morning;
    final afternoon = widget.day.afternoon;
    switch (handle) {
      case _Handle.morningStart:
        next = next.clamp(
          _trackStartMinutes.toDouble(),
          (morning.endMinutes - minBlockMinutes).toDouble(),
        );
        break;
      case _Handle.morningEnd:
        next = next.clamp(
          (morning.startMinutes + minBlockMinutes).toDouble(),
          afternoon.startMinutes.toDouble(),
        );
        break;
      case _Handle.afternoonStart:
        next = next.clamp(
          morning.endMinutes.toDouble(),
          (afternoon.endMinutes - minBlockMinutes).toDouble(),
        );
        break;
      case _Handle.afternoonEnd:
        next = next.clamp(
          (afternoon.startMinutes + minBlockMinutes).toDouble(),
          _trackEndMinutes.toDouble(),
        );
        break;
    }

    setState(() => _dragValue = next);

    final snapped = (next / snapMinutes).round() * snapMinutes;
    final updated = switch (handle) {
      _Handle.morningStart =>
        widget.day.copyWith(morning: morning.copyWith(startMinutes: snapped)),
      _Handle.morningEnd =>
        widget.day.copyWith(morning: morning.copyWith(endMinutes: snapped)),
      _Handle.afternoonStart => widget.day
          .copyWith(afternoon: afternoon.copyWith(startMinutes: snapped)),
      _Handle.afternoonEnd => widget.day
          .copyWith(afternoon: afternoon.copyWith(endMinutes: snapped)),
    };
    widget.onChanged(updated);
  }

  void _onDragEnd() {
    setState(() {
      _draggingHandle = null;
      _dragValue = null;
    });
    widget.onDragEnd();
  }

  Widget _handle(_Handle handle, int minutes) {
    final y = _minutesToY(minutes) - handleTouchHeight / 2;
    return Positioned(
      left: 0,
      right: 0,
      top: y,
      height: handleTouchHeight,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          key: ValueKey('handle-${widget.weekday}-${handle.name}'),
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (_) => _onDragStart(handle),
          onVerticalDragUpdate: (d) => _onDragUpdate(handle, d.delta.dy),
          onVerticalDragEnd: (_) => _onDragEnd(),
          child: Center(
            child: Container(
              height: 4,
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _block(
    double top,
    double bottom,
    Color color,
    Color onColor,
    String startLabel,
    String endLabel,
  ) {
    final height = (bottom - top).clamp(0.0, double.infinity);
    return Positioned(
      left: 1,
      right: 1,
      top: top,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: height > 28
            ? Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    startLabel,
                    style: TextStyle(
                      color: onColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    endLabel,
                    style: TextStyle(
                      color: onColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.center,
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _gcalBlock(ColorScheme scheme, GCalEvent event) {
    final top = _minutesToY(event.start.hour * 60 + event.start.minute)
        .clamp(0.0, double.infinity);
    final bottom = _minutesToY(event.end.hour * 60 + event.end.minute)
        .clamp(0.0, double.infinity);
    final height = (bottom - top).clamp(10.0, double.infinity);
    return Positioned(
      left: 1,
      right: 1,
      top: top,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer.withValues(alpha: 0.55),
          border: Border(left: BorderSide(width: 2, color: scheme.tertiary)),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.topCenter,
        child: height > 20
            ? Text(
                event.title,
                style: TextStyle(
                  color: scheme.onTertiaryContainer,
                  fontSize: 8,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final morningStart = _current(_Handle.morningStart);
    final morningEnd = _current(_Handle.morningEnd);
    final afternoonStart = _current(_Handle.afternoonStart);
    final afternoonEnd = _current(_Handle.afternoonEnd);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ColumnBackgroundPainter(
              startHour: widget.startHour,
              endHour: widget.endHour,
              pxPerMinute: widget.pxPerMinute,
              fillColor: scheme.surfaceContainerHighest,
              lineColor: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        for (final event in widget.gcalEvents) _gcalBlock(scheme, event),
        _block(
          _minutesToY(morningStart),
          _minutesToY(morningEnd),
          scheme.primary,
          scheme.onPrimary,
          _formatMinutesOfDay(morningStart),
          _formatMinutesOfDay(morningEnd),
        ),
        _block(
          _minutesToY(afternoonStart),
          _minutesToY(afternoonEnd),
          scheme.secondary,
          scheme.onSecondary,
          _formatMinutesOfDay(afternoonStart),
          _formatMinutesOfDay(afternoonEnd),
        ),
        if (widget.isFriday && widget.theoreticalEndMinutes != null)
          _TheoreticalEndLine(
            y: _minutesToY(widget.theoreticalEndMinutes!),
            label: _formatMinutesOfDay(widget.theoreticalEndMinutes!),
            color: scheme.error,
          ),
        _handle(_Handle.morningStart, morningStart),
        _handle(_Handle.morningEnd, morningEnd),
        _handle(_Handle.afternoonStart, afternoonStart),
        _handle(_Handle.afternoonEnd, afternoonEnd),
      ],
    );
  }
}

/// The dashed horizontal line on Friday showing the theoretical clock-out
/// time needed to keep the week at its 43-hour target, with a small time
/// label just beneath it.
class _TheoreticalEndLine extends StatelessWidget {
  final double y;
  final String label;
  final Color color;

  const _TheoreticalEndLine({
    required this.y,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: y - 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 2,
            child: CustomPaint(painter: _HorizontalDashedLinePainter(color: color)),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              label,
              key: const ValueKey('friday-theoretical-end-label'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalDashedLinePainter extends CustomPainter {
  final Color color;
  const _HorizontalDashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dashWidth = 4.0;
    const gapWidth = 3.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 1), Offset(x + dashWidth, 1), paint);
      x += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(covariant _HorizontalDashedLinePainter old) =>
      old.color != color;
}

/// Fills a day column's background and draws faint horizontal lines every
/// hour, aligned with [_HourGutterPainter]'s labels (both are driven by the
/// same [startHour]/[endHour]/[pxPerMinute]).
class _ColumnBackgroundPainter extends CustomPainter {
  final int startHour;
  final int endHour;
  final double pxPerMinute;
  final Color fillColor;
  final Color lineColor;

  const _ColumnBackgroundPainter({
    required this.startHour,
    required this.endHour,
    required this.pxPerMinute,
    required this.fillColor,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = fillColor,
    );
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var hour = startHour; hour <= endHour; hour++) {
      final y = (hour - startHour) * 60 * pxPerMinute;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ColumnBackgroundPainter old) =>
      old.startHour != startHour ||
      old.endHour != endHour ||
      old.pxPerMinute != pxPerMinute ||
      old.fillColor != fillColor ||
      old.lineColor != lineColor;
}

/// Paints the left gutter's hour labels, aligned with
/// [_ColumnBackgroundPainter]'s gridlines.
class _HourGutterPainter extends CustomPainter {
  final int startHour;
  final int endHour;
  final double pxPerMinute;
  final Color color;
  final bool use24Hour;

  const _HourGutterPainter({
    required this.startHour,
    required this.endHour,
    required this.pxPerMinute,
    required this.color,
    required this.use24Hour,
  });

  String _label(int hour) {
    if (use24Hour) return hour.toString().padLeft(2, '0');
    final period = hour < 12 ? 'a' : 'p';
    var h = hour % 12;
    if (h == 0) h = 12;
    return '$h$period';
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (var hour = startHour; hour <= endHour; hour++) {
      final y = (hour - startHour) * 60 * pxPerMinute;
      final painter = TextPainter(
        text: TextSpan(text: _label(hour), style: TextStyle(fontSize: 9, color: color)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      final labelY = (y - painter.height / 2).clamp(0.0, size.height - painter.height);
      painter.paint(canvas, Offset(2, labelY));
    }
  }

  @override
  bool shouldRepaint(covariant _HourGutterPainter old) =>
      old.startHour != startHour ||
      old.endHour != endHour ||
      old.pxPerMinute != pxPerMinute ||
      old.color != color ||
      old.use24Hour != use24Hour;
}
