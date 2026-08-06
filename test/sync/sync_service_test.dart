import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
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

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('sync_docs');
    syncDir = await Directory.systemTemp.createTemp('sync_target');
    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
    StorageService.resetJournalBaselineForTest();
    SyncService.resetForTest();
    Config.syncEnabled = true;
    Config.syncFolderPath = syncDir.path;
  });

  tearDown(() {
    Config.syncEnabled = false;
    Config.syncFolderPath = '';
    SyncService.resetForTest();
  });

  test('syncNow writes the task file and records a success entry', () async {
    await StorageService().saveTaskList([
      Task(title: 'Alpha', dueDate: DateTime.now()),
      Task(title: 'Beta'),
      Task(title: 'Gamma'),
    ]);

    final entry = await SyncService.instance.syncNow();

    expect(entry, isNotNull);
    expect(entry!.success, isTrue);
    expect(entry.itemCount, 3);
    expect(entry.durationMs, greaterThanOrEqualTo(0));

    final file = File('${syncDir.path}/${SyncService.syncFileName}');
    expect(await file.exists(), isTrue);
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(decoded['sync_version'], 1);
    expect(decoded['task_count'], 3);
    expect((decoded['tasks'] as List).length, 3);

    expect(SyncService.instance.entries.value.single.success, isTrue);
    expect(SyncService.instance.hasUnseenError.value, isFalse);
  });

  test('a vanished folder records a failure; the next success clears the flag',
      () async {
    await syncDir.delete(recursive: true);

    final failed = await SyncService.instance.syncNow();
    expect(failed!.success, isFalse);
    expect(failed.message, contains('Sync folder not found'));
    expect(SyncService.instance.hasUnseenError.value, isTrue);

    await syncDir.create();
    final ok = await SyncService.instance.syncNow();
    expect(ok!.success, isTrue);
    expect(SyncService.instance.hasUnseenError.value, isFalse);

    // Newest first, both runs kept in the history.
    final entries = SyncService.instance.entries.value;
    expect(entries.length, 2);
    expect(entries.first.success, isTrue);
    expect(entries.last.success, isFalse);
  });

  test('an unchosen folder fails gracefully and points at Settings', () async {
    Config.syncFolderPath = '';

    final entry = await SyncService.instance.syncNow();

    expect(entry!.success, isFalse);
    expect(entry.message, contains('No sync folder chosen'));
    expect(SyncService.instance.hasUnseenError.value, isTrue);
  });

  test('offline mode never writes or logs anything', () async {
    Config.syncEnabled = false;

    final entry = await SyncService.instance.syncNow();

    expect(entry, isNull);
    expect(SyncService.instance.entries.value, isEmpty);
    final file = File('${syncDir.path}/${SyncService.syncFileName}');
    expect(await file.exists(), isFalse);
  });

  test('history and the unseen-error flag survive a restart; markErrorSeen '
      'clears the flag for good', () async {
    await syncDir.delete(recursive: true);
    await SyncService.instance.syncNow();

    SyncService.resetForTest();
    await SyncService.instance.ensureLoaded();
    expect(SyncService.instance.entries.value.length, 1);
    expect(SyncService.instance.entries.value.single.success, isFalse);
    expect(SyncService.instance.hasUnseenError.value, isTrue);

    await SyncService.instance.markErrorSeen();
    SyncService.resetForTest();
    await SyncService.instance.ensureLoaded();
    expect(SyncService.instance.hasUnseenError.value, isFalse);
    expect(SyncService.instance.entries.value.length, 1);
  });

  test('quitting syncs exactly once until the app is resumed', () async {
    await StorageService().saveTaskList([Task(title: 'Alpha')]);
    final service = SyncService.instance;

    // hidden → paused → detached arrive in a row on the way out; only the
    // first may sync.
    service.onLifecycleChanged(AppLifecycleState.inactive);
    service.onLifecycleChanged(AppLifecycleState.hidden);
    await service.pendingQuitSync;
    service.onLifecycleChanged(AppLifecycleState.paused);
    service.onLifecycleChanged(AppLifecycleState.detached);
    await service.pendingQuitSync;

    expect(service.entries.value.length, 1);
    expect(service.entries.value.single.trigger, 'app quit');

    service.onLifecycleChanged(AppLifecycleState.resumed);
    service.onLifecycleChanged(AppLifecycleState.paused);
    await service.pendingQuitSync;

    expect(service.entries.value.length, 2);
  });

  test('the lifecycle hook does nothing in offline mode', () async {
    Config.syncEnabled = false;
    final service = SyncService.instance;

    service.onLifecycleChanged(AppLifecycleState.paused);

    expect(service.pendingQuitSync, isNull);
    expect(service.entries.value, isEmpty);
  });
}
