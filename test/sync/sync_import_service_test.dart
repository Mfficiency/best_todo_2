import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/sync_import_service.dart';
import 'package:besttodo/services/sync_service.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory docsDir;
  late Directory syncDir;

  File journalFile() =>
      File('${syncDir.path}/${SyncImportService.journalFileName}');

  Future<void> writeJournal(List<Map<String, dynamic>> ops,
      {int version = 1}) async {
    await journalFile().writeAsString(jsonEncode(<String, dynamic>{
      'journal_version': version,
      'device': 'obsidian-test',
      'ops': ops,
    }));
  }

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('sync_import_docs');
    syncDir = await Directory.systemTemp.createTemp('sync_import_target');
    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
    StorageService.resetJournalBaselineForTest();
    SyncService.resetForTest();
    SyncImportService.resetForTest();
    Config.syncEnabled = true;
    Config.syncFolderPath = syncDir.path;
  });

  tearDown(() {
    Config.syncEnabled = false;
    Config.syncFolderPath = '';
    SyncService.resetForTest();
    SyncImportService.resetForTest();
  });

  test('no journal file: nothing happens, no history entry', () async {
    final entry = await SyncImportService.instance.importPending();
    expect(entry, isNull);
    expect(SyncService.instance.entries.value, isEmpty);
  });

  test('an empty ops array: nothing happens, no history entry', () async {
    await writeJournal(const []);
    final entry = await SyncImportService.instance.importPending();
    expect(entry, isNull);
    expect(SyncService.instance.entries.value, isEmpty);
  });

  test('complete op marks an open task done and re-syncs', () async {
    final task = Task(title: 'Write report');
    await StorageService().saveTaskList([task]);
    await writeJournal([
      {
        'op': 'complete',
        'uid': task.uid,
        'at': DateTime.now().toIso8601String(),
      }
    ]);

    final entry = await SyncImportService.instance.importPending();
    expect(entry, isNotNull);
    expect(entry!.success, isTrue);
    expect(entry.itemCount, 1);
    expect(entry.trigger, 'import');

    final tasks = await StorageService().readTaskListRaw();
    expect(tasks.single.isDone, isTrue);
    expect(tasks.single.completedAt, isNotNull);

    // The journal was truncated to an empty envelope.
    final journalAfter =
        jsonDecode(await journalFile().readAsString()) as Map<String, dynamic>;
    expect(journalAfter['ops'], isEmpty);

    // A re-sync ran so the exported files reflect the import.
    final synced = File('${syncDir.path}/${SyncService.syncFileName}');
    expect(await synced.exists(), isTrue);
    final decoded =
        jsonDecode(await synced.readAsString()) as Map<String, dynamic>;
    expect((decoded['tasks'] as List).single['isDone'], isTrue);

    // A history entry lands in the same Sync history as regular syncs: one
    // for the import, one for the re-sync it triggered.
    expect(SyncService.instance.entries.value.length, 2);
    expect(
      SyncService.instance.entries.value
          .map((e) => e.trigger)
          .toSet(),
      {'import'},
    );
  });

  test('reopen op reopens a done task', () async {
    final task = Task(title: 'Ping team')
      ..isDone = true
      ..completedAt = DateTime.now().subtract(const Duration(hours: 1));
    await StorageService().saveTaskList([task]);
    await writeJournal([
      {
        'op': 'reopen',
        'uid': task.uid,
        'at': DateTime.now().toIso8601String(),
      }
    ]);

    await SyncImportService.instance.importPending();

    final tasks = await StorageService().readTaskListRaw();
    expect(tasks.single.isDone, isFalse);
    expect(tasks.single.completedAt, isNull);
  });

  test('a stale reopen op (older than the local completion) is dropped',
      () async {
    final completedAt = DateTime.now();
    final task = Task(title: 'Ping team')
      ..isDone = true
      ..completedAt = completedAt;
    await StorageService().saveTaskList([task]);
    await writeJournal([
      {
        'op': 'reopen',
        'uid': task.uid,
        'at': completedAt.subtract(const Duration(minutes: 5)).toIso8601String(),
      }
    ]);

    final entry = await SyncImportService.instance.importPending();
    // Nothing applied, so this is treated the same as an empty batch.
    expect(entry, isNotNull);
    expect(entry!.itemCount, 0);

    final tasks = await StorageService().readTaskListRaw();
    expect(tasks.single.isDone, isTrue);
    expect(tasks.single.completedAt, completedAt);
  });

  test('edit op renames a task and reschedules its due date', () async {
    final task = Task(title: 'Old title');
    await StorageService().saveTaskList([task]);
    final due = DateTime(2026, 9, 1);
    await writeJournal([
      {
        'op': 'edit',
        'uid': task.uid,
        'at': DateTime.now().toIso8601String(),
        'fields': {
          'title': 'New title',
          'label': 'home',
          'dueDate': due.toIso8601String(),
        },
      }
    ]);

    await SyncImportService.instance.importPending();

    final tasks = await StorageService().readTaskListRaw();
    expect(tasks.single.title, 'New title');
    expect(tasks.single.label, 'home');
    expect(tasks.single.dueDate, due);
  });

  test('an edit op older than the local reschedule loses the date field',
      () async {
    final rescheduledAt = DateTime.now();
    final localDue = DateTime(2026, 10, 1);
    final task = Task(title: 'Task', dueDate: localDue)
      ..rescheduledAt = rescheduledAt;
    await StorageService().saveTaskList([task]);
    await writeJournal([
      {
        'op': 'edit',
        'uid': task.uid,
        'at': rescheduledAt.subtract(const Duration(minutes: 1)).toIso8601String(),
        'fields': {'dueDate': DateTime(2026, 8, 1).toIso8601String()},
      }
    ]);

    await SyncImportService.instance.importPending();

    final tasks = await StorageService().readTaskListRaw();
    expect(tasks.single.dueDate, localDue);
  });

  test('create op adds a new task with the uid it brings', () async {
    await StorageService().saveTaskList(<Task>[]);
    final newUid = Task.newUid();
    await writeJournal([
      {
        'op': 'create',
        'at': DateTime.now().toIso8601String(),
        'fields': {'uid': newUid, 'title': 'From Obsidian'},
      }
    ]);

    await SyncImportService.instance.importPending();

    final tasks = await StorageService().readTaskListRaw();
    expect(tasks.single.uid, newUid);
    expect(tasks.single.title, 'From Obsidian');
  });

  test('a replayed create op is idempotent (no duplicate)', () async {
    final task = Task(title: 'Already here');
    await StorageService().saveTaskList([task]);
    await writeJournal([
      {
        'op': 'create',
        'at': DateTime.now().toIso8601String(),
        'fields': {'uid': task.uid, 'title': 'Already here'},
      }
    ]);

    final entry = await SyncImportService.instance.importPending();
    expect(entry!.itemCount, 0);

    final tasks = await StorageService().readTaskListRaw();
    expect(tasks, hasLength(1));
  });

  test('delete op tombstones a task without hard-deleting it', () async {
    final task = Task(title: 'Gone soon');
    await StorageService().saveTaskList([task]);
    await writeJournal([
      {
        'op': 'delete',
        'uid': task.uid,
        'at': DateTime.now().toIso8601String(),
      }
    ]);

    await SyncImportService.instance.importPending();

    final tasks = await StorageService().readTaskListRaw();
    expect(tasks.single.deletedAt, isNotNull);
  });

  test('a replayed complete op on an already-done task is a no-op', () async {
    final task = Task(title: 'Done already')
      ..isDone = true
      ..completedAt = DateTime.now().subtract(const Duration(days: 1));
    await StorageService().saveTaskList([task]);
    await writeJournal([
      {
        'op': 'complete',
        'uid': task.uid,
        'at': DateTime.now()
            .subtract(const Duration(days: 2))
            .toIso8601String(),
      }
    ]);

    final entry = await SyncImportService.instance.importPending();
    expect(entry!.itemCount, 0);
    final tasks = await StorageService().readTaskListRaw();
    expect(tasks.single.isDone, isTrue);
  });

  test('an op for an unknown uid is ignored, not an error', () async {
    await StorageService().saveTaskList(<Task>[]);
    await writeJournal([
      {
        'op': 'complete',
        'uid': 'does-not-exist',
        'at': DateTime.now().toIso8601String(),
      }
    ]);

    final entry = await SyncImportService.instance.importPending();
    expect(entry, isNotNull);
    expect(entry!.success, isTrue);
    expect(entry.itemCount, 0);
  });

  test('malformed JSON: red history entry, journal left untouched', () async {
    await journalFile().writeAsString('{not valid json');

    final entry = await SyncImportService.instance.importPending();
    expect(entry, isNotNull);
    expect(entry!.success, isFalse);
    expect(SyncService.instance.hasUnseenError.value, isTrue);

    // Not truncated: the malformed file is left for a human/future retry.
    expect(await journalFile().readAsString(), '{not valid json');
  });

  test('unknown journal_version: red history entry, journal left untouched',
      () async {
    await writeJournal(const [], version: 99);

    final entry = await SyncImportService.instance.importPending();
    expect(entry, isNotNull);
    expect(entry!.success, isFalse);

    final stillThere =
        jsonDecode(await journalFile().readAsString()) as Map<String, dynamic>;
    expect(stillThere['journal_version'], 99);
  });

  test('overlapping imports: the second call is a no-op', () async {
    final task = Task(title: 'Alpha');
    await StorageService().saveTaskList([task]);
    await writeJournal([
      {
        'op': 'complete',
        'uid': task.uid,
        'at': DateTime.now().toIso8601String(),
      }
    ]);

    final first = SyncImportService.instance.importPending();
    final second = SyncImportService.instance.importPending();
    expect(await second, isNull);
    expect(await first, isNotNull);
  });

  test('offline mode never imports anything', () async {
    Config.syncEnabled = false;
    await writeJournal([
      {'op': 'complete', 'uid': 'x', 'at': DateTime.now().toIso8601String()}
    ]);

    final entry = await SyncImportService.instance.importPending();
    expect(entry, isNull);
  });

  test('resuming the app runs the import (SyncService wiring)', () async {
    final task = Task(title: 'Alpha');
    await StorageService().saveTaskList([task]);
    await writeJournal([
      {
        'op': 'complete',
        'uid': task.uid,
        'at': DateTime.now().toIso8601String(),
      }
    ]);

    SyncService.instance.onLifecycleChanged(AppLifecycleState.resumed);
    await SyncService.instance.pendingResumeImport;

    final tasks = await StorageService().readTaskListRaw();
    expect(tasks.single.isDone, isTrue);
  });
}
