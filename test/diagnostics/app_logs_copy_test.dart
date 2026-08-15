import 'package:besttodo/services/log_service.dart';
import 'package:besttodo/services/render_diagnostics.dart';
import 'package:besttodo/services/sync_service.dart';
import 'package:besttodo/ui/app_logs_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// No fake path provider here on purpose: without one the log file is
/// unavailable, so the page falls back to the in-memory entries and nothing
/// touches dart:io inside the fake-async zone (see test/README.md).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clipboardCalls = <MethodCall>[];

  setUp(() {
    clipboardCalls.clear();
    LogService.resetForTest();
    SyncService.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
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
