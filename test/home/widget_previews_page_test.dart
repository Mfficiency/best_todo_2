import 'dart:io';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:besttodo/ui/widget_previews_page.dart';
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
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
  });

  testWidgets(
      'the dev-only Widget Previews drawer entry renders a mock of each '
      'Android home-screen widget', (tester) async {
    final now = DateTime.now();
    await tester.runAsync(() => StorageService().saveTaskList([
          Task(title: 'Buy milk', dueDate: now),
        ]));
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    // HomePage._loadTasks is real file I/O started in the fake-async zone;
    // give it real-event-loop slices until the seeded task shows up.
    final homeMarker = find.text('Buy milk');
    for (var i = 0; i < 300 && homeMarker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(homeMarker, findsOneWidget, reason: 'HomePage never loaded');

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    final widgetPreviewsEntry = find.text('Widget Previews');
    expect(widgetPreviewsEntry, findsOneWidget);
    await tester.ensureVisible(widgetPreviewsEntry);
    await tester.tap(widgetPreviewsEntry);
    await tester.pump();
    // WidgetPreviewsPage.initState kicks off its own real I/O (task +
    // alarm loads) the same way HomePage's does above.
    final previewMarker = find.text('Task widget');
    for (var i = 0; i < 300 && previewMarker.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // The pushed page's ancestor scopes these: HomePage stays mounted (just
    // covered) behind it, and its own task tile still carries "Buy milk"
    // verbatim, so an unscoped textContaining would match both.
    final previewsPage = find.byType(WidgetPreviewsPage);
    expect(find.descendant(of: previewsPage, matching: find.text('Task widget')),
        findsOneWidget);
    expect(
        find.descendant(
            of: previewsPage, matching: find.text('Alarms widget')),
        findsOneWidget);
    expect(
        find.descendant(
            of: previewsPage, matching: find.text('Food Diary widget')),
        findsOneWidget);
    // Today's seeded task shows up in the task-widget mock.
    expect(
        find.descendant(
            of: previewsPage, matching: find.textContaining('Buy milk')),
        findsOneWidget);
    // AlarmService seeds a small dev alarm list the first time it loads.
    expect(find.descendant(of: previewsPage, matching: find.text('Wake up')),
        findsOneWidget);
  });
}
