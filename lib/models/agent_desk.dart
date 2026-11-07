/// Agent Desk: the questions background agents ask, the decisions you give
/// them, and each project's status — all read from a shared folder of plain
/// files (see `AgentDeskService` and SPEC §10.6s). Every file has exactly one
/// writer: agents write `questions.jsonl`, `status.json` and `log.md`; each
/// device running BestToDo appends to its own `decisions-<device>.jsonl`, so
/// two PCs syncing the folder through git never edit the same file.

/// How urgent a question is. Only [blocking] and [normal] reach the
/// "Decide now" top three; [later] questions wait on the project page.
enum DeskPriority { blocking, normal, later }

DeskPriority _priorityFrom(Object? raw) {
  switch (raw) {
    case 'blocking':
      return DeskPriority.blocking;
    case 'later':
      return DeskPriority.later;
    default:
      return DeskPriority.normal;
  }
}

DateTime? _date(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toLocal() : null;

/// A question an agent put on the desk.
class DeskQuestion {
  final String id;
  final String projectId;
  final DateTime? at;
  final String topic;
  final String text;
  final List<String> options;
  final DeskPriority priority;
  final DateTime? deadline;

  const DeskQuestion({
    required this.id,
    required this.projectId,
    required this.text,
    this.at,
    this.topic = '',
    this.options = const [],
    this.priority = DeskPriority.normal,
    this.deadline,
  });

  factory DeskQuestion.fromJson(String projectId, Map<String, dynamic> json) =>
      DeskQuestion(
        id: json['id']?.toString() ?? '',
        projectId: projectId,
        at: _date(json['at']),
        topic: json['topic'] as String? ?? '',
        text: json['text'] as String? ?? '',
        options: (json['options'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.trim().isNotEmpty)
                .toList() ??
            const [],
        priority: _priorityFrom(json['priority']),
        deadline: _date(json['deadline']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (at != null) 'at': at!.toUtc().toIso8601String(),
        if (topic.isNotEmpty) 'topic': topic,
        'text': text,
        if (options.isNotEmpty) 'options': options,
        'priority': priority.name,
        if (deadline != null) 'deadline': deadline!.toUtc().toIso8601String(),
      };
}

/// An answer or instruction you gave, from any device.
class DeskDecision {
  final String id;
  final String projectId;
  final DateTime at;
  final String? questionId;
  final String topic;
  final String text;

  /// 'option' (a suggested answer was tapped) or 'text' (typed or spoken).
  final String via;
  final String device;

  const DeskDecision({
    required this.id,
    required this.projectId,
    required this.at,
    required this.text,
    this.questionId,
    this.topic = '',
    this.via = 'text',
    this.device = '',
  });

  factory DeskDecision.fromJson(String projectId, Map<String, dynamic> json) =>
      DeskDecision(
        id: json['id']?.toString() ?? '',
        projectId: projectId,
        at: _date(json['at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        questionId: json['questionId'] as String?,
        topic: json['topic'] as String? ?? '',
        text: json['text'] as String? ?? '',
        via: json['via'] as String? ?? 'text',
        device: json['device'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': at.toUtc().toIso8601String(),
        if (questionId != null) 'questionId': questionId,
        if (topic.isNotEmpty) 'topic': topic,
        'text': text,
        'via': via,
        if (device.isNotEmpty) 'device': device,
      };
}

/// What a project's agent is doing, from its `status.json`.
enum DeskState { working, waiting, idle, error }

/// One project folder on the desk.
class DeskProject {
  final String id;
  final String name;
  final String goal;
  final DeskState state;
  final String summary;

  /// Where its agent runs: 'beast', 'cloud' or 'both' (free text).
  final String where;
  final DateTime? updatedAt;
  final List<DeskQuestion> questions;
  final List<DeskDecision> decisions;

  /// The last lines of `log.md`, oldest first.
  final List<String> logTail;

  const DeskProject({
    required this.id,
    required this.name,
    this.goal = '',
    this.state = DeskState.idle,
    this.summary = '',
    this.where = '',
    this.updatedAt,
    this.questions = const [],
    this.decisions = const [],
    this.logTail = const [],
  });

  static DeskState stateFrom(Object? raw) {
    for (final s in DeskState.values) {
      if (s.name == raw) return s;
    }
    return DeskState.idle;
  }

  Set<String> get _answeredIds =>
      {for (final d in decisions) if (d.questionId != null) d.questionId!};

  /// Questions without a decision yet, in [AgentDeskRanking] order.
  List<DeskQuestion> get openQuestions {
    final answered = _answeredIds;
    return AgentDeskRanking.sort(
        questions.where((q) => !answered.contains(q.id)).toList());
  }

  /// The decision that answered [questionId], if any.
  DeskDecision? answerTo(String questionId) {
    for (final d in decisions.reversed) {
      if (d.questionId == questionId) return d;
    }
    return null;
  }

  /// Topics named by this project's questions, in first-seen order.
  List<String> get topics {
    final seen = <String>{};
    for (final q in questions) {
      if (q.topic.isNotEmpty) seen.add(q.topic);
    }
    return seen.toList();
  }
}

/// Everything on the desk at one moment.
class DeskSnapshot {
  final String folder;
  final List<DeskProject> projects;

  const DeskSnapshot({required this.folder, required this.projects});

  DeskProject? project(String id) {
    for (final p in projects) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<DeskQuestion> get openQuestions =>
      AgentDeskRanking.sort([for (final p in projects) ...p.openQuestions]);

  /// The "Decide now" row: up to [count] open questions that aren't
  /// [DeskPriority.later].
  List<DeskQuestion> topQuestions([int count = 3]) => openQuestions
      .where((q) => q.priority != DeskPriority.later)
      .take(count)
      .toList();
}

/// Ordering of open questions: blocking first, then those with a deadline
/// (soonest first), then the oldest. `later` always sorts last.
class AgentDeskRanking {
  static int _rank(DeskPriority p) => switch (p) {
        DeskPriority.blocking => 0,
        DeskPriority.normal => 1,
        DeskPriority.later => 2,
      };

  static int compare(DeskQuestion a, DeskQuestion b) {
    final byPriority = _rank(a.priority).compareTo(_rank(b.priority));
    if (byPriority != 0) return byPriority;
    final da = a.deadline, db = b.deadline;
    if (da != null && db == null) return -1;
    if (da == null && db != null) return 1;
    if (da != null && db != null && da != db) return da.compareTo(db);
    final ta = a.at, tb = b.at;
    if (ta != null && tb != null && ta != tb) return ta.compareTo(tb);
    if (ta != null && tb == null) return -1;
    if (ta == null && tb != null) return 1;
    return a.id.compareTo(b.id);
  }

  static List<DeskQuestion> sort(List<DeskQuestion> questions) =>
      [...questions]..sort(compare);
}
