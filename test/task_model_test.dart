import 'package:flutter_test/flutter_test.dart';
import 'package:best_todo_2/models/task.dart';

void main() {
  test('toggleDone switches task state', () {
    final task = Task(title: 'Test');
    expect(task.isDone, isFalse);
    task.toggleDone();
    expect(task.isDone, isTrue);
  });

  test('tasks generate unique ids and preserve them through serialization', () {
    final task1 = Task(title: 'A');
    final task2 = Task(title: 'B');
    expect(task1.id, isNotEmpty);
    expect(task2.id, isNotEmpty);
    expect(task1.id, isNot(task2.id));

    final json = task1.toJson();
    final restored = Task.fromJson(json);
    expect(restored.id, task1.id);
  });
}
