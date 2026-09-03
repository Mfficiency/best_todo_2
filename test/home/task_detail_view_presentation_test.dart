import 'dart:io';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/ui/task_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Task Details is shared by every Task-based view (Projects board, Archived
/// Items, Deleted bin); [TaskDetailPage.viewId] is how it learns which one it
/// was opened from, via [ViewPresentation.forView].
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  Task datedTask() =>
      Task(title: 'renew passport', dueDate: DateTime(2026, 8, 1, 18));

  // TaskCountdownSection loads countdown_timers.json in initState (real file
  // I/O against the fake path provider above, which the fake-async
  // testWidgets zone never services on its own — see CLAUDE.md) so every
  // pump waits it out with a runAsync delay loop until [marker] appears (or,
  // for the "omitted" cases, until settled with nothing further to wait for).
  Future<void> pumpDetail(
    WidgetTester tester,
    Task task, {
    String? viewId,
    String? marker,
  }) async {
    await tester.pumpWidget(
        MaterialApp(home: TaskDetailPage(task: task, viewId: viewId)));
    final markerFinder = marker == null ? null : find.text(marker);
    for (var i = 0; i < 300; i++) {
      if (markerFinder != null && markerFinder.evaluate().isNotEmpty) break;
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
    if (markerFinder != null) {
      expect(markerFinder, findsOneWidget,
          reason: 'TaskCountdownSection never finished loading');
    }
  }

  testWidgets('no viewId (e.g. Projects board): both capability sections '
      'render their offer', (tester) async {
    await pumpDetail(tester, datedTask(),
        marker: 'Add countdown to due date');
    expect(find.text('Remind me 15 min before due'), findsOneWidget);
    expect(find.text('Add countdown to due date'), findsOneWidget);
  });

  testWidgets('archived view: item-linked capability sections are omitted',
      (tester) async {
    await pumpDetail(tester, datedTask(), viewId: ViewFilterRules.archived);
    expect(find.text('Remind me 15 min before due'), findsNothing);
    expect(find.text('Add countdown to due date'), findsNothing);
  });

  testWidgets('deleted bin view: item-linked capability sections are omitted',
      (tester) async {
    await pumpDetail(tester, datedTask(), viewId: ViewFilterRules.bin);
    expect(find.text('Remind me 15 min before due'), findsNothing);
    expect(find.text('Add countdown to due date'), findsNothing);
  });
}
