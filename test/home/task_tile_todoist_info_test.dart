import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/task_change_source.dart';
import 'package:besttodo/services/item_event_journal.dart';
import 'package:besttodo/services/label_service.dart';
import 'package:besttodo/services/todoist_sync_service.dart';
import 'package:besttodo/ui/task_tile.dart';
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
  late Directory docsDir;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('task_tile_todoist_docs');
    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
    TodoistSyncService.resetForTest();
    ItemEventJournal.instance.resetForTest();
    LabelService.instance.resetForTest();
    // Expanding the tile renders LabelPickerField, which fires
    // LabelService.ensureLoaded()/registerTokens() fire-and-forget from
    // initState. Pre-loading here (a real async context, not the
    // testWidgets fake-async zone) means that call is a no-op by the time
    // it runs inside the test — otherwise its dart:io read never
    // completes inside the fake zone and the test hangs (see CLAUDE.md).
    await LabelService.instance.ensureLoaded();
  });

  Future<void> pumpTile(WidgetTester tester, Task task) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskTile(
          task: task,
          onChanged: () {},
          onToggle: () {},
          onMove: (_) {},
          onMoveNext: () {},
          onDelete: () {},
          pageIndex: 0,
        ),
      ),
    ));
    await tester.tap(find.text(task.title).first);
    await tester.pumpAndSettle();
  }

  /// Opens the info dialog and lets its lazy history load finish — the
  /// journal read is real dart:io, so it needs runAsync rounds (CLAUDE.md).
  Future<void> openInfo(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Task info'));
    await tester.pump();
    for (var i = 0;
        i < 60 && find.text('Loading…').evaluate().isNotEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
      'every task shows an info icon beside Note with its creation time, '
      'in-app origin and history', (tester) async {
    await tester.runAsync(() => TodoistSyncService.instance.ensureLoaded());
    final task = Task(
      title: 'Typed task',
      createdAt: DateTime(2026, 9, 30, 14, 5),
      origin: TaskChangeSource.user,
    );

    await pumpTile(tester, task);
    expect(find.byTooltip('Task info'), findsOneWidget);

    await openInfo(tester);

    expect(find.text('Task info'), findsOneWidget);
    expect(find.text('Created: 2026-09-30 14:05'), findsOneWidget);
    expect(find.text('Origin: Manually in the app'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('No history recorded for this task.'), findsOneWidget);
    expect(find.textContaining('Todoist ID'), findsNothing);
  });

  testWidgets(
      'a task pulled in from Todoist shows the approval path, Todoist id '
      'and sync date — none of it in the description', (tester) async {
    final task = Task(
      title: 'Synced task',
      description: 'Free-text notes',
      createdAt: DateTime(2026, 8, 20, 9),
      origin: TaskChangeSource.sync,
      pendingSourceTitle: 'Trip planning',
      approvedAt: DateTime(2026, 8, 21, 7, 30),
    );
    final stateFile = File('${docsDir.path}/todoist_sync_state.json');
    await tester.runAsync(() => stateFile.writeAsString(jsonEncode({
          'taskEntries': [
            {
              'localUid': task.uid,
              'todoistId': '999',
              'localFingerprint': 'fp',
              'remoteFingerprint': 'fp',
              'syncedAt': '2026-08-20T10:30:00.000Z',
            }
          ],
        })));
    await tester.runAsync(() => TodoistSyncService.instance.ensureLoaded());

    await pumpTile(tester, task);

    // The description field carries only the free text the user typed — no
    // Todoist id/date/source trailer.
    final descField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Description'));
    expect(descField.controller!.text, 'Free-text notes');
    expect(find.textContaining('Todoist ID'), findsNothing);

    await openInfo(tester);

    expect(find.text('Origin: Automatically via Todoist (approval path)'),
        findsOneWidget);
    expect(find.text('Todoist source: Trip planning'), findsOneWidget);
    expect(find.text('Approved: 2026-08-21 07:30'), findsOneWidget);
    expect(find.text('Todoist ID: 999'), findsOneWidget);
    expect(find.textContaining('Last synced:'), findsOneWidget);
  });
}
