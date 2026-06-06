/// A lightweight project that tasks can be assigned to and organised on a
/// Kanban-style board (To-Do / Ongoing / Closed).
class Project {
  final String id;
  final String name;

  const Project({required this.id, required this.name});

  /// Placeholder projects shown until real project management is added.
  static const List<Project> placeholders = [
    Project(id: 'project_1', name: 'Project 1'),
    Project(id: 'project_2', name: 'Project 2'),
    Project(id: 'project_3', name: 'Project 3'),
  ];
}
