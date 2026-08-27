import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('plain task shows its labels as tags', (tester) async {
    await tester.pumpWidget(
        _wrap(Task(title: 'Call plumber', label: 'urgent, home')));

    expect(find.text('urgent'), findsOneWidget);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('task with no labels and no project shows no tags',
      (tester) async {
    await tester.pumpWidget(_wrap(Task(title: 'Plain task')));

    expect(find.byType(ListTile), findsOneWidget);
    expect(
      tester.widget<ListTile>(find.byType(ListTile)).subtitle,
      isNull,
    );
  });

  testWidgets('project task shows project, stage and label tags',
      (tester) async {
    await tester.pumpWidget(_wrap(Task(
      title: 'Tagged task',
      projectId: 'project_1',
      label: 'priority-high',
    )));

    expect(find.text('Project 1'), findsOneWidget);
    expect(find.text('To-Do'), findsOneWidget);
    expect(find.text('priority-high'), findsOneWidget);
  });

  testWidgets('wish keeps the wish tag alongside its labels', (tester) async {
    await tester.pumpWidget(_wrap(Task(
      title: 'New bike',
      isWish: true,
      label: 'priority-medium, gear',
    )));

    expect(find.text('wish'), findsOneWidget);
    expect(find.text('priority-medium'), findsOneWidget);
    expect(find.text('gear'), findsOneWidget);
  });

  Color _pillColor(WidgetTester tester, String text) {
    final container = tester.widget<Container>(find
        .ancestor(of: find.text(text), matching: find.byType(Container))
        .first);
    final decoration = container.decoration as BoxDecoration;
    return decoration.color!;
  }

  Border? _pillBorder(WidgetTester tester, String text) {
    final container = tester.widget<Container>(find
        .ancestor(of: find.text(text), matching: find.byType(Container))
        .first);
    return (container.decoration as BoxDecoration).border as Border?;
  }

  testWidgets('the wish pill is colored differently from a plain label pill',
      (tester) async {
    await tester.pumpWidget(_wrap(
        Task(title: 'New bike', isWish: true, label: 'gear')));

    expect(_pillBorder(tester, 'wish'), isNotNull);
    expect(_pillBorder(tester, 'gear'), isNull);
    expect(_pillColor(tester, 'wish'), isNot(_pillColor(tester, 'gear')));
  });

  testWidgets(
      'a manually typed reserved word (e.g. "Archived") renders like the '
      'wish pill, not like a plain label', (tester) async {
    await tester.pumpWidget(
        _wrap(Task(title: 'Odd task', label: 'Archived, gear')));

    expect(_pillBorder(tester, 'Archived'), isNotNull);
    expect(_pillBorder(tester, 'gear'), isNull);
  });
}
