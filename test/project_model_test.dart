import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/project.dart';

void main() {
  test('placeholders provide three seed projects with stable ids', () {
    expect(Project.placeholders.length, 3);
    expect(
      Project.placeholders.map((p) => p.id).toList(),
      ['project_1', 'project_2', 'project_3'],
    );
    expect(Project.placeholders.first.name, 'Project 1');
    expect(Project.placeholders.first.description, '');
  });

  test('toJson/fromJson round-trips id, name and description', () {
    const project = Project(
      id: 'project_2',
      name: 'Renovation',
      description: 'Everything for the new kitchen',
    );
    final restored = Project.fromJson(project.toJson());
    expect(restored.id, 'project_2');
    expect(restored.name, 'Renovation');
    expect(restored.description, 'Everything for the new kitchen');
  });

  test('fromJson tolerates missing keys', () {
    final restored = Project.fromJson(const {'id': 'x'});
    expect(restored.id, 'x');
    expect(restored.name, '');
    expect(restored.description, '');
  });

  test('copyWith replaces only the given fields and never the id', () {
    const project = Project(id: 'project_1', name: 'Project 1');

    final renamed = project.copyWith(name: 'Household');
    expect(renamed.id, 'project_1');
    expect(renamed.name, 'Household');
    expect(renamed.description, '');

    final described = renamed.copyWith(description: 'Chores and repairs');
    expect(described.id, 'project_1');
    expect(described.name, 'Household');
    expect(described.description, 'Chores and repairs');
  });
}
