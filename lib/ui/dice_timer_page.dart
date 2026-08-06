import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/task.dart';
import '../services/alarm_ids.dart';
import '../services/alarm_sound.dart';
import '../services/alarm_vibration.dart';
import '../services/log_service.dart';
import '../services/notification_service.dart';
import 'dice_timer_settings.dart';
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

/// Which alert channels fire when the countdown hits zero — the settings
/// (`Config.diceTimerAlertMode` + `Config.diceTimerAlsoVibrate`) resolved into
/// the three things the ring can actually do.
class DiceAlertPlan {
  /// Play `Config.diceTimerMelody` at `Config.diceTimerVolume`, looping.
  final bool melody;

  /// Buzz the repeating vibration pattern.
  final bool vibrate;

  /// Post a "Time is up" notification. Silently does nothing when
  /// notifications are switched off in Settings.
  final bool notification;

  const DiceAlertPlan({
    required this.melody,
    required this.vibrate,
    required this.notification,
  });

  /// True when the ring makes no noise at all and the dial simply reads 0:00.
  bool get isSilent => !melody && !vibrate && !notification;
}

/// Resolves the dice timer's alert settings into a [DiceAlertPlan]. Pure, so
/// the routing is testable without a platform underneath.
///
/// `notification` is the default, and it needs the app's notifications to be
/// on: with them switched off the ring degrades to complete silence (the dial
/// just shows 0:00) instead of falling back to a sound nobody asked for.
DiceAlertPlan diceAlertPlan({
  String? mode,
  bool? alsoVibrate,
  bool? notificationsEnabled,
}) {
  final resolved = mode ?? Config.diceTimerAlertMode;
  final extraBuzz = alsoVibrate ?? Config.diceTimerAlsoVibrate;
  final canNotify = notificationsEnabled ?? Config.enableNotifications;
  switch (resolved) {
    case 'melody':
      return DiceAlertPlan(
          melody: true, vibrate: extraBuzz, notification: canNotify);
    case 'vibrate':
      return const DiceAlertPlan(
          melody: false, vibrate: true, notification: false);
    case 'silent':
      return const DiceAlertPlan(
          melody: false, vibrate: false, notification: false);
    case 'notification':
    default:
      return DiceAlertPlan(
          melody: false, vibrate: extraBuzz, notification: canNotify);
  }
}

/// What should happen to the OS-scheduled ring: [arm] it (the countdown is
/// running with the app away, so only the OS can deliver zero), [cancel] it
/// (the app is back and rings in-app, or there is nothing left to ring), or
/// [leave] it alone (it is ringing right now — only answering it clears it).
enum DiceOsAlarmAction { arm, cancel, leave }

/// The arming rule, kept pure so it can be read and tested on its own.
DiceOsAlarmAction diceOsAlarmAction({
  required DiceTimerPhase phase,
  required bool appResumed,
  required bool alertSilent,
}) {
  if (phase == DiceTimerPhase.ringing) return DiceOsAlarmAction.leave;
  if (phase == DiceTimerPhase.running && !appResumed && !alertSilent) {
    return DiceOsAlarmAction.arm;
  }
  return DiceOsAlarmAction.cancel;
}

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
  /// Configurable in Settings → Dice timer (20 minutes out of the box).
  static Duration get defaultDuration =>
      Duration(minutes: Config.diceTimerDefaultMinutes.clamp(1, 60));

  Task? _task;
  DiceTimerPhase _phase = DiceTimerPhase.setting;
  Duration _remaining = defaultDuration;
  Duration _total = defaultDuration;
  DateTime? _endAt;
  Timer? _ticker;

  /// True while the app is in the foreground. While it is, the ring is
  /// presented in-app; while it is not, the OS-scheduled alarm has to do it.
  bool _appResumed = true;

  /// True while [DiceTimerPage] is the page on screen — then zero rings on the
  /// dial itself (with the Done / Postpone / +min actions) instead of taking
  /// over the screen.
  bool _pageVisible = false;

  /// Observes app lifecycle while a countdown is live, so backgrounding the
  /// app hands the ring over to the OS alarm and returning takes it back.
  _DiceLifecycleWatcher? _lifecycle;

  /// Overridable ring side-effect (for tests); defaults to playing the alarm
  /// melody and posting a notification.
  Future<void> Function(Task task)? onRingAlert;

  /// Presents the full-screen alarm screen for [payload] — set by the app
  /// shell (`main.dart`) to the same presenter real alarms use, so a timer
  /// that runs out while the user is elsewhere in the app takes over the
  /// screen exactly like a ringing alarm. Null in tests.
  static void Function(Map<String, dynamic> payload)? presentFullScreenRing;

  Task? get task => _task;
  DiceTimerPhase get phase => _phase;
  Duration get remaining => _remaining;
  DateTime? get endAt => _endAt;

  /// True once a countdown has begun (running, paused or ringing) — i.e. there
  /// is a live timer to return to, versus an untouched dial.
  bool get isActive => _task != null && _phase != DiceTimerPhase.setting;

  /// True while [DiceTimerPage] is in the navigation stack — so a caller
  /// returning from the alarm screen doesn't push a second copy of it.
  bool get isPageVisible => _pageVisible;

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
    if (_phase == DiceTimerPhase.ringing) stopAlert();
    if (_phase != DiceTimerPhase.setting) {
      NotificationService.cancelDiceTimerAlarm();
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
    _syncOsAlarm();
    notifyListeners();
    LogService.add('DiceTimerController.pause', 'Paused "${_task?.title}"');
  }

  /// Resume from a pause, keeping the original total so the percentage carries
  /// on where it left off.
  void resume() {
    if (_phase != DiceTimerPhase.paused) return;
    _run(resetTotal: false);
  }

  /// Silences whichever alert channels the ring started (melody, vibration —
  /// a posted notification is dismissed by the user, like any other).
  void stopAlert() {
    AlarmSound.stop();
    AlarmVibration.stop();
  }

  /// Called by [DiceTimerPage] while it is on screen, and by the lifecycle
  /// watcher when the app comes and goes. Both decide who owns the ring: the
  /// page, the app, or the OS alarm.
  void setPageVisible(bool visible) {
    _pageVisible = visible;
  }

  void _setAppResumed(bool resumed) {
    if (_appResumed == resumed) return;
    _appResumed = resumed;
    _syncOsAlarm();
  }

  /// Keeps the OS-scheduled ring in step with the countdown: armed while a
  /// countdown is running with the app away (so zero rings as a full-screen
  /// alarm even if the app was killed meanwhile), cancelled as soon as the app
  /// is back and can ring in-app, or the countdown is paused/rewound/finished.
  ///
  /// A ring that is already going is left alone — only answering it (Stop,
  /// Done, Postpone, +min) clears it.
  void _syncOsAlarm() {
    final plan = diceAlertPlan();
    final endAt = _endAt;
    final action = diceOsAlarmAction(
      phase: _phase,
      appResumed: _appResumed,
      alertSilent: plan.isSilent,
    );
    switch (action) {
      case DiceOsAlarmAction.leave:
        return;
      case DiceOsAlarmAction.arm:
        if (endAt == null) return;
        NotificationService.scheduleDiceTimerAlarm(
          fireAt: endAt,
          taskTitle: _task?.title ?? '',
          // A melody alert vibrates through the alarm notification as well —
          // that is what a ringing alarm feels like.
          vibrate: plan.vibrate || plan.melody,
          melody: plan.melody ? Config.diceTimerMelody : null,
          volume: plan.melody ? Config.diceTimerVolume : null,
        );
      case DiceOsAlarmAction.cancel:
        NotificationService.cancelDiceTimerAlarm();
    }
  }

  /// Stop the ring and give the countdown [extra] more time.
  void addTime(Duration extra) {
    stopAlert();
    NotificationService.cancelDiceTimerAlarm();
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
    _watchLifecycle();
    _ensureRingPermissions();
    _syncOsAlarm();
    notifyListeners();
    LogService.add('DiceTimerController._run',
        'Running ${_remaining.inSeconds}s for "${_task?.title}"');
  }

  /// Asks (once per app run, Android only) for the permissions the ring needs
  /// to reach the user with the app closed: notifications, exact alarms and a
  /// battery-optimization exemption. Skipped entirely in silent mode, which
  /// never leaves the app.
  static bool _ringPermissionsAsked = false;

  void _ensureRingPermissions() {
    if (_ringPermissionsAsked) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (diceAlertPlan().isSilent) return;
    _ringPermissionsAsked = true;
    NotificationService.ensureAlarmPermissions();
  }

  /// Starts (once) listening for the app going to the background, so the OS
  /// alarm can take the ring over. Guarded: a plain `test()` has no binding.
  void _watchLifecycle() {
    if (_lifecycle != null) return;
    try {
      final watcher = _DiceLifecycleWatcher(this);
      WidgetsBinding.instance.addObserver(watcher);
      _lifecycle = watcher;
      _appResumed = WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    } catch (_) {}
  }

  void _unwatchLifecycle() {
    final watcher = _lifecycle;
    if (watcher == null) return;
    _lifecycle = null;
    try {
      WidgetsBinding.instance.removeObserver(watcher);
    } catch (_) {}
  }

  void _tick() {
    _remaining -= const Duration(seconds: 1);
    if (_remaining <= Duration.zero) {
      _remaining = Duration.zero;
      _ring();
    }
    notifyListeners();
  }

  /// Reached zero: stop ticking and alert. Who alerts depends on where the
  /// user is — the page shows its own ring actions, anywhere else in the app
  /// gets the full-screen alarm screen, and with the app away the
  /// OS-scheduled alarm (armed by [_syncOsAlarm]) does it. Not awaited —
  /// ringing must never block the UI, and every path swallows its errors.
  void _ring() {
    _ticker?.cancel();
    _ticker = null;
    _phase = DiceTimerPhase.ringing;
    final override = onRingAlert;
    if (override != null) {
      override(_task!);
    } else if (_pageVisible && _appResumed) {
      _defaultRingAlert(_task!);
    } else if (_appResumed) {
      _ringFullScreen(_task!);
    }
    LogService.add(
        'DiceTimerController._ring', 'Timer hit zero for "${_task?.title}"');
  }

  /// The app is open but the user is somewhere else in it: take over the whole
  /// screen with the alarm screen (same one real alarms use, so Stop works the
  /// way it always does) and drop the OS alarm that would ring on top of it.
  void _ringFullScreen(Task task) {
    final plan = diceAlertPlan();
    // A silent alert (silent mode, or a notification alert with notifications
    // switched off) stays out of the way: the dial reads 0:00 and that is all.
    if (plan.isSilent) return;
    final present = presentFullScreenRing;
    if (present == null) return;
    NotificationService.cancelDiceTimerAlarm();
    if (plan.vibrate) AlarmVibration.start();
    present(diceRingPayload(
      task.title,
      melody: plan.melody ? Config.diceTimerMelody : null,
      volume: plan.melody ? Config.diceTimerVolume : null,
      vibrate: plan.vibrate,
    ));
  }

  /// Dismiss the timer entirely (Done / postponed / abandoned): stop the
  /// ticker and melody and forget the task.
  void clear() {
    _ticker?.cancel();
    _ticker = null;
    stopAlert();
    NotificationService.cancelDiceTimerAlarm();
    _unwatchLifecycle();
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
    _unwatchLifecycle();
    onRingAlert = null;
    presentFullScreenRing = null;
    _appResumed = true;
    _pageVisible = false;
    _task = null;
    _phase = DiceTimerPhase.setting;
    _remaining = defaultDuration;
    _total = defaultDuration;
    _endAt = null;
  }

  /// Alerts according to the user's dice timer settings: melody, vibration,
  /// notification, any combination of those — or nothing at all in silent
  /// mode, where the dial reading 0:00 is the whole alert.
  static Future<void> _defaultRingAlert(Task task) async {
    final plan = diceAlertPlan();
    if (plan.melody) {
      await AlarmSound.play(
        melody: Config.diceTimerMelody,
        volume: Config.diceTimerVolume,
        loop: true,
      );
    }
    if (plan.vibrate) await AlarmVibration.start();
    if (plan.notification) {
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
}

/// Tells [DiceTimerController] when the app leaves and re-enters the
/// foreground, which is what decides whether a ring can be presented in-app or
/// has to come from the OS-scheduled alarm.
class _DiceLifecycleWatcher extends WidgetsBindingObserver {
  final DiceTimerController controller;

  _DiceLifecycleWatcher(this.controller);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller._setAppResumed(state == AppLifecycleState.resumed);
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

  /// Line shown above the task title — "The dice picked" for a dice roll,
  /// "Timer for" when the timer is started from the task list.
  final String caption;

  /// Icon next to [caption] (the dice for a roll, a timer otherwise).
  final IconData captionIcon;

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
    this.caption = 'The dice picked',
    this.captionIcon = Icons.casino,
  }) : super(key: key);

  @override
  State<DiceTimerPage> createState() => _DiceTimerPageState();
}

class _DiceTimerPageState extends State<DiceTimerPage> {
  /// One full turn of the dial, like a kitchen egg timer.
  static const int _maxMinutes = 60;

  DiceTimerController get _controller => DiceTimerController.instance;

  /// While true a full-screen scrim swallows every touch (and the system back)
  /// so the timer can't be nudged — e.g. pocketed, or during an incoming call —
  /// leaving only the Unlock button live.
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    if (widget.onRingAlert != null) {
      _controller.onRingAlert = widget.onRingAlert;
    }
    _controller.configure(widget.task);
    // While this page is up the ring belongs to the dial (Done / Postpone /
    // +min); leaving it hands the ring to the alarm screen.
    _controller.setPageVisible(true);
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.setPageVisible(false);
    _controller.removeListener(_onControllerChanged);
    // Leaving the page keeps a running or paused timer alive so it can be
    // reopened later; only a mid-ring exit silences the melody (the expired
    // state is kept, so returning still shows the finish actions).
    if (_controller.phase == DiceTimerPhase.ringing) _controller.stopAlert();
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

  /// Throw the timer away without answering for the task: the countdown, any
  /// ring and the OS-scheduled alarm all go, and the task is left exactly as it
  /// was (not done, not postponed). Unlike leaving the page, nothing keeps
  /// running in the background.
  void _cancelTimer() {
    LogService.add(
        'DiceTimerPage._cancelTimer', 'Cancelled "${_controller.task?.title}"');
    _controller.clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Timer cancelled')));
    Navigator.of(context).pop();
  }

  /// The same settings as the Settings page's "Dice timer" card, reachable
  /// from the gear while the timer is on screen — the moment the alert is
  /// actually on the user's mind. Changes apply to the ring that follows,
  /// including one that is already ringing (rebuilt on close).
  Future<void> _openSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Dice timer settings',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const DiceTimerSettingsList(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
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
        // A silent alert has nothing but the dial to say it: show the clock at
        // zero instead of shouting.
        if (diceAlertPlan().isSilent) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '0:00',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                "Time's up",
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          );
        }
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

  Widget _doneButton({bool filled = true}) {
    final onPressed = () => _finish(widget.onTaskDone);
    const icon = Icon(Icons.check);
    const label = Text('Done');
    return filled
        ? FilledButton.icon(icon: icon, label: label, onPressed: onPressed)
        : OutlinedButton.icon(icon: icon, label: label, onPressed: onPressed);
  }

  /// Shown from the moment there is a countdown to throw away; the muted
  /// destructive styling keeps it clearly apart from Done/Postpone, which
  /// answer for the task.
  Widget _cancelButton(BuildContext context) => TextButton.icon(
        icon: const Icon(Icons.timer_off_outlined),
        label: const Text('Cancel timer'),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: _cancelTimer,
      );

  Widget _lockButton() => OutlinedButton.icon(
        icon: const Icon(Icons.lock_outline),
        label: const Text('Lock touch'),
        onPressed: () => setState(() => _locked = true),
      );

  /// Buttons under the dial. Done and Lock touch are available from the start
  /// (even before the countdown begins); running adds Pause, paused adds
  /// Resume, both add Cancel timer, and the ring swaps in the
  /// finish/postpone/extend actions.
  Widget _actions() {
    switch (_controller.phase) {
      case DiceTimerPhase.setting:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _doneButton(),
            const SizedBox(height: 12),
            _lockButton(),
          ],
        );
      case DiceTimerPhase.running:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _doneButton(),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.pause),
              label: const Text('Pause'),
              onPressed: _controller.pause,
            ),
            const SizedBox(height: 12),
            _lockButton(),
            const SizedBox(height: 4),
            _cancelButton(context),
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
            _doneButton(filled: false),
            const SizedBox(height: 12),
            _lockButton(),
            const SizedBox(height: 4),
            _cancelButton(context),
          ],
        );
      case DiceTimerPhase.ringing:
        return _ringActions();
    }
  }

  /// Full-screen scrim shown while [_locked]: absorbs everything below and
  /// offers only Unlock, so a stray touch (pocket, incoming call) can't disturb
  /// the timer.
  Widget _lockOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final live = _controller.phase == DiceTimerPhase.running ||
        _controller.phase == DiceTimerPhase.paused;
    return Material(
      color: Colors.black.withAlpha(200),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock, size: 48, color: Colors.white),
            const SizedBox(height: 12),
            const Text(
              'Screen locked',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            if (live) ...[
              const SizedBox(height: 8),
              Text(
                _formatRemaining(_controller.remaining),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
            const SizedBox(height: 28),
            FilledButton.icon(
              icon: const Icon(Icons.lock_open),
              label: const Text('Unlock'),
              onPressed: () => setState(() => _locked = false),
            ),
          ],
        ),
      ),
    );
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
        const SizedBox(height: 4),
        _cancelButton(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Dice timer',
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Timer settings',
            onPressed: _openSettingsSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.captionIcon, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(widget.caption, style: theme.textTheme.titleSmall),
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
              const SizedBox(height: 24),
              _actions(),
            ],
          ),
        ),
      ),
    );

    // Locking blocks the system back button too, so the timer can only be
    // reached through Unlock.
    return PopScope(
      canPop: !_locked,
      child: Stack(
        children: [
          AbsorbPointer(absorbing: _locked, child: page),
          if (_locked) Positioned.fill(child: _lockOverlay(context)),
        ],
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
