import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/project.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/ui/project_board_page.dart';
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

  Future<void> pumpBoard(
    WidgetTester tester,
    List<Task> tasks, {
    Project? project,
    VoidCallback? onChanged,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: ProjectBoardPage(
        project: project ?? Project.placeholders.first,
        tasks: tasks,
        onChanged: onChanged ?? () {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('groups the project tasks into the three columns',
      (tester) async {
    final tasks = [
      Task(title: 'Plan', projectId: 'project_1'),
      Task(
          title: 'Build',
          projectId: 'project_1',
          kanbanStatus: Task.kanbanOngoing),
      Task(
          title: 'Ship',
          projectId: 'project_1',
          kanbanStatus: Task.kanbanClosed),
      Task(title: 'Other project', projectId: 'project_2'),
      Task(title: 'Unassigned'),
    ];
    await pumpBoard(tester, tasks);

    expect(find.text('To-Do (1)'), findsOneWidget);
    expect(find.text('Ongoing (1)'), findsOneWidget);
    expect(find.text('Closed (1)'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('Build'), findsOneWidget);
    expect(find.text('Ship'), findsOneWidget);
    expect(find.text('Other project'), findsNothing);
    expect(find.text('Unassigned'), findsNothing);
  });

  testWidgets('dragging a card to another column changes its stage',
      (tester) async {
    final task = Task(title: 'Plan', projectId: 'project_1');
    var changed = 0;
    await pumpBoard(tester, [task], onChanged: () => changed++);

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Plan')));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(find.text('Ongoing (0)')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(task.kanbanStatus, Task.kanbanOngoing);
    expect(changed, 1);
    expect(find.text('To-Do (0)'), findsOneWidget);
    expect(find.text('Ongoing (1)'), findsOneWidget);
  });

  testWidgets('the close button removes a task from the project',
      (tester) async {
    final task = Task(
        title: 'Plan',
        projectId: 'project_1',
        kanbanStatus: Task.kanbanOngoing);
    var changed = 0;
    await pumpBoard(tester, [task], onChanged: () => changed++);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(task.projectId, isNull);
    expect(task.kanbanStatus, Task.kanbanTodo);
    expect(changed, 1);
    expect(find.text('Plan'), findsNothing);
  });

  testWidgets('edit dialog saves name and description', (tester) async {
    await tester.runAsync(() => ProjectService.instance.load());
    await pumpBoard(tester, []);

    await tester.tap(find.byTooltip('Edit project'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'Household');
    await tester.enterText(
        find.widgetWithText(TextField, 'Description'), 'Chores and repairs');
    await tester.tap(find.text('Save'));
    // The save path awaits a real projects.json write (started in the fake
    // zone) before calling setState; each I/O hop needs a real-event-loop
    // slice plus a pump. Poll the SERVICE state (the closing dialog's text
    // field would satisfy a find.text check prematurely).
    for (var i = 0;
        i < 300 && ProjectService.instance.nameOf('project_1') != 'Household';
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // App bar title and the description banner update in place.
    expect(find.text('Household'), findsOneWidget);
    expect(find.text('Chores and repairs'), findsOneWidget);
    // The service (and through it projects.json) holds the change.
    expect(ProjectService.instance.nameOf('project_1'), 'Household');
    expect(ProjectService.instance.byId('project_1')!.description,
        'Chores and repairs');
  });

  testWidgets('cancelling the edit dialog changes nothing', (tester) async {
    await tester.runAsync(() => ProjectService.instance.load());
    await pumpBoard(tester, []);

    await tester.tap(find.byTooltip('Edit project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Nope');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Project 1'), findsOneWidget);
    expect(find.text('Nope'), findsNothing);
    expect(ProjectService.instance.nameOf('project_1'), 'Project 1');
  });

  testWidgets('an empty name keeps the previous project name', (tester) async {
    await tester.runAsync(() => ProjectService.instance.load());
    await pumpBoard(tester, []);

    await tester.tap(find.byTooltip('Edit project'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), '   ');
    await tester.enterText(
        find.widgetWithText(TextField, 'Description'), 'Still described');
    await tester.tap(find.text('Save'));
    for (var i = 0;
        i < 300 &&
            ProjectService.instance.byId('project_1')!.description !=
                'Still described';
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Project 1'), findsOneWidget);
    expect(ProjectService.instance.nameOf('project_1'), 'Project 1');
    expect(ProjectService.instance.byId('project_1')!.description,
        'Still described');
  });
}
