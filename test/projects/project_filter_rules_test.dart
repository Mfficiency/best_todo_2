import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/ui/project_board_page.dart';
import 'package:besttodo/ui/projects_page.dart';
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

  tearDown(() {
    Config.viewFilterRules = {};
  });

  testWidgets('a Projects exclude-tag rule hides matching tasks',
      (tester) async {
    Config.viewFilterRules[ViewFilterRules.projects] =
        ViewFilterRules(excludeTags: ['later']);

    final tasks = [
      Task(title: 'Visible task', label: 'ok'),
      Task(title: 'Hidden task', label: 'later'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: ProjectsPage(tasks: tasks, onChanged: () {}),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('Visible task'), findsOneWidget);
    expect(find.text('Hidden task'), findsNothing);
  });

  testWidgets('the same rule hides matching tasks on a project board',
      (tester) async {
    Config.viewFilterRules[ViewFilterRules.projects] =
        ViewFilterRules(excludeTags: ['later']);

    await tester.runAsync(() => ProjectService.instance.load());
    final project = ProjectService.instance.projects.value.first;
    final tasks = [
      Task(
        title: 'Visible task',
        label: 'ok',
        projectId: project.id,
        kanbanStatus: Task.kanbanTodo,
      ),
      Task(
        title: 'Hidden task',
        label: 'later',
        projectId: project.id,
        kanbanStatus: Task.kanbanTodo,
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: ProjectBoardPage(project: project, tasks: tasks, onChanged: () {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Visible task'), findsOneWidget);
    expect(find.text('Hidden task'), findsNothing);
  });

  testWidgets(
      'an includeTags: [Project] rule (the literal default) does not hide '
      'unassigned tasks from the "All Tasks" assign pane, but still applies '
      'on the project board', (tester) async {
    Config.viewFilterRules[ViewFilterRules.projects] =
        ViewFilterRules(includeTags: ['Project']);

    final unassigned = Task(title: 'Unassigned task');
    await tester.pumpWidget(MaterialApp(
      home: ProjectsPage(tasks: [unassigned], onChanged: () {}),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('Unassigned task'), findsOneWidget);
  });
}
