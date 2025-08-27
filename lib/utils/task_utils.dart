import '../models/task.dart';

int _firstDoneIndex(List<Task> tasks) => tasks.indexWhere((t) => t.isDone);

void insertTask(List<Task> tasks, Task task) {
  final index = _firstDoneIndex(tasks);
  if (index == -1) {
    tasks.add(task);
  } else {
    tasks.insert(index, task);
  }
}

void reorderAfterToggle(List<Task> tasks, Task task) {
  tasks.remove(task);
  if (task.isDone) {
    tasks.add(task);
  } else {
    insertTask(tasks, task);
  }
}

void sortTasks(List<Task> tasks) {
  tasks.sort((a, b) {
    if (a.isDone == b.isDone) return 0;
    return a.isDone ? 1 : -1;
  });
}
