import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/task.dart';
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

  testWidgets('a task with no Todoist link shows no info icon beside Note',
      (tester) async {
    await tester.runAsync(() => TodoistSyncService.instance.ensureLoaded());
    final task = Task(title: 'Unsynced task');

    await pumpTile(tester, task);

    expect(find.byIcon(Icons.info_outline), findsNothing);
  });

  testWidgets(
      'a task synced with Todoist shows an info icon beside Note with '
      'source, synced date and Todoist id — none of it in the description',
      (tester) async {
    final task = Task(title: 'Synced task', description: 'Free-text notes');
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

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    // The description field carries only the free text the user typed — no
    // Todoist id/date/source trailer.
    final descField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Description'));
    expect(descField.controller!.text, 'Free-text notes');
    expect(find.text('Todoist ID: 999'), findsNothing);

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.text('Source: Todoist'), findsOneWidget);
    expect(find.text('Todoist ID: 999'), findsOneWidget);
    expect(find.textContaining('Synced:'), findsOneWidget);
  });
}
