import 'dart:io';

import 'package:besttodo/models/alarm.dart';
import 'package:besttodo/services/alarm_storage_service.dart';
import 'package:besttodo/services/pre_update_backup.dart';
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
    PreUpdateBackup.resetForTest();
  });

  test('a corrupt alarms.json falls back to its .bak instead of losing the '
      'alarms', () async {
    final storage = AlarmStorageService();
    final alarm = Alarm(name: 'work day', hour: 6, minute: 45);
    await storage.saveAlarms([alarm]);
    await storage.saveAlarms([alarm]); // rotate a .bak into place
    await File('${tempDir.path}/alarms.json')
        .writeAsString('[broken', flush: true);

    final loaded = await storage.loadAlarms();
    expect(loaded.single.name, 'work day');
    expect(loaded.single.uid, alarm.uid);
    expect(loaded.single.hour, 6);

    // The unreadable original is quarantined for manual recovery.
    final corrupt = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('alarms.json.corrupt-'));
    expect(corrupt, hasLength(1));
  });

  test('the first alarm save also triggers the pre-update snapshot',
      () async {
    const oldAlarms = '[{"name":"legacy","hour":8,"minute":0}]';
    await File('${tempDir.path}/alarms.json')
        .writeAsString(oldAlarms, flush: true);

    final storage = AlarmStorageService();
    final alarms = await storage.loadAlarms();
    await storage.saveAlarms(alarms);

    final backup = File(
        '${tempDir.path}/${PreUpdateBackup.backupDirName}/alarms.json');
    expect(await backup.readAsString(), oldAlarms);
  });
}
