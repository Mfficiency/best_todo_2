import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/auto_backup_service.dart';
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
  late Directory docsDir;
  late Directory backupDir;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp();
    backupDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
    Config.autoBackupFrequency = 'off';
    Config.autoBackupDirectory = '';
  });

  tearDown(() {
    Config.autoBackupFrequency = 'off';
    Config.autoBackupDirectory = '';
  });

  test('isDue follows the off/daily/weekly schedule', () {
    final now = DateTime(2026, 8, 6, 9, 30);

    Config.autoBackupFrequency = 'off';
    expect(AutoBackupService.isDue(null, now), isFalse);

    Config.autoBackupFrequency = 'daily';
    expect(AutoBackupService.isDue(null, now), isTrue);
    expect(AutoBackupService.isDue(DateTime(2026, 8, 6, 0, 5), now), isFalse);
    expect(AutoBackupService.isDue(DateTime(2026, 8, 5, 23, 55), now), isTrue);

    Config.autoBackupFrequency = 'weekly';
    expect(AutoBackupService.isDue(null, now), isTrue);
    expect(AutoBackupService.isDue(DateTime(2026, 7, 31), now), isFalse);
    expect(AutoBackupService.isDue(DateTime(2026, 7, 30), now), isTrue);
  });

  test('maybeRun is a no-op when off or without a folder', () async {
    Config.autoBackupFrequency = 'off';
    Config.autoBackupDirectory = backupDir.path;
    expect(await AutoBackupService.maybeRun(), isNull);

    Config.autoBackupFrequency = 'daily';
    Config.autoBackupDirectory = '';
    expect(await AutoBackupService.maybeRun(), isNull);
    expect(backupDir.listSync(), isEmpty);
  });

  test('maybeRun writes a restorable full backup and records the run',
      () async {
    Config.autoBackupFrequency = 'daily';
    Config.autoBackupDirectory = backupDir.path;
    final storage = StorageService();
    await storage.saveTaskList([Task(title: 'Backed up task')]);

    final now = DateTime(2026, 8, 6, 9, 30);
    final file = await AutoBackupService.maybeRun(now: now);
    expect(file, isNotNull);
    expect(file!.path, contains('besttodo_backup_20260806_093000.json'));

    // Same shape as "Export Everything", so the Import button restores it.
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(decoded['export_version'], 1);
    expect(decoded['settings'], isA<Map>());
    expect(decoded.containsKey('countdown_timers'), isTrue);
    final bundle = decoded['tasks_bundle'] as Map<String, dynamic>;
    final tasks = bundle['tasks'] as List;
    expect(tasks.single['title'], 'Backed up task');

    // The run was recorded, so the same day is no longer due...
    expect(await AutoBackupService.lastRun(), now);
    expect(await AutoBackupService.maybeRun(now: now), isNull);
    // ...but the next day is.
    final nextDay = now.add(const Duration(days: 1));
    expect(await AutoBackupService.maybeRun(now: nextDay), isNotNull);
    expect(backupDir.listSync(), hasLength(2));
  });

  test('runNow reports failure by returning null', () async {
    Config.autoBackupFrequency = 'daily';
    Config.autoBackupDirectory =
        '${backupDir.path}${Platform.pathSeparator}does_not_exist';
    expect(await AutoBackupService.runNow(), isNull);
  });

  test('backup settings survive the config round trip', () {
    Config.applyMap({
      'autoBackupFrequency': 'weekly',
      'autoBackupDirectory': '/backups',
    });
    expect(Config.autoBackupFrequency, 'weekly');
    expect(Config.autoBackupDirectory, '/backups');

    final map = Config.toMap();
    expect(map['autoBackupFrequency'], 'weekly');
    expect(map['autoBackupDirectory'], '/backups');

    // Unknown frequencies are ignored, missing keys leave values untouched.
    Config.applyMap({'autoBackupFrequency': 'hourly'});
    expect(Config.autoBackupFrequency, 'weekly');
    Config.applyMap(const {});
    expect(Config.autoBackupFrequency, 'weekly');
    expect(Config.autoBackupDirectory, '/backups');
  });
}
