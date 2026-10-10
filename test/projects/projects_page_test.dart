import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/ui/projects_page.dart';
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
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
  });

  Future<void> pumpPage(
    WidgetTester tester,
    List<Task> tasks, {
    VoidCallback? onChanged,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: ProjectsPage(tasks: tasks, onChanged: onChanged ?? () {}),
    ));
    // initState fires ProjectService.load() (real file I/O); give it a slice
    // of real event loop so it completes before assertions.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  Future<void> longPressDrag(
    WidgetTester tester,
    Finder from,
    Finder to,
  ) async {
    final gesture = await tester.startGesture(tester.getCenter(from));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(to));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('shows all active tasks and the three seed projects',
      (tester) async {
    final tasks = [
      Task(title: 'Alpha'),
      Task(title: 'Beta'),
      Task(title: 'Gone', deletedAt: DateTime(2026, 1, 1)),
    ];
    await pumpPage(tester, tasks);

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gone'), findsNothing);
    expect(find.text('Project 1'), findsOneWidget);
    expect(find.text('Project 2'), findsOneWidget);
    expect(find.text('Project 3'), findsOneWidget);
    expect(find.text('0 tasks'), findsNWidgets(3));
  });

  testWidgets('dragging a task onto a project assigns it', (tester) async {
    final task = Task(title: 'Alpha');
    var changed = 0;
    await pumpPage(tester, [task], onChanged: () => changed++);

    await longPressDrag(
      tester,
      find.text('Alpha'),
      find.text('Project 1'),
    );

    expect(task.projectId, 'project_1');
    expect(task.kanbanStatus, Task.kanbanTodo);
    expect(changed, 1);
    expect(find.text('Added "Alpha" to Project 1'), findsOneWidget);
    expect(find.text('1 task'), findsOneWidget);

    // Drain the snackbar's auto-dismiss timer so the test ends clean.
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets(
      'on desktop a plain mouse drag (no long-press) assigns the task',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final task = Task(title: 'Alpha');
    var changed = 0;
    await pumpPage(tester, [task], onChanged: () => changed++);

    // Mouse users get the immediate Draggable and the shorter hint.
    expect(find.text('Drag a task onto a project below.'), findsOneWidget);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Alpha')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveTo(tester.getCenter(find.text('Project 1')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(task.projectId, 'project_1');
    expect(changed, 1);

    // Drain the snackbar's auto-dismiss timer so the test ends clean.
    await tester.pumpAndSettle(const Duration(seconds: 3));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('touch platforms keep the long-press hint', (tester) async {
    await pumpPage(tester, [Task(title: 'Alpha')]);

    expect(find.text('Long-press a task and drag it onto a project below.'),
        findsOneWidget);
  });

  testWidgets('an assigned task shows its project as a chip in the task pane',
      (tester) async {
    final task = Task(title: 'Alpha', projectId: 'project_2');
    await pumpPage(tester, [task]);

    // Once on the project card, once as the chip on the task row.
    expect(find.text('Project 2'), findsNWidgets(2));
  });

  testWidgets('tapping a project card opens its board when a task chip shares the name',
      (tester) async {
    final task = Task(title: 'Alpha', projectId: 'project_1');
    await pumpPage(tester, [task]);

    // The assigned task's row shows a "Project 1" chip inside the ListTile's
    // own InkWell, so widgetWithText(InkWell, ...) is ambiguous here; the
    // card must be targeted through its DragTarget (as the screenshot
    // integration test does).
    expect(find.widgetWithText(InkWell, 'Project 1'), findsAtLeastNWidgets(2));

    await tester.tap(find.descendant(
      of: find.byType(DragTarget<Task>),
      matching: find.text('Project 1'),
    ));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Edit project'), findsOneWidget);
  });

  testWidgets('renamed projects load from disk and show on the cards',
      (tester) async {
    await tester.runAsync(
        () => File('${tempDir.path}/projects.json').writeAsString(jsonEncode([
              {'id': 'project_1', 'name': 'Household', 'description': 'Chores'},
              {'id': 'project_2', 'name': 'Work'},
              {'id': 'project_3', 'name': 'Project 3'},
            ])));
    // Load deterministically before pumping; the page's own initState load is
    // then a no-op (load only reads once per session).
    await tester.runAsync(() => ProjectService.instance.load());

    await pumpPage(tester, [Task(title: 'Alpha')]);

    expect(find.text('Household'), findsOneWidget);
    expect(find.text('Chores'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Project 1'), findsNothing);
  });
}
