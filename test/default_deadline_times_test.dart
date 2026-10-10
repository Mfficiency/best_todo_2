import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/utils/task_utils.dart';

void main() {
  test('a single task on a day is set to 18:00', () {
    final tasks = [
      Task(title: 'a', dueDate: DateTime(2026, 6, 3, 9, 30), listRanking: 1),
    ];

    applyDefaultDeadlineTimes(tasks);

    final due = tasks.single.dueDate!;
    expect(due, DateTime(2026, 6, 3, 18, 0));
  });

  test('tasks on the same day increment by a minute in ranking order', () {
    final tasks = [
      Task(title: 'second', dueDate: DateTime(2026, 6, 3, 8), listRanking: 2),
      Task(title: 'first', dueDate: DateTime(2026, 6, 3, 8), listRanking: 1),
      Task(title: 'third', dueDate: DateTime(2026, 6, 3, 8), listRanking: 3),
    ];

    applyDefaultDeadlineTimes(tasks);

    Task byTitle(String t) => tasks.firstWhere((task) => task.title == t);
    expect(byTitle('first').dueDate, DateTime(2026, 6, 3, 18, 0));
    expect(byTitle('second').dueDate, DateTime(2026, 6, 3, 18, 1));
    expect(byTitle('third').dueDate, DateTime(2026, 6, 3, 18, 2));
  });

  test('different days each start fresh at 18:00', () {
    final tasks = [
      Task(title: 'mon', dueDate: DateTime(2026, 6, 1, 8), listRanking: 1),
      Task(title: 'tue', dueDate: DateTime(2026, 6, 2, 8), listRanking: 1),
    ];

    applyDefaultDeadlineTimes(tasks);

    expect(tasks[0].dueDate, DateTime(2026, 6, 1, 18, 0));
    expect(tasks[1].dueDate, DateTime(2026, 6, 2, 18, 0));
  });

  test('the calendar date is preserved, only the time changes', () {
    final tasks = [
      Task(title: 'a', dueDate: DateTime(2300, 1, 1), listRanking: 1),
    ];

    applyDefaultDeadlineTimes(tasks);

    final due = tasks.single.dueDate!;
    expect(due.year, 2300);
    expect(due.month, 1);
    expect(due.day, 1);
    expect(due.hour, 18);
    expect(due.minute, 0);
  });

  test('tasks without a due date are left untouched', () {
    final tasks = [Task(title: 'no date')];

    applyDefaultDeadlineTimes(tasks);

    expect(tasks.single.dueDate, isNull);
  });
}
