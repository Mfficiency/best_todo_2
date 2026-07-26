import 'dart:io';

import 'package:besttodo/models/daily_task_stats.dart';
import 'package:besttodo/models/item_event.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/item_event_journal.dart';
import 'package:besttodo/services/item_history_seeder.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  group('buildSeedEvents (pure)', () {
    test('maps lifecycle timestamps to seeded events, oldest first', () {
      final task = Task(
        title: 'old friend',
        createdAt: DateTime(2026, 1, 1, 9),
        movedAt: DateTime(2026, 1, 3, 10),
        completedAt: DateTime(2026, 1, 5, 20),
        isDone: true,
        dueDate: DateTime(2026, 1, 4, 18),
      );
      final events = ItemHistorySeeder.buildSeedEvents(
        tasks: [task],
        deletedTasks: const [],
        dailyStatsByDay: const {},
      );
      expect(events.map((e) => e.type), [
        ItemEvent.typeCreated,
        ItemEvent.typeScheduled,
        ItemEvent.typeStatusChanged,
      ]);
      expect(events.every((e) => e.seeded), isTrue);
      expect(events.first.patch.single.to, 'old friend');
    });

    test('deleted list tasks produce deleted events; restore heuristic '
        'matches _deriveTaskEvents', () {
      final deleted = Task(
        title: 'swept',
        createdAt: DateTime(2026, 2, 1),
        completedAt: DateTime(2026, 2, 2),
        deletedAt: DateTime(2026, 2, 3),
        isDone: true,
      );
      final restored = Task(
        title: 'came back',
        completedAt: DateTime(2026, 2, 4),
        isDone: false,
      );
      final events = ItemHistorySeeder.buildSeedEvents(
        tasks: [restored],
        deletedTasks: [deleted],
        dailyStatsByDay: const {},
      );
      final forDeleted =
          events.where((e) => e.itemId == deleted.uid).map((e) => e.type);
      expect(forDeleted, [
        ItemEvent.typeCreated,
        ItemEvent.typeStatusChanged,
        ItemEvent.typeDeleted,
      ]);
      final forRestored =
          events.where((e) => e.itemId == restored.uid).map((e) => e.type);
      expect(forRestored,
          [ItemEvent.typeStatusChanged, ItemEvent.typeRestored]);
    });

    test('daily stats fill gaps at day-noon but never duplicate or invent '
        'unknown uids', () {
      final noTimestamps = Task(title: 'stats only');
      final hasCreated =
          Task(title: 'covered', createdAt: DateTime(2026, 3, 1, 8));
      final stats = DailyTaskStats(
        dayKey: '2026-03-02',
        createdDuringDayTaskIds: {
          noTimestamps.uid,
          hasCreated.uid, // already covered by createdAt — must not duplicate
          'gone-uid', // fell off the deleted list — nothing to attach to
        },
        completedFromCreatedTaskIds: {noTimestamps.uid},
      );
      final events = ItemHistorySeeder.buildSeedEvents(
        tasks: [noTimestamps, hasCreated],
        deletedTasks: const [],
        dailyStatsByDay: {stats.dayKey: stats},
      );
      expect(events.where((e) => e.itemId == 'gone-uid'), isEmpty);
      expect(
          events
              .where((e) =>
                  e.itemId == hasCreated.uid &&
                  e.type == ItemEvent.typeCreated)
              .length,
          1);
      final forStatsOnly =
          events.where((e) => e.itemId == noTimestamps.uid).toList();
      expect(forStatsOnly.map((e) => e.type),
          [ItemEvent.typeCreated, ItemEvent.typeStatusChanged]);
      expect(forStatsOnly.first.at, DateTime(2026, 3, 2, 12));
    });
  });

  group('runOnce', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp();
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      await File(
              '${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
          .writeAsString('done');
      StorageService.resetJournalBaselineForTest();
      ItemEventJournal.instance.resetForTest();
    });

    test('seeds once, writes the flag, and never runs twice', () async {
      final service = StorageService();
      final task = Task(
        title: 'pre-journal task',
        createdAt: DateTime(2026, 5, 1, 9),
        movedAt: DateTime(2026, 5, 2, 9),
      );
      await service.saveTaskList([task]);

      await ItemHistorySeeder.runOnce();
      await ItemEventJournal.instance.pendingWrites;

      final events =
          await ItemEventJournal.instance.eventsForItem(task.uid);
      expect(events.map((e) => e.type),
          [ItemEvent.typeCreated, ItemEvent.typeScheduled]);
      expect(events.every((e) => e.seeded), isTrue);
      expect(
          File('${tempDir.path}/${ItemHistorySeeder.seedFlagFileName}')
              .existsSync(),
          isTrue);

      // Second run is a no-op: same event count afterwards.
      await ItemHistorySeeder.runOnce();
      await ItemEventJournal.instance.pendingWrites;
      final again = await ItemEventJournal.instance.eventsForItem(task.uid);
      expect(again.length, events.length);
    });

    test('pre-created flag opts out entirely', () async {
      await File('${tempDir.path}/${ItemHistorySeeder.seedFlagFileName}')
          .writeAsString('done');
      final service = StorageService();
      await service
          .saveTaskList([Task(title: 'x', createdAt: DateTime(2026, 6, 1))]);

      await ItemHistorySeeder.runOnce();
      await ItemEventJournal.instance.pendingWrites;
      expect(await ItemEventJournal.instance.allEvents(), isEmpty);
    });

    test('timeline interleaves seeded past before live events by time',
        () async {
      final service = StorageService();
      final task = Task(
        title: 'veteran',
        createdAt: DateTime(2026, 5, 1, 9),
      );
      await service.saveTaskList([task]);

      // A live edit happens before the deferred seeder gets to run.
      task.title = 'veteran (renamed)';
      await service.saveTaskList([task]);
      await ItemHistorySeeder.runOnce();
      await ItemEventJournal.instance.pendingWrites;

      final events =
          await ItemEventJournal.instance.eventsForItem(task.uid);
      expect(events.first.type, ItemEvent.typeCreated);
      expect(events.first.seeded, isTrue);
      expect(events.last.type, ItemEvent.typeEdited);
      expect(events.last.seeded, isFalse);
    });
  });
}
