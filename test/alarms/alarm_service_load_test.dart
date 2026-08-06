import 'dart:io';

import 'package:besttodo/models/alarm.dart';
import 'package:besttodo/services/alarm_service.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent load() calls share one in-flight reload', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    await AlarmStorageService().saveAlarms([Alarm(name: 'Wake', hour: 7)]);

    // The app-start load runs deferred after the first frame and can race the
    // alarms page's own load(); both must share the same underlying reload
    // instead of rescheduling the OS alarms twice concurrently.
    final service = AlarmService.instance;
    final first = service.load();
    final second = service.load();
    expect(identical(first, second), isTrue);

    await first;
    expect(service.list.length, 1);
    expect(service.list.first.name, 'Wake');

    // Once loaded, load() completes immediately without another reload.
    await service.load();
    expect(service.list.length, 1);
  });
}
