import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/task.dart';
import '../services/alarm_sound.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import 'subpage_app_bar.dart';

/// Angle of [point] around [center] in radians, measured clockwise from
/// 12 o'clock, normalized to `[0, 2π)`.
double dialAngle(Offset center, Offset point) {
  final angle = math.atan2(point.dx - center.dx, center.dy - point.dy);
  return angle < 0 ? angle + 2 * math.pi : angle;
}

/// Signed shortest way around the dial from [from] to [to], in radians
/// (positive = clockwise). Keeps a drag continuous when the finger crosses
/// the 12 o'clock boundary instead of jumping a full turn.
double dialAngleDelta(double from, double to) {
  var delta = to - from;
  while (delta > math.pi) {
    delta -= 2 * math.pi;
  }
  while (delta < -math.pi) {
    delta += 2 * math.pi;
  }
  return delta;
}

/// The dice timer's states: winding the dial, counting down, paused, and
/// ringing at zero.
enum DiceTimerPhase { setting, running, paused, ringing }

/// Holds the dice timer's live state so it survives leaving and re-entering
/// [DiceTimerPage]: the ticker runs here, in a singleton, not in the page's
/// [State]. The page is a thin view that listens for changes and forwards the
/// user's dial and button input, so navigating away leaves the countdown
/// running and reopening reattaches to it.
class DiceTimerController extends ChangeNotifier {
  DiceTimerController._();

  /// Shared instance driving whichever [DiceTimerPage] is (or was) open.
  static final DiceTimerController instance = DiceTimerController._();

  /// Where the dial sits when a fresh timer opens; turn back for less time.
  static const Duration defaultDuration = Duration(minutes: 20);

  Task? _task;
  DiceTimerPhase _phase = DiceTimerPhase.setting;
  Duration _remaining = defaultDuration;
  Duration _total = defaultDuration;
  DateTime? _endAt;
  Timer? _ticker;

  /// Overridable ring side-effect (for tests); defaults to playing the alarm
  /// melody and posting a notification.
  Future<void> Function(Task task)? onRingAlert;

  Task? get task => _task;
  DiceTimerPhase get phase => _phase;
  Duration get remaining => _remaining;
  DateTime? get endAt => _endAt;

  /// True once a countdown has begun (running, paused or ringing) — i.e. there
  /// is a live timer to return to, versus an untouched dial.
  bool get isActive => _task != null && _phase != DiceTimerPhase.setting;

  /// Whole-percent of the started duration still left on the countdown.
  int get percentLeft {
    final total = _total.inSeconds;
    if (total <= 0) return 0;
    return (_remaining.inSeconds / total * 100).clamp(0, 100).round();
  }

  /// Points the dial at [task] at the default duration. Re-configuring the
  /// same already-running task is a no-op, so reopening the page keeps the
  /// countdown going; configuring a different task discards the old timer.
  ///
  /// Called from the page's `initState` (i.e. during a build), so it must not
  /// `notifyListeners` — the page rebuilds itself right after and no listener
  /// observes an `isActive` change here (a fresh timer stays in `setting`).
  void configure(Task task) {
    if (isActive && identical(_task, task)) return;
    _ticker?.cancel();
    _ticker = null;
    _task = task;
    _phase = DiceTimerPhase.setting;
    _remaining = defaultDuration;
    _total = defaultDuration;
    _endAt = null;
  }

  /// Live dial adjustment while setting.
  void setRemaining(Duration value) {
    _remaining = value;
    notifyListeners();
  }

  /// Grabbing the dial pauses a running countdown (and silences a ring) so it
  /// can be rewound; whole-minute snapping mirrors the dial's numbers.
  void grabDial() {
    _ticker?.cancel();
    _ticker = null;
    if (_phase == DiceTimerPhase.ringing) AlarmSound.stop();
    if (_phase != DiceTimerPhase.setting) {
      _phase = DiceTimerPhase.setting;
      _endAt = null;
      _remaining = Duration(minutes: (_remaining.inSeconds / 60).ceil());
      notifyListeners();
    }
  }

  /// Releasing the dial starts the countdown from the wound-up duration.
  void releaseDial() {
    if (_remaining > Duration.zero) _run(resetTotal: true);
  }

  /// Pause a running countdown, freezing the time left.
  void pause() {
    if (_phase != DiceTimerPhase.running) return;
    _ticker?.cancel();
    _ticker = null;
    _phase = DiceTimerPhase.paused;
    _endAt = null;
    notifyListeners();
    LogService.add('DiceTimerController.pause', 'Paused "${_task?.title}"');
  }

  /// Resume from a pause, keeping the original total so the percentage carries
  /// on where it left off.
  void resume() {
    if (_phase != DiceTimerPhase.paused) return;
    _run(resetTotal: false);
  }

  /// Stop the ring and give the countdown [extra] more time.
  void addTime(Duration extra) {
    AlarmSound.stop();
    _remaining += extra;
    _run(resetTotal: true);
  }

  void _run({required bool resetTotal}) {
    if (_remaining <= Duration.zero) return;
    _ticker?.cancel();
    _phase = DiceTimerPhase.running;
    if (resetTotal) _total = _remaining;
    _endAt = DateTime.now().add(_remaining);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    notifyListeners();
    LogService.add('DiceTimerController._run',
        'Running ${_remaining.inSeconds}s for "${_task?.title}"');
  }

  void _tick() {
    _remaining -= const Duration(seconds: 1);
    if (_remaining <= Duration.zero) {
      _remaining = Duration.zero;
      _ring();
    }
    notifyListeners();
  }

  /// Reached zero: stop ticking and start the alert. Not awaited — ringing
  /// must never block the UI, and both default alert paths swallow errors.
  void _ring() {
    _ticker?.cancel();
    _ticker = null;
    _phase = DiceTimerPhase.ringing;
    (onRingAlert ?? _defaultRingAlert)(_task!);
    LogService.add(
        'DiceTimerController._ring', 'Timer hit zero for "${_task?.title}"');
  }

  /// Dismiss the timer entirely (Done / postponed / abandoned): stop the
  /// ticker and melody and forget the task.
  void clear() {
    _ticker?.cancel();
    _ticker = null;
    AlarmSound.stop();
    _task = null;
    _phase = DiceTimerPhase.setting;
    _remaining = defaultDuration;
    _total = defaultDuration;
    _endAt = null;
    notifyListeners();
  }

  /// Reset to a pristine state between tests (no notification, no melody).
  @visibleForTesting
  void resetForTest() {
    _ticker?.cancel();
    _ticker = null;
    onRingAlert = null;
    _task = null;
    _phase = DiceTimerPhase.setting;
    _remaining = defaultDuration;
    _total = defaultDuration;
    _endAt = null;
  }

  static Future<void> _defaultRingAlert(Task task) async {
    await AlarmSound.play(melody: 'Classic', volume: 0.8, loop: true);
    try {
      await NotificationService.showTaskNotification(
        'Time is up: ${task.title}',
        delaySeconds: 0,
      );
    } catch (_) {
      // Notifications are best-effort (no plugin host on desktop/tests).
    }
  }
}

/// Egg-timer page for a randomly rolled task: the rotary dial opens pre-wound
/// to 20 minutes — turn it back for less time (or on past 20 for more), let go
/// and the countdown starts (showing the wall-clock end time and the
/// percentage of time left). At zero an alarm rings and the task can be
/// confirmed done, postponed to tomorrow, or given some extra time.
class DiceTimerPage extends StatefulWidget {
  /// The task the dice landed on.
  final Task task;

  /// Called when the user confirms the task is done at (or after) the ring.
  final VoidCallback onTaskDone;

  /// Called when the user postpones the task to tomorrow at the ring.
  final VoidCallback onTaskPostponed;

  /// Overridable ring side-effect (for tests); defaults to playing the alarm
  /// melody and posting a notification.
  final Future<void> Function(Task task)? onRingAlert;

  const DiceTimerPage({
    Key? key,
    required this.task,
    required this.onTaskDone,
    required this.onTaskPostponed,
    this.onRingAlert,
  }) : super(key: key);

  @override
  State<DiceTimerPage> createState() => _DiceTimerPageState();
}

class _DiceTimerPageState extends State<DiceTimerPage> {
  /// One full turn of the dial, like a kitchen egg timer.
  static const int _maxMinutes = 60;

  DiceTimerController get _controller => DiceTimerController.instance;

  @override
  void initState() {
    super.initState();
    if (widget.onRingAlert != null) {
      _controller.onRingAlert = widget.onRingAlert;
    }
    _controller.configure(widget.task);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    // Leaving the page keeps a running or paused timer alive so it can be
    // reopened later; only a mid-ring exit silences the melody (the expired
    // state is kept, so returning still shows the finish actions).
    if (_controller.phase == DiceTimerPhase.ringing) AlarmSound.stop();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  /// Dismiss the timer (via a Done/Postpone action) and return to the caller.
  void _finish(VoidCallback callback) {
    callback();
    _controller.clear();
    Navigator.of(context).pop();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  String _formatRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '$m:${_two(s)}';
  }

  Widget _dialCenter(BuildContext context) {
    final theme = Theme.of(context);
    switch (_controller.phase) {
      case DiceTimerPhase.setting:
        if (_controller.remaining == Duration.zero) {
          return Text(
            'Turn me',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          );
        }
        return Text(
          '${_controller.remaining.inMinutes} min',
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        );
      case DiceTimerPhase.running:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatRemaining(_controller.remaining),
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${_controller.percentLeft}% left',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        );
      case DiceTimerPhase.paused:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatRemaining(_controller.remaining),
              style: theme.textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Paused',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );
      case DiceTimerPhase.ringing:
        return Text(
          "Time's up!",
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.bold,
          ),
        );
    }
  }

  Widget _statusLine(BuildContext context) {
    final theme = Theme.of(context);
    switch (_controller.phase) {
      case DiceTimerPhase.setting:
        return Text(
          'Turn the dial back for less time, then let go to start.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        );
      case DiceTimerPhase.running:
        return Text(
          'Ends at ${_formatClock(_controller.endAt!)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        );
      case DiceTimerPhase.paused:
        return Text(
          'Paused — resume when you are ready.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        );
      case DiceTimerPhase.ringing:
        return Text(
          'Did you finish this task?',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        );
    }
  }

  /// Buttons under the dial; nothing while still winding. Running offers an
  /// early Done and a Pause; paused offers Resume and Done; the ring offers
  /// the finish/postpone/extend actions.
  Widget _actions() {
    switch (_controller.phase) {
      case DiceTimerPhase.setting:
        return const SizedBox.shrink();
      case DiceTimerPhase.running:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Done'),
              onPressed: () => _finish(widget.onTaskDone),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.pause),
              label: const Text('Pause'),
              onPressed: _controller.pause,
            ),
          ],
        );
      case DiceTimerPhase.paused:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Resume'),
              onPressed: _controller.resume,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Done'),
              onPressed: () => _finish(widget.onTaskDone),
            ),
          ],
        );
      case DiceTimerPhase.ringing:
        return _ringActions();
    }
  }

  Widget _ringActions() {
    Widget addButton(int minutes) => OutlinedButton(
          onPressed: () => _controller.addTime(Duration(minutes: minutes)),
          child: Text('+$minutes min'),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Done'),
          onPressed: () => _finish(widget.onTaskDone),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.update),
          label: const Text('Postpone to tomorrow'),
          onPressed: () => _finish(widget.onTaskPostponed),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            addButton(1),
            const SizedBox(width: 8),
            addButton(5),
            const SizedBox(width: 8),
            addButton(10),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: buildSubpageAppBar(context, title: 'Dice timer'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.casino, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('The dice picked', style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.task.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 24),
              SizedBox.square(
                dimension: 280,
                child: DiceTimerDial(
                  value: _controller.remaining,
                  maxMinutes: _maxMinutes,
                  onDragStart: _controller.grabDial,
                  onChanged: _controller.setRemaining,
                  onDragEnd: _controller.releaseDial,
                  center: _dialCenter(context),
                ),
              ),
              const SizedBox(height: 24),
              _statusLine(context),
              if (_controller.phase != DiceTimerPhase.setting) ...[
                const SizedBox(height: 24),
                _actions(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A rotary egg-timer dial: drag around the face to wind it up. Reports whole
/// minutes while winding via [onChanged]; [onDragStart] / [onDragEnd] bracket
/// every grab so the owner can pause and (re)start the countdown.
class DiceTimerDial extends StatefulWidget {
  final Duration value;
  final int maxMinutes;
  final ValueChanged<Duration> onChanged;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final Widget? center;

  const DiceTimerDial({
    Key? key,
    required this.value,
    required this.onChanged,
    required this.onDragStart,
    required this.onDragEnd,
    this.maxMinutes = 60,
    this.center,
  }) : super(key: key);

  @override
  State<DiceTimerDial> createState() => _DiceTimerDialState();
}

class _DiceTimerDialState extends State<DiceTimerDial> {
  /// Continuous wound-up minutes during a drag; fractional so slow drags
  /// accumulate, reported rounded to whole minutes.
  double _minutes = 0;
  double? _lastAngle;
  int? _pointer;
  Size _size = Size.zero;

  void _handleStart(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _minutes = widget.value.inSeconds / 60.0;
    _lastAngle = dialAngle(_size.center(Offset.zero), event.localPosition);
    widget.onDragStart();
  }

  void _handleUpdate(PointerMoveEvent event) {
    final last = _lastAngle;
    if (last == null || event.pointer != _pointer) return;
    final angle = dialAngle(_size.center(Offset.zero), event.localPosition);
    _lastAngle = angle;
    final deltaMinutes =
        dialAngleDelta(last, angle) / (2 * math.pi) * widget.maxMinutes;
    _minutes = (_minutes + deltaMinutes)
        .clamp(0.0, widget.maxMinutes.toDouble())
        .toDouble();
    widget.onChanged(Duration(minutes: _minutes.round()));
  }

  void _handleEnd(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _lastAngle = null;
    widget.onDragEnd();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dimension = math.min(constraints.maxWidth, constraints.maxHeight);
        _size = Size.square(dimension);
        final fraction = (widget.value.inSeconds / 60.0 / widget.maxMinutes)
            .clamp(0.0, 1.0)
            .toDouble();
        // Raw pointer events instead of a pan recognizer: the dial must keep
        // winding even when an ancestor scrollable would win a (mostly
        // vertical) drag in the gesture arena.
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handleStart,
          onPointerMove: _handleUpdate,
          onPointerUp: _handleEnd,
          onPointerCancel: _handleEnd,
          child: CustomPaint(
            painter: _DialPainter(
              fraction: fraction,
              wedgeColor: scheme.primary,
              faceColor: scheme.surfaceContainerHighest,
              innerColor: scheme.surface,
              tickColor: scheme.onSurfaceVariant,
            ),
            child: SizedBox.square(
              dimension: dimension,
              child: Center(child: widget.center),
            ),
          ),
        );
      },
    );
  }
}

class _DialPainter extends CustomPainter {
  final double fraction;
  final Color wedgeColor;
  final Color faceColor;
  final Color innerColor;
  final Color tickColor;

  const _DialPainter({
    required this.fraction,
    required this.wedgeColor,
    required this.faceColor,
    required this.innerColor,
    required this.tickColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    canvas.drawCircle(center, radius, Paint()..color = faceColor);

    // Wound-up wedge from 12 o'clock clockwise — the classic egg-timer look.
    if (fraction > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 4),
        -math.pi / 2,
        2 * math.pi * fraction,
        true,
        Paint()..color = wedgeColor.withAlpha(70),
      );
    }

    // Minute ticks, longer every 5 minutes.
    for (var i = 0; i < 60; i++) {
      final major = i % 5 == 0;
      final angle = i / 60 * 2 * math.pi - math.pi / 2;
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + dir * (radius - (major ? 16 : 10)),
        center + dir * (radius - 4),
        Paint()
          ..color = tickColor
          ..strokeWidth = major ? 2.5 : 1.0
          ..strokeCap = StrokeCap.round,
      );
    }

    // Inner disc keeps the center label readable over the wedge.
    canvas.drawCircle(center, radius * 0.55, Paint()..color = innerColor);

    // Pointer from the inner disc to the rim at the wound position.
    final pointerAngle = 2 * math.pi * fraction - math.pi / 2;
    final dir = Offset(math.cos(pointerAngle), math.sin(pointerAngle));
    canvas.drawLine(
      center + dir * (radius * 0.55),
      center + dir * (radius - 6),
      Paint()
        ..color = wedgeColor
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center + dir * (radius - 6), 7, Paint()..color = wedgeColor);
  }

  @override
  bool shouldRepaint(_DialPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.wedgeColor != wedgeColor ||
      oldDelegate.faceColor != faceColor ||
      oldDelegate.innerColor != innerColor ||
      oldDelegate.tickColor != tickColor;
}
