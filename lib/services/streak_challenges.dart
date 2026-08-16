import 'dart:math';

import 'package:flutter/material.dart';

import 'streak_service.dart';

/// One Duolingo-style streak challenge with its live progress.
///
/// [progress] counts toward [target]; the challenge is [earned] once the
/// target is reached. Binary challenges (e.g. "complete a task before 8:00")
/// use target 1.
class StreakChallenge {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final int target;
  final int progress;

  const StreakChallenge({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.target,
    required this.progress,
  });

  bool get earned => progress >= target;

  /// 0.0 → 1.0 for a progress bar.
  double get fraction => target <= 0 ? 0 : min(1.0, progress / target);
}

/// Evaluates all streak challenges against the service's recorded history.
///
/// Everything derives from `completionsByDay` (counts) and `minutesByDay`
/// (completion times, live completions only): streak lengths, per-day counts,
/// weekday/calendar patterns and times of day. Challenges are self-healing —
/// they recompute from history on every build, so nothing extra is persisted.
List<StreakChallenge> evaluateStreakChallenges(StreakService service) {
  final byDay = service.completionsByDayView;
  final minutesByDay = service.minutesByDayView;
  final days = byDay.keys
      .map((key) => DateTime.tryParse(key))
      .whereType<DateTime>()
      .toList()
    ..sort();

  final totalCompletions = service.totalCompletions();
  final activeDays = days.length;
  final longest = max(service.longestStreak(), service.currentStreak());
  final bestDayCount = service.bestDay()?.value ?? 0;

  final allMinutes = minutesByDay.values.expand((list) => list);
  final earliestMinute =
      allMinutes.isEmpty ? null : allMinutes.reduce(min);
  final latestMinute = allMinutes.isEmpty ? null : allMinutes.reduce(max);
  final hasLunchCompletion =
      allMinutes.any((m) => m >= 12 * 60 && m < 14 * 60);

  var hasMonday = false;
  var hasFirstOfMonth = false;
  var hasWeekendPair = false;
  var hasComeback = false;
  final activePerMonth = <String, int>{};
  for (final day in days) {
    if (day.weekday == DateTime.monday) hasMonday = true;
    if (day.day == 1) hasFirstOfMonth = true;
    if (day.weekday == DateTime.saturday &&
        byDay.containsKey(
            StreakService.dayKey(day.add(const Duration(days: 1))))) {
      hasWeekendPair = true;
    }
    final monthKey = '${day.year}-${day.month}';
    activePerMonth[monthKey] = (activePerMonth[monthKey] ?? 0) + 1;
  }
  for (var i = 1; i < days.length; i++) {
    // A comeback: the streak was broken (2+ missed days, beyond even the 48h
    // grace) and a new one was started anyway.
    if (days[i].difference(days[i - 1]).inDays - 1 >= 2) hasComeback = true;
  }
  final hasFullMonth = activePerMonth.entries.any((entry) {
    final parts = entry.key.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    return entry.value >= DateTime(year, month + 1, 0).day;
  });

  int binary(bool earned) => earned ? 1 : 0;

  return [
    StreakChallenge(
      id: 'first_spark',
      title: 'First Spark',
      description: 'Complete your very first task',
      icon: Icons.auto_awesome,
      target: 1,
      progress: min(totalCompletions, 1),
    ),
    StreakChallenge(
      id: 'early_bird',
      title: 'Early Bird',
      description: 'Complete a task before 8:00 in the morning',
      icon: Icons.wb_twilight,
      target: 1,
      progress: binary(earliestMinute != null && earliestMinute < 8 * 60),
    ),
    StreakChallenge(
      id: 'dawn_patrol',
      title: 'Dawn Patrol',
      description: 'Complete a task before 6:00 — while the world sleeps',
      icon: Icons.wb_sunny,
      target: 1,
      progress: binary(earliestMinute != null && earliestMinute < 6 * 60),
    ),
    StreakChallenge(
      id: 'night_owl',
      title: 'Night Owl',
      description: 'Complete a task after 22:00',
      icon: Icons.nights_stay,
      target: 1,
      progress: binary(latestMinute != null && latestMinute >= 22 * 60),
    ),
    StreakChallenge(
      id: 'lunch_break',
      title: 'Lunch Break Hero',
      description: 'Complete a task between 12:00 and 14:00',
      icon: Icons.lunch_dining,
      target: 1,
      progress: binary(hasLunchCompletion),
    ),
    StreakChallenge(
      id: 'hat_trick',
      title: 'Hat Trick',
      description: 'Complete 3 tasks in a single day',
      icon: Icons.looks_3,
      target: 3,
      progress: bestDayCount,
    ),
    StreakChallenge(
      id: 'high_five',
      title: 'High Five',
      description: 'Complete 5 tasks in a single day',
      icon: Icons.front_hand,
      target: 5,
      progress: bestDayCount,
    ),
    StreakChallenge(
      id: 'perfect_ten',
      title: 'Perfect Ten',
      description: 'Complete 10 tasks in a single day',
      icon: Icons.star,
      target: 10,
      progress: bestDayCount,
    ),
    StreakChallenge(
      id: 'task_tornado',
      title: 'Task Tornado',
      description: 'Complete 20 tasks in a single day',
      icon: Icons.cyclone,
      target: 20,
      progress: bestDayCount,
    ),
    StreakChallenge(
      id: 'week_of_fire',
      title: 'Week of Fire',
      description: 'Keep a 7-day streak',
      icon: Icons.local_fire_department,
      target: 7,
      progress: longest,
    ),
    StreakChallenge(
      id: 'fortnight_flame',
      title: 'Fortnight Flame',
      description: 'Keep a 14-day streak',
      icon: Icons.whatshot,
      target: 14,
      progress: longest,
    ),
    StreakChallenge(
      id: 'monthly_blaze',
      title: 'Monthly Blaze',
      description: 'Keep a 30-day streak',
      icon: Icons.fireplace,
      target: 30,
      progress: longest,
    ),
    StreakChallenge(
      id: 'quarter_inferno',
      title: 'Quarter Inferno',
      description: 'Keep a 90-day streak',
      icon: Icons.volcano,
      target: 90,
      progress: longest,
    ),
    StreakChallenge(
      id: 'half_year_furnace',
      title: 'Half-Year Furnace',
      description: 'Keep a 180-day streak',
      icon: Icons.factory,
      target: 180,
      progress: longest,
    ),
    StreakChallenge(
      id: 'eternal_flame',
      title: 'Eternal Flame',
      description: 'Keep a 365-day streak — a full year of fire',
      icon: Icons.emoji_events,
      target: 365,
      progress: longest,
    ),
    StreakChallenge(
      id: 'weekend_warrior',
      title: 'Weekend Warrior',
      description: 'Complete tasks on a Saturday and the Sunday right after',
      icon: Icons.weekend,
      target: 1,
      progress: binary(hasWeekendPair),
    ),
    StreakChallenge(
      id: 'monday_hero',
      title: 'Monday Hero',
      description: 'Complete a task on a Monday',
      icon: Icons.coffee,
      target: 1,
      progress: binary(hasMonday),
    ),
    StreakChallenge(
      id: 'fresh_start',
      title: 'Fresh Start',
      description: 'Complete a task on the 1st of a month',
      icon: Icons.calendar_today,
      target: 1,
      progress: binary(hasFirstOfMonth),
    ),
    StreakChallenge(
      id: 'full_month',
      title: 'Full Month',
      description: 'Complete a task on every single day of a calendar month',
      icon: Icons.calendar_month,
      target: 1,
      progress: binary(hasFullMonth),
    ),
    StreakChallenge(
      id: 'comeback_kid',
      title: 'Comeback Kid',
      description: 'Start a new streak after one broke — falling is fine, '
          'staying down is not',
      icon: Icons.replay,
      target: 1,
      progress: binary(hasComeback),
    ),
    StreakChallenge(
      id: 'explorer',
      title: 'Explorer',
      description: 'Complete tasks on 10 different days',
      icon: Icons.explore,
      target: 10,
      progress: activeDays,
    ),
    StreakChallenge(
      id: 'regular',
      title: 'Regular',
      description: 'Complete tasks on 50 different days',
      icon: Icons.event_repeat,
      target: 50,
      progress: activeDays,
    ),
    StreakChallenge(
      id: 'veteran',
      title: 'Veteran',
      description: 'Complete tasks on 100 different days',
      icon: Icons.workspace_premium,
      target: 100,
      progress: activeDays,
    ),
    StreakChallenge(
      id: 'century_club',
      title: 'Century Club',
      description: 'Complete 100 tasks in total',
      icon: Icons.military_tech,
      target: 100,
      progress: totalCompletions,
    ),
    StreakChallenge(
      id: 'task_machine',
      title: 'Task Machine',
      description: 'Complete 500 tasks in total',
      icon: Icons.precision_manufacturing,
      target: 500,
      progress: totalCompletions,
    ),
    StreakChallenge(
      id: 'task_legend',
      title: 'Task Legend',
      description: 'Complete 1000 tasks in total',
      icon: Icons.diamond,
      target: 1000,
      progress: totalCompletions,
    ),
  ];
}
