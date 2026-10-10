import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/project.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/ui/task_tile.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Widget _wrap(Task task) => MaterialApp(
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
    );

void main() {
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    ProjectService.instance.resetForTest();
  });

  testWidgets('task without a project shows no tags', (tester) async {
    await tester.pumpWidget(_wrap(Task(title: 'Plain task')));

    expect(find.text('Project 1'), findsNothing);
    expect(find.text('To-Do'), findsNothing);
  });

  testWidgets('assigned task shows project name and stage tags',
      (tester) async {
    final task = Task(title: 'Tagged task', projectId: 'project_1');
    await tester.pumpWidget(_wrap(task));

    expect(find.text('Project 1'), findsOneWidget);
    expect(find.text('To-Do'), findsOneWidget);
  });

  testWidgets('stage tag follows the kanban status', (tester) async {
    final task = Task(
      title: 'Busy task',
      projectId: 'project_2',
      kanbanStatus: Task.kanbanOngoing,
    );
    await tester.pumpWidget(_wrap(task));

    expect(find.text('Project 2'), findsOneWidget);
    expect(find.text('Ongoing'), findsOneWidget);
    expect(find.text('To-Do'), findsNothing);
  });

  testWidgets('closed stage shows the Closed tag', (tester) async {
    final task = Task(
      title: 'Done task',
      projectId: 'project_3',
      kanbanStatus: Task.kanbanClosed,
    );
    await tester.pumpWidget(_wrap(task));

    expect(find.text('Closed'), findsOneWidget);
  });

  testWidgets('renaming a project updates the tag on the tile',
      (tester) async {
    final task = Task(title: 'Tagged task', projectId: 'project_1');
    await tester.pumpWidget(_wrap(task));
    expect(find.text('Project 1'), findsOneWidget);

    // runAsync: upsert writes projects.json — real I/O must run outside the
    // fake-async test zone or the await never completes.
    await tester.runAsync(() => ProjectService.instance.upsert(
          const Project(id: 'project_1', name: 'Household'),
        ));
    await tester.pump();

    expect(find.text('Household'), findsOneWidget);
    expect(find.text('Project 1'), findsNothing);
  });

  testWidgets('tag falls back to the raw id when the project is unknown',
      (tester) async {
    final task = Task(title: 'Orphan task', projectId: 'ghost_project');
    await tester.pumpWidget(_wrap(task));

    expect(find.text('ghost_project'), findsOneWidget);
  });
}
