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

  /// A repeating timer means `pumpAndSettle` never settles, so the cycle stops
  /// under the widget-test bindings (which also keeps the screenshot runs
  /// deterministic). The test that covers the cycling itself sets this to true
  /// and pumps fixed frames.
  static bool debugForceCycle = false;

  @override
  State<StreakFlameButton> createState() => _StreakFlameButtonState();
}

class _StreakFlameButtonState extends State<StreakFlameButton> {
  Timer? _cycleTimer;
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
    }
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    super.dispose();
  }

  String _tooltip(StreakKind kind, int streak) {
    final info = streakFlameInfo(kind);
    if (!info.configured) return info.title;
    return streak > 0
        ? '${info.short}: $streak-day streak'
        : '${info.short}: no streak yet';
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
        final color = kind.flameColor(progress, theme);

        return IconButton(
          tooltip: _tooltip(kind, streak),
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
              child: Icon(
                streak > 0
                    ? Icons.local_fire_department
                    : Icons.local_fire_department_outlined,
                size: flameSizeFor(progress),
                color: color,
              ),
            ),
          ),
        );
      },
    );
  }
}
