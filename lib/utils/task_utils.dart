import '../models/task.dart';

/// Default deadline time of day for tasks, expressed in minutes since
/// midnight. 18 * 60 == 18:00.
const int defaultDeadlineMinutesOfDay = 18 * 60;

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

/// Ensures every task's deadline time defaults to 18:00. When several tasks
/// fall on the same calendar day the time is incremented by a minute
/// (18:01, 18:02, ...) so that no two tasks on the same day share a time.
///
/// Ordering within a day follows [listRanking] (then [Task.uid] for a stable
/// result), so the earliest-ranked task keeps 18:00. Tasks without a due date
/// are left untouched. The calendar date itself is never changed; only the
/// time-of-day component is normalized.
void applyDefaultDeadlineTimes(List<Task> tasks) {
  final byDay = <String, List<Task>>{};
  for (final task in tasks) {
    final due = task.dueDate;
    if (due == null) continue;
    final key = '${due.year}-${due.month}-${due.day}';
    byDay.putIfAbsent(key, () => <Task>[]).add(task);
  }

  for (final dayTasks in byDay.values) {
    dayTasks.sort((a, b) {
      final ra = a.listRanking ?? 1 << 31;
      final rb = b.listRanking ?? 1 << 31;
      if (ra != rb) return ra.compareTo(rb);
      return a.uid.compareTo(b.uid);
    });
    // Tasks with an explicitly chosen time (e.g. placed on the Chronize
    // timeline) keep their time; only the remaining tasks get the 18:00, 18:01…
    // default slots, assigned in listRanking order.
    var slot = 0;
    for (final task in dayTasks) {
      if (task.hasExplicitTime) continue;
      final due = task.dueDate!;
      // Cap at 23:59 so the time never spills into the next calendar day.
      final minutes =
          (defaultDeadlineMinutesOfDay + slot).clamp(0, 24 * 60 - 1);
      slot++;
      final hour = minutes ~/ 60;
      final minute = minutes % 60;
      final updated = DateTime(due.year, due.month, due.day, hour, minute);
      if (updated != due) {
        task.dueDate = updated;
      }
    }
  }
}
