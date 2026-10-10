import 'dart:math';

import 'package:flutter/material.dart';

import 'streak_page.dart';

/// Plays the short "streak kept" flame burst over the current screen: a flame
/// that pops in with a few sparks and the new streak count, then fades out on
/// its own after ~1.4s. Purely decorative — taps pass straight through.
void showStreakCelebration(BuildContext context, int streakDays) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _StreakCelebration(
      streakDays: streakDays,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _StreakCelebration extends StatefulWidget {
  final int streakDays;
  final VoidCallback onDone;

  const _StreakCelebration({required this.streakDays, required this.onDone});

  @override
  State<_StreakCelebration> createState() => _StreakCelebrationState();
}

class _StreakCelebrationState extends State<_StreakCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          // Pop in fast (0-0.2), hold, fade out at the end (0.75-1).
          final popIn = Curves.elasticOut.transform(min(1, t / 0.35));
          final fade = t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25;
          final color = flameColorFor(
              min(1.0, widget.streakDays / 365), theme);
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Sparks flying outward as the flame pops.
                      for (var i = 0; i < 8; i++)
                        Transform.translate(
                          offset: Offset(
                            cos(i * pi / 4) * 70 * t,
                            sin(i * pi / 4) * 70 * t - 20 * t,
                          ),
                          child: Opacity(
                            opacity: (1 - t).clamp(0.0, 1.0),
                            child: Icon(
                              Icons.circle,
                              size: 6 + (i % 3) * 3,
                              color: i.isEven ? Colors.orange : Colors.amber,
                            ),
                          ),
                        ),
                      Transform.scale(
                        scale: 0.4 + 0.8 * popIn,
                        child: Icon(
                          Icons.local_fire_department,
                          size: 96,
                          color: color,
                          shadows: [
                            Shadow(
                              color:
                                  color.withValues(alpha: 0.6 * fade),
                              blurRadius: 40,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: Text(
                      widget.streakDays > 1
                          ? 'Streak kept — ${widget.streakDays} days! 🔥'
                          : 'Streak started! 🔥',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                        shadows: const [
                          Shadow(color: Colors.black26, blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
