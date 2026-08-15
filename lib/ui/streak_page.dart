import 'dart:math';

import 'package:flutter/material.dart';

import '../config.dart';
import '../services/streak_service.dart';
import '../utils/date_time_format.dart';
import 'settings_page.dart';
import 'subpage_app_bar.dart';

/// Flame colour for a streak progress between 0 (no streak, cold grey) and 1
/// (maximum fire after a full year): orange → deep orange → red.
Color flameColorFor(double progress, ThemeData theme) {
  if (progress <= 0) return theme.disabledColor;
  if (progress < 0.5) {
    return Color.lerp(Colors.orange, Colors.deepOrange, progress * 2)!;
  }
  return Color.lerp(Colors.deepOrange, Colors.red.shade700, (progress - 0.5) * 2)!;
}

/// Icon size for the home-page flame: grows with the streak.
double flameSizeFor(double progress) => 22 + 8 * progress;

/// The flame's detail page: a big animated flame, fun streak stats and the
/// streak's settings.
class StreakPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const StreakPage({super.key, this.onSettingsChanged});

  @override
  State<StreakPage> createState() => _StreakPageState();
}

class _StreakPageState extends State<StreakPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flicker;

  StreakService get _streak => StreakService.instance;

  @override
  void initState() {
    super.initState();
    _flicker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _flicker.dispose();
    super.dispose();
  }

  String _funLevelName(int streak) {
    if (streak <= 0) return 'Cold ashes';
    if (streak < 3) return 'First spark';
    if (streak < 7) return 'Small flame';
    if (streak < 14) return 'Steady fire';
    if (streak < 30) return 'Campfire';
    if (streak < 60) return 'Bonfire';
    if (streak < 120) return 'Blazing furnace';
    if (streak < 240) return 'Wildfire';
    if (streak < StreakService.maxStreakDays) return 'Inferno';
    return 'MAXIMUM FIRE';
  }

  Widget _statTile(IconData icon, String title, String value) {
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(
        value,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildFlame(ThemeData theme, int streak, double progress) {
    final color = flameColorFor(progress, theme);
    final size = 96 + 64 * progress;
    return AnimatedBuilder(
      animation: _flicker,
      builder: (context, _) {
        // Flicker: gentle scale and sway, stronger glow the hotter the flame.
        final t = _flicker.value;
        final scale = 0.94 + 0.12 * t;
        final angle = (t - 0.5) * 0.08;
        return Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: streak > 0 ? scale : 1,
            child: Container(
              decoration: streak > 0
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(
                              alpha: 0.25 + 0.35 * progress * t),
                          blurRadius: 30 + 50 * progress,
                          spreadRadius: 4 + 12 * progress,
                        ),
                      ],
                    )
                  : null,
              child: Icon(
                streak > 0
                    ? Icons.local_fire_department
                    : Icons.local_fire_department_outlined,
                size: size,
                color: color,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final streak = _streak.currentStreak();
    final progress = _streak.flameProgress();
    final longest = _streak.longestStreak();
    final activeDays = _streak.totalActiveDays();
    final completions = _streak.totalCompletions();
    final best = _streak.bestDay();
    final start = _streak.currentStreakStart();
    final daysToMax = StreakService.maxStreakDays - streak;
    final maxed = streak >= StreakService.maxStreakDays;

    return Scaffold(
      appBar: buildSubpageAppBar(
        context,
        title: 'Streak',
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Streak settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsPage(
                    onSettingsChanged: widget.onSettingsChanged,
                  ),
                ),
              ).then((_) {
                if (mounted) setState(() {});
              });
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _streak,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),
            Center(child: _buildFlame(theme, streak, progress)),
            const SizedBox(height: 16),
            Center(
              child: Text(
                streak > 0
                    ? '$streak-day streak'
                    : 'No streak yet',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Center(
              child: Text(
                _funLevelName(streak),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: flameColorFor(progress, theme),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                streak > 0
                    ? (maxed
                        ? 'The flame cannot burn any brighter. Legend. 🔥'
                        : '$daysToMax days until maximum fire')
                    : 'Complete one task today to light the flame.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            // Progress toward the one-year maximum flame.
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                color: flameColorFor(max(progress, 0.05), theme),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '${(progress * 100).round()}% of a full year',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Text(
                      'Fun stats',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (start != null)
                    _statTile(Icons.flag, 'Streak started',
                        formatTimerDate(start)),
                  _statTile(Icons.emoji_events, 'Longest streak ever',
                      longest > 0 ? '$longest days' : '—'),
                  _statTile(Icons.calendar_month, 'Days with a done task',
                      '$activeDays'),
                  _statTile(Icons.task_alt, 'Tasks completed on those days',
                      '$completions'),
                  if (best != null)
                    _statTile(
                        Icons.star,
                        'Best day (${best.value} tasks)',
                        (DateTime.tryParse(best.key) != null)
                            ? formatTimerDate(DateTime.parse(best.key))
                            : best.key),
                  if (activeDays > 0)
                    _statTile(
                        Icons.local_fire_department,
                        'Average tasks per active day',
                        (completions / activeDays).toStringAsFixed(1)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Text(
                  Config.streakGraceHours >= 48
                      ? 'Grace period: 48 hours — one missed day is forgiven. '
                          'Change it in the streak settings (gear icon above).'
                      : 'Grace period: 24 hours — complete a task every day '
                          'to keep the flame alive. Change it in the streak '
                          'settings (gear icon above).',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
