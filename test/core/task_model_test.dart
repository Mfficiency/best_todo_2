import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/task.dart';

void main() {
  test('toggleDone switches task state', () {
    final task = Task(title: 'Test');
    expect(task.isDone, isFalse);
    task.toggleDone();
    expect(task.isDone, isTrue);
  });

  test('tasks generate unique ids', () {
    final a = Task(title: 'a');
    final b = Task(title: 'b');
    expect(a.uid, isNotEmpty);
    expect(b.uid, isNotEmpty);
    expect(a.uid, isNot(b.uid));
    expect(a.listRanking, isNull);
  });

  test('recurrence fields serialize and deserialize', () {
    final due = DateTime(2026, 2, 21);
    final end = DateTime(2026, 3, 1);
    final task = Task(
      title: 'Recurring',
      dueDate: due,
      isRecurring: true,
      recurrenceEndDate: end,
      recurrenceIntervalDays: 2,
      recurrenceParentUid: 'parent',
      recurrenceInstanceKey: '2026-02-23',
    );

    final map = task.toJson();
    final decoded = Task.fromJson(map);

    expect(decoded.isRecurring, isTrue);
    expect(decoded.recurrenceIntervalDays, 2);
    expect(decoded.recurrenceEndDate, end);
    expect(decoded.recurrenceParentUid, 'parent');
    expect(decoded.recurrenceInstanceKey, '2026-02-23');
  });

  test('legacy recurrenceIntervalDays migrates to frequency/interval', () {
    final legacy = Task.fromJson(<String, dynamic>{
      'title': 'Every other day',
      'dueDate': DateTime(2026, 2, 21).toIso8601String(),
      'isRecurring': true,
      'recurrenceIntervalDays': 2,
      'recurrenceEndDate': DateTime(2026, 3, 1).toIso8601String(),
    });

    expect(legacy.recurrenceFrequency, 'daily');
    expect(legacy.recurrenceInterval, 2);
    expect(legacy.recurrenceEndType, 'date');
    expect(legacy.recurrenceEndDate, DateTime(2026, 3, 1));
    expect(legacy.recurrenceWeekdays, isEmpty);
    expect(legacy.recurrenceExceptionDates, isEmpty);
    expect(legacy.recurrenceOverride, isFalse);
  });

  test('new recurrence fields round-trip through JSON', () {
    final task = Task(
      title: 'Weekly',
      dueDate: DateTime(2026, 2, 23), // a Monday
      isRecurring: true,
      recurrenceFrequency: 'weekly',
      recurrenceInterval: 2,
      recurrenceWeekdays: [DateTime.monday, DateTime.wednesday],
      recurrenceEndType: 'count',
      recurrenceOccurrenceCount: 6,
      recurrenceExceptionDates: ['2026-03-04'],
      recurrenceOverride: true,
    );

    final decoded = Task.fromJson(task.toJson());
    expect(decoded.recurrenceFrequency, 'weekly');
    expect(decoded.recurrenceInterval, 2);
    expect(decoded.recurrenceWeekdays, [DateTime.monday, DateTime.wednesday]);
    expect(decoded.recurrenceEndType, 'count');
    expect(decoded.recurrenceOccurrenceCount, 6);
    expect(decoded.recurrenceExceptionDates, ['2026-03-04']);
    expect(decoded.recurrenceOverride, isTrue);
  });

  test('project fields default and serialize', () {
    final task = Task(title: 'Plain');
    expect(task.projectId, isNull);
    expect(task.kanbanStatus, Task.kanbanTodo);

    task.projectId = 'project_1';
    task.kanbanStatus = Task.kanbanOngoing;

    final decoded = Task.fromJson(task.toJson());
    expect(decoded.projectId, 'project_1');
    expect(decoded.kanbanStatus, Task.kanbanOngoing);
  });

  test('isWish defaults to false and serializes', () {
    final task = Task(title: 'Plain');
    expect(task.isWish, isFalse);
    expect(Task.fromJson(<String, dynamic>{'title': 'legacy'}).isWish, isFalse);

    task.isWish = true;
    expect(Task.fromJson(task.toJson()).isWish, isTrue);
  });
}
