class Task {
  /// Unique identifier for the task. Generated automatically when a task is
  /// created or imported without an id.
  String id;

  String title;
  String description;
  String note;
  String label;
  DateTime? dueDate;
  bool isDone;

  /// Position of the task within its list. This value is optional and not
  /// required to be unique. It is updated based on the task's position in the
  /// UI lists.
  int? listRanking;

  Task({
    String? id,
    required this.title,
    this.description = '',
    this.note = '',
    this.label = '',
    this.dueDate,
    this.isDone = false,
    this.listRanking,
  }) : id = id ?? generateId();

  /// Generates a pseudo-unique identifier based on the current timestamp.
  static String generateId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// Ensures that every task in the provided list has a unique id. Tasks with
  /// missing or duplicate ids are assigned new ones.
  static void ensureUniqueIds(List<Task> tasks) {
    final ids = <String>{};
    for (final task in tasks) {
      if (task.id.isEmpty || ids.contains(task.id)) {
        task.id = generateId();
      }
      ids.add(task.id);
    }
  }

  void toggleDone() {
    isDone = !isDone;
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      note: json['note'] as String? ?? '',
      label: json['label'] as String? ?? '',
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      isDone: json['isDone'] as bool? ?? false,
      listRanking: json['listRanking'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'note': note,
        'label': label,
        'dueDate': dueDate?.toIso8601String(),
        'isDone': isDone,
        if (listRanking != null) 'listRanking': listRanking,
      };
}
