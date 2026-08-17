import 'dart:async';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/streak_kind.dart';
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
    if (streak <= 0) return '${kind.label}: no streak yet';
    final streakText = '${kind.label}: $streak-day streak';
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

        final kind = kinds[_index % kinds.length];
        final streak = _streak.currentStreak(kind: kind, now: widget.now);
        final progress = _streak.flameProgress(kind: kind, now: widget.now);
        final theme = Theme.of(context);
        final doneToday =
            _streak.isDayDone(widget.now ?? DateTime.now(), kind: kind);
        // The flame is only lit once today's action happened; a streak that is
        // still riding on yesterday stays grey (and pulses) until it does.
        final color =
            doneToday ? kind.flameColor(progress, theme) : theme.disabledColor;

        return IconButton(
          tooltip: _tooltip(kind, streak, doneToday),
          onPressed: () => _openStreakPage(kind),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            child: Badge(
              // Keyed by challenge so the switcher cross-fades on every hop.
              key: ValueKey(kind),
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
