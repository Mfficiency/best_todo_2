import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/streak_kind.dart';
import 'package:besttodo/models/streak_reminder.dart';
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

  late String tempPath;
  final day = DateTime(2026, 8, 4);
  DateTime daysAgo(int n) => day.subtract(Duration(days: n));

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    tempPath = tempDir.path;
    PathProviderPlatform.instance = _FakePathProvider(tempPath);
    StreakService.instance.resetForTest();
    Config.showStreak = true;
    Config.streakGraceHours = 24;
    Config.streakReminderEnabled = false;
    Config.streakReminders = [];
    for (final key in Config.streakKindKeys) {
      Config.streakKindEnabled[key] = true;
    }
  });

  test('the three challenges keep independent streaks', () {
    final service = StreakService.instance;
    service.recordCompletion(daysAgo(1));
    service.recordCompletion(day);
    service.recordCreation(day);

    expect(service.currentStreak(kind: StreakKind.complete, now: day), 2);
    expect(service.currentStreak(kind: StreakKind.create, now: day), 1);
    expect(service.currentStreak(kind: StreakKind.plan, now: day), 0);
    // The no-argument form still means the completion streak.
    expect(service.currentStreak(now: day), 2);
  });

  test('planning is recorded once per day, however often it happens', () {
    final service = StreakService.instance;
    expect(service.recordPlanning(day), isTrue);
    expect(service.recordPlanning(day), isFalse);
    expect(service.completionsOn(day, kind: StreakKind.plan), 1);
    expect(service.isDayDone(day, kind: StreakKind.plan), isTrue);
  });

  test('un-completing a task leaves the other challenges alone', () {
    final service = StreakService.instance;
    service.recordCompletion(day);
    service.recordCreation(day);
    service.recordPlanning(day);

    service.recordUncompletion(day);

    expect(service.isDayDone(day), isFalse);
    expect(service.isDayDone(day, kind: StreakKind.create), isTrue);
    expect(service.isDayDone(day, kind: StreakKind.plan), isTrue);
  });

  test('all three histories survive a save/load round trip', () async {
    final service = StreakService.instance;
    service.recordCompletion(day);
    service.recordCreation(day);
    service.recordCreation(daysAgo(1));
    service.recordPlanning(daysAgo(2));
    await service.saveNow();

    final raw = jsonDecode(await File('$tempPath/streak.json').readAsString())
        as Map<String, dynamic>;
    expect(raw.keys,
        containsAll(['completionsByDay', 'createsByDay', 'planByDay']));

    service.resetForTest();
    await service.load();

    expect(service.currentStreak(kind: StreakKind.complete, now: day), 1);
    expect(service.currentStreak(kind: StreakKind.create, now: day), 2);
    expect(service.totalActiveDays(kind: StreakKind.plan), 1);
  });

  test('a pre-existing file with only completions still loads', () async {
    await File('$tempPath/streak.json').writeAsString(jsonEncode({
      'completionsByDay': {StreakService.dayKey(day): 3},
    }));
    final service = StreakService.instance;
    await service.load();

    expect(service.currentStreak(now: day), 1);
    expect(service.currentStreak(kind: StreakKind.create, now: day), 0);
    expect(service.needsSeed, isFalse);
  });

  test('seeding backfills creates and planning moves from the tasks', () {
    final service = StreakService.instance;
    service.seedFromHistory(
      tasks: [
        Task(title: 'Done', createdAt: daysAgo(3), completedAt: daysAgo(2)),
        Task(title: 'Moved', createdAt: daysAgo(2), movedAt: daysAgo(1)),
        Task(title: 'Fresh', createdAt: daysAgo(1)),
      ],
      dailyStats: {},
    );

    expect(service.isDayDone(daysAgo(2)), isTrue);
    expect(service.isDayDone(daysAgo(3), kind: StreakKind.create), isTrue);
    expect(service.currentStreak(kind: StreakKind.create, now: daysAgo(1)), 3);
    expect(service.isDayDone(daysAgo(1), kind: StreakKind.plan), isTrue);
  });

  test('the dev seed lights all three flames at different lengths', () {
    final service = StreakService.instance;
    service.seedDevStreak(days: 12, now: day);

    expect(service.currentStreak(kind: StreakKind.complete, now: day), 12);
    expect(service.currentStreak(kind: StreakKind.create, now: day), 8);
    expect(service.currentStreak(kind: StreakKind.plan, now: day), 6);
  });

  test('enabledKinds follows the settings switches', () {
    final service = StreakService.instance;
    expect(service.enabledKinds, StreakKind.values);

    Config.streakKindEnabled['create'] = false;
    expect(service.enabledKinds, [StreakKind.complete, StreakKind.plan]);
  });

  test('the reminder body names what is still open and the streak at risk', () {
    final service = StreakService.instance;
    service.recordCompletion(daysAgo(1));
    service.recordCompletion(day);

    final body = service.reminderBody(day);
    expect(body, contains('create a task'));
    expect(body, contains('plan ahead'));
    expect(body, isNot(contains('finish a task')));
    expect(body, contains('2-day streak'));

    service.recordCreation(day);
    service.recordPlanning(day);
    expect(service.reminderBody(day), contains('Everything done today'));
  });

  test('reminders survive a settings round trip', () async {
    Config.streakReminderEnabled = true;
    Config.streakReminders = [
      StreakReminder(minutes: 9 * 60),
      StreakReminder(
          minutes: 21 * 60 + 30, mode: StreakAlertMode.sound, enabled: false),
    ];
    Config.streakKindEnabled['plan'] = false;

    final map = Config.toMap();
    Config.streakReminders = [];
    Config.streakKindEnabled['plan'] = true;
    Config.applyMap(map);

    expect(Config.streakReminders.length, 2);
    expect(Config.streakReminders.first.minutes, 9 * 60);
    expect(Config.streakReminders.first.mode, StreakAlertMode.notification);
    expect(Config.streakReminders.last.mode, StreakAlertMode.sound);
    expect(Config.streakReminders.last.enabled, isFalse);
    expect(Config.isStreakKindEnabled('plan'), isFalse);
    Config.streakKindEnabled['plan'] = true;
  });

  test('settings from before the reminder list migrate to one reminder', () {
    Config.streakReminders = [];
    Config.applyMap({
      'streakReminderEnabled': true,
      'streakReminderMinutes': 19 * 60 + 15,
    });

    expect(Config.streakReminders.length, 1);
    expect(Config.streakReminders.single.minutes, 19 * 60 + 15);
    expect(Config.streakReminders.single.enabled, isTrue);
  });
}
