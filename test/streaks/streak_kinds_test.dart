import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/streak_goal.dart';
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
    Config.streakGoals = {};
    for (final key in Config.streakKindKeys) {
      Config.streakKindEnabled[key] = true;
    }
  });

  test('the three flames keep independent streaks', () {
    final service = StreakService.instance;
    service.recordCompletion(daysAgo(1));
    service.recordCompletion(day);
    service.recordGoal(StreakKind.create, day);

    expect(service.currentStreak(kind: StreakKind.complete, now: day), 2);
    expect(service.currentStreak(kind: StreakKind.create, now: day), 1);
    expect(service.currentStreak(kind: StreakKind.plan, now: day), 0);
    // The no-argument form still means the completion streak.
    expect(service.currentStreak(now: day), 2);
  });

  test('a goal is recorded once per day, however often it fires', () {
    final service = StreakService.instance;
    expect(service.recordGoal(StreakKind.plan, day), isTrue);
    expect(service.recordGoal(StreakKind.plan, day), isFalse);
    expect(service.completionsOn(day, kind: StreakKind.plan), 1);
    expect(service.isDayDone(day, kind: StreakKind.plan), isTrue);
  });

  test('un-completing a task leaves the other flames alone', () {
    final service = StreakService.instance;
    service.recordCompletion(day);
    service.recordGoal(StreakKind.create, day);
    service.recordGoal(StreakKind.plan, day);

    service.recordUncompletion(day);

    expect(service.isDayDone(day), isFalse);
    expect(service.isDayDone(day, kind: StreakKind.create), isTrue);
    expect(service.isDayDone(day, kind: StreakKind.plan), isTrue);
  });

  test('recordUncompletion reverts a specific goal kind', () {
    final service = StreakService.instance;
    service.recordGoal(StreakKind.create, day);
    expect(service.isDayDone(day, kind: StreakKind.create), isTrue);

    service.recordUncompletion(day, kind: StreakKind.create);

    expect(service.isDayDone(day, kind: StreakKind.create), isFalse);
  });

  test('all three histories survive a save/load round trip', () async {
    final service = StreakService.instance;
    service.recordCompletion(day);
    service.recordGoal(StreakKind.create, day);
    service.recordGoal(StreakKind.create, daysAgo(1));
    service.recordGoal(StreakKind.plan, daysAgo(2));
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

  test('seeding only backfills the complete kind — create/plan are goals now',
      () {
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
    expect(service.totalActiveDays(kind: StreakKind.create), 0);
    expect(service.totalActiveDays(kind: StreakKind.plan), 0);
  });

  test('the dev seed only lights the complete flame', () {
    final service = StreakService.instance;
    service.seedDevStreak(days: 12, now: day);

    expect(service.currentStreak(kind: StreakKind.complete, now: day), 12);
    expect(service.currentStreak(kind: StreakKind.create, now: day), 0);
    expect(service.currentStreak(kind: StreakKind.plan, now: day), 0);
  });

  test('enabledKinds follows the settings switches', () {
    final service = StreakService.instance;
    expect(service.enabledKinds, StreakKind.values);

    Config.streakKindEnabled['create'] = false;
    expect(service.enabledKinds, [StreakKind.complete, StreakKind.plan]);
  });

  test('a task-targeted goal matches its recurring instances, not others', () {
    final goal = StreakGoal(
      target: StreakGoalTarget.task,
      targetId: 'parent-1',
      title: 'Exercise',
    );
    final parent = Task(uid: 'parent-1', title: 'Exercise', isRecurring: true);
    final instance = Task(
        uid: 'instance-1', title: 'Exercise', recurrenceParentUid: 'parent-1');
    final other = Task(uid: 'other', title: 'Something else');

    expect(goal.matches(parent), isTrue);
    expect(goal.matches(instance), isTrue);
    expect(goal.matches(other), isFalse);
  });

  test('a project-targeted goal matches any task filed under it', () {
    final goal = StreakGoal(
      target: StreakGoalTarget.project,
      targetId: 'proj-1',
      title: 'Health',
    );
    final inProject = Task(title: 'Anything', projectId: 'proj-1');
    final elsewhere = Task(title: 'Anything', projectId: 'proj-2');
    final unfiled = Task(title: 'Anything');

    expect(goal.matches(inProject), isTrue);
    expect(goal.matches(elsewhere), isFalse);
    expect(goal.matches(unfiled), isFalse);
  });

  test('isGoalMissing is true only once a task-targeted goal\'s task is gone',
      () {
    final service = StreakService.instance;
    Config.streakGoals['create'] = StreakGoal(
      target: StreakGoalTarget.task,
      targetId: 'parent-1',
      title: 'Exercise',
    );

    service.syncKnownTasks([Task(uid: 'parent-1', title: 'Exercise')]);
    expect(service.isGoalMissing(StreakKind.create), isFalse);

    service.syncKnownTasks([Task(uid: 'other', title: 'Something else')]);
    expect(service.isGoalMissing(StreakKind.create), isTrue);

    // An unconfigured flame is just cold, never "missing".
    expect(service.isGoalMissing(StreakKind.plan), isFalse);
  });

  test('streak goals survive a settings round trip', () {
    Config.streakGoals['create'] = StreakGoal(
      target: StreakGoalTarget.task,
      targetId: 'parent-1',
      title: 'Exercise',
    );
    Config.streakGoals['plan'] = StreakGoal(
      target: StreakGoalTarget.project,
      targetId: 'proj-1',
      title: 'Health',
    );

    final map = Config.toMap();
    Config.streakGoals = {};
    Config.applyMap(map);

    expect(Config.streakGoals['create']!.target, StreakGoalTarget.task);
    expect(Config.streakGoals['create']!.targetId, 'parent-1');
    expect(Config.streakGoals['create']!.title, 'Exercise');
    expect(Config.streakGoals['plan']!.target, StreakGoalTarget.project);
    expect(Config.streakGoals['plan']!.targetId, 'proj-1');
  });

  test('the reminder body ignores unconfigured create/plan slots', () {
    final service = StreakService.instance;
    // Yesterday and the day before are done; today (day) is still open, so
    // the streak-at-risk text and the "still open" text both have something
    // to report without needing a completion on `day` itself.
    service.recordCompletion(daysAgo(1));
    service.recordCompletion(daysAgo(2));

    final body = service.reminderBody(day);
    expect(body, contains('finish a task'));
    expect(body, isNot(contains('no goal set')));
    expect(body, contains('2-day streak'));
  });

  test('the reminder body names a configured goal by its own title', () {
    final service = StreakService.instance;
    Config.streakGoals['create'] = StreakGoal(
      target: StreakGoalTarget.project,
      targetId: 'proj-1',
      title: 'Exercise',
    );
    service.recordCompletion(day);

    final body = service.reminderBody(day);
    expect(body, contains('exercise'));

    service.recordGoal(StreakKind.create, day);
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
