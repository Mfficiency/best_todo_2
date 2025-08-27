import 'package:flutter_test/flutter_test.dart';
import 'package:best_todo_2/models/task.dart';
import 'package:best_todo_2/utils/task_utils.dart';

void main() {
  test('completed tasks are sorted to the end', () {
    final tasks = [
      Task(title: 'pending1', isDone: false, listRanking: 1),
      Task(title: 'done1', isDone: true, listRanking: 2),
      Task(title: 'pending2', isDone: false, listRanking: 3),
      Task(title: 'done2', isDone: true, listRanking: 4),
    ];

    sortTasks(tasks);

    expect(tasks.map((t) => t.title).toList(),
        ['pending1', 'pending2', 'done1', 'done2']);
  });

  test('new tasks appear before completed tasks', () {
    final tasks = [
      Task(title: 'pending1', isDone: false, listRanking: 1),
      Task(title: 'done1', isDone: true, listRanking: 2),
    ];
    final newTask = Task(title: 'new', isDone: false);
    tasks.add(newTask);

    sortTasks(tasks);

    expect(tasks.map((t) => t.title).toList(), ['pending1', 'new', 'done1']);
  });
}
