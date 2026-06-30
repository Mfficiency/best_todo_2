import 'dart:io';

import 'package:besttodo/models/alarm.dart';
import 'package:besttodo/services/alarm_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  test('saveAlarms then loadAlarms round-trips the list', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    final service = AlarmStorageService();
    final alarms = [
      Alarm(name: 'Wake', hour: 7, minute: 0, isRepeating: true, repeatDays: [
        DateTime.monday,
        DateTime.tuesday,
      ]),
      Alarm(name: 'Nap', hour: 14, minute: 30, enabled: false),
    ];
    await service.saveAlarms(alarms);

    final loaded = await service.loadAlarms();
    expect(loaded.length, 2);
    expect(loaded.first.name, 'Wake');
    expect(loaded.first.repeatDays, [DateTime.monday, DateTime.tuesday]);
    expect(loaded[1].enabled, isFalse);
  });

  test('loadAlarms returns empty list when file missing', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    final service = AlarmStorageService();
    final loaded = await service.loadAlarms();
    expect(loaded, isEmpty);
  });
}
