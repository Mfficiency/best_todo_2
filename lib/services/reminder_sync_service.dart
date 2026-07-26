import 'dart:async' show unawaited;

import '../models/alarm.dart';
import '../models/task.dart';
import 'alarm_service.dart';

/// Keeps item-linked alarms (reminders) aligned with their task's schedule.
///
/// The alarm delivery machinery — ladder, verification, watchdog, ring UI —
/// is untouched: a reminder is an ordinary one-off [Alarm] whose
/// date/hour/minute this service rewrites from the task whenever the task
/// list is saved. Rules:
///
/// * task rescheduled → the reminder follows (anchor ± offset), re-enabling
///   a reminder that was only off because the task had no usable time
/// * task completed or schedule removed → the reminder is disabled (never
///   deleted, so reopening the task revives it)
/// * task gone from the list (deleted) → the reminder is removed
/// * task renamed → the reminder's name follows
///
/// Startup/speed contract: [syncAfterSave] works purely on the in-memory
/// alarm list — when no linked alarm exists (the common case, and always in
/// widget tests where [AlarmService] never loaded) it returns without any
/// I/O; when something changed, the persist + OS reschedule runs
/// fire-and-forget through [AlarmService].
class ReminderSyncService {
  /// Default reminder offset: 15 minutes before the anchor.
  static const int defaultOffsetMinutes = -15;

  /// Applies [task]'s current state to its linked [alarm]. Returns true when
  /// the alarm changed. Pure — no I/O, no service calls.
  static bool applyTaskToAlarm(Task task, Alarm alarm) {
    var changed = false;
    if (alarm.name != task.title) {
      alarm.name = task.title;
      changed = true;
    }
    final anchor =
        alarm.triggerAnchor == Alarm.anchorStart ? task.startAt : task.endAt;
    if (task.isDone || anchor == null) {
      if (alarm.enabled) {
        alarm.enabled = false;
        changed = true;
      }
      return changed;
    }
    final fireAt = anchor.add(Duration(minutes: alarm.triggerOffsetMinutes));
    final date = DateTime(fireAt.year, fireAt.month, fireAt.day);
    if (alarm.isRepeating || alarm.repeatDays.isNotEmpty) {
      alarm.isRepeating = false;
      alarm.repeatDays = <int>[];
      changed = true;
    }
    if (alarm.date != date ||
        alarm.hour != fireAt.hour ||
        alarm.minute != fireAt.minute) {
      alarm.date = date;
      alarm.hour = fireAt.hour;
      alarm.minute = fireAt.minute;
      // The schedule moved: a reminder that was only off because the task
      // was done/undated comes back with it.
      if (!alarm.enabled) alarm.enabled = true;
      changed = true;
    }
    return changed;
  }

  /// Computes the mutations [tasks] imply for [alarms] in place. Returns
  /// true when anything changed; uids of reminders whose task disappeared
  /// are added to [removals]. Pure — callers decide how to persist.
  static bool computeSync(
      List<Task> tasks, List<Alarm> alarms, List<String> removals) {
    var changed = false;
    final byUid = {for (final t in tasks) t.uid: t};
    for (final alarm in alarms) {
      final itemUid = alarm.itemUid;
      if (itemUid == null) continue;
      final task = byUid[itemUid];
      if (task == null) {
        removals.add(alarm.uid);
        changed = true;
        continue;
      }
      if (applyTaskToAlarm(task, alarm)) changed = true;
    }
    return changed;
  }

  /// Called (fire-and-forget) after every task-list save. Free when no
  /// linked alarms exist in memory.
  static void syncAfterSave(List<Task> tasks) {
    try {
      final service = AlarmService.instance;
      final alarms = service.list;
      if (!alarms.any((a) => a.itemUid != null)) return;
      final removals = <String>[];
      final changed = computeSync(tasks, alarms, removals);
      if (!changed) return;
      // Reassign so ValueNotifier listeners (alarm list, widget) rebuild —
      // computeSync mutates the alarm objects in place.
      service.alarms.value = service.list
          .where((a) => !removals.contains(a.uid))
          .toList();
      unawaited(service
          .commitExternalChange(trigger: 'reminder sync after task save')
          .catchError((_) {}));
    } catch (_) {}
  }

  /// Builds a new reminder for [task], anchored [offsetMinutes] from the end
  /// of its schedule (default: 15 minutes before the deadline). Returns null
  /// for undated tasks — there is nothing to anchor to.
  static Alarm? buildReminder(Task task,
      {int offsetMinutes = defaultOffsetMinutes}) {
    if (task.endAt == null) return null;
    final alarm = Alarm(
      name: task.title,
      itemUid: task.uid,
      triggerAnchor: Alarm.anchorEnd,
      triggerOffsetMinutes: offsetMinutes,
    );
    applyTaskToAlarm(task, alarm);
    return alarm;
  }
}
