import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/streak_kind.dart';
import '../services/streak_flame_display.dart';
import '../services/streak_service.dart';
import 'streak_page.dart';

/// The home app bar's flame. With more than one streak challenge switched on
/// it cycles through them — orange for finishing, green for creating, blue for
/// planning ahead — so a glance at the app bar shows all three colours (and a
/// grey flame for whatever is still open today). Tapping opens the streak page
/// on the challenge currently shown.
///
/// A challenge whose action has not happened yet today burns grey and outlined
/// no matter how long the streak is, and pulses towards white so the open day
/// catches the eye instead of blending into the app bar.
///
/// Once every active challenge is done for the day the cycling stops: the
/// button settles on one steady red flame badged with the longest of the
/// streaks, so a finished day reads at a glance instead of flickering through
/// three identical "done" flames.
class StreakFlameButton extends StatefulWidget {
  /// The "today" the streaks are evaluated against (the home page's dev date
  /// arrows move it).
  final DateTime? now;

  /// Called after returning from the streak page, so the home page can pick up
  /// settings changed there.
  final VoidCallback? onSettingsChanged;

  const StreakFlameButton({super.key, this.now, this.onSettingsChanged});

  /// How long each challenge stays on screen before the next one fades in.
  static const Duration cycleInterval = Duration(milliseconds: 2400);

  /// One breath of the "still open today" pulse (grey → white → grey takes
  /// twice this long).
  static const Duration pulseInterval = Duration(milliseconds: 900);

  /// A repeating timer or animation means `pumpAndSettle` never settles, so
  /// the cycle and the pulse stop under the widget-test bindings (which also
  /// keeps the screenshot runs deterministic). The tests that cover the
  /// cycling and the pulse set this to true and pump fixed frames.
  static bool debugForceCycle = false;

  /// The steady flame shown once every active challenge is done for the day.
  static const Color allDoneColor = Color(0xFFD32F2F); // red 700

  @override
  State<StreakFlameButton> createState() => _StreakFlameButtonState();
}

class _StreakFlameButtonState extends State<StreakFlameButton>
    with SingleTickerProviderStateMixin {
  Timer? _cycleTimer;

  /// Null under the widget-test bindings — see
  /// [StreakFlameButton.debugForceCycle].
  AnimationController? _pulse;
  int _index = 0;

  StreakService get _streak => StreakService.instance;

  @override
  void initState() {
    super.initState();
    if (StreakFlameButton.debugForceCycle ||
        !WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      _cycleTimer = Timer.periodic(StreakFlameButton.cycleInterval, (_) {
        if (mounted) setState(() => _index++);
      });
      _pulse = AnimationController(
        vsync: this,
        duration: StreakFlameButton.pulseInterval,
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _pulse?.dispose();
    super.dispose();
  }

  String _tooltip(StreakKind kind, int streak, bool doneToday) {
    final info = streakFlameInfo(kind);
    if (!info.configured) return info.title;
    if (streak <= 0) return '${info.short}: no streak yet';
    final streakText = '${info.short}: $streak-day streak';
    return doneToday ? streakText : '$streakText — still open today';
  }

  /// The flame icon itself. Done for the day it just burns in the challenge's
  /// colour; still open it stays grey and outlined, and breathes towards white
  /// (growing a little with each breath) so an unfinished day is hard to miss.
  Widget _flame(
      StreakKind kind, double progress, Color color, bool doneToday) {
    Widget icon(Color color, double scale) => Transform.scale(
          scale: scale,
          child: Icon(
            doneToday
                ? Icons.local_fire_department
                : Icons.local_fire_department_outlined,
            size: flameSizeFor(progress),
            color: color,
          ),
        );

    final pulse = _pulse;
    if (doneToday || pulse == null) return icon(color, 1);
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(pulse.value);
        return icon(Color.lerp(color, Colors.white, t)!, 1 + 0.12 * t);
      },
    );
  }

  void _openStreakPage(StreakKind kind) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StreakPage(
          initialKind: kind,
          onSettingsChanged: widget.onSettingsChanged,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _streak,
      builder: (context, _) {
        if (!Config.showStreak || !Config.isFeatureEnabled('streak')) {
          return const SizedBox.shrink();
        }
        final kinds = _streak.enabledKinds;
        // Every challenge switched off leaves nothing to show.
        if (kinds.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        final today = widget.now ?? DateTime.now();
        // Only kinds with an actual challenge behind them can complete the
        // day: `complete` always is one, but an unconfigured create/plan slot
        // (see StreakGoal) never records anything, so it would otherwise
        // block "all done" forever.
        final trackedKinds = kinds
            .where((kind) =>
                kind == StreakKind.complete ||
                Config.streakGoals.containsKey(kind.id))
            .toList();
        // Nothing left open today: stop hopping and burn one steady red flame
        // carrying the best of the streaks. A single tracked challenge keeps
        // its own colour — there is no cycle to collapse.
        final allDone = trackedKinds.length > 1 &&
            trackedKinds.every((kind) => _streak.isDayDone(today, kind: kind));

        final kind = allDone
            ? trackedKinds.reduce((best, kind) =>
                _streak.currentStreak(kind: kind, now: widget.now) >
                        _streak.currentStreak(kind: best, now: widget.now)
                    ? kind
                    : best)
            : kinds[_index % kinds.length];
        final streak = _streak.currentStreak(kind: kind, now: widget.now);
        final progress = _streak.flameProgress(kind: kind, now: widget.now);
        final doneToday = allDone || _streak.isDayDone(today, kind: kind);
        // The flame is only lit once today's action happened; a streak that is
        // still riding on yesterday stays grey (and pulses) until it does.
        final color = allDone
            ? StreakFlameButton.allDoneColor
            : doneToday
                ? kind.flameColor(progress, theme)
                : theme.disabledColor;

        return IconButton(
          tooltip: allDone
              ? 'All ${trackedKinds.length} challenges done today — '
                  '$streak-day streak'
              : _tooltip(kind, streak, doneToday),
          onPressed: () => _openStreakPage(kind),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Badge(
              // Keyed by challenge so the switcher cross-fades on every hop;
              // the all-done flame keeps one key so it never cross-fades.
              key: allDone ? const ValueKey('all-done') : ValueKey(kind),
              isLabelVisible: streak > 0,
              label: Text('$streak'),
              backgroundColor: color,
              child: _flame(kind, progress, color, doneToday),
            ),
          ),
        );
      },
    );
  }
}
