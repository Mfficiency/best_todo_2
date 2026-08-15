import 'dart:io';

import 'package:besttodo/services/log_service.dart';
import 'package:besttodo/services/sync_service.dart';
import 'package:besttodo/ui/app_logs_page.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// See test/README.md: real dart:io/platform-channel work started inside a
/// testWidgets handler needs real event-loop slices, not just pump().
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clipboardCalls = <MethodCall>[];
  final originalSelector = FileSelectorPlatform.instance;
  late Directory exportDir;

  setUp(() {
    clipboardCalls.clear();
    LogService.resetForTest();
    SyncService.resetForTest();
    exportDir = Directory.systemTemp.createTempSync('besttodo_logs_export');
    FileSelectorPlatform.instance = _FakeFolderPicker(exportDir.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    FileSelectorPlatform.instance = originalSelector;
    if (exportDir.existsSync()) exportDir.deleteSync(recursive: true);
    LogService.resetForTest();
    SyncService.resetForTest();
  });

  Future<void> settleIo(WidgetTester tester, {int rounds = 20}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('the copy button puts the current log on the clipboard',
      (tester) async {
    LogService.logs.value = <String>[
      '2026-08-15T10:00:00.000 [widget] tap received: besttodotask://open',
    ];

    await tester.pumpWidget(const MaterialApp(home: AppLogsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copy logs'));
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(clipboardCalls, hasLength(1));
    final copied = clipboardCalls.single.arguments['text'] as String;
    expect(copied, contains('tap received: besttodotask://open'));
    expect(
      find.text('Logs copied — paste them into your report'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the export button writes the log to a file', (tester) async {
    LogService.logs.value = <String>[
      for (var i = 0; i < 200; i++) '2026-08-15T10:00:00.000 [widget] entry $i',
    ];

    await tester.pumpWidget(const MaterialApp(home: AppLogsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export logs to a file'));
    await settleIo(tester, rounds: 60);
    await tester.pumpAndSettle();

    final written = await tester.runAsync(() async => exportDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.txt'))
        .toList());
    expect(written, hasLength(1));
    final contents =
        await tester.runAsync(() => written!.single.readAsString());
    expect(contents, contains('entry 0'), reason: 'export is not trimmed');
    expect(contents, contains('entry 199'));
    expect(find.textContaining('Exported to '), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('canceling the folder picker exports nothing', (tester) async {
    FileSelectorPlatform.instance = _FakeFolderPicker(null);
    LogService.logs.value = <String>['2026-08-15T10:00:00.000 [widget] hi'];

    await tester.pumpWidget(const MaterialApp(home: AppLogsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export logs to a file'));
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(find.text('Export canceled'), findsOneWidget);
    expect(await tester.runAsync(() async => exportDir.listSync()), isEmpty);

    await tester.pump(const Duration(seconds: 5));
  });
}

/// Stands in for the OS folder dialog: [directory] is what the user picks,
/// null means they canceled.
class _FakeFolderPicker extends FileSelectorPlatform {
  _FakeFolderPicker(this.directory);

  final String? directory;

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async =>
      directory;
}
