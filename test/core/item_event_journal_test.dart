import 'dart:io';

import 'package:besttodo/models/item_event.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/item_event_journal.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/task_detail_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  group('diffSnapshots (pure)', () {
    Map<String, Map<String, dynamic>> snap(List<Task> tasks) =>
        {for (final t in tasks) t.uid: t.toJson()};

    List<ItemEvent> diff(List<Task> before, List<Task> after,
        {Set<String> seen = const {}}) {
      final seqs = <String, int>{};
      return ItemEventJournal.diffSnapshots(
        before: snap(before),
        after: snap(after),
        nextSeq: (uid) => seqs[uid] = (seqs[uid] ?? 0) + 1,
        wasSeen: (uid) => seen.contains(uid),
        at: DateTime(2026, 7, 17, 12),
      );
    }

    test('new uid is a created event carrying the title', () {
      final task = Task(title: 'buy milk');
      final events = diff([], [task]);
      expect(events, hasLength(1));
      expect(events.single.type, ItemEvent.typeCreated);
      expect(events.single.itemId, task.uid);
      expect(events.single.seq, 1);
      expect(events.single.patch.single.to, 'buy milk');
    });

    test('new uid the journal has seen before is a restore', () {
      final task = Task(title: 'back again');
      final events = diff([], [task], seen: {task.uid});
      expect(events.single.type, ItemEvent.typeRestored);
    });

    test('field changes group into one event per aspect', () {
      final before = Task(title: 'a', description: 'x');
      final after = Task(
        uid: before.uid,
        title: 'b',
        description: 'y',
        dueDate: DateTime(2026, 8, 1, 18),
      );
      final events = diff([before], [after]);
      expect(events, hasLength(2));
      final edited =
          events.singleWhere((e) => e.type == ItemEvent.typeEdited);
      expect(edited.patch.map((c) => c.field), ['title', 'description']);
      final scheduled =
          events.singleWhere((e) => e.type == ItemEvent.typeScheduled);
      // Schema v2 records the real interval plus the legacy dueDate mirror
      // (the mirror is what the timeline UI reads for its wording).
      expect(scheduled.patch.map((c) => c.field).toSet(),
          {'dueDate', 'startAt', 'endAt'});
      final due = scheduled.patch.singleWhere((c) => c.field == 'dueDate');
      expect(due.from, isNull);
      expect(due.to, DateTime(2026, 8, 1, 18).toIso8601String());
    });

    test('status, project, wish and label changes get their own types', () {
      final before = Task(title: 'a');
      final after = Task(uid: before.uid, title: 'a')
        ..isDone = true
        ..projectId = 'project_1'
        ..kanbanStatus = Task.kanbanOngoing
        ..isWish = true
        ..label = 'urgent';
      final events = diff([before], [after]);
      expect(events.map((e) => e.type).toSet(), {
        ItemEvent.typeStatusChanged,
        ItemEvent.typeProjectChanged,
        ItemEvent.typeWishChanged,
        ItemEvent.typeLabeled,
      });
      // Per-item sequence keeps counting across the events of one diff.
      expect(events.map((e) => e.seq).toSet(), {1, 2, 3, 4});
    });

    test('listRanking and lifecycle timestamps are ignored', () {
      final before = Task(title: 'a');
      final after = Task(uid: before.uid, title: 'a')
        ..listRanking = 5
        ..movedAt = DateTime(2026, 1, 1)
        ..rescheduledAt = DateTime(2026, 1, 2)
        ..completedAt = DateTime(2026, 1, 3);
      expect(diff([before], [after]), isEmpty);
    });

    test('disappearing uid is a deleted event', () {
      final task = Task(title: 'gone');
      final events = diff([task], []);
      expect(events.single.type, ItemEvent.typeDeleted);
      expect(events.single.itemId, task.uid);
    });
  });

  group('journal persistence through StorageService', () {
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

    test('saves diff into the journal; first contact is silent', () async {
      final service = StorageService();
      final task = Task(title: 'first');
      // First save has no baseline: snapshot only, no events.
      await service.saveTaskList([task]);
      task.title = 'renamed';
      await service.saveTaskList([task]);
      final added = Task(title: 'second');
      await service.saveTaskList([task, added]);
      await service.saveTaskList([added]);

      final events = await ItemEventJournal.instance.allEvents();
      final forFirst =
          events.where((e) => e.itemId == task.uid).toList();
      expect(forFirst.map((e) => e.type),
          [ItemEvent.typeEdited, ItemEvent.typeDeleted]);
      expect(forFirst.map((e) => e.seq), [1, 2]);
      final forAdded =
          events.where((e) => e.itemId == added.uid).toList();
      expect(forAdded.single.type, ItemEvent.typeCreated);
    });

    test('reappearing after a recorded delete is a restore', () async {
      final service = StorageService();
      // First contact only snapshots (no events), so establish the baseline
      // with an empty save — the next save then records phoenix's creation.
      await service.saveTaskList([]);
      final task = Task(title: 'phoenix');
      await service.saveTaskList([task]);
      final other = Task(title: 'keeper');
      await service.saveTaskList([task, other]);
      await service.saveTaskList([other]); // deletes phoenix
      await service.saveTaskList([other, task]); // brings it back

      final events =
          await ItemEventJournal.instance.eventsForItem(task.uid);
      expect(events.map((e) => e.type), [
        ItemEvent.typeCreated,
        ItemEvent.typeDeleted,
        ItemEvent.typeRestored,
      ]);
    });

    test('day rollover sweep records deleted events', () async {
      final service = StorageService();
      await service.saveTaskList([
        Task(title: 'done yesterday', isDone: true),
        Task(title: 'still open'),
      ]);
      await File('${tempDir.path}/last_opened.txt').writeAsString(
          DateTime.now().subtract(const Duration(days: 1)).toIso8601String());
      // A fresh session: the baseline comes from the file on load.
      StorageService.resetJournalBaselineForTest();

      final loaded = await service.loadTaskList();
      expect(loaded.single.title, 'still open');
      final events = await ItemEventJournal.instance.allEvents();
      expect(events.single.type, ItemEvent.typeDeleted);
    });

    test('journal survives a reload and keeps per-item seq counting',
        () async {
      final service = StorageService();
      final task = Task(title: 'v1');
      await service.saveTaskList([task]);
      task.title = 'v2';
      await service.saveTaskList([task]);

      // New session: caches cleared, files remain.
      StorageService.resetJournalBaselineForTest();
      ItemEventJournal.instance.resetForTest();

      final reloaded = await service.loadTaskList();
      reloaded.single.title = 'v3';
      await service.saveTaskList(reloaded);

      final events =
          await ItemEventJournal.instance.eventsForItem(task.uid);
      expect(events.map((e) => e.seq), [1, 2]);
      expect(events.last.patch.single.to, 'v3');
    });

    test('export payload carries the journal as item_events', () async {
      final service = StorageService();
      final task = Task(title: 'exported');
      await service.saveTaskList([task]);
      task.isDone = true;
      await service.saveTaskList([task]);

      final file = await service.exportTaskData(
        tasks: [task],
        deletedTasks: const [],
        dailyStatsByDay: const {},
        path: '${tempDir.path}/export.json',
      );
      expect(file, isNotNull);
      final payload = await file!.readAsString();
      expect(payload, contains('"item_events"'));
      expect(payload, contains('"statusChanged"'));
    });
  });

  group('describeItemEvent', () {
    ItemEvent event(String type,
            {List<FieldChange> patch = const [], bool seeded = false}) =>
        ItemEvent(
          itemId: 'x',
          seq: 1,
          at: DateTime(2026, 7, 17),
          type: type,
          patch: patch,
          seeded: seeded,
        );

    test('covers the common lifecycle wordings', () {
      expect(describeItemEvent(event(ItemEvent.typeCreated)), 'Created');
      expect(describeItemEvent(event(ItemEvent.typeDeleted)), 'Deleted');
      expect(describeItemEvent(event(ItemEvent.typeRestored)), 'Restored');
      expect(
          describeItemEvent(event(ItemEvent.typeStatusChanged,
              patch: [FieldChange('isDone', false, true)])),
          'Completed');
      expect(
          describeItemEvent(event(ItemEvent.typeScheduled, patch: [
            FieldChange('dueDate', null, '2026-08-01T18:00:00.000'),
          ])),
          'Rescheduled to 2026-08-01');
      expect(
          describeItemEvent(event(ItemEvent.typeEdited,
              patch: [FieldChange('title', 'a', 'b')])),
          'Edited title');
      expect(describeItemEvent(event(ItemEvent.typeCreated, seeded: true)),
          'Created (reconstructed)');
    });
  });
}
