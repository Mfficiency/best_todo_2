import 'package:flutter_test/flutter_test.dart';
import 'package:best_todo_2/models/task.dart';

void main() {
  group('task reordering', () {
    test('reordering updates list rankings', () {
      final tasks = [
        Task(title: 'a', listRanking: 1),
        Task(title: 'b', listRanking: 2),
        Task(title: 'c', listRanking: 3),
      ];

      // Simulate reorder from index 0 to 2 (move first to end)
      final oldIndex = 0;
      var newIndex = 2;
      if (newIndex > oldIndex) newIndex -= 1;
      final task = tasks.removeAt(oldIndex);
      tasks.insert(newIndex, task);
      for (var i = 0; i < tasks.length; i++) {
        tasks[i].listRanking = i + 1;
      }

      expect(tasks.map((t) => t.title).toList(), ['b', 'c', 'a']);
      expect(tasks[0].listRanking, 1);
      expect(tasks[1].listRanking, 2);
      expect(tasks[2].listRanking, 3);
    });
  });
}
