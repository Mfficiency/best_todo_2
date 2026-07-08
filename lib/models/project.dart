/// A lightweight project that tasks can be assigned to and organised on a
/// Kanban-style board (To-Do / Ongoing / Closed).
class Project {
  final String id;
  final String name;
  final String description;

  const Project({
    required this.id,
    required this.name,
    this.description = '',
  });

  Project copyWith({String? name, String? description}) => Project(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
      );

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
      };

  /// Default projects seeded on first run until project create/delete is
  /// added. Names are editable afterwards (persisted in projects.json).
  static const List<Project> placeholders = [
    Project(id: 'project_1', name: 'Project 1'),
    Project(id: 'project_2', name: 'Project 2'),
    Project(id: 'project_3', name: 'Project 3'),
  ];
}
