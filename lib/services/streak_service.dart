import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/daily_task_stats.dart';
import '../models/task.dart';
import 'notification_service.dart';
import 'safe_file.dart';

/// Tracks the daily completion streak: every calendar day on which at least
/// one (non-wish) task was completed counts as an "active" day. Consecutive
/// active days form the streak that the home-page flame visualizes; the flame
/// reaches maximum fire after [maxStreakDays] days.
///
/// Persistence is a JSON map of dayKey → completion count in `streak.json`
/// (atomic via [SafeFile]), plus a parallel dayKey → minutes-of-day list for
/// the time-of-day challenges. Counts, not booleans, so an accidental
/// toggle-then-untoggle on the same day cancels out exactly and the stats
/// page can show per-day totals.
///
/// The grace period ([Config.streakGraceHours]) decides how forgiving the
/// streak is: 24h means every calendar day needs a completion; 48h tolerates
/// a single missed day between active days. The current day never breaks the
/// streak while it is still running.
class StreakService extends ChangeNotifier {
  StreakService._();

  static final StreakService instance = StreakService._();

  static const _fileName = 'streak.json';

  /// Days of unbroken streak needed for the flame to reach maximum fire.
  static const int maxStreakDays = 365;

  final Map<String, int> _completionsByDay = {};

  /// Minute-of-day (0..1439) of each completion, per day. Only populated from
  /// live completions — seeded/backfilled history has counts but no times —
  /// so time-of-day challenges start counting from the day the feature ships.
  final Map<String, List<int>> _minutesByDay = {};
  bool _loaded = false;
  bool _hadFile = false;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String dayKey(DateTime d) {
    final day = _dateOnly(d);
    final m = day.month.toString().padLeft(2, '0');
    final dd = day.day.toString().padLeft(2, '0');
    return '${day.year}-$m-$dd';
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Loads the persisted streak history. Safe to call more than once.
  Future<void> load() async {
    try {
      final file = await _getFile();
      final data = await SafeFile.readWithRecovery(
        file,
        (contents) => jsonDecode(contents) as Map<String, dynamic>,
      );
      if (data != null) {
        _hadFile = true;
        final byDay = data['completionsByDay'];
        if (byDay is Map) {
          byDay.forEach((key, value) {
            if (key is String && value is num && value > 0) {
              _completionsByDay[key] = value.round();
            }
          });
        }
        final minutes = data['minutesByDay'];
        if (minutes is Map) {
          minutes.forEach((key, value) {
            if (key is String && value is List) {
              final list = value
                  .whereType<num>()
                  .map((m) => m.round())
                  .where((m) => m >= 0 && m < 24 * 60)
                  .toList();
              if (list.isNotEmpty) _minutesByDay[key] = list;
            }
          });
        }
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
    unawaited(syncReminder());
  }

  /// True when no streak file existed yet — the caller should backfill from
  /// existing history via [seedFromHistory] so long-time users don't start
  /// from a cold flame.
  bool get needsSeed => _loaded && !_hadFile;

  /// One-time backfill from data that predates the streak feature: the daily
  /// task stats (completions per day) and any tasks still carrying a
  /// `completedAt` timestamp (including deleted ones). Per day the larger of
  /// the two counts wins so nothing is double-counted.
  void seedFromHistory({
    required Iterable<Task> tasks,
    required Map<String, DailyTaskStats> dailyStats,
  }) {
    final fromStats = <String, int>{};
    dailyStats.forEach((day, stats) {
      final count = stats.completedFromOpeningTaskIds.length +
          stats.completedFromCreatedTaskIds.length;
      if (count > 0 && day.isNotEmpty) fromStats[day] = count;
    });
    final fromTasks = <String, int>{};
    for (final task in tasks) {
      if (task.isWish) continue;
      final at = task.completedAt;
      if (at == null) continue;
      final key = dayKey(at);
      fromTasks[key] = (fromTasks[key] ?? 0) + 1;
    }
    for (final key in {...fromStats.keys, ...fromTasks.keys}) {
      final count = max(fromStats[key] ?? 0, fromTasks[key] ?? 0);
      if (count > 0) {
        _completionsByDay[key] = max(_completionsByDay[key] ?? 0, count);
      }
    }
    _hadFile = true;
    unawaited(_save());
    notifyListeners();
    unawaited(syncReminder());
  }

  /// Dev/demo-only backfill: marks the last [days] calendar days (ending on
  /// [now]) as active so the flame starts at a presentable streak. Existing
  /// counts win where they are larger, so this only fills gaps — call it
  /// after [seedFromHistory] and only while [needsSeed] was true, otherwise
  /// it would paper over a genuinely broken streak while testing.
  void seedDevStreak({int days = Config.devSeedStreakDays, DateTime? now}) {
    if (days <= 0) return;
    final today = _dateOnly(now ?? DateTime.now());
    for (var back = 0; back < days; back++) {
      final key = dayKey(today.subtract(Duration(days: back)));
      _completionsByDay[key] = max(_completionsByDay[key] ?? 0, 1);
    }
    _hadFile = true;
    unawaited(_save());
    notifyListeners();
    unawaited(syncReminder());
  }

  /// Records a task completion. Returns true when this was the first
  /// completion of that day — the moment the streak is kept — so the caller
  /// can celebrate.
  bool recordCompletion(DateTime when) {
    final key = dayKey(when);
    final before = _completionsByDay[key] ?? 0;
    _completionsByDay[key] = before + 1;
    (_minutesByDay[key] ??= []).add(when.hour * 60 + when.minute);
    unawaited(_save());
    notifyListeners();
    unawaited(syncReminder());
    return before == 0;
  }

  /// Reverts one completion (task un-toggled). At zero the day stops counting
  /// toward the streak, so toggle + untoggle cancel out exactly.
  void recordUncompletion(DateTime when) {
    final key = dayKey(when);
    final before = _completionsByDay[key] ?? 0;
    if (before <= 1) {
      _completionsByDay.remove(key);
      _minutesByDay.remove(key);
    } else {
      _completionsByDay[key] = before - 1;
      // We can't know which completion was undone; dropping the latest keeps
      // toggle + untoggle an exact no-op for the time-of-day challenges too.
      final minutes = _minutesByDay[key];
      if (minutes != null && minutes.isNotEmpty) minutes.removeLast();
      if (minutes != null && minutes.isEmpty) _minutesByDay.remove(key);
    }
    unawaited(_save());
    notifyListeners();
    unawaited(syncReminder());
  }

  bool isDayDone(DateTime day) => _completionsByDay.containsKey(dayKey(day));

  /// Completions recorded on the given day (0 when none).
  int completionsOn(DateTime day) => _completionsByDay[dayKey(day)] ?? 0;

  /// Largest gap of missed days the streak survives between two active days.
  /// 24h grace → 0 (every day needs a completion), 48h → 1 missed day.
  static int _allowedGap() => Config.streakGraceHours >= 48 ? 1 : 0;

  DateTime? _previousActiveDay(DateTime from, int allowedGap) {
    for (var back = 1; back <= allowedGap + 1; back++) {
      final candidate = from.subtract(Duration(days: back));
      if (isDayDone(candidate)) return candidate;
    }
    return null;
  }

  /// The current streak in days, evaluated as of [now]. A day still in
  /// progress never breaks the streak; with 48h grace a single missed day is
  /// also survived.
  int currentStreak({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    final allowedGap = _allowedGap();
    DateTime? anchor = isDayDone(today) ? today : null;
    anchor ??= _previousActiveDay(today, allowedGap);
    if (anchor == null) return 0;
    var streak = 1;
    var cursor = anchor;
    while (true) {
      final previous = _previousActiveDay(cursor, allowedGap);
      if (previous == null) break;
      streak++;
      cursor = previous;
    }
    return streak;
  }

  /// First day of the current streak, or null without one.
  DateTime? currentStreakStart({DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    final allowedGap = _allowedGap();
    DateTime? anchor = isDayDone(today) ? today : null;
    anchor ??= _previousActiveDay(today, allowedGap);
    if (anchor == null) return null;
    var cursor = anchor;
    while (true) {
      final previous = _previousActiveDay(cursor, allowedGap);
      if (previous == null) return cursor;
      cursor = previous;
    }
  }

  /// The longest streak ever recorded, under the current grace setting.
  int longestStreak() {
    final days = _completionsByDay.keys
        .map((key) => DateTime.tryParse(key))
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (days.isEmpty) return 0;
    final allowedGap = _allowedGap();
    var longest = 1;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      final gap = days[i].difference(days[i - 1]).inDays - 1;
      if (gap <= allowedGap) {
        run++;
      } else {
        run = 1;
      }
      if (run > longest) longest = run;
    }
    return longest;
  }

  /// First and last active day of the longest streak ever, under the current
  /// grace setting, or null without any history. When several runs tie, the
  /// earliest one wins (matching [longestStreak]'s scan order).
  ({DateTime start, DateTime end})? longestStreakRange() {
    final days = _completionsByDay.keys
        .map((key) => DateTime.tryParse(key))
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (days.isEmpty) return null;
    final allowedGap = _allowedGap();
    var bestStart = days.first;
    var bestEnd = days.first;
    var bestLen = 1;
    var runStart = days.first;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      final gap = days[i].difference(days[i - 1]).inDays - 1;
      if (gap <= allowedGap) {
        run++;
      } else {
        run = 1;
        runStart = days[i];
      }
      if (run > bestLen) {
        bestLen = run;
        bestStart = runStart;
        bestEnd = days[i];
      }
    }
    return (start: bestStart, end: bestEnd);
  }

  /// Read-only view of the full history (dayKey → completion count) for the
  /// streak calendar and the challenges.
  Map<String, int> get completionsByDayView =>
      Map.unmodifiable(_completionsByDay);

  /// Read-only view of the recorded completion times (dayKey → minutes of
  /// day) for the time-of-day challenges.
  Map<String, List<int>> get minutesByDayView =>
      Map.unmodifiable(_minutesByDay);

  /// Days on which at least one task was completed, ever.
  int totalActiveDays() => _completionsByDay.length;

  /// Total completions recorded across all days.
  int totalCompletions() =>
      _completionsByDay.values.fold(0, (sum, count) => sum + count);

  /// The day with the most completions, or null when there is no history.
  MapEntry<String, int>? bestDay() {
    MapEntry<String, int>? best;
    for (final entry in _completionsByDay.entries) {
      if (best == null || entry.value > best.value) best = entry;
    }
    return best;
  }

  /// 0.0 (no streak) → 1.0 (maximum fire after a year) for the flame's size
  /// and colour.
  double flameProgress({DateTime? now}) =>
      min(1.0, currentStreak(now: now) / maxStreakDays);

  /// Re-schedules (or cancels) the daily "keep your streak" reminder to match
  /// the current settings and today's completion state. One-shot: it re-arms
  /// on every app start, completion and settings change.
  Future<void> syncReminder({DateTime? now}) async {
    if (!Config.streakReminderEnabled ||
        !Config.showStreak ||
        !Config.isFeatureEnabled('streak')) {
      await NotificationService.cancelStreakReminder();
      return;
    }
    final current = now ?? DateTime.now();
    final today = _dateOnly(current);
    var fireAt =
        today.add(Duration(minutes: Config.streakReminderMinutes.clamp(0, 1439)));
    if (!fireAt.isAfter(current) || isDayDone(current)) {
      fireAt = fireAt.add(const Duration(days: 1));
    }
    final streak = currentStreak(now: current);
    final body = streak > 0
        ? 'Complete one task today to keep your $streak-day streak alive.'
        : 'Complete one task today to start a streak.';
    await NotificationService.scheduleStreakReminder(fireAt: fireAt, body: body);
  }

  /// Notifies listeners and re-syncs the reminder after a streak-related
  /// setting changed (visibility, grace period, reminder time...).
  void settingsChanged() {
    notifyListeners();
    unawaited(syncReminder());
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      await SafeFile.writeString(
          file,
          jsonEncode({
            'completionsByDay': _completionsByDay,
            'minutesByDay': _minutesByDay,
          }));
    } catch (_) {}
  }

  /// Awaitable save for tests.
  Future<void> saveNow() => _save();

  void resetForTest() {
    _completionsByDay.clear();
    _minutesByDay.clear();
    _loaded = false;
    _hadFile = false;
  }
}
