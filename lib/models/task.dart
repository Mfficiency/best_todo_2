import 'package:uuid/uuid.dart';

class Task {
  static final Uuid _uuid = const Uuid();

  static String newUid() => _uuid.v4();

  String uid;
  String title;
  String description;
  String note;
  String label;
  DateTime? dueDate;
  DateTime? deletedAt;
  bool isDone;
  int? listRanking;
  bool isRecurring;
  DateTime? recurrenceEndDate;
  int recurrenceIntervalDays;
  String? recurrenceParentUid;
  String? recurrenceInstanceKey;

  Task({
    String? uid,
    required this.title,
    this.description = '',
    this.note = '',
    this.label = '',
    this.dueDate,
    this.deletedAt,
    this.isDone = false,
    this.listRanking,
    this.isRecurring = false,
    this.recurrenceEndDate,
    this.recurrenceIntervalDays = 1,
    this.recurrenceParentUid,
    this.recurrenceInstanceKey,
  }) : uid = uid ?? Task.newUid();

  void toggleDone() {
    isDone = !isDone;
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      uid: json['uid'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      note: json['note'] as String? ?? '',
      label: json['label'] as String? ?? '',
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : null,
      isDone: json['isDone'] as bool? ?? false,
      listRanking: json['listRanking'] as int?,
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurrenceEndDate: json['recurrenceEndDate'] != null
          ? DateTime.parse(json['recurrenceEndDate'] as String)
          : null,
      recurrenceIntervalDays: json['recurrenceIntervalDays'] as int? ?? 1,
      recurrenceParentUid: json['recurrenceParentUid'] as String?,
      recurrenceInstanceKey: json['recurrenceInstanceKey'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'title': title,
        'description': description,
        'note': note,
        'label': label,
        'dueDate': dueDate?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'isDone': isDone,
        if (listRanking != null) 'listRanking': listRanking,
        'isRecurring': isRecurring,
        'recurrenceEndDate': recurrenceEndDate?.toIso8601String(),
        'recurrenceIntervalDays': recurrenceIntervalDays,
        if (recurrenceParentUid != null)
          'recurrenceParentUid': recurrenceParentUid,
        if (recurrenceInstanceKey != null)
          'recurrenceInstanceKey': recurrenceInstanceKey,
      };
}
