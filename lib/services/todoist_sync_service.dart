import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/project.dart';
import '../models/sync_log_entry.dart';
import '../models/task.dart';
import '../models/todoist_sync_map_entry.dart';
import 'item_repository.dart';
import 'log_service.dart';
import 'project_service.dart';
import 'safe_file.dart';
import 'todoist_api_client.dart';
import 'todoist_metadata_codec.dart';

/// Two-way sync between the local task list and a Todoist account.
///
/// Mirrors [SyncService]'s shape (lifecycle-triggered background run, manual
/// "Sync now", a small persisted run log) but writes both directions:
///
///  * **Push**: a new/edited/completed/deleted local task creates, updates,
///    closes or deletes its Todoist counterpart.
///  * **Pull**: a task created, edited or completed on the Todoist side is
///    reflected locally, including tasks that were never touched by
///    BestToDo before.
///
/// Todoist's REST API has no per-task "updated at" and no endpoint for
/// completed tasks, so this can't diff against a live timestamp. Instead
/// [TodoistSyncMapEntry] stores a fingerprint of each side's fields as they
/// stood after the last successful sync; a run recomputes both current
/// fingerprints and compares them against the stored ones. **Conflict rule:
/// local wins** — if a task changed on both sides between runs, the local
/// edit is pushed and the Todoist-side edit is overwritten. A task's
/// disappearance from Todoist's active-task list (the only signal the API
/// gives for "done") is treated as a completion, never a delete, so no data
/// is ever lost on that ambiguity.
///
/// Fields with no Todoist equivalent — [Task.note], [Task.label], the
/// project/Kanban assignment — round-trip through a trailer appended to
/// Todoist's `description` field; see [TodoistMetadataCodec]. Wishlist items
/// and recurring tasks (parents and generated instances) are out of scope —
/// Todoist's own recurrence engine has no clean mapping to this app's
/// generated-instance model, so those stay local-only.
class TodoistSyncService {
  TodoistSyncService._();
  static TodoistSyncService instance = TodoistSyncService._();

  static const _stateFileName = 'todoist_sync_state.json';
  static const _logFileName = 'todoist_sync_log.json';
  static const _maxLogEntries = 100;

  final ValueNotifier<List<SyncLogEntry>> entries =
      ValueNotifier<List<SyncLogEntry>>(<SyncLogEntry>[]);
  final ValueNotifier<bool> hasUnseenError = ValueNotifier<bool>(false);
  final ValueNotifier<bool> syncing = ValueNotifier<bool>(false);

  List<TodoistSyncMapEntry> _taskMap = <TodoistSyncMapEntry>[];
  Map<String, String> _projectMap = <String, String>{};

  Future<void>? _loadFuture;
  bool _syncInFlight = false;
  bool _syncedThisBackground = false;

  /// Lets tests substitute a fake [TodoistApiClient] instead of hitting the
  /// network.
  @visibleForTesting
  TodoistApiClient Function(String token)? apiClientFactory;

  /// The sync started by the last quit-shaped lifecycle change; tests await
  /// it, production fires and forgets.
  @visibleForTesting
  Future<SyncLogEntry?>? pendingQuitSync;

  TodoistApiClient _newClient(String token) =>
      (apiClientFactory ?? (t) => TodoistApiClient(apiToken: t))(token);

  Future<void> ensureLoaded() {
    _loadFuture ??= _load();
    return _loadFuture!;
  }

  Future<File> _stateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_stateFileName');
  }

  Future<File> _logFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_logFileName');
  }

  Future<void> _load() async {
    try {
      final stateFile = await _stateFile();
      final data = await SafeFile.readWithRecovery(
          stateFile, (contents) => jsonDecode(contents));
      if (data is Map) {
        final rawEntries = data['taskEntries'];
        if (rawEntries is List) {
          _taskMap = [
            for (final e in rawEntries)
              if (e is Map)
                TodoistSyncMapEntry.fromJson(Map<String, dynamic>.from(e)),
          ];
        }
        final rawProjectMap = data['projectMap'];
        if (rawProjectMap is Map) {
          _projectMap = Map<String, String>.from(rawProjectMap);
        }
      }
    } catch (_) {
      // No documents dir (web/tests) or unreadable state: start empty.
    }
    try {
      final logFile = await _logFile();
      final data = await SafeFile.readWithRecovery(
          logFile, (contents) => jsonDecode(contents));
      if (data is Map) {
        final rawEntries = data['entries'];
        if (rawEntries is List) {
          entries.value = [
            for (final e in rawEntries)
              if (e is Map) SyncLogEntry.fromJson(Map<String, dynamic>.from(e)),
          ];
        }
        hasUnseenError.value = data['unseen_error'] as bool? ?? false;
      }
    } catch (_) {}
  }

  /// Lifecycle hook, called from the root widget's observer alongside
  /// [SyncService]'s. Same once-per-background latch.
  void onLifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncedThisBackground = false;
      return;
    }
    final quitting = state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (!quitting || _syncedThisBackground) return;
    _syncedThisBackground = true;
    if (!Config.todoistSyncEnabled || Config.todoistApiToken.trim().isEmpty) {
      return;
    }
    pendingQuitSync = syncNow(trigger: 'app quit');
  }

  /// A cheap authenticated call to confirm a token works before it's saved.
  /// Throws [TodoistApiException] (or a network error) on failure.
  Future<void> testConnection(String token) async {
    final client = _newClient(token);
    try {
      await client.fetchProjects();
    } finally {
      client.close();
    }
  }

  /// Runs one sync pass. Returns the recorded entry, or null when sync is
  /// off, no token is set, or a sync is already running. Never throws.
  Future<SyncLogEntry?> syncNow({String trigger = 'manual'}) async {
    if (!Config.todoistSyncEnabled) return null;
    final token = Config.todoistApiToken.trim();
    if (token.isEmpty) return null;
    if (_syncInFlight) return null;
    _syncInFlight = true;
    syncing.value = true;
    try {
      await ensureLoaded();
      final stopwatch = Stopwatch()..start();
      SyncLogEntry entry;
      try {
        final client = _newClient(token);
        int changeCount;
        try {
          changeCount = await _runSync(client);
        } finally {
          client.close();
        }
        stopwatch.stop();
        entry = SyncLogEntry(
          at: DateTime.now(),
          durationMs: stopwatch.elapsedMilliseconds,
          itemCount: changeCount,
          success: true,
          trigger: trigger,
        );
      } catch (e) {
        stopwatch.stop();
        entry = SyncLogEntry(
          at: DateTime.now(),
          durationMs: stopwatch.elapsedMilliseconds,
          itemCount: 0,
          success: false,
          message: e is TodoistApiException ? e.message : e.toString(),
          trigger: trigger,
        );
      }
      await _record(entry);
      return entry;
    } finally {
      _syncInFlight = false;
      syncing.value = false;
    }
  }

  // ---------------------------------------------------------------------
  // The sync algorithm.
  // ---------------------------------------------------------------------

  Future<int> _runSync(TodoistApiClient client) async {
    await ProjectService.instance.load();
    final projectsById = {
      for (final p in ProjectService.instance.list) p.id: p,
    };

    final allLocal = await ItemRepository.instance.loadItems();
    final deletedLocal = await ItemRepository.instance.loadDeletedItems();
    final deletedByUid = {for (final t in deletedLocal) t.uid: t};

    // Wishlist items and recurring tasks (parents and generated instances)
    // are out of scope — see the class doc.
    final syncable = allLocal
        .where((t) =>
            !t.isWish && !t.isRecurring && t.recurrenceParentUid == null)
        .toList();
    final syncableByUid = {for (final t in syncable) t.uid: t};

    final remoteTasks = await client.fetchActiveTasks();
    final remoteById = {for (final r in remoteTasks) _idOf(r['id']): r};

    final remoteProjects = await client.fetchProjects();
    final remoteProjectNameToId = {
      for (final p in remoteProjects)
        (p['name'] as String? ?? '').toLowerCase(): _idOf(p['id']),
    };
    final todoistToLocalProject = {
      for (final e in _projectMap.entries) e.value: e.key,
    };

    final entriesAtStart = List<TodoistSyncMapEntry>.of(_taskMap);
    final mapByUidStart = {for (final e in entriesAtStart) e.localUid: e};
    final handledTodoistIds = <String>{};
    final removedUids = <String>{};
    var changeCount = 0;
    final now = DateTime.now();

    // --- 1: local task no longer active (completed-and-rolled-over, or
    // deleted) -> reconcile on the Todoist side. --------------------------
    for (final entry in entriesAtStart) {
      if (syncableByUid.containsKey(entry.localUid)) continue;
      final terminal = deletedByUid[entry.localUid];
      final wasCompletion = terminal?.isDone ?? false;
      try {
        if (wasCompletion) {
          await client.closeTask(entry.todoistId);
        } else {
          await client.deleteTask(entry.todoistId);
        }
      } on TodoistApiException catch (e) {
        // 404 = already gone on the Todoist side too; anything else is a
        // real failure, so leave the mapping to retry next run.
        if (e.statusCode != 404) continue;
      }
      handledTodoistIds.add(entry.todoistId);
      removedUids.add(entry.localUid);
      changeCount++;
    }

    // --- 2: local task still active but marked done -> close on Todoist. -
    for (final task in syncable) {
      if (!task.isDone) continue;
      final entry = mapByUidStart[task.uid];
      if (entry == null) continue; // never synced while open; nothing to do
      try {
        await client.closeTask(entry.todoistId);
      } on TodoistApiException catch (e) {
        if (e.statusCode != 404) continue;
      }
      handledTodoistIds.add(entry.todoistId);
      removedUids.add(task.uid);
      changeCount++;
    }

    // --- 3: open local tasks -> create, or push/pull an edit. ------------
    for (final task in syncable) {
      if (task.isDone) continue;
      final entry = mapByUidStart[task.uid];
      final localFp = _localFingerprint(task);

      if (entry == null) {
        final todoistProjectId = await _todoistProjectFor(
          client,
          task.projectId,
          projectsById,
          remoteProjectNameToId,
        );
        final payload = _buildRemotePayload(task, projectsById);
        final created = await client.createTask(
          content: task.title,
          description: payload.description,
          projectId: todoistProjectId,
          dueDate: payload.dueDate,
          dueDatetime: payload.dueDatetime,
          labels: payload.labels,
        );
        final id = _idOf(created['id']);
        _taskMap.add(TodoistSyncMapEntry(
          localUid: task.uid,
          todoistId: id,
          localProjectId: task.projectId,
          todoistProjectId: todoistProjectId,
          localFingerprint: localFp,
          remoteFingerprint: _remoteFingerprintForLocal(task, payload.dueKey),
          syncedAt: now,
        ));
        handledTodoistIds.add(id);
        changeCount++;
        continue;
      }

      final remoteTask = remoteById[entry.todoistId];
      if (remoteTask == null) {
        // Vanished from Todoist's active list without going through step 1
        // (it was still open locally) — step 5 below reflects that as a
        // completion. Nothing to push.
        continue;
      }
      handledTodoistIds.add(entry.todoistId);

      final remoteFp = _remoteFingerprintForRemote(
        remoteTask,
        todoistToLocalProject,
      );
      final localChanged = localFp != entry.localFingerprint;
      final remoteChanged = remoteFp != entry.remoteFingerprint;

      if (localChanged) {
        final todoistProjectId = await _todoistProjectFor(
          client,
          task.projectId,
          projectsById,
          remoteProjectNameToId,
        );
        final payload = _buildRemotePayload(task, projectsById);
        await client.updateTask(
          entry.todoistId,
          content: task.title,
          description: payload.description,
          dueDate: payload.dueDate,
          dueDatetime: payload.dueDatetime,
          clearDue: payload.dueDate == null && payload.dueDatetime == null,
          labels: payload.labels,
        );
        entry.todoistProjectId = todoistProjectId;
        entry.localProjectId = task.projectId;
        entry.localFingerprint = localFp;
        entry.remoteFingerprint = _remoteFingerprintForLocal(
          task,
          payload.dueKey,
        );
        entry.syncedAt = now;
        changeCount++;
      } else if (remoteChanged) {
        _applyRemoteToLocal(task, remoteTask, todoistToLocalProject);
        entry.localFingerprint = _localFingerprint(task);
        entry.remoteFingerprint = remoteFp;
        entry.localProjectId = task.projectId;
        entry.syncedAt = now;
        changeCount++;
      }
    }

    // --- 4: brand-new Todoist tasks -> pull into a local task. ------------
    for (final remoteTask in remoteTasks) {
      final id = _idOf(remoteTask['id']);
      if (handledTodoistIds.contains(id)) continue;
      if (mapByUidStart.values.any((e) => e.todoistId == id)) continue;

      final parts = TodoistMetadataCodec.parse(
        remoteTask['description'] as String? ?? '',
      );
      final embeddedUid = parts.meta?['uid'] as String?;
      if (embeddedUid != null &&
          syncableByUid.containsKey(embeddedUid) &&
          !mapByUidStart.containsKey(embeddedUid)) {
        // The local task exists but the mapping was lost (e.g. state file
        // reset) — relink instead of creating a duplicate.
        final task = syncableByUid[embeddedUid]!;
        _applyRemoteToLocal(task, remoteTask, todoistToLocalProject);
        _taskMap.add(TodoistSyncMapEntry(
          localUid: embeddedUid,
          todoistId: id,
          localProjectId: task.projectId,
          todoistProjectId: remoteTask['project_id'] == null
              ? null
              : _idOf(remoteTask['project_id']),
          localFingerprint: _localFingerprint(task),
          remoteFingerprint: _remoteFingerprintForRemote(
            remoteTask,
            todoistToLocalProject,
          ),
          syncedAt: now,
        ));
        handledTodoistIds.add(id);
        changeCount++;
        continue;
      }

      final newTask = _taskFromRemote(remoteTask, todoistToLocalProject);
      allLocal.add(newTask);
      _taskMap.add(TodoistSyncMapEntry(
        localUid: newTask.uid,
        todoistId: id,
        localProjectId: newTask.projectId,
        todoistProjectId: remoteTask['project_id'] == null
            ? null
            : _idOf(remoteTask['project_id']),
        localFingerprint: _localFingerprint(newTask),
        remoteFingerprint: _remoteFingerprintForRemote(
          remoteTask,
          todoistToLocalProject,
        ),
        syncedAt: now,
      ));
      handledTodoistIds.add(id);
      changeCount++;
    }

    // --- 5: Todoist-side completions of tasks still open locally. --------
    // A task's disappearance from the active list is Todoist's only
    // signal here — it can mean completed *or* deleted, and treating it as
    // "done" rather than "gone" never loses data on that ambiguity.
    for (final entry in entriesAtStart) {
      if (handledTodoistIds.contains(entry.todoistId)) continue;
      if (removedUids.contains(entry.localUid)) continue;
      if (remoteById.containsKey(entry.todoistId)) continue;
      final task = syncableByUid[entry.localUid];
      if (task == null) continue;
      task.isDone = true;
      task.completedAt ??= now;
      removedUids.add(entry.localUid);
      changeCount++;
    }

    _taskMap.removeWhere((e) => removedUids.contains(e.localUid));

    await ItemRepository.instance.saveItems(allLocal);
    await _persistState();
    return changeCount;
  }

  Future<String?> _todoistProjectFor(
    TodoistApiClient client,
    String? localProjectId,
    Map<String, Project> projectsById,
    Map<String, String> remoteProjectNameToId,
  ) async {
    if (localProjectId == null) return null;
    final cached = _projectMap[localProjectId];
    if (cached != null) return cached;
    final name = projectsById[localProjectId]?.name ?? localProjectId;
    final existingId = remoteProjectNameToId[name.toLowerCase()];
    if (existingId != null) {
      _projectMap[localProjectId] = existingId;
      return existingId;
    }
    final created = await client.createProject(name);
    final id = _idOf(created['id']);
    _projectMap[localProjectId] = id;
    remoteProjectNameToId[name.toLowerCase()] = id;
    return id;
  }

  void _applyRemoteToLocal(
    Task task,
    Map<String, dynamic> remoteTask,
    Map<String, String> todoistToLocalProject,
  ) {
    task.title = remoteTask['content'] as String? ?? task.title;
    final parts = TodoistMetadataCodec.parse(
      remoteTask['description'] as String? ?? '',
    );
    task.description = parts.visible;
    final meta = parts.meta;
    if (meta != null) {
      task.note = meta['note'] as String? ?? '';
      task.label = meta['label'] as String? ?? task.label;
      final kanban = meta['kanbanStatus'] as String?;
      if (kanban != null) task.kanbanStatus = kanban;
    } else {
      task.label = _labelsFromRemote(remoteTask);
    }
    final remoteProjectId = remoteTask['project_id'] == null
        ? null
        : _idOf(remoteTask['project_id']);
    if (remoteProjectId == null) {
      task.projectId = null;
    } else {
      final mapped = todoistToLocalProject[remoteProjectId];
      // An unmapped Todoist project (one this app didn't create) leaves the
      // task's existing project assignment alone.
      if (mapped != null) task.projectId = mapped;
    }
    _applyRemoteDue(task, remoteTask['due']);
  }

  void _applyRemoteDue(Task task, dynamic due) {
    if (due is! Map) {
      task.hasExplicitTime = false;
      task.dueDate = null;
      return;
    }
    // Unlike REST v2's separate `date`/`datetime` keys, v1's `due.date` is a
    // single field holding either a bare date ("2026-09-01") or a full
    // datetime ("2026-09-01T14:30:00[Z]") — a "T" tells them apart.
    final dateStr = due['date'] as String?;
    if (dateStr != null && dateStr.contains('T')) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) {
        task.hasExplicitTime = true;
        task.dueDate = parsed.toLocal();
        return;
      }
    }
    final parsed = dateStr != null ? DateTime.tryParse(dateStr) : null;
    if (parsed != null) {
      task.hasExplicitTime = false;
      // Date-only tasks default to 18:00, matching new tasks created in-app
      // (see `applyDefaultDeadlineTimes`).
      task.dueDate = DateTime(parsed.year, parsed.month, parsed.day, 18, 0);
    } else {
      task.hasExplicitTime = false;
      task.dueDate = null;
    }
  }

  Task _taskFromRemote(
    Map<String, dynamic> remoteTask,
    Map<String, String> todoistToLocalProject,
  ) {
    final parts = TodoistMetadataCodec.parse(
      remoteTask['description'] as String? ?? '',
    );
    final meta = parts.meta;
    final remoteProjectId = remoteTask['project_id'] == null
        ? null
        : _idOf(remoteTask['project_id']);
    final task = Task(
      title: remoteTask['content'] as String? ?? '',
      description: parts.visible,
      note: meta?['note'] as String? ?? '',
      label: meta?['label'] as String? ?? _labelsFromRemote(remoteTask),
      createdAt: DateTime.now(),
      projectId:
          remoteProjectId == null ? null : todoistToLocalProject[remoteProjectId],
      kanbanStatus: meta?['kanbanStatus'] as String? ?? Task.kanbanTodo,
    );
    _applyRemoteDue(task, remoteTask['due']);
    return task;
  }

  String _labelsFromRemote(Map<String, dynamic> remoteTask) {
    final labels = remoteTask['labels'];
    if (labels is List) return labels.whereType<String>().join(', ');
    return '';
  }

  // ---------------------------------------------------------------------
  // Fingerprints (see the class doc for why there's no real timestamp diff).
  // ---------------------------------------------------------------------

  String _dueKeyFromLocal(Task task) {
    final due = task.endAt;
    if (due == null) return '';
    return task.hasExplicitTime
        ? due.toUtc().toIso8601String().substring(0, 16)
        : _isoDate(due);
  }

  String _dueKeyFromRemote(dynamic due) {
    if (due is! Map) return '';
    final dateStr = due['date'] as String?;
    if (dateStr != null && dateStr.contains('T')) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) {
        return parsed.toUtc().toIso8601String().substring(0, 16);
      }
    }
    return dateStr ?? '';
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Everything pushed to Todoist for [task] — drives the push decision.
  String _localFingerprint(Task task) => [
        task.title,
        task.description.trim(),
        task.note.trim(),
        task.label.trim(),
        task.projectId ?? '',
        task.kanbanStatus,
        _dueKeyFromLocal(task),
      ].join(' ');

  /// Only the fields a Todoist-side edit can actually change — drives the
  /// pull decision. Computed identically from either side so the two are
  /// comparable.
  String _remoteFingerprintForRemote(
    Map<String, dynamic> remoteTask,
    Map<String, String> todoistToLocalProject,
  ) {
    final parts = TodoistMetadataCodec.parse(
      remoteTask['description'] as String? ?? '',
    );
    final remoteProjectId = remoteTask['project_id'] == null
        ? null
        : _idOf(remoteTask['project_id']);
    final projectId =
        remoteProjectId == null ? null : todoistToLocalProject[remoteProjectId];
    return [
      remoteTask['content'] as String? ?? '',
      parts.visible,
      _dueKeyFromRemote(remoteTask['due']),
      projectId ?? '',
    ].join(' ');
  }

  String _remoteFingerprintForLocal(Task task, String dueKey) => [
        task.title,
        task.description.trim(),
        dueKey,
        task.projectId ?? '',
      ].join(' ');

  _RemotePayload _buildRemotePayload(Task task, Map<String, Project> projectsById) {
    final project = task.projectId != null ? projectsById[task.projectId] : null;
    final meta = <String, dynamic>{
      'uid': task.uid,
      if (task.note.trim().isNotEmpty) 'note': task.note,
      if (task.label.trim().isNotEmpty) 'label': task.label,
      if (task.projectId != null) 'projectId': task.projectId,
      if (project != null) 'projectName': project.name,
      'kanbanStatus': task.kanbanStatus,
      'kanbanStageLabel': ProjectService.stageLabel(task.kanbanStatus),
      if (task.createdAt != null) 'createdAt': task.createdAt!.toIso8601String(),
    };
    final description =
        TodoistMetadataCodec.build(visible: task.description, meta: meta);
    String? dueDate;
    String? dueDatetime;
    final due = task.endAt;
    if (due != null) {
      if (task.hasExplicitTime) {
        dueDatetime = due.toUtc().toIso8601String();
      } else {
        dueDate = _isoDate(due);
      }
    }
    final labels = task.label.trim().isEmpty
        ? const <String>[]
        : task.label
            .split(RegExp(r'[,\s]+'))
            .where((s) => s.isNotEmpty)
            .toList();
    return _RemotePayload(
      description: description,
      dueDate: dueDate,
      dueDatetime: dueDatetime,
      dueKey: _dueKeyFromLocal(task),
      labels: labels,
    );
  }

  String _idOf(dynamic v) => v?.toString() ?? '';

  Future<void> _record(SyncLogEntry entry) async {
    final updated = <SyncLogEntry>[entry, ...entries.value];
    if (updated.length > _maxLogEntries) {
      updated.removeRange(_maxLogEntries, updated.length);
    }
    entries.value = updated;
    hasUnseenError.value = !entry.success;
    LogService.add(
      'Todoist sync',
      entry.success
          ? 'Synced ${entry.itemCount} change(s) in ${entry.durationMs} ms '
              '(${entry.trigger})'
          : 'Sync failed (${entry.trigger}): ${entry.message}',
    );
    try {
      final file = await _logFile();
      await SafeFile.writeString(
        file,
        jsonEncode(<String, dynamic>{
          'unseen_error': hasUnseenError.value,
          'entries': [for (final e in entries.value) e.toJson()],
        }),
      );
    } catch (_) {}
  }

  /// Called when the App Logs page opens: the error has been seen, so the
  /// drawer dot goes away (the failed entry itself stays in the history).
  Future<void> markErrorSeen() async {
    if (!hasUnseenError.value) return;
    hasUnseenError.value = false;
    try {
      final file = await _logFile();
      await SafeFile.writeString(
        file,
        jsonEncode(<String, dynamic>{
          'unseen_error': false,
          'entries': [for (final e in entries.value) e.toJson()],
        }),
      );
    } catch (_) {}
  }

  Future<void> _persistState() async {
    try {
      final file = await _stateFile();
      await SafeFile.writeString(
        file,
        jsonEncode(<String, dynamic>{
          'taskEntries': [for (final e in _taskMap) e.toJson()],
          'projectMap': _projectMap,
        }),
      );
    } catch (_) {
      // No documents dir (web/tests): state stays in-memory only.
    }
  }

  /// Fresh instance for tests (mirrors `SyncService.resetForTest`).
  static void resetForTest() {
    instance = TodoistSyncService._();
  }
}

class _RemotePayload {
  final String description;
  final String? dueDate;
  final String? dueDatetime;
  final String dueKey;
  final List<String> labels;

  _RemotePayload({
    required this.description,
    required this.dueDate,
    required this.dueDatetime,
    required this.dueKey,
    required this.labels,
  });
}
