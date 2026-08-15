import 'dart:io';

import 'package:besttodo/services/log_service.dart';
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
    tempDir = await Directory.systemTemp.createTemp('app_log');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    LogService.resetForTest();
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  File logFile() => File('${tempDir.path}/${LogService.fileName}');

  test('entries are written to the log file as well as the live list',
      () async {
    LogService.add('widget', 'tap received: besttodotask://open');
    await LogService.flush();

    expect(LogService.logs.value.single, contains('tap received'));
    final written = await logFile().readAsString();
    expect(written, contains('[widget] tap received: besttodotask://open'));
  });

  test('the previous run is restored after a force-close', () async {
    LogService.add('render', 'NO FRAME 1000ms after resume — window is black');
    await LogService.flush();

    // A force-close loses everything in memory — the file is the only record.
    LogService.resetForTest();
    expect(LogService.logs.value, isEmpty);

    await LogService.restore();
    expect(LogService.logs.value.single, contains('NO FRAME'));

    // Restoring twice must not duplicate the entries.
    await LogService.restore();
    expect(LogService.logs.value, hasLength(1));
  });

  test('readFile hands over the whole file for the copy button', () async {
    LogService.add('render', 'app start — BestToDo 1.2.3+4');
    LogService.add('widget', 'tap received: besttodotask://open');
    await LogService.flush();

    final report = await LogService.readFile();
    expect(report, contains('app start'));
    expect(report, contains('tap received'));
  });

  test('clearing removes the file as well as the list', () async {
    LogService.add('widget', 'tap received: besttodotask://open');
    await LogService.flush();
    expect(await logFile().exists(), isTrue);

    LogService.clear();
    await LogService.flush();

    expect(LogService.logs.value, isEmpty);
    expect(await logFile().exists(), isFalse);
  });
}
