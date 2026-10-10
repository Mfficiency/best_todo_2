import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/daily_task_stats.dart';
import '../models/item_event.dart';
import '../models/task.dart';
import '../models/task_change_source.dart';
import 'item_event_journal.dart';
import 'storage_service.dart';

/// One-time backfill of the item-history journal from everything the app
/// recorded before the journal existed: the lifecycle timestamps on each
/// task, the deleted list, and the per-day `DailyTaskStats` id sets. Every
/// reconstructed event is marked `seeded`, so timelines can show it as
/// "(reconstructed)" and analytics can tell exact history from best-effort.
///
/// Startup-speed contract: [runOnce] is invoked a few seconds after the
/// first frame (see `main.dart`), never on the startup path. Once the guard
/// flag exists the call is a single file-exists check. Errors are swallowed
/// like all persistence in this app; the seed retries on the next launch if
/// it could not complete.
class ItemHistorySeeder {
  /// Guard flag: present once seeding completed. Public so tests can
  /// pre-create it to opt out.
  static const String seedFlagFileName = 'item_events_seed_v1.txt';

  /// Runs the seed exactly once per install. Safe to call repeatedly.
  static Future<void> runOnce() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final flag = File('${dir.path}/$seedFlagFileName');
      if (await flag.exists()) return;

      final storage = StorageService();
      final tasks = await storage.loadTaskList();
      final deleted = await storage.loadDeletedTaskList();
      final stats = await storage.loadDailyTaskStats();

      final events = buildSeedEvents(
        tasks: tasks,
        deletedTasks: deleted,
        dailyStatsByDay: stats,
      );
      if (events.isNotEmpty) {
        ItemEventJournal.instance.recordEvents(events);
        await ItemEventJournal.instance.pendingWrites;
      }
      await flag.writeAsString(DateTime.now().toIso8601String(), flush: true);
    } catch (_) {
      // No documents dir (web/tests) or a failed write: try again next start.
    }
  }

  /// Reconstructs seed events, oldest first. Pure so tests can cover the
  /// mapping without touching storage. Stats-derived events only cover uids
  /// that still exist in [tasks] or [deletedTasks] — history of items that
  /// fell off the capped deleted list has nothing to attach to.
  static List<ItemEvent> buildSeedEvents({
    required List<Task> tasks,
    required List<Task> deletedTasks,
    required Map<String, DailyTaskStats> dailyStatsByDay,
  }) {
    final events = <ItemEvent>[];
    final knownUids = <String>{
      for (final t in tasks) t.uid,
      for (final t in deletedTasks) t.uid,
    };
    // Track which uids got a created/completed event from task timestamps so
    // the coarser stats-derived events don't duplicate them.
    final createdCovered = <String>{};
    final completedCovered = <String>{};

    ItemEvent seed(String uid, DateTime at, String type,
            [List<FieldChange>? patch]) =>
        ItemEvent(
          itemId: uid,
          seq: 0,
          at: at,
          type: type,
          patch: patch,
          seeded: true,
          source: TaskChangeSource.system,
        );

    for (final task in <Task>[...tasks, ...deletedTasks]) {
      final createdAt = task.createdAt;
      if (createdAt != null) {
        events.add(seed(task.uid, createdAt, ItemEvent.typeCreated,
            [FieldChange('title', null, task.title)]));
        createdCovered.add(task.uid);
      }
      final movedAt = task.movedAt;
      if (movedAt != null) {
        events.add(seed(task.uid, movedAt, ItemEvent.typeScheduled,
            [FieldChange('dueDate', null, task.dueDate?.toIso8601String())]));
      }
      final rescheduledAt = task.rescheduledAt;
      if (rescheduledAt != null && rescheduledAt != movedAt) {
        events.add(seed(task.uid, rescheduledAt, ItemEvent.typeScheduled,
            [FieldChange('dueDate', null, task.dueDate?.toIso8601String())]));
      }
      final completedAt = task.completedAt;
      if (completedAt != null) {
        events.add(seed(task.uid, completedAt, ItemEvent.typeStatusChanged,
            [FieldChange('isDone', false, true)]));
        completedCovered.add(task.uid);
        // Mirrors _deriveTaskEvents: a task with a completion stamp that is
        // neither done nor deleted was restored at some point.
        if (task.deletedAt == null && !task.isDone) {
          events.add(seed(task.uid, completedAt, ItemEvent.typeRestored));
        }
      }
      final deletedAt = task.deletedAt;
      if (deletedAt != null) {
        events.add(seed(task.uid, deletedAt, ItemEvent.typeDeleted));
      }
    }

    // DailyTaskStats know membership per day but not the exact moment; noon
    // of the day keeps the reconstruction honest about its precision.
    for (final stats in dailyStatsByDay.values) {
      final day = DateTime.tryParse('${stats.dayKey}T12:00:00');
      if (day == null) continue;
      for (final uid in stats.createdDuringDayTaskIds) {
        if (!knownUids.contains(uid) || createdCovered.contains(uid)) continue;
        createdCovered.add(uid);
        events.add(seed(uid, day, ItemEvent.typeCreated));
      }
      for (final uid in {
        ...stats.completedFromOpeningTaskIds,
        ...stats.completedFromCreatedTaskIds,
      }) {
        if (!knownUids.contains(uid) || completedCovered.contains(uid)) {
          continue;
        }
        completedCovered.add(uid);
        events.add(seed(uid, day, ItemEvent.typeStatusChanged,
            [FieldChange('isDone', false, true)]));
      }
      for (final uid in stats.movedFromOpeningTaskIds) {
        if (!knownUids.contains(uid)) continue;
        events.add(seed(uid, day, ItemEvent.typeScheduled));
      }
    }

    events.sort((a, b) => a.at.compareTo(b.at));
    return events;
  }
}
