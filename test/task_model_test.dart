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
}
