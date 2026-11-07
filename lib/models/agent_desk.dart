import '../services/todoist_metadata_codec.dart';
import '../utils/label_utils.dart';

/// Agent Desk: what background agents ask and report, as plain Todoist tasks
/// (SPEC §10.6s). Every desk task carries the label [agentDeskToken]; its
/// Todoist project is the desk project; its description is the (big) context
/// in Markdown with `[Key: value]` marker lines; its comments hold the
/// attachments and your answers. Nothing here knows about the local task list.

/// How urgent a question is. Only [blocking] and [normal] reach the top of
/// the queue; [later] questions are parked below them.
enum DeskPriority { blocking, normal, later }

/// What a project's agent is doing, from its status item's `[State: …]`.
enum DeskState { working, waiting, idle, error }

/// Project name of a desk task in the Todoist Inbox.
const String deskGeneralProject = 'General';

final RegExp _markerLine = RegExp(
  r'^[ \t]*\[(option|priority|topic|state|where|updated):[ \t]*([^\]\n]*)\][ \t]*$',
  caseSensitive: false,
  multiLine: true,
);

/// Splits a description into the visible Markdown and its desk markers
/// (lowercase key → values in order). Our sync's generated trailer, which a
/// device running the full Todoist sync may have added, is dropped too.
(String, Map<String, List<String>>) parseDeskMarkers(String description) {
  final visible = TodoistMetadataCodec.parse(description).visible;
  final markers = <String, List<String>>{};
  for (final m in _markerLine.allMatches(visible)) {
    final value = m.group(2)!.trim();
    if (value.isEmpty) continue;
    markers.putIfAbsent(m.group(1)!.toLowerCase(), () => []).add(value);
  }
  final body = visible
      .replaceAll(_markerLine, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return (body, markers);
}

DeskPriority _priorityFrom(String? raw) {
  switch (raw?.toLowerCase()) {
    case 'blocking':
      return DeskPriority.blocking;
    case 'later':
      return DeskPriority.later;
    default:
      return DeskPriority.normal;
  }
}

DeskState _stateFrom(String? raw) {
  for (final s in DeskState.values) {
    if (s.name == raw?.toLowerCase()) return s;
  }
  return DeskState.idle;
}

/// A file on one of the task's comments.
class DeskAttachment {
  final String name;
  final String url;
  final String type;

  const DeskAttachment({required this.name, required this.url, this.type = ''});

  bool get isImage {
    if (type.toLowerCase().startsWith('image')) return true;
    final lower = name.toLowerCase();
    return const ['.png', '.jpg', '.jpeg', '.gif', '.webp']
        .any(lower.endsWith);
  }

  static DeskAttachment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = (raw['file_url'] ?? raw['url'])?.toString() ?? '';
    if (url.isEmpty) return null;
    final name = (raw['file_name'] ?? raw['title'])?.toString() ?? '';
    final uri = Uri.tryParse(url);
    return DeskAttachment(
      name: name.isNotEmpty
          ? name
          : (uri != null && uri.pathSegments.isNotEmpty
              ? uri.pathSegments.last
              : url),
      url: url,
      type: (raw['file_type'] ?? raw['resource_type'])?.toString() ?? '',
    );
  }
}

/// One comment on a desk task: an agent's note, a file, or your answer.
class DeskComment {
  /// The prefix an answer given on the desk starts with.
  static const String answerPrefix = '[Answer]';

  final String content;
  final DateTime? at;
  final DeskAttachment? attachment;

  const DeskComment({required this.content, this.at, this.attachment});

  bool get isAnswer => content.trimLeft().startsWith(answerPrefix);

  /// [content] without the answer prefix.
  String get text => isAnswer
      ? content.trimLeft().substring(answerPrefix.length).trim()
      : content.trim();

  factory DeskComment.fromJson(Map<String, dynamic> json) => DeskComment(
        content: json['content'] as String? ?? '',
        at: DateTime.tryParse(
                (json['posted_at'] ?? json['posted'])?.toString() ?? '')
            ?.toLocal(),
        attachment: DeskAttachment.fromJson(json['file_attachment']),
      );
}

/// A desk task: a question, an instruction or a project's status item.
class DeskItem {
  /// The Todoist task id.
  final String id;
  final String project;
  final String title;

  /// The description as Markdown, without markers.
  final String body;
  final List<String> labels;
  final String topic;
  final List<String> options;
  final DeskPriority priority;
  final DateTime? deadline;
  final DateTime? at;

  /// The state/where/updated markers (status items only).
  final Map<String, List<String>> markers;

  const DeskItem({
    required this.id,
    required this.project,
    required this.title,
    this.body = '',
    this.labels = const [],
    this.topic = '',
    this.options = const [],
    this.priority = DeskPriority.normal,
    this.deadline,
    this.at,
    this.markers = const {},
  });

  bool _has(String token) =>
      labels.any((l) => l.toLowerCase() == token.toLowerCase());

  bool get isStatus => _has(agentDeskStatusToken);
  bool get isInstruction => _has(agentDeskInstructionToken);
  bool get isAnswered => _has(agentDeskAnsweredToken);

  /// Still waiting for you.
  bool get isOpen => !isStatus && !isInstruction && !isAnswered;

  factory DeskItem.fromRemote(
    Map<String, dynamic> task,
    Map<String, String> projectNames,
  ) {
    final (body, markers) =
        parseDeskMarkers(task['description'] as String? ?? '');
    final labels = task['labels'] is List
        ? (task['labels'] as List).whereType<String>().toList()
        : const <String>[];
    final due = task['due'];
    final dueDate = due is Map ? due['date'] as String? : null;
    final project = projectNames[task['project_id']?.toString()];
    return DeskItem(
      id: task['id']?.toString() ?? '',
      project: project == null || project.isEmpty ? deskGeneralProject : project,
      title: task['content'] as String? ?? '',
      body: body,
      labels: labels,
      topic: markers['topic']?.first ?? '',
      options: markers['option'] ?? const [],
      priority: _priorityFrom(markers['priority']?.first),
      deadline:
          dueDate == null ? null : DateTime.tryParse(dueDate)?.toLocal(),
      at: DateTime.tryParse(
              (task['added_at'] ?? task['created_at'])?.toString() ?? '')
          ?.toLocal(),
      markers: markers,
    );
  }
}

/// A desk project: every desk task in one Todoist project.
class DeskProject {
  final String name;
  final DeskItem? status;
  final List<DeskItem> open;
  final List<DeskItem> answered;
  final List<DeskItem> instructions;

  const DeskProject({
    required this.name,
    this.status,
    this.open = const [],
    this.answered = const [],
    this.instructions = const [],
  });

  DeskState get state => _stateFrom(status?.markers['state']?.first);

  /// The status item's title: one line on where things stand.
  String get summary => status?.title ?? '';

  /// The status item's description: the goal, the rules, the log.
  String get brief => status?.body ?? '';

  /// Where its agent runs: 'beast', 'cloud' or 'both' (free text).
  String get where => status?.markers['where']?.first ?? '';

  DateTime? get updatedAt {
    final raw = status?.markers['updated']?.first;
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }
}

/// Everything on the desk at one moment.
class DeskBoard {
  final List<DeskProject> projects;

  const DeskBoard({this.projects = const []});

  bool get isEmpty => projects.isEmpty;

  factory DeskBoard.fromRemote(
    List<Map<String, dynamic>> tasks,
    Map<String, String> projectNames,
  ) {
    final byProject = <String, List<DeskItem>>{};
    for (final task in tasks) {
      final labels = task['labels'];
      if (labels is! List ||
          !labels.any((l) =>
              l is String && l.toLowerCase() == agentDeskToken.toLowerCase())) {
        continue;
      }
      final item = DeskItem.fromRemote(task, projectNames);
      if (item.id.isEmpty) continue;
      byProject.putIfAbsent(item.project, () => []).add(item);
    }
    final names = byProject.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return DeskBoard(projects: [
      for (final name in names)
        DeskProject(
          name: name,
          status: byProject[name]!
              .where((i) => i.isStatus)
              .cast<DeskItem?>()
              .firstWhere((_) => true, orElse: () => null),
          open: AgentDeskRanking.sort(
              byProject[name]!.where((i) => i.isOpen).toList()),
          answered: byProject[name]!.where((i) => i.isAnswered).toList(),
          instructions:
              byProject[name]!.where((i) => i.isInstruction).toList(),
        ),
    ]);
  }

  DeskProject? project(String name) {
    for (final p in projects) {
      if (p.name == name) return p;
    }
    return null;
  }

  DeskItem? item(String id) {
    for (final p in projects) {
      for (final i in [...p.open, ...p.answered]) {
        if (i.id == id) return i;
      }
    }
    return null;
  }

  /// Every open question, in [AgentDeskRanking] order.
  List<DeskItem> get open =>
      AgentDeskRanking.sort([for (final p in projects) ...p.open]);

  List<DeskItem> get answered => [for (final p in projects) ...p.answered];
}

/// Ordering of open questions: blocking first, then those with a deadline
/// (soonest first), then the oldest. `later` always sorts last.
class AgentDeskRanking {
  static int _rank(DeskPriority p) => switch (p) {
        DeskPriority.blocking => 0,
        DeskPriority.normal => 1,
        DeskPriority.later => 2,
      };

  static int compare(DeskItem a, DeskItem b) {
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

  static List<DeskItem> sort(List<DeskItem> items) =>
      [...items]..sort(compare);
}
