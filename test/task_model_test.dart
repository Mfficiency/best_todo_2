import 'package:flutter_test/flutter_test.dart';
import 'package:best_todo_2/models/task.dart';

void main() {
  test('toggleDone switches task state', () {
    final task = Task(title: 'Test');
    expect(task.isDone, isFalse);
    task.toggleDone();
    expect(task.isDone, isTrue);
  });
}
