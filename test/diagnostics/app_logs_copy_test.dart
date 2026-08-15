import 'dart:io';

import 'package:besttodo/services/log_service.dart';
import 'package:besttodo/services/render_diagnostics.dart';
import 'package:besttodo/services/sync_service.dart';
import 'package:besttodo/ui/app_logs_page.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// No fake path provider here on purpose: without one the log file is
/// unavailable, so the page falls back to the in-memory entries and nothing
/// touches dart:io inside the fake-async zone (see test/README.md). The export
/// test does write a real file, so it round-pumps with runAsync.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clipboardCalls = <MethodCall>[];
  final originalSelector = FileSelectorPlatform.instance;
  late Directory exportDir;

  setUp(() {
    clipboardCalls.clear();
    LogService.resetForTest();
    SyncService.resetForTest();
    // Made outside the fake-async zone so the dart:io call completes.
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

  /// Walks real-event-loop slices so the futures the copy handler awaits —
  /// the log reads and the clipboard channel — actually complete; plain
  /// `pump()` never advances them (see test/README.md).
  Future<void> settleIo(WidgetTester tester, {int rounds = 20}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('the copy button hands over the app log and the device log',
      (tester) async {
    LogService.logs.value = <String>[
      '2026-08-15T10:00:00.000 [widget] tap received: besttodotask://open',
      '2026-08-15T10:00:02.000 [render] NO FRAME 1000ms after resume — '
          'window is black',
    ];

    await tester.pumpWidget(const MaterialApp(home: AppLogsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copy logs'));
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(clipboardCalls, hasLength(1));
    final copied = clipboardCalls.single.arguments['text'] as String;
    expect(copied, contains('===== APP LOG ====='));
    expect(copied, contains('tap received: besttodotask://open'));
    expect(copied, contains('NO FRAME'));
    expect(copied, contains('===== DEVICE LOG (Android) ====='));
    expect(
      find.text('Logs copied — paste them into your report'),
      findsOneWidget,
    );

    // Let the snackbar's dismiss timer expire before the test ends.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the Device tab explains itself when there is nothing to show',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppLogsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Device'));
    await tester.pumpAndSettle();

    // Off-Android the native breadcrumb file does not exist, and the tab says
    // so instead of looking broken.
    expect(find.textContaining('only recorded on Android'), findsOneWidget);
  });

  testWidgets('the export button writes the whole bundle to a file',
      (tester) async {
    // More app entries than the copy button's tail keeps, so the export can be
    // told apart from it: the file must carry the oldest line too.
    LogService.logs.value = <String>[
      for (var i = 0; i < 200; i++) '2026-08-15T10:00:00.000 [widget] entry $i',
    ];

    await tester.pumpWidget(const MaterialApp(home: AppLogsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Export logs to a file'));
    // Fixed rounds: the handler writes the file before the snackbar shows, so
    // a condition-driven poll would exit early (see test/README.md).
    await settleIo(tester, rounds: 60);
    await tester.pumpAndSettle();

    final written = await tester.runAsync(() async => exportDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.txt'))
        .toList());
    expect(written, hasLength(1));
    final contents = await tester.runAsync(() => written!.single.readAsString());
    expect(contents, contains('===== DEVICE LOG (Android) ====='));
    expect(contents, contains('===== APP LOG ====='));
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

  testWidgets('the render snapshot names every field that decides a frame',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

    final snapshot = RenderDiagnostics.snapshot();
    expect(snapshot, contains('frames='));
    expect(snapshot, contains('hasScheduledFrame='));
    expect(snapshot, contains('framesEnabled='));
    expect(snapshot, contains('lifecycle='));
    expect(snapshot, contains('view='));
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
