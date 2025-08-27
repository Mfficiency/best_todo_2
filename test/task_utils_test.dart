import 'package:flutter_test/flutter_test.dart';
import 'package:best_todo_2/models/task.dart';
import 'package:best_todo_2/utils/task_utils.dart';

void main() {
  test('completed tasks stay at bottom and new tasks are inserted above them', () {
    final tasks = <Task>[];
    final t1 = Task(title: 'task1');
    final t2 = Task(title: 'task2');
    insertTask(tasks, t1);
    insertTask(tasks, t2);

    t1.isDone = true;
    reorderAfterToggle(tasks, t1);

    final t3 = Task(title: 'task3');
    insertTask(tasks, t3);
    expect(tasks.map((t) => t.title).toList(), ['task2', 'task3', 'task1']);

    t2.isDone = true;
    reorderAfterToggle(tasks, t2);
    t1.isDone = false;
    reorderAfterToggle(tasks, t1);
    expect(tasks.map((t) => t.title).toList(), ['task3', 'task1', 'task2']);
  });
}
