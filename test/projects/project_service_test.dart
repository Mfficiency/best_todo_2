import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/project.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:flutter_test/flutter_test.dart';
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

  File projectsFile() => File('${tempDir.path}/projects.json');

  test('first load seeds the placeholder projects and persists them',
      () async {
    await ProjectService.instance.load();

    expect(ProjectService.instance.list.length, 3);
    expect(ProjectService.instance.list.first.name, 'Project 1');
    expect(await projectsFile().exists(), isTrue);

    final data = jsonDecode(await projectsFile().readAsString()) as List;
    expect(data.length, 3);
  });

  test('upsert renames a project, persists it and survives a reload',
      () async {
    await ProjectService.instance.load();

    final renamed = ProjectService.instance.list.first.copyWith(
      name: 'Household',
      description: 'Chores and repairs',
    );
    await ProjectService.instance.upsert(renamed);

    expect(ProjectService.instance.nameOf('project_1'), 'Household');

    // Fresh load (new session) must read the persisted rename back.
    ProjectService.instance.resetForTest();
    expect(ProjectService.instance.nameOf('project_1'), 'Project 1');
    await ProjectService.instance.load();
    expect(ProjectService.instance.nameOf('project_1'), 'Household');
    expect(ProjectService.instance.byId('project_1')!.description,
        'Chores and repairs');
  });

  test('upsert adds a project with an unknown id', () async {
    await ProjectService.instance.load();
    await ProjectService.instance
        .upsert(const Project(id: 'project_9', name: 'New one'));

    expect(ProjectService.instance.list.length, 4);
    expect(ProjectService.instance.byId('project_9')!.name, 'New one');
  });

  test('byId and nameOf handle null and unknown ids', () async {
    await ProjectService.instance.load();

    expect(ProjectService.instance.byId(null), isNull);
    expect(ProjectService.instance.byId('nope'), isNull);
    expect(ProjectService.instance.nameOf(null), '');
    // Unknown ids fall back to the raw id so a task whose project vanished
    // still shows something identifying.
    expect(ProjectService.instance.nameOf('ghost_project'), 'ghost_project');
  });

  test('a corrupt projects.json falls back to the placeholder projects',
      () async {
    await projectsFile().writeAsString('this is not json');

    await ProjectService.instance.load();
    expect(ProjectService.instance.list.length, 3);
    expect(ProjectService.instance.list.first.name, 'Project 1');
  });

  test('an empty or id-less projects file keeps the placeholders', () async {
    await projectsFile().writeAsString(jsonEncode([
      {'name': 'no id, dropped'},
    ]));

    await ProjectService.instance.load();
    expect(ProjectService.instance.list.length, 3);
  });

  test('load only reads the file once per session', () async {
    await ProjectService.instance.load();
    await ProjectService.instance
        .upsert(const Project(id: 'project_1', name: 'Renamed'));

    // A second load in the same session must not clobber in-memory state
    // with the (already stale) file contents... which here are identical,
    // so instead prove it by making the file unreadable.
    await projectsFile().writeAsString('garbage');
    await ProjectService.instance.load();
    expect(ProjectService.instance.nameOf('project_1'), 'Renamed');
  });

  test('stageLabel maps kanban ids to display names', () {
    expect(ProjectService.stageLabel(Task.kanbanTodo), 'To-Do');
    expect(ProjectService.stageLabel(Task.kanbanOngoing), 'Ongoing');
    expect(ProjectService.stageLabel(Task.kanbanClosed), 'Closed');
    expect(ProjectService.stageLabel('unknown'), 'To-Do');
  });
}
