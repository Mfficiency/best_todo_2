import '../models/task.dart';

/// Sorts tasks so that pending ones come first and completed ones appear last.
/// Within each group, tasks are ordered by their [listRanking] value.
void sortTasks(List<Task> list) {
  list.sort((a, b) {
    final doneCompare = (a.isDone ? 1 : 0).compareTo(b.isDone ? 1 : 0);
    if (doneCompare != 0) return doneCompare;
    return (a.listRanking ?? 1 << 31)
        .compareTo(b.listRanking ?? 1 << 31);
  });
}
