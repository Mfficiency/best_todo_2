import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/utils/date_utils.dart';

void main() {
  test('tasks due tomorrow are not included in today list', () {
    final now = DateTime(2024, 5, 3, 23); // May 3, 11PM
    final tasks = [
      Task(title: 'today', dueDate: DateTime(2024, 5, 3, 10)),
      Task(title: 'tomorrow', dueDate: DateTime(2024, 5, 4, 9)),
    ];

    final todayTasks = tasks.where((task) {
      final diff = dateDiffInDays(task.dueDate!, now);
      return diff <= 0;
    }).toList();

    expect(todayTasks.length, 1);
    expect(todayTasks.first.title, 'today');
  });

  test('dateDiffInDays ignores the time of day', () {
    final now = DateTime(2024, 5, 3, 23);
    final tomorrowMorning = DateTime(2024, 5, 4, 1);
    expect(dateDiffInDays(tomorrowMorning, now), 1);
  });

  test('tasks beyond 30 days fall into next month list', () {
    final now = DateTime(2024, 5, 3);
    final futureDate = DateTime(2300, 1, 1);
    final tasks = [
      Task(title: 'next week', dueDate: now.add(const Duration(days: 5))),
      Task(title: 'next month', dueDate: now.add(const Duration(days: 40))),
      Task(title: 'future', dueDate: futureDate),
    ];

    final nextWeekTasks = tasks.where((task) {
      final diff = dateDiffInDays(task.dueDate!, now);
      return diff >= 3 && diff < 30;
    }).toList();

    final nextMonthTasks = tasks.where((task) {
      final diff = dateDiffInDays(task.dueDate!, now);
      return diff >= 30 && task.dueDate != futureDate;
    }).toList();

    final futureTasks = tasks.where((task) {
      return task.dueDate == futureDate;
    }).toList();

    expect(nextWeekTasks.length, 1);
    expect(nextWeekTasks.first.title, 'next week');
    expect(nextMonthTasks.length, 1);
    expect(nextMonthTasks.first.title, 'next month');
    expect(futureTasks.length, 1);
    expect(futureTasks.first.title, 'future');
  });
}

