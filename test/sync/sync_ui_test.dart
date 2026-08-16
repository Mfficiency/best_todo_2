import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/sync_log_entry.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/test_report.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/sync_service.dart';
import 'package:besttodo/services/test_report_service.dart';
import 'package:besttodo/ui/app_logs_page.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:besttodo/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp('sync_ui');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    StorageService.resetJournalBaselineForTest();
    ProjectService.instance.resetForTest();
    SyncService.resetForTest();
    TestReportService.instance.resetForTest();
    TestReportService.instance
        .setOnlineReportForTest(TestReport(available: false));
  });

  tearDown(() {
    Config.syncEnabled = false;
    Config.syncFolderPath = '';
    SyncService.resetForTest();
    TestReportService.instance.resetForTest();
  });

  /// Walks real-event-loop slices so dart:io futures started inside the fake
  /// zone (initState loads, save-on-tap) complete (see test/README.md).
  Future<void> settleIo(WidgetTester tester, {int rounds = 60}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets(
      'the Sync tab lists every sync with duration and item count, and '
      'opening the page clears the unseen-error flag', (tester) async {
    SyncService.instance.entries.value = [
      SyncLogEntry(
        at: DateTime(2026, 8, 6, 12, 30, 5),
        durationMs: 12,
        itemCount: 5,
        success: true,
        trigger: 'app quit',
      ),
      SyncLogEntry(
        at: DateTime(2026, 8, 5, 9, 0, 0),
        durationMs: 3,
        itemCount: 0,
        success: false,
        message: 'Sync folder not found: /gone',
        trigger: 'app quit',
      ),
    ];
    SyncService.instance.hasUnseenError.value = true;

    await tester.pumpWidget(const MaterialApp(home: AppLogsPage()));
    await settleIo(tester);

    await tester.tap(find.text('Sync'));
    await tester.pumpAndSettle();

    expect(find.text('Synced 5 items in 12 ms'), findsOneWidget);
    expect(
      find.textContaining('Sync failed: Sync folder not found'),
      findsOneWidget,
    );
    expect(find.textContaining('app quit'), findsNWidgets(2));
    expect(SyncService.instance.hasUnseenError.value, isFalse);
  });

  Future<void> pumpHomeUntilLoaded(WidgetTester tester) async {
    await tester.runAsync(() => StorageService()
        .saveTaskList([Task(title: 'Alpha', dueDate: DateTime.now())]));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    final marker = find.text('Alpha');
    for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(marker, findsOneWidget, reason: 'HomePage never loaded the tasks');
  }

  /// Settings sections all start collapsed, so a test that wants a setting
  /// has to open its section first.
  Future<void> openSection(WidgetTester tester, String title) async {
    if (find.byTooltip('Collapse $title').evaluate().isNotEmpty) return;
    // The section headers are built lazily, so the header has to be scrolled
    // to before it can be tapped.
    final header = find.byTooltip('Expand $title');
    await tester.scrollUntilVisible(header, 80,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  testWidgets('a failed sync puts a red dot on the App Logs drawer entry',
      (tester) async {
    SyncService.instance.hasUnseenError.value = true;

    await pumpHomeUntilLoaded(tester);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('App Logs'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync-error-dot')), findsOneWidget);
    // The CI-test-failure dot is a different signal and must stay off.
    expect(find.byKey(const Key('test-failure-dot')), findsNothing);
  });

  testWidgets('no dot without a sync error', (tester) async {
    await pumpHomeUntilLoaded(tester);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('App Logs'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync-error-dot')), findsNothing);
  });

  testWidgets(
      'the Synced mode switch persists and reveals the sync folder tile',
      (tester) async {
    // A pre-chosen folder keeps the native folder picker out of the test.
    Config.syncFolderPath = '/backups/todo';

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await settleIo(tester);

    await openSection(tester, 'Sync & export');
    await tester.scrollUntilVisible(find.text('Synced mode'), 80,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();

    expect(find.text('Sync folder'), findsNothing);
    await tester.tap(find.text('Synced mode'));
    await settleIo(tester);

    expect(Config.syncEnabled, isTrue);
    await tester.scrollUntilVisible(find.text('Sync folder'), 80,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('/backups/todo'), findsOneWidget);

    // The switch was persisted, not just flipped in memory.
    Config.syncEnabled = false;
    await tester.runAsync(Config.load);
    expect(Config.syncEnabled, isTrue);
  });
}
