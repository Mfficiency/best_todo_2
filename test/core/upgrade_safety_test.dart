import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/daily_task_stats.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/item_event_journal.dart';
import 'package:besttodo/services/pre_update_backup.dart';
import 'package:besttodo/services/safe_file.dart';
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
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
    StorageService.resetJournalBaselineForTest();
    ItemEventJournal.instance.resetForTest();
    PreUpdateBackup.resetForTest();
  });

  File dataFile(String name) => File('${tempDir.path}/$name');

  group('SafeFile', () {
    test('writes atomically and rotates the previous content to .bak',
        () async {
      final file = dataFile('t.json');
      await SafeFile.writeString(file, 'one');
      await SafeFile.writeString(file, 'two');
      expect(await file.readAsString(), 'two');
      expect(await File('${file.path}.bak').readAsString(), 'one');
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test('recovers from .bak and quarantines the unreadable original',
        () async {
      final file = dataFile('t.json');
      await SafeFile.writeString(file, '["good"]');
      await SafeFile.writeString(file, '["newer"]');
      // Corrupt the main file behind the store's back (torn write).
      await file.writeAsString('["newer', flush: true);

      final parsed = await SafeFile.readWithRecovery(
          file, (c) => jsonDecode(c) as List<dynamic>);
      // Falls back to the last good backup...
      expect(parsed, ['good']);
      // ...the corrupt bytes are quarantined, not destroyed...
      final quarantined = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('t.json.corrupt-'))
          .toList();
      expect(quarantined, hasLength(1));
      expect(await quarantined.single.readAsString(), '["newer');
      // ...and a following save cannot clobber them.
      await SafeFile.writeString(file, '["fresh"]');
      expect(quarantined.single.existsSync(), isTrue);
    });

    test('missing file (and no backup) is null, not an error', () async {
      expect(
          await SafeFile.readWithRecovery(dataFile('none.json'), (c) => c),
          isNull);
    });

    test('overlapping writes to the same file serialize; the last one wins',
        () async {
      final file = dataFile('t.json');
      // Unawaited concurrent saves used to race on the shared .tmp: one
      // rename stole it and the other threw PathNotFoundException.
      await Future.wait([
        for (var i = 0; i < 10; i++) SafeFile.writeString(file, 'write $i'),
      ]);
      expect(await file.readAsString(), 'write 9');
      expect(await File('${file.path}.bak').readAsString(), 'write 8');
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });
  });

  group('corrupt stores recover instead of wiping', () {
    test('tasks.json falls back to its .bak; the corrupt file survives later '
        'saves', () async {
      final service = StorageService();
      final keeper = Task(title: 'precious');
      await service.saveTaskList([keeper]);
      await service.saveTaskList([keeper]); // rotate a .bak into place
      await dataFile('tasks.json').writeAsString('{broken', flush: true);

      final loaded = await service.loadTaskList();
      expect(loaded.single.title, 'precious');
      expect(loaded.single.uid, keeper.uid);

      // The old failure mode: this save used to overwrite the only copy.
      await service.saveTaskList(loaded);
      final corrupt = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('tasks.json.corrupt-'));
      expect(corrupt, hasLength(1));
      expect((await service.loadTaskList()).single.title, 'precious');
    });

    test('a corrupt file with no backup is quarantined, never overwritten',
        () async {
      await dataFile('tasks.json').writeAsString('not json', flush: true);
      final service = StorageService();
      final loaded = await service.loadTaskList();
      expect(loaded, isEmpty);
      // The unreadable original still exists for manual recovery.
      final corrupt = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('tasks.json.corrupt-'));
      expect(corrupt, hasLength(1));
      expect(await corrupt.single.readAsString(), 'not json');
    });

    test('deleted list and daily stats recover the same way', () async {
      final service = StorageService();
      await service
          .saveDeletedTaskList([Task(title: 'old friend', isDone: true)]);
      await service.saveDeletedTaskList(await service.loadDeletedTaskList());
      await dataFile('deleted_tasks.json').writeAsString('{{{', flush: true);
      expect((await service.loadDeletedTaskList()).single.title,
          'old friend');

      final stats = DailyTaskStats(dayKey: '2026-01-01');
      await service.saveDailyTaskStats({stats.dayKey: stats});
      await service.saveDailyTaskStats(await service.loadDailyTaskStats());
      await dataFile('daily_task_stats.json').writeAsString('xx', flush: true);
      expect((await service.loadDailyTaskStats()).keys,
          contains('2026-01-01'));
    });
  });

  group('pre-update snapshot', () {
    test('the first write of the new version snapshots every existing data '
        'file byte-for-byte', () async {
      // Files as some previous version left them.
      const oldTasks = '[{"title":"from 0.1.42","isDone":false}]';
      const oldAlarms = '[{"name":"wake","hour":7,"minute":30}]';
      const oldWishes = '[{"title":"pony"}]';
      await dataFile('tasks.json').writeAsString(oldTasks, flush: true);
      await dataFile('alarms.json').writeAsString(oldAlarms, flush: true);
      await dataFile('wishlist.json').writeAsString(oldWishes, flush: true);

      final service = StorageService();
      final loaded = await service.loadTaskList();
      // The wishlist drain saves during load — the snapshot must still have
      // captured the ORIGINAL wishlist.json (save-then-empty ordering).
      expect(loaded.map((t) => t.title).toSet(),
          {'from 0.1.42', 'pony'});

      final backup = '${tempDir.path}/${PreUpdateBackup.backupDirName}';
      expect(await File('$backup/tasks.json').readAsString(), oldTasks);
      expect(await File('$backup/alarms.json').readAsString(), oldAlarms);
      expect(await File('$backup/wishlist.json').readAsString(), oldWishes);
      expect(
          File('${tempDir.path}/${PreUpdateBackup.backupFlagFileName}')
              .existsSync(),
          isTrue);
    });

    test('runs once: later saves never touch the snapshot', () async {
      await dataFile('tasks.json')
          .writeAsString('[{"title":"original"}]', flush: true);
      final service = StorageService();
      final tasks = await service.loadTaskList();
      await service.saveTaskList(tasks);

      tasks.first.title = 'renamed after update';
      await service.saveTaskList(tasks);
      PreUpdateBackup.resetForTest(); // even a fresh session re-checks flag
      await service.saveTaskList(tasks);

      final backup =
          '${tempDir.path}/${PreUpdateBackup.backupDirName}/tasks.json';
      expect(await File(backup).readAsString(), '[{"title":"original"}]');
    });

    test('a pre-created flag opts out entirely', () async {
      await File('${tempDir.path}/${PreUpdateBackup.backupFlagFileName}')
          .writeAsString('done');
      await StorageService().saveTaskList([Task(title: 'x')]);
      expect(
          Directory('${tempDir.path}/${PreUpdateBackup.backupDirName}')
              .existsSync(),
          isFalse);
    });
  });

  group('upgrade matrix — payload shapes from earlier versions load intact',
      () {
    Future<List<Task>> loadFrom(String payload) async {
      await dataFile('tasks.json').writeAsString(payload, flush: true);
      StorageService.resetJournalBaselineForTest();
      return StorageService().loadTaskList();
    }

    test('earliest era: bare fields, no uid', () async {
      final tasks = await loadFrom(
          '[{"title":"buy milk","isDone":true},{"title":"call mom"}]');
      expect(tasks.map((t) => t.title), ['buy milk', 'call mom']);
      expect(tasks.every((t) => t.uid.isNotEmpty), isTrue);
      expect(tasks.first.isDone, isTrue);
    });

    test('analytics era: timestamps and labels survive', () async {
      final tasks = await loadFrom(jsonEncode([
        {
          'uid': 'a-1',
          'title': 'report',
          'label': 'work, urgent',
          'createdAt': '2026-02-01T09:00:00.000',
          'movedAt': '2026-02-03T10:00:00.000',
          'dueDate': '2026-02-05T18:00:00.000',
        }
      ]));
      final t = tasks.single;
      expect(t.uid, 'a-1');
      expect(t.label, 'work, urgent');
      expect(t.createdAt, DateTime(2026, 2, 1, 9));
      expect(t.movedAt, DateTime(2026, 2, 3, 10));
      expect(t.dueDate, DateTime(2026, 2, 5, 18));
      expect(t.startAt, DateTime(2026, 2, 5, 18)); // v1 → v2 upgrade
    });

    test('projects + wishlist era: projectId, kanbanStatus, isWish survive',
        () async {
      final tasks = await loadFrom(jsonEncode([
        {
          'uid': 'p-1',
          'title': 'board task',
          'projectId': 'project_2',
          'kanbanStatus': 'ongoing',
        },
        {'uid': 'w-1', 'title': 'wish', 'isWish': true},
      ]));
      expect(tasks.first.projectId, 'project_2');
      expect(tasks.first.kanbanStatus, Task.kanbanOngoing);
      expect(tasks.last.isWish, isTrue);
    });

    test('round-trip after upgrade: reload preserves everything and writes '
        'schema v2', () async {
      final tasks = await loadFrom(jsonEncode([
        {
          'uid': 'r-1',
          'title': 'keeper',
          'dueDate': '2026-03-01T18:00:00.000',
          'isRecurring': true,
          'recurrenceIntervalDays': 7,
        }
      ]));
      await StorageService().saveTaskList(tasks);
      final raw = jsonDecode(await dataFile('tasks.json').readAsString())
          as List<dynamic>;
      final record = raw.single as Map<String, dynamic>;
      expect(record['schemaVersion'], Task.currentSchemaVersion);
      expect(record['dueDate'], isNotNull); // downgrade mirror kept

      final reloaded = await StorageService().loadTaskList();
      final t = reloaded.single;
      expect(t.uid, 'r-1');
      expect(t.isRecurring, isTrue);
      expect(t.recurrenceIntervalDays, 7);
      expect(t.dueDate, DateTime(2026, 3, 1, 18));
    });
  });
}
