class Task {
  String title;
  String description;
  String note;
  String label;
  DateTime? dueDate;
  bool isDone;

  Task({
    required this.title,
    this.description = '',
    this.note = '',
    this.label = '',
    this.dueDate,
    this.isDone = false,
  });

  void toggleDone() {
    isDone = !isDone;
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      note: json['note'] as String? ?? '',
      label: json['label'] as String? ?? '',
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      isDone: json['isDone'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'note': note,
        'label': label,
        'dueDate': dueDate?.toIso8601String(),
        'isDone': isDone,
      };
}
