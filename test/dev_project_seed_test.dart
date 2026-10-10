import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/project.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/utils/task_utils.dart';

void main() {
  List<Task> makeTasks(int count) =>
      List.generate(count, (i) => Task(title: 'Seed $i'));

  test('spreads one task per Kanban column into each project', () {
    final tasks = makeTasks(20);

    assignDevProjectSeed(tasks, Project.placeholders);

    final assigned = tasks.where((t) => t.projectId != null).toList();
    expect(assigned, hasLength(9));
    for (final project in Project.placeholders) {
      final stages = assigned
          .where((t) => t.projectId == project.id)
          .map((t) => t.kanbanStatus)
          .toList();
      expect(stages, hasLength(3));
      expect(stages.toSet(),
          {Task.kanbanTodo, Task.kanbanOngoing, Task.kanbanClosed});
    }
    // Tasks beyond the 3×3 slots stay untouched.
    for (final task in tasks.skip(9)) {
      expect(task.projectId, isNull);
      expect(task.kanbanStatus, Task.kanbanTodo);
    }
  });

  test('fills every To-Do column first when there are few tasks', () {
    final tasks = makeTasks(4);

    assignDevProjectSeed(tasks, Project.placeholders);

    expect(tasks[0].projectId, 'project_1');
    expect(tasks[1].projectId, 'project_2');
    expect(tasks[2].projectId, 'project_3');
    for (final task in tasks.take(3)) {
      expect(task.kanbanStatus, Task.kanbanTodo);
    }
    expect(tasks[3].projectId, 'project_1');
    expect(tasks[3].kanbanStatus, Task.kanbanOngoing);
  });

  test('does nothing when a seed task already carries a project', () {
    final tasks = makeTasks(5);
    tasks[2].projectId = 'project_2';
    tasks[2].kanbanStatus = Task.kanbanOngoing;

    assignDevProjectSeed(tasks, Project.placeholders);

    // Manual assignments survive: nothing was added or reshuffled.
    final assigned = tasks.where((t) => t.projectId != null).toList();
    expect(assigned, hasLength(1));
    expect(tasks[2].projectId, 'project_2');
    expect(tasks[2].kanbanStatus, Task.kanbanOngoing);
  });

  test('is a no-op for empty task or project lists', () {
    final tasks = makeTasks(3);
    assignDevProjectSeed(tasks, const []);
    expect(tasks.every((t) => t.projectId == null), isTrue);

    // Must not throw on an empty task list.
    assignDevProjectSeed(<Task>[], Project.placeholders);
  });
}
