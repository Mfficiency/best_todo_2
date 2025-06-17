import 'package:flutter_test/flutter_test.dart';
import 'package:my_todo_app/models/task.dart';

void main() {
  test('toggleDone switches task state', () {
    final task = Task(title: 'Test');
    expect(task.isDone, isFalse);
    task.toggleDone();
    expect(task.isDone, isTrue);
  });
}
