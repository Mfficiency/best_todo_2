import 'dart:math';

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/streak_kind.dart';
import '../services/streak_challenges.dart';
import '../services/streak_flame_display.dart';
import '../services/streak_service.dart';
import '../utils/date_time_format.dart';
import 'settings_page.dart';
import 'streak_calendar_page.dart';
import 'subpage_app_bar.dart';

/// Flame colour for a streak progress between 0 (no streak, cold grey) and 1
/// (maximum fire after a full year). Every challenge burns in its own hue —
/// see [StreakKind.flameColor].
Color flameColorFor(double progress, ThemeData theme,
        {StreakKind kind = StreakKind.complete}) =>
    kind.flameColor(progress, theme);

/// Icon size for the home-page flame: grows with the streak.
double flameSizeFor(double progress) => 22 + 8 * progress;

/// The flame's detail page: a big animated flame per challenge, today's open
/// challenges, fun streak stats and the streak's settings.
class StreakPage extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  /// The challenge the page opens on — the one the home-page flame was
  /// showing when it was tapped.
  final StreakKind? initialKind;

  const StreakPage({super.key, this.onSettingsChanged, this.initialKind});

  @override
  State<StreakPage> createState() => _StreakPageState();
}

class _StreakPageState extends State<StreakPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flicker;
  late StreakKind _kind;

  StreakService get _streak => StreakService.instance;

  @override
  void initState() {
    super.initState();
    final enabled = _streak.enabledKinds;
    _kind = widget.initialKind ??
        (enabled.isEmpty ? StreakKind.complete : enabled.first);
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

  /// Stat labels for the fun-stats card, worded per challenge.
  ({String activeDays, String events, String best, String average}) _statLabels(
      StreakKind kind) {
    switch (kind) {
      case StreakKind.complete:
        return (
          activeDays: 'Days with a done task',
          events: 'Tasks completed on those days',
          best: 'tasks',
          average: 'Average tasks per active day',
        );
      case StreakKind.create:
      case StreakKind.plan:
        return (
          activeDays: 'Days the goal was met',
          events: 'Completions on those days',
          best: 'completions',
          average: 'Average completions per active day',
        );
    }
  }

  Widget _statTile(IconData icon, String title, String value,
      {String? subtitle, VoidCallback? onTap}) {
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: Text(
        value,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      onTap: onTap,
    );
  }

  /// Divider between the still-open challenges and the earned ones.
  Widget _challengeGroupHeader(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.amber.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: theme.dividerColor)),
        ],
      ),
    );
  }

  Widget _challengeTile(StreakChallenge challenge) {
    final theme = Theme.of(context);
    final earned = challenge.earned;
    final accent = earned ? Colors.amber.shade700 : theme.disabledColor;
    return ListTile(
      dense: true,
      leading: Icon(challenge.icon, color: accent, size: 28),
      title: Text(
        challenge.title,
        style: TextStyle(
          fontWeight: earned ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(challenge.description),
          if (!earned && challenge.target > 1) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: challenge.fraction,
                minHeight: 5,
                color: Colors.deepOrange,
              ),
            ),
          ],
        ],
      ),
      trailing: earned
          ? Icon(Icons.check_circle, color: Colors.amber.shade700)
          : (challenge.target > 1
              ? Text('${challenge.progress}/${challenge.target}',
                  style: theme.textTheme.bodySmall)
              : null),
    );
  }

  /// One selectable mini flame per active challenge — the page's tab row.
  Widget _buildKindSelector(ThemeData theme, List<StreakKind> kinds) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final kind in kinds)
          ChoiceChip(
            selected: kind == _kind,
            onSelected: (_) => setState(() => _kind = kind),
            avatar: Icon(
              _streak.currentStreak(kind: kind) > 0
                  ? Icons.local_fire_department
                  : Icons.local_fire_department_outlined,
              color: kind.flameColor(_streak.flameProgress(kind: kind), theme),
            ),
            label: Text(
                '${streakFlameInfo(kind).short} ${_streak.currentStreak(kind: kind)}'),
          ),
      ],
    );
  }

  /// What is still open today, per active challenge. The quickest answer to
  /// "why is that flame grey?".
  Widget _buildTodayCard(ThemeData theme, List<StreakKind> kinds) {
    final today = DateTime.now();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              'Today',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          for (final kind in kinds) _buildTodayTile(theme, kind, today),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTodayTile(ThemeData theme, StreakKind kind, DateTime today) {
    final info = streakFlameInfo(kind);
    return ListTile(
      dense: true,
      leading: Icon(
        kind.icon,
        color: kind.flameColor(_streak.flameProgress(kind: kind), theme),
      ),
      title: Text(info.title),
      subtitle: Text(info.description),
      trailing: !info.configured
          ? Text('Not set', style: theme.textTheme.bodySmall)
          : info.missing
              ? Icon(Icons.error_outline, color: theme.colorScheme.error)
              : (_streak.isDayDone(today, kind: kind)
                  ? Icon(Icons.check_circle, color: kind.warm)
                  : Text('Open', style: theme.textTheme.bodySmall)),
      onTap: () => setState(() => _kind = kind),
    );
  }

  Widget _buildFlame(ThemeData theme, int streak, double progress) {
    final color = _kind.flameColor(progress, theme);
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
    final kinds = _streak.enabledKinds;
    final streak = _streak.currentStreak(kind: _kind);
    final progress = _streak.flameProgress(kind: _kind);
    final longest = _streak.longestStreak(kind: _kind);
    final activeDays = _streak.totalActiveDays(kind: _kind);
    final events = _streak.totalCompletions(kind: _kind);
    final best = _streak.bestDay(kind: _kind);
    final start = _streak.currentStreakStart(kind: _kind);
    final labels = _statLabels(_kind);
    final info = streakFlameInfo(_kind);
    final daysToMax = StreakService.maxStreakDays - streak;
    final maxed = streak >= StreakService.maxStreakDays;
    final challenges = evaluateStreakChallenges(_streak);
    // What is still to play for goes first; the trophies collect at the
    // bottom, so the list opens on the next thing to chase instead of on a
    // wall of check marks.
    final openChallenges = challenges.where((c) => !c.earned).toList();
    final earnedChallenges = challenges.where((c) => c.earned).toList();

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
            if (kinds.length > 1) ...[
              _buildKindSelector(theme, kinds),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            Center(child: _buildFlame(theme, streak, progress)),
            const SizedBox(height: 16),
            Center(
              child: Text(
                streak > 0 ? '$streak-day streak' : 'No streak yet',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Center(
              child: Text(
                '${info.title} · ${_funLevelName(streak)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: _kind.flameColor(progress, theme),
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                streak > 0
                    ? (maxed
                        ? 'The flame cannot burn any brighter. Legend. 🔥'
                        : '$daysToMax days until maximum fire')
                    : info.callToAction,
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
                color: _kind.flameColor(max(progress, 0.05), theme),
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
            if (kinds.isNotEmpty) ...[
              _buildTodayCard(theme, kinds),
              const SizedBox(height: 8),
            ],
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
                      longest > 0 ? '$longest days' : '—',
                      subtitle: 'Tap to see it on the calendar',
                      onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    StreakCalendarPage(kind: _kind)),
                          )),
                  _statTile(
                      Icons.calendar_month, labels.activeDays, '$activeDays'),
                  _statTile(_kind.icon, labels.events, '$events'),
                  if (best != null)
                    _statTile(
                        Icons.star,
                        'Best day (${best.value} ${labels.best})',
                        (DateTime.tryParse(best.key) != null)
                            ? formatTimerDate(DateTime.parse(best.key))
                            : best.key),
                  if (activeDays > 0)
                    _statTile(Icons.local_fire_department, labels.average,
                        (events / activeDays).toStringAsFixed(1)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Challenges',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          '${earnedChallenges.length} / ${challenges.length} '
                          'earned',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.amber.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final challenge in openChallenges)
                    _challengeTile(challenge),
                  if (openChallenges.isNotEmpty && earnedChallenges.isNotEmpty)
                    _challengeGroupHeader(theme, 'Earned'),
                  for (final challenge in earnedChallenges)
                    _challengeTile(challenge),
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
                      : 'Grace period: 24 hours — meet the challenge every day '
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
