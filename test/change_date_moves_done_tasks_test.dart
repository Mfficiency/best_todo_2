import 'package:flutter_test/flutter_test.dart';
import 'package:best_todo_2/models/task.dart';

void main() {
  test('done tasks move to deleted list on day change', () {
    final tasks = [
      Task(title: 'd1', isDone: true),
      Task(title: 'p1', isDone: false),
      Task(title: 'd2', isDone: true),
    ];
    final deleted = <Task>[];

    void changeDate(int delta) {
      if (delta > 0) {
        final doneTasks = tasks.where((t) => t.isDone).toList();
        for (final task in doneTasks) {
          tasks.remove(task);
          deleted.insert(0, task);
          if (deleted.length > 100) {
            deleted.removeLast();
          }
        }
      }
    }

    changeDate(1);

    expect(tasks.map((t) => t.title).toList(), ['p1']);
    expect(deleted.map((t) => t.title).toList(), ['d2', 'd1']);
  });
}
