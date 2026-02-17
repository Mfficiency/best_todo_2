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
}

