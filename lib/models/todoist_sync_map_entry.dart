/// One task's link between BestToDo and Todoist, persisted in
/// `todoist_sync_map.json` by `TodoistSyncService`.
///
/// The two fingerprints are what make the sync two-way without a real
/// "updated at" field from Todoist's REST API: [localFingerprint] is a
/// snapshot of the local task fields at the moment they were last pushed (or
/// pulled) into agreement with Todoist, and [remoteFingerprint] is the same
/// snapshot from Todoist's side. A sync run recomputes both current
/// fingerprints and diffs them against the stored ones to tell "changed
/// locally", "changed on Todoist" and "changed on both" apart — see
/// `TodoistSyncService` for the resolution rules.
class TodoistSyncMapEntry {
  /// [Task.uid] on the BestToDo side.
  String localUid;

  /// Todoist task id.
  String todoistId;

  /// Local project id the Todoist project was mapped from/to, if any.
  String? localProjectId;

  /// Todoist project id the task was last pushed into (null = Todoist Inbox).
  String? todoistProjectId;

  String localFingerprint;
  String remoteFingerprint;
  DateTime syncedAt;

  TodoistSyncMapEntry({
    required this.localUid,
    required this.todoistId,
    this.localProjectId,
    this.todoistProjectId,
    required this.localFingerprint,
    required this.remoteFingerprint,
    required this.syncedAt,
  });

  factory TodoistSyncMapEntry.fromJson(Map<String, dynamic> json) =>
      TodoistSyncMapEntry(
        localUid: json['localUid'] as String? ?? '',
        todoistId: json['todoistId'] as String? ?? '',
        localProjectId: json['localProjectId'] as String?,
        todoistProjectId: json['todoistProjectId'] as String?,
        localFingerprint: json['localFingerprint'] as String? ?? '',
        remoteFingerprint: json['remoteFingerprint'] as String? ?? '',
        syncedAt: DateTime.tryParse(json['syncedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'localUid': localUid,
        'todoistId': todoistId,
        if (localProjectId != null) 'localProjectId': localProjectId,
        if (todoistProjectId != null) 'todoistProjectId': todoistProjectId,
        'localFingerprint': localFingerprint,
        'remoteFingerprint': remoteFingerprint,
        'syncedAt': syncedAt.toIso8601String(),
      };
}
