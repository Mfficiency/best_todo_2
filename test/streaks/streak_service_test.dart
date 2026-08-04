import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/daily_task_stats.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/streak_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final day = DateTime(2026, 8, 4);
  DateTime daysAgo(int n) => day.subtract(Duration(days: n));

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    StreakService.instance.resetForTest();
    Config.showStreak = true;
    Config.streakGraceHours = 24;
    Config.streakReminderEnabled = false;
    Config.streakCompletionAnimation = true;
  });

  test('first completion of a day is flagged, later ones are not', () {
    final service = StreakService.instance;
    expect(service.recordCompletion(day), isTrue);
    expect(service.recordCompletion(day), isFalse);
    expect(service.completionsOn(day), 2);
    expect(service.currentStreak(now: day), 1);
  });

  test('consecutive days build a streak; today pending does not break it', () {
    final service = StreakService.instance;
    service.recordCompletion(daysAgo(3));
    service.recordCompletion(daysAgo(2));
    service.recordCompletion(daysAgo(1));
    // Nothing done today yet — the streak still stands at 3.
    expect(service.currentStreak(now: day), 3);
    service.recordCompletion(day);
    expect(service.currentStreak(now: day), 4);
  });

  test('24h grace: a missed day breaks the streak', () {
    Config.streakGraceHours = 24;
    final service = StreakService.instance;
    service.recordCompletion(daysAgo(4));
    service.recordCompletion(daysAgo(3));
    // daysAgo(2) missed.
    service.recordCompletion(daysAgo(1));
    service.recordCompletion(day);
    expect(service.currentStreak(now: day), 2);
  });

  test('48h grace: one missed day is forgiven, two are not', () {
    Config.streakGraceHours = 48;
    final service = StreakService.instance;
    service.recordCompletion(daysAgo(4));
    service.recordCompletion(daysAgo(3));
    // daysAgo(2) missed — forgiven under 48h.
    service.recordCompletion(daysAgo(1));
    service.recordCompletion(day);
    expect(service.currentStreak(now: day), 4);

    StreakService.instance.resetForTest();
    service.recordCompletion(daysAgo(5));
    // daysAgo(4) and daysAgo(3) both missed — streak broken even with 48h.
    service.recordCompletion(daysAgo(2));
    service.recordCompletion(daysAgo(1));
    expect(service.currentStreak(now: day), 2);
  });

  test('48h grace: yesterday missed still shows the streak from before', () {
    Config.streakGraceHours = 48;
    final service = StreakService.instance;
    service.recordCompletion(daysAgo(3));
    service.recordCompletion(daysAgo(2));
    // Yesterday missed, today not done yet — 48h keeps it alive.
    expect(service.currentStreak(now: day), 2);
    Config.streakGraceHours = 24;
    expect(service.currentStreak(now: day), 0);
  });

  test('untoggling the only completion removes the day again', () {
    final service = StreakService.instance;
    service.recordCompletion(day);
    expect(service.currentStreak(now: day), 1);
    service.recordUncompletion(day);
    expect(service.currentStreak(now: day), 0);
    expect(service.completionsOn(day), 0);

    // Two completions: untoggling one keeps the day.
    service.recordCompletion(day);
    service.recordCompletion(day);
    service.recordUncompletion(day);
    expect(service.currentStreak(now: day), 1);
  });

  test('streak history persists across a reload', () async {
    final service = StreakService.instance;
    service.recordCompletion(daysAgo(1));
    service.recordCompletion(day);
    service.recordCompletion(day);
    await service.saveNow();

    service.resetForTest();
    expect(service.currentStreak(now: day), 0);
    await service.load();
    expect(service.currentStreak(now: day), 2);
    expect(service.completionsOn(day), 2);
    expect(service.needsSeed, isFalse);
  });

  test('longest streak scans all history under the grace setting', () {
    final service = StreakService.instance;
    // Runs: 5 days (10..6 days ago), gap, 2 days (2..1 days ago).
    for (var back = 10; back >= 6; back--) {
      service.recordCompletion(daysAgo(back));
    }
    service.recordCompletion(daysAgo(2));
    service.recordCompletion(daysAgo(1));
    expect(service.longestStreak(), 5);
    Config.streakGraceHours = 48;
    // Still two separate runs (3 missed days between them).
    expect(service.longestStreak(), 5);
  });

  test('seedFromHistory merges daily stats and completedAt without doubles',
      () async {
    final service = StreakService.instance;
    await service.load();
    expect(service.needsSeed, isTrue);

    final statsDay = StreakService.dayKey(daysAgo(1));
    final stats = DailyTaskStats(dayKey: statsDay)
      ..completedFromOpeningTaskIds.addAll({'a', 'b'})
      ..completedFromCreatedTaskIds.add('c');
    final doneTask = Task(title: 'done', dueDate: daysAgo(1))
      ..isDone = true
      ..completedAt = daysAgo(1);
    final wish = Task(title: 'wish', isWish: true)
      ..isDone = true
      ..completedAt = day;

    service.seedFromHistory(
      tasks: [doneTask, wish],
      dailyStats: {statsDay: stats},
    );

    // Stats say 3 for yesterday, the task list says 1 → the larger wins.
    expect(service.completionsOn(daysAgo(1)), 3);
    // The wish item must not create a streak day.
    expect(service.completionsOn(day), 0);
    expect(service.needsSeed, isFalse);
  });

  test('flame progress reaches maximum fire after a year', () {
    final service = StreakService.instance;
    expect(service.flameProgress(now: day), 0);
    for (var back = 400; back >= 0; back--) {
      service.recordCompletion(daysAgo(back));
    }
    expect(service.currentStreak(now: day), 401);
    expect(service.flameProgress(now: day), 1.0);
  });

  test('fun stats: totals, best day and streak start', () {
    final service = StreakService.instance;
    service.recordCompletion(daysAgo(2));
    service.recordCompletion(daysAgo(1));
    service.recordCompletion(daysAgo(1));
    service.recordCompletion(daysAgo(1));
    service.recordCompletion(day);
    expect(service.totalActiveDays(), 3);
    expect(service.totalCompletions(), 5);
    expect(service.bestDay()!.key, StreakService.dayKey(daysAgo(1)));
    expect(service.bestDay()!.value, 3);
    expect(service.currentStreakStart(now: day), daysAgo(2));
  });
}
