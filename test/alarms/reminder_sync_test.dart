import 'package:besttodo/models/alarm.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/alarm_service.dart';
import 'package:besttodo/services/reminder_sync_service.dart';
import 'package:besttodo/ui/task_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Alarm reminder-link JSON', () {
    test('standalone alarms serialize exactly as before (no link keys)', () {
      final map = Alarm(name: 'wake up').toJson();
      expect(map.containsKey('itemUid'), isFalse);
      expect(map.containsKey('triggerAnchor'), isFalse);
      expect(map.containsKey('triggerOffsetMinutes'), isFalse);
    });

    test('linked alarms round-trip their link', () {
      final alarm = Alarm(
        name: 'hand in report',
        itemUid: 'task-1',
        triggerAnchor: Alarm.anchorStart,
        triggerOffsetMinutes: -30,
      );
      final decoded = Alarm.fromJson(alarm.toJson());
      expect(decoded.itemUid, 'task-1');
      expect(decoded.triggerAnchor, Alarm.anchorStart);
      expect(decoded.triggerOffsetMinutes, -30);
    });
  });

  group('applyTaskToAlarm', () {
    test('follows the task deadline with the offset applied', () {
      final task = Task(
        title: 'hand in report',
        dueDate: DateTime(2026, 8, 1, 18, 0),
      );
      final alarm = ReminderSyncService.buildReminder(task)!;
      expect(alarm.itemUid, task.uid);
      expect(alarm.date, DateTime(2026, 8, 1));
      expect(alarm.hour, 17);
      expect(alarm.minute, 45);
      expect(alarm.enabled, isTrue);

      task.dueDate = DateTime(2026, 8, 3, 9, 0);
      expect(ReminderSyncService.applyTaskToAlarm(task, alarm), isTrue);
      expect(alarm.date, DateTime(2026, 8, 3));
      expect(alarm.hour, 8);
      expect(alarm.minute, 45);
      // Unchanged state reports no change.
      expect(ReminderSyncService.applyTaskToAlarm(task, alarm), isFalse);
    });

    test('completing disables; rescheduling re-enables; rename follows', () {
      final task = Task(title: 'v1', dueDate: DateTime(2026, 8, 1, 18));
      final alarm = ReminderSyncService.buildReminder(task)!;

      task.isDone = true;
      expect(ReminderSyncService.applyTaskToAlarm(task, alarm), isTrue);
      expect(alarm.enabled, isFalse);

      task.isDone = false;
      task.title = 'v2';
      task.dueDate = DateTime(2026, 8, 2, 18);
      expect(ReminderSyncService.applyTaskToAlarm(task, alarm), isTrue);
      expect(alarm.enabled, isTrue);
      expect(alarm.name, 'v2');
    });

    test('a task without a schedule cannot get a reminder; losing the '
        'schedule disables an existing one', () {
      final undated = Task(title: 'someday');
      expect(ReminderSyncService.buildReminder(undated), isNull);

      final task = Task(title: 'x', dueDate: DateTime(2026, 8, 1, 18));
      final alarm = ReminderSyncService.buildReminder(task)!;
      task.dueDate = null;
      expect(ReminderSyncService.applyTaskToAlarm(task, alarm), isTrue);
      expect(alarm.enabled, isFalse);
    });

    test('start-anchored reminders use the interval start', () {
      final task = Task(
        title: 'deep work',
        startAt: DateTime(2026, 8, 3, 9),
        endAt: DateTime(2026, 8, 3, 11),
        hasExplicitTime: true,
      );
      final alarm = Alarm(
        name: 'deep work',
        itemUid: task.uid,
        triggerAnchor: Alarm.anchorStart,
        triggerOffsetMinutes: -5,
      );
      ReminderSyncService.applyTaskToAlarm(task, alarm);
      expect(alarm.hour, 8);
      expect(alarm.minute, 55);
    });
  });

  group('computeSync', () {
    test('reminders of vanished tasks are listed for removal', () {
      final kept = Task(title: 'kept', dueDate: DateTime(2026, 8, 1, 18));
      final keptReminder = ReminderSyncService.buildReminder(kept)!;
      final orphan = Alarm(name: 'orphan', itemUid: 'gone-uid');
      final standalone = Alarm(name: 'wake up');

      final removals = <String>[];
      final changed = ReminderSyncService.computeSync(
          [kept], [keptReminder, orphan, standalone], removals);
      expect(changed, isTrue);
      expect(removals, [orphan.uid]);
    });
  });

  group('TaskReminderSection', () {
    setUp(() => AlarmService.instance.alarms.value = <Alarm>[]);
    tearDown(() => AlarmService.instance.alarms.value = <Alarm>[]);

    Future<void> pumpDetail(WidgetTester tester, Task task) async {
      await tester.pumpWidget(MaterialApp(home: TaskDetailPage(task: task)));
      await tester.pump();
    }

    testWidgets('undated tasks offer no reminder', (tester) async {
      await pumpDetail(tester, Task(title: 'someday'));
      expect(find.text('Remind me 15 min before due'), findsNothing);
    });

    testWidgets('dated tasks offer the one-tap reminder', (tester) async {
      await pumpDetail(
          tester, Task(title: 'due', dueDate: DateTime(2026, 8, 1, 18)));
      expect(find.text('Remind me 15 min before due'), findsOneWidget);
    });

    testWidgets('an existing linked reminder shows with a remove action',
        (tester) async {
      final task = Task(title: 'due', dueDate: DateTime(2026, 8, 1, 18));
      AlarmService.instance.alarms.value = [
        ReminderSyncService.buildReminder(task)!
      ];
      await pumpDetail(tester, task);
      expect(find.text('Remind me 15 min before due'), findsNothing);
      expect(find.byTooltip('Remove reminder'), findsOneWidget);
      expect(find.textContaining('17:45'), findsOneWidget);
    });
  });
}
