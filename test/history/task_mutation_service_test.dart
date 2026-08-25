import 'dart:io';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/task_change_source.dart';
import 'package:besttodo/services/item_event_journal.dart';
import 'package:besttodo/services/item_repository.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/task_mutation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Lets the microtask [TaskMutationService] schedules internally (to
/// coalesce same-tick note* calls into one undo entry) run before assertions
/// look at the stacks.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Directory tempDir;
  final service = TaskMutationService.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    StorageService.resetJournalBaselineForTest();
    ItemEventJournal.instance.resetForTest();
    service.resetForTest();
  });

  group('note* + flush', () {
    test('an unchanged list produces no undo entry', () async {
      final tasks = [Task(title: 'a')];
      service.noteBaseline(active: tasks, deleted: const [], bin: const []);
      service.noteActiveChange(tasks);
      await _settle();
      expect(service.canUndo, isFalse);
    });

    test('a real change pushes exactly one undo entry', () async {
      final tasks = [Task(title: 'a')];
      service.noteBaseline(active: tasks, deleted: const [], bin: const []);
      tasks.add(Task(title: 'b'));
      service.noteActiveChange(tasks);
      await _settle();
      expect(service.canUndo, isTrue);
      expect(service.undoDescription, 'Created "b"');
    });

    test(
        'active + deleted noted back to back (an archive) coalesce into one entry',
        () async {
      final task = Task(title: 'gone');
      final active = [task];
      final deleted = <Task>[];
      service.noteBaseline(active: active, deleted: deleted, bin: const []);

      active.remove(task);
      deleted.add(task);
      // Mirrors how a delete handler calls _saveTasks() then
      // _saveDeletedTasks() synchronously, with no await between them.
      service.noteActiveChange(active);
      service.noteDeletedChange(deleted);
      await _settle();

      expect(service.canUndo, isTrue);
      expect(service.undoDescription, 'Archived "gone"');
      // Exactly one entry, not two — a bulk/paired change undoes as one
      // action.
      final undone = await service.undo();
      expect(undone, isNotNull);
      expect(service.canUndo, isFalse);
    });

    test(
        'deleted + bin noted back to back (archive -> bin) coalesce into one entry',
        () async {
      final task = Task(title: 'moved on');
      final deleted = [task];
      final bin = <Task>[];
      service.noteBaseline(active: const [], deleted: deleted, bin: bin);

      deleted.remove(task);
      bin.add(task);
      // Mirrors HomePage._moveArchivedToBin: _saveDeletedTasks() then
      // _saveBinTasks(), synchronously, no await between them.
      service.noteDeletedChange(deleted);
      service.noteBinChange(bin);
      await _settle();

      expect(service.canUndo, isTrue);
      expect(service.undoDescription, 'Deleted "moved on"');
      final undone = await service.undo();
      expect(undone, isNotNull);
      expect(undone!.deleted.single.title, 'moved on');
      expect(undone.bin, isEmpty);
      expect(service.canUndo, isFalse);
    });

    test('a Waiting for Approval denial (active straight to bin) reads as deleted',
        () async {
      final task = Task(title: 'denied');
      final active = [task];
      final bin = <Task>[];
      service.noteBaseline(active: active, deleted: const [], bin: bin);

      active.remove(task);
      bin.add(task);
      service.noteActiveChange(active);
      service.noteBinChange(bin);
      await _settle();

      expect(service.undoDescription, 'Deleted "denied"');
    });

    test('a new mutation after the first is a second, separate entry',
        () async {
      final tasks = [Task(title: 'a')];
      service.noteBaseline(active: tasks, deleted: const [], bin: const []);

      tasks.add(Task(title: 'b'));
      service.noteActiveChange(tasks);
      await _settle();

      tasks.add(Task(title: 'c'));
      service.noteActiveChange(tasks);
      await _settle();

      expect(service.undoDescription, 'Created "c"');
      await service.undo();
      expect(service.undoDescription, 'Created "b"');
    });
  });

  group('undo/redo', () {
    test('undo restores the prior snapshot and enables redo', () async {
      final task = Task(title: 'a');
      final tasks = [task];
      service.noteBaseline(active: tasks, deleted: const [], bin: const []);

      task.isDone = true;
      service.noteActiveChange(tasks);
      await _settle();
      expect(service.undoDescription, 'Completed "a"');

      final result = await service.undo();
      expect(result, isNotNull);
      expect(result!.active.single.isDone, isFalse);
      expect(service.canUndo, isFalse);
      expect(service.canRedo, isTrue);
      expect(service.redoDescription, 'Completed "a"');
    });

    test('redo re-applies the undone change', () async {
      final task = Task(title: 'a');
      final tasks = [task];
      service.noteBaseline(active: tasks, deleted: const [], bin: const []);
      task.isDone = true;
      service.noteActiveChange(tasks);
      await _settle();

      await service.undo();
      final redone = await service.redo();
      expect(redone, isNotNull);
      expect(redone!.active.single.isDone, isTrue);
      expect(service.canRedo, isFalse);
      expect(service.canUndo, isTrue);
    });

    test('restoring straight from the bin to active is one undo entry',
        () async {
      final task = Task(title: 'from bin');
      final bin = [task];
      final active = <Task>[];
      service.noteBaseline(active: active, deleted: const [], bin: bin);

      bin.remove(task);
      active.add(task);
      service.noteActiveChange(active);
      service.noteBinChange(bin);
      await _settle();

      expect(service.undoDescription, 'Restored "from bin"');
      final result = await service.undo();
      expect(result!.active, isEmpty);
      expect(result.bin.single.title, 'from bin');
    });

    test('multiple sequential undos walk back through history in order',
        () async {
      final tasks = <Task>[];
      service.noteBaseline(active: tasks, deleted: const [], bin: const []);

      tasks.add(Task(title: 'first'));
      service.noteActiveChange(tasks);
      await _settle();
      tasks.add(Task(title: 'second'));
      service.noteActiveChange(tasks);
      await _settle();
      tasks.add(Task(title: 'third'));
      service.noteActiveChange(tasks);
      await _settle();

      final afterFirstUndo = await service.undo();
      expect(afterFirstUndo!.active.map((t) => t.title), ['first', 'second']);
      final afterSecondUndo = await service.undo();
      expect(afterSecondUndo!.active.map((t) => t.title), ['first']);
      final afterThirdUndo = await service.undo();
      expect(afterThirdUndo!.active, isEmpty);
      expect(service.canUndo, isFalse);
    });

    test('a fresh mutation after an undo clears the redo stack', () async {
      final tasks = [Task(title: 'a')];
      service.noteBaseline(active: tasks, deleted: const [], bin: const []);
      tasks.add(Task(title: 'b'));
      service.noteActiveChange(tasks);
      await _settle();

      await service.undo();
      expect(service.canRedo, isTrue);

      tasks.add(Task(title: 'c'));
      service.noteActiveChange(tasks);
      await _settle();
      expect(service.canRedo, isFalse);
    });

    test('undo/redo persist through the repository tagged accordingly',
        () async {
      // Mirrors how home_page._saveTasks() pairs a note* call with the
      // actual persist, which is what feeds StorageService's own journal
      // baseline (a separate concern from TaskMutationService's).
      final repo = ItemRepository.instance;
      final task = Task(title: 'a');
      final tasks = [task];
      await repo.saveItems(tasks);
      service.noteBaseline(active: tasks, deleted: const [], bin: const []);

      task.isDone = true;
      service.noteActiveChange(tasks);
      await repo.saveItems(tasks);
      await _settle();

      await service.undo();
      final events = await ItemEventJournal.instance.eventsForItem(task.uid);
      expect(events.last.source, TaskChangeSource.undo);

      await service.redo();
      final eventsAfterRedo =
          await ItemEventJournal.instance.eventsForItem(task.uid);
      expect(eventsAfterRedo.last.source, TaskChangeSource.redo);
    });

    test('undo on an empty stack returns null and stays a no-op', () async {
      expect(await service.undo(), isNull);
      expect(await service.redo(), isNull);
    });
  });

  group('bounded history', () {
    test('the undo stack never grows past maxEntries', () async {
      final tasks = <Task>[];
      service.noteBaseline(active: tasks, deleted: const [], bin: const []);
      for (var i = 0; i < TaskMutationService.maxEntries + 10; i++) {
        tasks.add(Task(title: 'task $i'));
        service.noteActiveChange(tasks);
        await _settle();
      }
      var undoCount = 0;
      while (service.canUndo) {
        await service.undo();
        undoCount++;
      }
      expect(undoCount, TaskMutationService.maxEntries);
    });
  });

  group('describeChange wording', () {
    Map<String, Map<String, dynamic>> snap(List<Task> tasks) =>
        {for (final t in tasks) t.uid: t.toJson()};

    test('bulk changes of the same kind describe as one grouped phrase', () {
      final a = Task(title: 'a');
      final b = Task(title: 'b');
      final before = [Task(uid: a.uid, title: 'a'), Task(uid: b.uid, title: 'b')];
      final after = [
        Task(uid: a.uid, title: 'a', isDone: true),
        Task(uid: b.uid, title: 'b', isDone: true),
      ];
      final description = TaskMutationService.describeChange(
        beforeActive: snap(before),
        afterActive: snap(after),
        beforeDeleted: const {},
        afterDeleted: const {},
      );
      expect(description, 'Completed 2 tasks');
    });

    test('an empty diff describes as "Updated tasks"', () {
      final description = TaskMutationService.describeChange(
        beforeActive: const {},
        afterActive: const {},
        beforeDeleted: const {},
        afterDeleted: const {},
      );
      expect(description, 'Updated tasks');
    });

    test('archive, bin-move and restore each get their own wording', () {
      final archived = Task(title: 'archived one');
      final describeArchive = TaskMutationService.describeChange(
        beforeActive: snap([archived]),
        afterActive: const {},
        beforeDeleted: const {},
        afterDeleted: snap([archived]),
      );
      expect(describeArchive, 'Archived "archived one"');

      final binned = Task(title: 'binned one');
      final describeBin = TaskMutationService.describeChange(
        beforeActive: const {},
        afterActive: const {},
        beforeDeleted: snap([binned]),
        afterDeleted: const {},
        beforeBin: const {},
        afterBin: snap([binned]),
      );
      expect(describeBin, 'Deleted "binned one"');

      final restored = Task(title: 'restored one');
      final describeRestore = TaskMutationService.describeChange(
        beforeActive: const {},
        afterActive: snap([restored]),
        beforeDeleted: const {},
        afterDeleted: const {},
        beforeBin: snap([restored]),
        afterBin: const {},
      );
      expect(describeRestore, 'Restored "restored one"');
    });
  });
}
