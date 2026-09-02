import '../models/project.dart';
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

/// Dev-only seed helper: spreads [seedTasks] across [projects] — one task per
/// Kanban column (To-Do/Ongoing/Closed) in each project — so the Projects
/// tool opens with populated cards and boards in dev builds. Assignment goes
/// round-robin over the projects, filling every project's To-Do column
/// first, then Ongoing, then Closed; tasks beyond `projects × 3` are left
/// untouched. No-op when either list is empty or when any seed task already
/// carries a project, so manual (re)assignments survive reloads.
void assignDevProjectSeed(List<Task> seedTasks, List<Project> projects) {
  if (seedTasks.isEmpty || projects.isEmpty) return;
  if (seedTasks.any((t) => t.projectId != null)) return;
  const stages = <String>[
    Task.kanbanTodo,
    Task.kanbanOngoing,
    Task.kanbanClosed,
  ];
  final slots = projects.length * stages.length;
  final limit = seedTasks.length < slots ? seedTasks.length : slots;
  for (var i = 0; i < limit; i++) {
    seedTasks[i].projectId = projects[i % projects.length].id;
    seedTasks[i].kanbanStatus = stages[(i ~/ projects.length) % stages.length];
  }
}

/// Ensures every task's deadline time defaults into the 18:00+ range, with
/// several tasks on the same calendar day incrementing by a minute (18:01,
/// 18:02, ...) so that no two share a time. Tasks without a due date are
/// left untouched. The calendar date itself is never changed; only the
/// time-of-day component is normalized.
///
/// A task that already sits on a distinct default-range slot keeps it as-is,
/// even if its [listRanking] relative to its day-mates has since changed —
/// this runs on every task-list save (see HomePage._saveTasks), so without
/// that stability, completing or deleting one task would reshuffle every
/// other same-day task's time as an unrelated, invisible side effect. Only a
/// task that's new to the default range, or actually collides with another,
/// gets assigned a fresh slot — in [listRanking] order (then [Task.uid] for
/// a stable tie-break) among just those needing one.
void applyDefaultDeadlineTimes(List<Task> tasks) {
  final byDay = <String, List<Task>>{};
  for (final task in tasks) {
    final due = task.dueDate;
    if (due == null) continue;
    final key = '${due.year}-${due.month}-${due.day}';
    byDay.putIfAbsent(key, () => <Task>[]).add(task);
  }

  const lastMinuteOfDay = 24 * 60 - 1;

  for (final dayTasks in byDay.values) {
    // Tasks with an explicitly chosen time (e.g. placed on the Chronize
    // timeline) are never touched here.
    final candidates = dayTasks.where((t) => !t.hasExplicitTime).toList()
      ..sort((a, b) {
        final ra = a.listRanking ?? 1 << 31;
        final rb = b.listRanking ?? 1 << 31;
        if (ra != rb) return ra.compareTo(rb);
        return a.uid.compareTo(b.uid);
      });

    final usedMinutes = <int>{};
    final needsSlot = <Task>[];
    for (final task in candidates) {
      final due = task.dueDate!;
      final minute = due.hour * 60 + due.minute;
      if (minute >= defaultDeadlineMinutesOfDay && usedMinutes.add(minute)) {
        continue; // Already on a unique default-range slot — leave it.
      }
      needsSlot.add(task);
    }

    var slot = 0;
    for (final task in needsSlot) {
      var minutes =
          (defaultDeadlineMinutesOfDay + slot).clamp(0, lastMinuteOfDay);
      while (usedMinutes.contains(minutes) && minutes < lastMinuteOfDay) {
        slot++;
        minutes =
            (defaultDeadlineMinutesOfDay + slot).clamp(0, lastMinuteOfDay);
      }
      usedMinutes.add(minutes);
      slot++;
      final due = task.dueDate!;
      final hour = minutes ~/ 60;
      final minute = minutes % 60;
      final updated = DateTime(due.year, due.month, due.day, hour, minute);
      if (updated != due) {
        task.dueDate = updated;
      }
    }
  }
}
