import 'package:flutter_test/flutter_test.dart';
import 'package:best_todo_2/models/task.dart';
import 'package:best_todo_2/utils/date_utils.dart';

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
}
