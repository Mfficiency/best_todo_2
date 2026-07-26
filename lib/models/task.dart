import 'package:uuid/uuid.dart';

class Task {
  static final Uuid _uuid = const Uuid();

  static String newUid() => _uuid.v4();

  /// Version of the on-disk task record. Bump when a field changes meaning;
  /// [fromJson] upgrades older records on read (v1 → v2: the single
  /// `dueDate` became the `startAt`/`endAt` interval) and [toJson] always
  /// writes the current version plus the legacy `dueDate` mirror, so a
  /// downgrade or an old import keeps working.
  static const int currentSchemaVersion = 2;

  String uid;
  String title;
  String description;
  String note;
  String label;
  DateTime? createdAt;
  DateTime? completedAt;
  DateTime? movedAt;
  DateTime? rescheduledAt;

  /// Scheduled interval (schema v2). A deadline-style task — everything the
  /// UI creates today — has `startAt == endAt`; a future blocked-time item
  /// gets a real duration. Undated tasks have both null.
  DateTime? startAt;
  DateTime? endAt;

  DateTime? deletedAt;
  bool autoDeleted;
  bool isDone;
  /// When true, the schedule's time-of-day was set deliberately (e.g. placed
  /// on the Chronize timeline) and must not be overwritten by the default
  /// 18:00 deadline normalization.
  bool hasExplicitTime;

  /// Legacy view of the schedule: the deadline. Reading gives [endAt];
  /// writing collapses the interval to a deadline (`startAt = endAt =
  /// value`), which is exactly what every current caller means. Range-aware
  /// code should use [startAt]/[endAt] directly.
  DateTime? get dueDate => endAt;
  set dueDate(DateTime? value) {
    startAt = value;
    endAt = value;
  }

  /// All-day semantics derive from [hasExplicitTime] — a task without a
  /// deliberately chosen time is date-only (the 18:00 default is a display
  /// convention, not data).
  bool get allDay => !hasExplicitTime;

  /// The scheduled length; zero for deadline-style tasks, null when undated.
  Duration? get duration => (startAt == null || endAt == null)
      ? null
      : endAt!.difference(startAt!);
  int? listRanking;
  bool isRecurring;
  DateTime? recurrenceEndDate;
  int recurrenceIntervalDays;
  String? recurrenceParentUid;
  String? recurrenceInstanceKey;

  /// When true this task belongs to the wishlist: it shows up in the
  /// Wishlist tool (a pre-filtered view over the one task list, like a
  /// project) and, lacking a due date, buckets into the Future tab.
  bool isWish;

  /// Id of the project this task is assigned to, or null if unassigned.
  String? projectId;

  /// Kanban column for this task within its project: one of
  /// [kanbanTodo], [kanbanOngoing] or [kanbanClosed].
  String kanbanStatus;

  /// Kanban column identifiers used by the Projects board.
  static const String kanbanTodo = 'todo';
  static const String kanbanOngoing = 'ongoing';
  static const String kanbanClosed = 'closed';

  Task({
    String? uid,
    required this.title,
    this.description = '',
    this.note = '',
    this.label = '',
    this.createdAt,
    this.completedAt,
    this.movedAt,
    this.rescheduledAt,
    DateTime? dueDate,
    DateTime? startAt,
    DateTime? endAt,
    this.deletedAt,
    this.autoDeleted = false,
    this.isDone = false,
    this.hasExplicitTime = false,
    this.listRanking,
    this.isRecurring = false,
    this.recurrenceEndDate,
    this.recurrenceIntervalDays = 1,
    this.recurrenceParentUid,
    this.recurrenceInstanceKey,
    this.isWish = false,
    this.projectId,
    this.kanbanStatus = kanbanTodo,
  })  : uid = uid ?? Task.newUid(),
        // An explicit interval wins; a plain dueDate is a deadline
        // (start == end), matching what every existing caller means.
        startAt = startAt ?? dueDate,
        endAt = endAt ?? dueDate;

  void toggleDone() {
    isDone = !isDone;
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) => json[key] != null
        ? DateTime.tryParse(json[key] as String? ?? '')
        : null;
    // Schema upgrade on read. v1 records only carry dueDate; v2 carries the
    // startAt/endAt interval (dueDate kept as a mirror for downgrades). A v2
    // record missing endAt still falls back to dueDate so hand-edited or
    // partial payloads import sanely.
    final legacyDue = date('dueDate');
    var start = date('startAt');
    var end = date('endAt');
    end ??= legacyDue;
    start ??= end;
    return Task(
      uid: json['uid'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      note: json['note'] as String? ?? '',
      label: json['label'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      movedAt: json['movedAt'] != null
          ? DateTime.parse(json['movedAt'] as String)
          : null,
      rescheduledAt: json['rescheduledAt'] != null
          ? DateTime.parse(json['rescheduledAt'] as String)
          : null,
      startAt: start,
      endAt: end,
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : null,
      autoDeleted: json['autoDeleted'] as bool? ?? false,
      isDone: json['isDone'] as bool? ?? false,
      hasExplicitTime: json['hasExplicitTime'] as bool? ?? false,
      listRanking: json['listRanking'] as int?,
      isRecurring: json['isRecurring'] as bool? ?? false,
      recurrenceEndDate: json['recurrenceEndDate'] != null
          ? DateTime.parse(json['recurrenceEndDate'] as String)
          : null,
      recurrenceIntervalDays: json['recurrenceIntervalDays'] as int? ?? 1,
      recurrenceParentUid: json['recurrenceParentUid'] as String?,
      recurrenceInstanceKey: json['recurrenceInstanceKey'] as String?,
      isWish: json['isWish'] as bool? ?? false,
      projectId: json['projectId'] as String?,
      kanbanStatus: json['kanbanStatus'] as String? ?? kanbanTodo,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': currentSchemaVersion,
        'uid': uid,
        'title': title,
        'description': description,
        'note': note,
        'label': label,
        'createdAt': createdAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'movedAt': movedAt?.toIso8601String(),
        'rescheduledAt': rescheduledAt?.toIso8601String(),
        'startAt': startAt?.toIso8601String(),
        'endAt': endAt?.toIso8601String(),
        // Legacy mirror of the deadline so downgrades and old importers work.
        'dueDate': dueDate?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'autoDeleted': autoDeleted,
        'isDone': isDone,
        'hasExplicitTime': hasExplicitTime,
        if (listRanking != null) 'listRanking': listRanking,
        'isRecurring': isRecurring,
        'recurrenceEndDate': recurrenceEndDate?.toIso8601String(),
        'recurrenceIntervalDays': recurrenceIntervalDays,
        if (recurrenceParentUid != null)
          'recurrenceParentUid': recurrenceParentUid,
        if (recurrenceInstanceKey != null)
          'recurrenceInstanceKey': recurrenceInstanceKey,
        'isWish': isWish,
        if (projectId != null) 'projectId': projectId,
        'kanbanStatus': kanbanStatus,
      };
}
