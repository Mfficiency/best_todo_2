import 'package:flutter/material.dart';

import '../models/weekly_hours_plan.dart';
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
/// This is a standalone template, not tied to actual calendar dates yet — a
/// future version overlays it on the user's Google Calendar.
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _service.load();
    if (!mounted) return;
    setState(() {
      _plan = _service.plan.value;
      _loading = false;
    });
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
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
        const SizedBox(height: 12),
        for (var i = 0; i < _plan.days.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _DayRow(
              weekday: WeeklyHoursPlan.weekdayNames[i],
              day: _plan.days[i],
              isFriday: i == _plan.days.length - 1,
              theoreticalEndMinutes:
                  i == _plan.days.length - 1 ? _plan.theoreticalFridayEndMinutes : null,
              onChanged: (day) => _onDayChanged(i, day),
              onDragEnd: _persist,
            ),
          ),
        const SizedBox(height: 8),
        Card(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.calendar_month_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Overlaying your Google Calendar on top of this plan is '
                    'coming in a future update.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

String _formatMinutesOfDay(int minutes) {
  final clamped = minutes.clamp(0, 24 * 60 - 1);
  return formatTimerTime(DateTime(2000, 1, 1, clamped ~/ 60, clamped % 60));
}

/// One weekday's horizontal timeline: a track spanning [_DayRow.trackStart]
/// to [_DayRow.trackEnd] with the morning and afternoon blocks drawn as
/// colored bars, four draggable handles at their ends, and (Friday only) a
/// dotted line marking [theoreticalEndMinutes].
class _DayRow extends StatefulWidget {
  final String weekday;
  final DayPlan day;
  final bool isFriday;
  final int? theoreticalEndMinutes;
  final ValueChanged<DayPlan> onChanged;
  final VoidCallback onDragEnd;

  const _DayRow({
    required this.weekday,
    required this.day,
    required this.isFriday,
    required this.theoreticalEndMinutes,
    required this.onChanged,
    required this.onDragEnd,
  });

  @override
  State<_DayRow> createState() => _DayRowState();
}

enum _Handle { morningStart, morningEnd, afternoonStart, afternoonEnd }

class _DayRowState extends State<_DayRow> {
  static const int trackStartMinutes = 6 * 60;
  static const int trackEndMinutes = 22 * 60;
  static const int minBlockMinutes = 30;
  static const int snapMinutes = 5;
  static const double trackHeight = 44;
  static const double handleWidth = 20;

  /// Unsnapped running value for the handle currently being dragged, in
  /// minutes since midnight. Null when nothing is being dragged.
  double? _dragValue;
  _Handle? _draggingHandle;

  double _minutesToX(int minutes, double width) {
    final span = trackEndMinutes - trackStartMinutes;
    final x = (minutes - trackStartMinutes) / span * width;
    return x.clamp(0.0, width);
  }

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

  void _onDragUpdate(_Handle handle, double deltaDx, double width) {
    if (_draggingHandle != handle || _dragValue == null) return;
    final span = trackEndMinutes - trackStartMinutes;
    final deltaMinutes = deltaDx / width * span;
    var next = _dragValue! + deltaMinutes;

    final morning = widget.day.morning;
    final afternoon = widget.day.afternoon;
    switch (handle) {
      case _Handle.morningStart:
        next = next.clamp(
          trackStartMinutes.toDouble(),
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
          trackEndMinutes.toDouble(),
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

  Widget _handle(_Handle handle, int minutes, double width) {
    final x = _minutesToX(minutes, width) - handleWidth / 2;
    return Positioned(
      left: x,
      top: 0,
      bottom: 0,
      width: handleWidth,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          key: ValueKey('handle-${widget.weekday}-${handle.name}'),
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => _onDragStart(handle),
          onHorizontalDragUpdate: (d) =>
              _onDragUpdate(handle, d.delta.dx, width),
          onHorizontalDragEnd: (_) => _onDragEnd(),
          child: Center(
            child: Container(
              width: 4,
              height: trackHeight - 8,
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

  Widget _block(ColorScheme scheme, double left, double right, Color color,
      String label) {
    final width = (right - left).clamp(0.0, double.infinity);
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: width,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: width > 60
            ? Text(
                label,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.clip,
                maxLines: 1,
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
    final worked =
        (morningEnd - morningStart) + (afternoonEnd - afternoonStart);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.weekday, style: theme.textTheme.titleSmall),
            ),
            Text(
              _formatDuration(worked),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.disabledColor),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              height: trackHeight,
              width: width,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  _block(
                    scheme,
                    _minutesToX(morningStart, width),
                    _minutesToX(morningEnd, width),
                    scheme.primary,
                    '${_formatMinutesOfDay(morningStart)}–${_formatMinutesOfDay(morningEnd)}',
                  ),
                  _block(
                    scheme,
                    _minutesToX(afternoonStart, width),
                    _minutesToX(afternoonEnd, width),
                    scheme.secondary,
                    '${_formatMinutesOfDay(afternoonStart)}–${_formatMinutesOfDay(afternoonEnd)}',
                  ),
                  if (widget.isFriday && widget.theoreticalEndMinutes != null)
                    _TheoreticalEndLine(
                      x: _minutesToX(widget.theoreticalEndMinutes!, width),
                      height: trackHeight,
                      label: _formatMinutesOfDay(widget.theoreticalEndMinutes!),
                      color: scheme.error,
                    ),
                  _handle(_Handle.morningStart, morningStart, width),
                  _handle(_Handle.morningEnd, morningEnd, width),
                  _handle(_Handle.afternoonStart, afternoonStart, width),
                  _handle(_Handle.afternoonEnd, afternoonEnd, width),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

/// The dotted vertical line on Friday showing the theoretical clock-out
/// time needed to keep the week at its 43-hour target, with a small time
/// label above the track.
class _TheoreticalEndLine extends StatelessWidget {
  final double x;
  final double height;
  final String label;
  final Color color;

  const _TheoreticalEndLine({
    required this.x,
    required this.height,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const labelWidth = 60.0;
    return Positioned(
      left: x - 1,
      top: -20,
      bottom: 0,
      child: SizedBox(
        width: 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -labelWidth / 2 + 1,
              top: 0,
              width: labelWidth,
              child: Text(
                label,
                key: const ValueKey('friday-theoretical-end-label'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            Positioned(
              top: 20,
              bottom: 0,
              child: CustomPaint(
                size: Size(2, height),
                painter: _DashedLinePainter(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dashHeight = 4.0;
    const gapHeight = 3.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(1, y), Offset(1, y + dashHeight), paint);
      y += dashHeight + gapHeight;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
