import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/daily_task_stats.dart';
import '../models/streak_goal.dart';
import '../models/streak_kind.dart';
import '../models/streak_reminder.dart';
import '../models/task.dart';
import 'notification_service.dart';
import 'safe_file.dart';

/// Tracks the daily streaks: for every [StreakKind] a calendar day counts as
/// "active" once its challenge was met. [StreakKind.complete] is fixed: any
/// task completed. [StreakKind.create] and [StreakKind.plan] (the green and
/// blue flames) are user-configured goals instead — see [StreakGoal] and
/// [Config.streakGoals] — met when a task matching the chosen recurring task
/// or project is completed; unconfigured, they simply stay cold. Consecutive
/// active days form the streak each flame visualizes; a flame reaches
/// maximum fire after [maxStreakDays] days.
///
/// Persistence is a JSON map of dayKey → count per kind in `streak.json`
/// (atomic via [SafeFile]), plus a parallel dayKey → minutes-of-day list of the
/// completions for the time-of-day challenges. Counts, not booleans, so an
/// accidental toggle-then-untoggle on the same day cancels out exactly and the
/// stats page can show per-day totals.
///
/// The grace period ([Config.streakGraceHours]) decides how forgiving the
/// streaks are: 24h means every calendar day needs its challenge met, 48h
/// tolerates a single missed day between active days. The current day never
/// breaks a streak while it is still running.
class StreakService extends ChangeNotifier {
  StreakService._();

  static final StreakService instance = StreakService._();

  static const _fileName = 'streak.json';

  /// Days of unbroken streak needed for a flame to reach maximum fire.
  static const int maxStreakDays = 365;

  /// Persisted key of each kind's day map. The `complete` kind keeps the
  /// original `completionsByDay` name so old files load unchanged.
  static const Map<StreakKind, String> _dayMapKeys = {
    StreakKind.complete: 'completionsByDay',
    StreakKind.create: 'createsByDay',
    StreakKind.plan: 'planByDay',
  };

  final Map<StreakKind, Map<String, int>> _byKind = {
    for (final kind in StreakKind.values) kind: <String, int>{},
  };

  /// Minute-of-day (0..1439) of each completion, per day. Only populated from
  /// live completions — seeded/backfilled history has counts but no times —
  /// so time-of-day challenges start counting from the day the feature ships.
  final Map<String, List<int>> _minutesByDay = {};
  bool _loaded = false;
  bool _hadFile = false;

  /// Whether reminders may still be pending with the OS (see [syncReminder]).
  bool _remindersArmed = true;

  /// uids of every task currently on the list (kept in sync by the home page
  /// via [syncKnownTasks]), so a configured goal whose target task was
  /// deleted can be told apart from one that just has not fired yet today.
  Set<String> _knownTaskUids = {};

  Map<String, int> _days(StreakKind kind) => _byKind[kind]!;

  /// Refreshes the set of task uids a task-targeted [StreakGoal] can match
  /// against. Cheap to call on every build: a no-op (no listener churn) once
  /// the set has already settled.
  void syncKnownTasks(Iterable<Task> tasks) {
    final uids = tasks.map((t) => t.uid).toSet();
    if (uids.length == _knownTaskUids.length &&
        uids.every(_knownTaskUids.contains)) {
      return;
    }
    _knownTaskUids = uids;
    notifyListeners();
  }

  /// True when [kind]'s configured goal points at a task that no longer
  /// exists among the tasks last reported to [syncKnownTasks] — the flame
  /// should show a "goal missing" prompt instead of its usual streak. A
  /// project-targeted goal is checked by the caller against [ProjectService]
  /// directly. False for an unconfigured flame (that is just cold).
  bool isGoalMissing(StreakKind kind) {
    final goal = Config.streakGoals[kind.id];
    if (goal == null || goal.target != StreakGoalTarget.task) return false;
    return !_knownTaskUids.contains(goal.targetId);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String dayKey(DateTime d) {
    final day = _dateOnly(d);
    final m = day.month.toString().padLeft(2, '0');
    final dd = day.day.toString().padLeft(2, '0');
    return '${day.year}-$m-$dd';
  }

  /// The challenges the user left switched on, in enum order. Everything that
  /// shows or schedules a flame iterates this instead of [StreakKind.values].
  List<StreakKind> get enabledKinds => [
        for (final kind in StreakKind.values)
          if (Config.isStreakKindEnabled(kind.id)) kind,
      ];

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
        for (final kind in StreakKind.values) {
          final byDay = data[_dayMapKeys[kind]];
          if (byDay is Map) {
            byDay.forEach((key, value) {
              if (key is String && value is num && value > 0) {
                _days(kind)[key] = value.round();
              }
            });
          }
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
  /// task stats (completions per day) and the tasks themselves (including
  /// deleted ones), which carry a `completedAt` timestamp. The `create` and
  /// `plan` kinds are user-configured goals now (see [StreakGoal]) with no
  /// fixed app-wide meaning, so there is nothing generic to backfill for them
  /// — they simply start cold and unconfigured. Per day the larger of the
  /// available counts wins so nothing is double-counted.
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
      final completedAt = task.completedAt;
      if (completedAt != null) {
        final key = dayKey(completedAt);
        fromTasks[key] = (fromTasks[key] ?? 0) + 1;
      }
    }
    for (final key in {...fromStats.keys, ...fromTasks.keys}) {
      final count = max(fromStats[key] ?? 0, fromTasks[key] ?? 0);
      if (count > 0) _mergeDay(StreakKind.complete, key, count);
    }
    _hadFile = true;
    unawaited(_save());
    notifyListeners();
    unawaited(syncReminder());
  }

  void _mergeDay(StreakKind kind, String key, int count) {
    _days(kind)[key] = max(_days(kind)[key] ?? 0, count);
  }

  /// Dev/demo-only backfill: marks the last [days] calendar days (ending on
  /// [now]) as active for the `complete` kind so the flame starts at a
  /// presentable streak. Existing counts win where they are larger, so this
  /// only fills gaps — call it after [seedFromHistory] and only while
  /// [needsSeed] was true, otherwise it would paper over a genuinely broken
  /// streak while testing. The `create`/`plan` kinds are user-configured
  /// goals with no fixed meaning, so there is nothing to seed for them.
  void seedDevStreak({int days = Config.devSeedStreakDays, DateTime? now}) {
    if (days <= 0) return;
    final today = _dateOnly(now ?? DateTime.now());
    for (var back = 0; back < days; back++) {
      _mergeDay(
          StreakKind.complete, dayKey(today.subtract(Duration(days: back))), 1);
    }
    _hadFile = true;
    unawaited(_save());
    notifyListeners();
    unawaited(syncReminder());
  }

  /// Records that [kind]'s challenge was met on [when]. Returns true when this
  /// was the first such event of that day — the moment the streak is kept — so
  /// the caller can celebrate.
  bool record(StreakKind kind, DateTime when) {
    final key = dayKey(when);
    final before = _days(kind)[key] ?? 0;
    _days(kind)[key] = before + 1;
    if (kind == StreakKind.complete) {
      (_minutesByDay[key] ??= []).add(when.hour * 60 + when.minute);
    }
    unawaited(_save());
    notifyListeners();
    unawaited(syncReminder());
    return before == 0;
  }

  /// Records a task completion (see [record]).
  bool recordCompletion(DateTime when) => record(StreakKind.complete, when);

  /// Records that a user-configured goal (the `create`/`plan` flame slots,
  /// see [StreakGoal]) was met on [when] — only the first such event of the
  /// day is stored, so re-checking a day's goal on every toggle cannot
  /// inflate the count.
  bool recordGoal(StreakKind kind, DateTime when) {
    if (isDayDone(when, kind: kind)) return false;
    return record(kind, when);
  }

  /// Reverts one event of [kind] (task un-toggled). At zero the day stops
  /// counting toward the streak, so toggle + untoggle cancel out exactly.
  void recordUncompletion(DateTime when, {StreakKind kind = StreakKind.complete}) {
    final key = dayKey(when);
    final days = _days(kind);
    final before = days[key] ?? 0;
    if (before <= 1) {
      days.remove(key);
      if (kind == StreakKind.complete) _minutesByDay.remove(key);
    } else {
      days[key] = before - 1;
      if (kind == StreakKind.complete) {
        // We can't know which completion was undone; dropping the latest
        // keeps toggle + untoggle an exact no-op for the time-of-day
        // challenges too.
        final minutes = _minutesByDay[key];
        if (minutes != null && minutes.isNotEmpty) minutes.removeLast();
        if (minutes != null && minutes.isEmpty) _minutesByDay.remove(key);
      }
    }
    unawaited(_save());
    notifyListeners();
    unawaited(syncReminder());
  }

  bool isDayDone(DateTime day, {StreakKind kind = StreakKind.complete}) =>
      _days(kind).containsKey(dayKey(day));

  /// Events of [kind] recorded on the given day (0 when none).
  int completionsOn(DateTime day, {StreakKind kind = StreakKind.complete}) =>
      _days(kind)[dayKey(day)] ?? 0;

  /// Largest gap of missed days a streak survives between two active days.
  /// 24h grace → 0 (every day needs an event), 48h → 1 missed day.
  static int _allowedGap() => Config.streakGraceHours >= 48 ? 1 : 0;

  DateTime? _previousActiveDay(StreakKind kind, DateTime from, int allowedGap) {
    for (var back = 1; back <= allowedGap + 1; back++) {
      final candidate = from.subtract(Duration(days: back));
      if (isDayDone(candidate, kind: kind)) return candidate;
    }
    return null;
  }

  /// The current streak of [kind] in days, evaluated as of [now]. A day still
  /// in progress never breaks the streak; with 48h grace a single missed day
  /// is also survived.
  int currentStreak({StreakKind kind = StreakKind.complete, DateTime? now}) {
    final today = _dateOnly(now ?? DateTime.now());
    final allowedGap = _allowedGap();
    DateTime? anchor = isDayDone(today, kind: kind) ? today : null;
    anchor ??= _previousActiveDay(kind, today, allowedGap);
    if (anchor == null) return 0;
    var streak = 1;
    var cursor = anchor;
    while (true) {
      final previous = _previousActiveDay(kind, cursor, allowedGap);
      if (previous == null) break;
      streak++;
      cursor = previous;
    }
    return streak;
  }

  /// First day of the current streak, or null without one.
  DateTime? currentStreakStart({
    StreakKind kind = StreakKind.complete,
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final allowedGap = _allowedGap();
    DateTime? anchor = isDayDone(today, kind: kind) ? today : null;
    anchor ??= _previousActiveDay(kind, today, allowedGap);
    if (anchor == null) return null;
    var cursor = anchor;
    while (true) {
      final previous = _previousActiveDay(kind, cursor, allowedGap);
      if (previous == null) return cursor;
      cursor = previous;
    }
  }

  List<DateTime> _sortedDays(StreakKind kind) => _days(kind)
      .keys
      .map((key) => DateTime.tryParse(key))
      .whereType<DateTime>()
      .toList()
    ..sort();

  /// The longest streak ever recorded, under the current grace setting.
  int longestStreak({StreakKind kind = StreakKind.complete}) {
    final days = _sortedDays(kind);
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
  ({DateTime start, DateTime end})? longestStreakRange({
    StreakKind kind = StreakKind.complete,
  }) {
    final days = _sortedDays(kind);
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

  /// Read-only view of a kind's full history (dayKey → count) for the streak
  /// calendar and the challenges.
  Map<String, int> completionsByDayOf(StreakKind kind) =>
      Map.unmodifiable(_days(kind));

  /// Read-only view of the completion history (dayKey → count).
  Map<String, int> get completionsByDayView =>
      completionsByDayOf(StreakKind.complete);

  /// Read-only view of the recorded completion times (dayKey → minutes of
  /// day) for the time-of-day challenges.
  Map<String, List<int>> get minutesByDayView =>
      Map.unmodifiable(_minutesByDay);

  /// Days on which [kind]'s challenge was met, ever.
  int totalActiveDays({StreakKind kind = StreakKind.complete}) =>
      _days(kind).length;

  /// Total events of [kind] recorded across all days.
  int totalCompletions({StreakKind kind = StreakKind.complete}) =>
      _days(kind).values.fold(0, (sum, count) => sum + count);

  /// The day with the most events of [kind], or null when there is no history.
  MapEntry<String, int>? bestDay({StreakKind kind = StreakKind.complete}) {
    MapEntry<String, int>? best;
    for (final entry in _days(kind).entries) {
      if (best == null || entry.value > best.value) best = entry;
    }
    return best;
  }

  /// 0.0 (no streak) → 1.0 (maximum fire after a year) for a flame's size
  /// and colour.
  double flameProgress({StreakKind kind = StreakKind.complete, DateTime? now}) =>
      min(1.0, currentStreak(kind: kind, now: now) / maxStreakDays);

  /// Re-schedules (or cancels) every "keep your streak" reminder to match the
  /// current settings and today's state. One-shot schedules: they re-arm on
  /// every app start, recorded event and settings change.
  Future<void> syncReminder({DateTime? now}) async {
    final kinds = enabledKinds;
    if (!Config.streakReminderEnabled ||
        !Config.showStreak ||
        !Config.isFeatureEnabled('streak') ||
        kinds.isEmpty) {
      // Reminders are re-synced on every recorded event, so skip the (up to
      // 24) cancel calls once we know nothing is pending. Starts true so the
      // first sync after a launch always clears a stale schedule.
      if (_remindersArmed) {
        await NotificationService.cancelStreakReminders();
        _remindersArmed = false;
      }
      return;
    }
    final current = now ?? DateTime.now();
    final today = _dateOnly(current);
    final reminders = Config.streakReminders
        .where((reminder) => reminder.enabled)
        .take(maxStreakReminders)
        .toList();
    await NotificationService.cancelStreakReminders();
    _remindersArmed = reminders.isNotEmpty;
    for (var slot = 0; slot < reminders.length; slot++) {
      final reminder = reminders[slot];
      var fireAt =
          today.add(Duration(minutes: reminder.minutes.clamp(0, 1439)));
      // A time already past, or a day whose challenges are all met, moves the
      // nudge to tomorrow. An unconfigured create/plan slot has no challenge
      // to meet, so it does not block the "all done" shortcut.
      final trackedKinds = kinds
          .where((kind) =>
              kind == StreakKind.complete || Config.streakGoals.containsKey(kind.id))
          .toList();
      if (!fireAt.isAfter(current) ||
          (trackedKinds.isNotEmpty &&
              trackedKinds.every((kind) => isDayDone(current, kind: kind)))) {
        fireAt = fireAt.add(const Duration(days: 1));
      }
      await NotificationService.scheduleStreakReminderSlot(
        slot: slot,
        fireAt: fireAt,
        body: reminderBody(fireAt, kinds: kinds),
        loud: reminder.mode == StreakAlertMode.sound,
      );
    }
  }

  /// The reminder text for [day]: what is still open, plus the streak that is
  /// on the line. Public so the settings preview and the tests can show it.
  /// An unconfigured `create`/`plan` slot has nothing to nudge about, so it is
  /// left out — only a kind with a real challenge behind it can be "open".
  String reminderBody(DateTime day, {List<StreakKind>? kinds}) {
    final active = (kinds ?? enabledKinds)
        .where((kind) =>
            kind == StreakKind.complete || Config.streakGoals.containsKey(kind.id))
        .toList();
    final pending =
        active.where((kind) => !isDayDone(day, kind: kind)).toList();
    if (pending.isEmpty) {
      return 'Everything done today — come back tomorrow to keep it going.';
    }
    final best = active.fold<int>(
        0, (top, kind) => max(top, currentStreak(kind: kind, now: day)));
    final list = pending
        .map((kind) => (kind == StreakKind.complete
                ? kind.label
                : Config.streakGoals[kind.id]!.title)
            .toLowerCase())
        .join(', ');
    final open = 'Still open today: $list.';
    return best > 0 ? '$open Keep your $best-day streak alive.' : open;
  }

  /// Notifies listeners and re-syncs the reminders after a streak-related
  /// setting changed (visibility, grace period, challenges, reminders...).
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
            for (final kind in StreakKind.values)
              _dayMapKeys[kind]!: _days(kind),
            'minutesByDay': _minutesByDay,
          }));
    } catch (_) {}
  }

  /// Awaitable save for tests.
  Future<void> saveNow() => _save();

  void resetForTest() {
    for (final kind in StreakKind.values) {
      _days(kind).clear();
    }
    _minutesByDay.clear();
    _knownTaskUids = {};
    _loaded = false;
    _hadFile = false;
  }
}
