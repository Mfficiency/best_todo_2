import '../models/countdown_timer.dart';
import '../models/task.dart';

/// Keeps item-linked countdown timers aligned with their task's due date.
///
/// This is the countdown counterpart of `ReminderSyncService`, but pull-based
/// rather than eager: countdown milestone notifications are a foreground-only
/// feature (checked while the Countdown page is open, no background delivery
/// — see `CountdownTimerPage`'s ticker), so there is nothing that needs the
/// target correct between app opens. [resolveAgainstTasks] is called once
/// when the Countdown page loads instead of on every task-list save.
///
/// Rules:
/// * task's due date changes → the linked timer's [CountdownTimerItem.target]
///   follows it
/// * task is gone (deleted or never existed) → the timer is unlinked, not
///   removed: unlike a reminder, a countdown still means something on its
///   own once detached from its task
class CountdownSyncService {
  /// Applies [task]'s current due date to its linked [timer] in place.
  /// Returns true when the timer changed. Pure — no I/O, no service calls.
  static bool applyTaskToTimer(Task task, CountdownTimerItem timer) {
    final due = task.dueDate;
    if (due == null) return false;
    if (timer.target != due) {
      timer.target = due;
      timer.editedAt = DateTime.now();
      return true;
    }
    return false;
  }

  /// Resolves every item-linked timer in [timers] against [tasks]. Returns
  /// true when [timers] changed and should be persisted. Pure — callers
  /// decide how to persist.
  static bool resolveAgainstTasks(
    List<CountdownTimerItem> timers,
    List<Task> tasks,
  ) {
    var changed = false;
    final byUid = {for (final t in tasks) t.uid: t};
    for (final timer in timers) {
      final itemUid = timer.itemUid;
      if (itemUid == null) continue;
      final task = byUid[itemUid];
      if (task == null) {
        timer.itemUid = null;
        changed = true;
        continue;
      }
      if (applyTaskToTimer(task, timer)) changed = true;
    }
    return changed;
  }

  /// Builds a new timer linked to [task], targeting its due date. Returns
  /// null for an undated task — there is nothing to count down to.
  static CountdownTimerItem? buildLinkedTimer(Task task) {
    final due = task.dueDate;
    if (due == null) return null;
    return CountdownTimerItem(
      label: task.title,
      target: due,
      itemUid: task.uid,
    );
  }
}
