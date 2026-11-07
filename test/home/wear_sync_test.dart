import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/alarm.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/streak_service.dart';
import 'package:besttodo/services/task_widget_service.dart';
import 'package:besttodo/services/wear_sync_service.dart';
import 'package:besttodo/utils/label_utils.dart';
import 'package:flutter/services.dart';
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

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('test');
    StorageService.resetJournalBaselineForTest();
    StreakService.instance.resetForTest();
    WearSyncService.resetForTest();
  });

  tearDown(() {
    WearSyncService.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(WearSyncService.channel, null);
  });

  final now = DateTime(2026, 8, 5, 10);
  final today = DateTime(2026, 8, 5);
  final tomorrow = DateTime(2026, 8, 6);

  Task taskDue(String title, DateTime due, {bool done = false, int? ranking}) =>
      Task(
        title: title,
        dueDate: due,
        isDone: done,
        listRanking: ranking,
        createdAt: DateTime(2026, 1, 1),
      );

  group('tasksPayload', () {
    test('today is the widget list, tomorrow the Tomorrow tab', () {
      final tasks = [
        taskDue('done today', today, done: true, ranking: 1),
        taskDue('open today', today, ranking: 2),
        taskDue('overdue', today.subtract(const Duration(days: 3)), ranking: 3),
        taskDue('tomorrow', tomorrow, ranking: 4),
        taskDue('day after', today.add(const Duration(days: 2)), ranking: 5),
        Task(title: 'no date', createdAt: now),
      ];

      final json = jsonDecode(WearSyncService.tasksPayload(tasks, now: now))
          as Map<String, dynamic>;

      expect(json['v'], 1);
      expect(json['day'], '2026-08-05');
      expect((json['today'] as List).map((r) => r['title']),
          ['open today', 'overdue', 'done today']);
      expect((json['today'] as List).last['done'], isTrue);
      expect((json['today'] as List).first['id'], tasks[1].uid);
      expect((json['tomorrow'] as List).map((r) => r['title']), ['tomorrow']);
      expect(json['todayMore'], 0);
      expect(json['tomorrowMore'], 0);
    });

    test('keeps the widget gates: mlr, approval, deleted, food diary', () {
      final tasks = [
        taskDue('visible', today, ranking: 1),
        taskDue('worklist only', today, ranking: 2)..label = worklistToken,
        taskDue('worklist tomorrow', tomorrow, ranking: 3)
          ..label = worklistToken,
        taskDue('waiting', today, ranking: 4)..label = waitingApprovalToken,
        taskDue('deleted', tomorrow, ranking: 5)..deletedAt = now,
        taskDue('meal', today, ranking: 6)..isEatingHabit = true,
        taskDue('research', tomorrow, ranking: 7)..isResearch = true,
      ];

      final json = jsonDecode(WearSyncService.tasksPayload(tasks, now: now))
          as Map<String, dynamic>;

      expect((json['today'] as List).map((r) => r['title']), ['visible']);
      expect(json['tomorrow'], isEmpty);
    });

    test('caps each list and counts the rest', () {
      final tasks = [
        for (var i = 0; i < WearSyncService.maxRows + 3; i++)
          taskDue('t$i', today, ranking: i),
      ];
      final json = jsonDecode(WearSyncService.tasksPayload(tasks, now: now))
          as Map<String, dynamic>;
      expect((json['today'] as List).length, WearSyncService.maxRows);
      expect(json['todayMore'], 3);
    });
  });

  test('alarmsPayload: soonest ring first, switched-off ones last', () {
    final later = Alarm(name: 'Later', hour: 18, minute: 0);
    final soon = Alarm(name: '', hour: 11, minute: 30);
    final off = Alarm(name: 'Off', hour: 6, minute: 0, enabled: false);
    final json = jsonDecode(
            WearSyncService.alarmsPayload([later, off, soon], now: now))
        as Map<String, dynamic>;
    final rows = json['alarms'] as List;
    expect(rows.map((r) => r['name']), ['Alarm', 'Later', 'Off']);
    expect(rows.first['time'], '11:30');
    expect(rows.first['next'],
        DateTime(2026, 8, 5, 11, 30).millisecondsSinceEpoch);
    expect(rows.last['on'], isFalse);
    expect(rows.last['next'], isNull);
  });

  test('parseCommands skips malformed entries', () {
    final commands = WearSyncService.parseCommands([
      '{"action":"complete","id":"a","at":1000}',
      'not json',
      '{"action":"complete"}',
      '{"action":"complete","id":"  "}',
      42,
      {'action': 'complete', 'id': 'b'},
    ]);
    expect(commands.map((c) => c.id), ['a', 'b']);
    expect(commands.first.at, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(commands.last.at, isNull);
    expect(WearSyncService.parseCommands(null), isEmpty);
  });

  test('completionsFor: open tasks once; done, deleted, unknown ignored', () {
    final open = taskDue('open', today);
    final done = taskDue('done', today, done: true);
    final deleted = taskDue('deleted', today)..deletedAt = now;
    final at = DateTime(2026, 8, 5, 9);
    final result = WearSyncService.completionsFor([open, done, deleted], [
      WearCommand(action: WearCommand.complete, id: open.uid, at: at),
      WearCommand(action: WearCommand.complete, id: open.uid),
      WearCommand(action: WearCommand.complete, id: done.uid),
      WearCommand(action: WearCommand.complete, id: deleted.uid),
      const WearCommand(action: WearCommand.complete, id: 'nope'),
      WearCommand(action: 'uncomplete', id: done.uid),
    ]);
    expect(result.map((c) => c.task.title), ['open']);
    expect(result.single.at, at);
  });

  group('completeInStorage (the watch while the app is closed)', () {
    test('completes an open task and records the streak', () async {
      final storage = StorageService();
      final task = taskDue('Water the plants', today, ranking: 1);
      await storage.saveTaskList([task]);

      final at = DateTime(2026, 8, 5, 9, 30);
      await TaskWidgetService.completeInStorage(task.uid, now: at);

      final stored = await storage.loadTaskList();
      expect(stored.single.isDone, isTrue);
      expect(stored.single.completedAt, at);
      expect(StreakService.instance.completionsOn(at), 1);
    });

    test('never un-completes a task that is done already', () async {
      final storage = StorageService();
      final doneAt = DateTime(2026, 8, 5, 8);
      final task = taskDue('Done on the phone', today, done: true, ranking: 1)
        ..completedAt = doneAt;
      await storage.saveTaskList([task]);

      await TaskWidgetService.completeInStorage(task.uid,
          now: DateTime(2026, 8, 5, 9, 30));

      final stored = await storage.loadTaskList();
      expect(stored.single.isDone, isTrue);
      expect(stored.single.completedAt, doneAt);
    });
  });

  group('platform channel', () {
    final calls = <MethodCall>[];

    void mockChannel({List<Object?> queue = const []}) {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WearSyncService.channel, (call) async {
        calls.add(call);
        if (call.method == 'takeCommands') return queue;
        return null;
      });
    }

    test('does nothing off Android', () async {
      mockChannel(queue: ['{"action":"complete","id":"a"}']);
      WearSyncService.debugIsAndroid = false;
      WearSyncService.publishTasks([taskDue('x', today)], now: now);
      expect(await WearSyncService.takeCommands(), isEmpty);
      expect(calls, isEmpty);
    });

    test('publishes a changed list once and hands over the queue', () async {
      mockChannel(queue: ['{"action":"complete","id":"a","at":5}']);
      WearSyncService.debugIsAndroid = true;
      final task = taskDue('x', today);

      WearSyncService.publishTasks([task], now: now);
      WearSyncService.publishTasks([task], now: now);
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c.method == 'publish').length, 1);
      final args = calls.first.arguments as Map;
      expect(args['path'], WearSyncService.todayPath);
      expect(jsonDecode(args['json'] as String)['today'].single['title'], 'x');

      task.isDone = true;
      WearSyncService.publishTasks([task], now: now);
      WearSyncService.publishAlarms([Alarm(name: 'Wake', hour: 7, minute: 0)], now: now);
      await Future<void>.delayed(Duration.zero);
      expect(
          calls
              .where((c) => c.method == 'publish')
              .map((c) => (c.arguments as Map)['path']),
          [
            WearSyncService.todayPath,
            WearSyncService.todayPath,
            WearSyncService.alarmsPath,
          ]);

      final commands = await WearSyncService.takeCommands();
      expect(commands.single.id, 'a');
    });

    test('a failed publish is retried on the next sync', () async {
      WearSyncService.debugIsAndroid = true;
      var attempts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WearSyncService.channel, (call) async {
        attempts++;
        throw PlatformException(code: 'no-play-services');
      });
      final tasks = [taskDue('x', today)];
      WearSyncService.publishTasks(tasks, now: now);
      await Future<void>.delayed(Duration.zero);
      WearSyncService.publishTasks(tasks, now: now);
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 2);
    });
  });

}
