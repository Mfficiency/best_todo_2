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
}
