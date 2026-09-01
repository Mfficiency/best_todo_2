import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/project.dart';
import '../models/sync_log_entry.dart';
import '../models/task.dart';
import '../models/task_change_source.dart';
import '../models/todoist_sync_map_entry.dart';
import '../utils/label_utils.dart';
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
/// Fields with no Todoist equivalent — [Task.note], the project/Kanban
/// assignment — round-trip through a trailer appended to Todoist's
/// `description` field; see [TodoistMetadataCodec]. [Task.label] instead
/// maps onto Todoist's own native labels, which is the single source of
/// truth for it in both directions (see [_labelsFromRemote],
/// [_applyRemoteToLocal]) — the trailer only echoes it for human
/// readability in the Todoist app. A Kanban project's *name* is kept in
/// sync too, independent of its tasks — see [_syncProjectNames]. Recurring
/// tasks (parents and generated instances) are out of scope — Todoist's own
/// recurrence engine has no clean mapping to this app's generated-instance
/// model, so those stay local-only.
///
/// Wishlist items sync like any other task, but always land in a dedicated
/// **Wishlist** Todoist project (created on first push) regardless of any
/// local Kanban project — see [_targetProjectKey]. Likewise, any other
/// unprojected task with no due date (the Future tab bucket) lands in a
/// dedicated **Future** Todoist project. Pulling a task back out of either
/// project restores the matching local state (`isWish`, unassigned).
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

  /// Last-known-synced name for each real Kanban project in [_projectMap]
  /// (never the Wishlist/Future sentinel keys) — the baseline a project-name
  /// sync pass diffs both sides against, mirroring how [TodoistSyncMapEntry]
  /// fingerprints drive task sync. See [_syncProjectNames].
  Map<String, String> _projectNameMap = <String, String>{};

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

  /// The sync map entry linking [localUid] to a Todoist task, or null if this
  /// task has never been synced. Lets the UI surface the Todoist id and last
  /// synced date (see the task edit view's info icon) without exposing the
  /// sync map itself. Call [ensureLoaded] first — this reads whatever is
  /// already in memory.
  TodoistSyncMapEntry? entryForLocalUid(String localUid) {
    for (final e in _taskMap) {
      if (e.localUid == localUid) return e;
    }
    return null;
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
        final rawProjectNameMap = data['projectNameMap'];
        if (rawProjectNameMap is Map) {
          _projectNameMap = Map<String, String>.from(rawProjectNameMap);
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

  /// First-launch import (desktop "Import from Todoist" chooser, before any
  /// local task exists): pulls just today's (and overdue) tasks synchronously
  /// so the caller can open the home screen right away, then returns a
  /// closure that pulls everything else in the background — [syncing] stays
  /// true until that closure finishes, so the home page can show a "still
  /// importing" indicator. Pure pull, no push and no conflict resolution
  /// (there is nothing local yet to conflict with); [syncNow] takes over for
  /// every run after this one. Returns null when disabled, no token, or a
  /// sync is already running; throws on a network/API failure so the caller
  /// can show it before the home screen opens.
  Future<TodoistFirstImport?> startFirstLaunchImport() async {
    if (!Config.todoistSyncEnabled) return null;
    final token = Config.todoistApiToken.trim();
    if (token.isEmpty) return null;
    if (_syncInFlight) return null;
    _syncInFlight = true;
    syncing.value = true;
    await ensureLoaded();
    final stopwatch = Stopwatch()..start();
    final client = _newClient(token);
    List<Map<String, dynamic>> remoteTasks;
    List<Map<String, dynamic>> remoteProjects;
    try {
      remoteTasks = await client.fetchActiveTasks();
      remoteProjects = await client.fetchProjects();
    } catch (e) {
      _syncInFlight = false;
      syncing.value = false;
      await _record(SyncLogEntry(
        at: DateTime.now(),
        durationMs: stopwatch.elapsedMilliseconds,
        itemCount: 0,
        success: false,
        message: e is TodoistApiException ? e.message : e.toString(),
        trigger: 'first_launch_import',
      ));
      rethrow;
    } finally {
      client.close();
    }

    final remoteProjectNameToId = {
      for (final p in remoteProjects)
        (p['name'] as String? ?? '').toLowerCase(): _idOf(p['id']),
    };
    // Inbox is excluded: every task not otherwise assigned lands there, so
    // its name is never a useful "which conversation" signal.
    final remoteProjectIdToName = {
      for (final p in remoteProjects)
        if (p['is_inbox_project'] != true) _idOf(p['id']): p['name'] as String? ?? '',
    };
    // Same recognition as `_runSync` — see its comment.
    final todoistToLocalProject = <String, String>{
      for (final e in _projectMap.entries) e.value: e.key,
    };
    final wishlistId = remoteProjectNameToId['wishlist'];
    if (wishlistId != null) {
      todoistToLocalProject.putIfAbsent(
          wishlistId, () => _wishlistProjectKey);
    }
    final futureId = remoteProjectNameToId['future'];
    if (futureId != null) {
      todoistToLocalProject.putIfAbsent(futureId, () => _futureProjectKey);
    }

    final todayRemote = <Map<String, dynamic>>[];
    final restRemote = <Map<String, dynamic>>[];
    for (final t in remoteTasks) {
      (_isTodayOrOverdueRemote(t) ? todayRemote : restRemote).add(t);
    }

    final now = DateTime.now();
    List<Task> pull(List<Map<String, dynamic>> remote) {
      final pulled = <Task>[];
      for (final r in remote) {
        final id = _idOf(r['id']);
        if (_taskMap.any((e) => e.todoistId == id)) continue;
        final task = _taskFromRemote(r, todoistToLocalProject,
            remoteProjectNames: remoteProjectIdToName);
        pulled.add(task);
        _taskMap.add(TodoistSyncMapEntry(
          localUid: task.uid,
          todoistId: id,
          localProjectId: _targetProjectKey(task),
          todoistProjectId:
              r['project_id'] == null ? null : _idOf(r['project_id']),
          localFingerprint: _localFingerprint(task),
          remoteFingerprint:
              _remoteFingerprintForRemote(r, todoistToLocalProject),
          syncedAt: now,
        ));
      }
      return pulled;
    }

    final existing = await ItemRepository.instance.loadItems();
    final todayLocal = pull(todayRemote);
    existing.addAll(todayLocal);
    await ItemRepository.instance
        .saveItems(existing, source: TaskChangeSource.sync);
    await _persistState();

    Future<SyncLogEntry?> finish() async {
      try {
        final restLocal = pull(restRemote);
        if (restLocal.isNotEmpty) {
          final current = await ItemRepository.instance.loadItems();
          current.addAll(restLocal);
          await ItemRepository.instance
              .saveItems(current, source: TaskChangeSource.sync);
        }
        await _persistState();
        stopwatch.stop();
        final entry = SyncLogEntry(
          at: DateTime.now(),
          durationMs: stopwatch.elapsedMilliseconds,
          itemCount: todayLocal.length + restLocal.length,
          success: true,
          trigger: 'first_launch_import',
        );
        await _record(entry);
        return entry;
      } catch (e) {
        stopwatch.stop();
        final entry = SyncLogEntry(
          at: DateTime.now(),
          durationMs: stopwatch.elapsedMilliseconds,
          itemCount: todayLocal.length,
          success: false,
          message: e is TodoistApiException ? e.message : e.toString(),
          trigger: 'first_launch_import',
        );
        await _record(entry);
        return entry;
      } finally {
        _syncInFlight = false;
        syncing.value = false;
      }
    }

    return TodoistFirstImport(
      todayCount: todayLocal.length,
      finishInBackground: finish,
    );
  }

  /// "Today" here means the same bucket as the home page's Today tab: any
  /// due date on or before today, including overdue. An undated task belongs
  /// to the Future tab instead, so it is never "today".
  bool _isTodayOrOverdueRemote(Map<String, dynamic> remoteTask) {
    final due = remoteTask['due'];
    if (due is! Map) return false;
    final dateStr = due['date'] as String?;
    if (dateStr == null) return false;
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return false;
    final local = dateStr.contains('T') ? parsed.toLocal() : parsed;
    final today = DateTime.now();
    final dueDay = DateTime(local.year, local.month, local.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    return !dueDay.isAfter(todayDay);
  }

  // ---------------------------------------------------------------------
  // The sync algorithm.
  // ---------------------------------------------------------------------

  /// Wraps [_runSyncBody] with a rollback: [_taskMap], [_projectMap] and
  /// [_projectNameMap] are mutated in place as a run progresses, but only
  /// persisted (alongside the matching local task list) once every step has
  /// succeeded. Without this wrapper, a run that throws partway through
  /// (a single flaky/rate-limited API call is enough) leaves those maps
  /// holding entries — e.g. for a task just pulled in from Todoist — whose
  /// local-side counterpart was never actually saved. The next run would
  /// then read that as "the local task is gone", which it never was, and
  /// delete the still-wanted task back on Todoist. Rolling the maps back to
  /// their pre-run snapshot on any failure keeps a failed run from poisoning
  /// the one after it.
  Future<int> _runSync(TodoistApiClient client) async {
    final taskMapBackup = [
      for (final e in _taskMap) TodoistSyncMapEntry.fromJson(e.toJson()),
    ];
    final projectMapBackup = Map<String, String>.from(_projectMap);
    final projectNameMapBackup = Map<String, String>.from(_projectNameMap);
    try {
      return await _runSyncBody(client);
    } catch (_) {
      _taskMap = taskMapBackup;
      _projectMap = projectMapBackup;
      _projectNameMap = projectNameMapBackup;
      rethrow;
    }
  }

  Future<int> _runSyncBody(TodoistApiClient client) async {
    await ProjectService.instance.load();
    var projectsById = {
      for (final p in ProjectService.instance.list) p.id: p,
    };

    final allLocal = await ItemRepository.instance.loadItems();
    final deletedLocal = await ItemRepository.instance.loadDeletedItems();
    // The real bin (denials, or archived items sent on) counts too — a task
    // no longer active there is just as "gone" as one still in the archive.
    final binLocal = await ItemRepository.instance.loadBinItems();
    final deletedByUid = {
      for (final t in deletedLocal.followedBy(binLocal)) t.uid: t,
    };

    // Recurring tasks (parents and generated instances) are out of scope —
    // see the class doc. Wishlist items are in scope (routed to the
    // Wishlist project below). Food Diary entries never leave the app.
    final syncable = allLocal
        .where((t) =>
            !t.isRecurring &&
            t.recurrenceParentUid == null &&
            !t.isEatingHabit)
        .toList();
    final syncableByUid = {for (final t in syncable) t.uid: t};

    final remoteTasks = await client.fetchActiveTasks();
    final remoteById = {for (final r in remoteTasks) _idOf(r['id']): r};

    final remoteProjects = await client.fetchProjects();
    final remoteProjectNameToId = {
      for (final p in remoteProjects)
        (p['name'] as String? ?? '').toLowerCase(): _idOf(p['id']),
    };
    // Inbox is excluded: every task not otherwise assigned lands there, so
    // its name is never a useful "which conversation" signal.
    final remoteProjectIdToName = {
      for (final p in remoteProjects)
        if (p['is_inbox_project'] != true) _idOf(p['id']): p['name'] as String? ?? '',
    };
    final todoistToLocalProject = {
      for (final e in _projectMap.entries) e.value: e.key,
    };
    // Recognize a Todoist project literally named "Wishlist"/"Future" even
    // before this app has cached it in _projectMap (a fresh install, a reset
    // state file, or another device having pushed there first) — mirrors
    // the name-based reuse _todoistProjectFor does on push. putIfAbsent so
    // this never overrides a real Kanban project this app already mapped to
    // that same Todoist project id.
    final wishlistId = remoteProjectNameToId['wishlist'];
    if (wishlistId != null) {
      todoistToLocalProject.putIfAbsent(wishlistId, () => _wishlistProjectKey);
    }
    final futureId = remoteProjectNameToId['future'];
    if (futureId != null) {
      todoistToLocalProject.putIfAbsent(futureId, () => _futureProjectKey);
    }
    // Needed to move a task back to "no project": Inbox is a real project on
    // Todoist's side (with its own id), unlike this app's null projectId.
    final inboxProject = remoteProjects
        .cast<Map<String, dynamic>?>()
        .firstWhere((p) => p?['is_inbox_project'] == true, orElse: () => null);
    final inboxProjectId =
        inboxProject == null ? null : _idOf(inboxProject['id']);

    final entriesAtStart = List<TodoistSyncMapEntry>.of(_taskMap);
    final mapByUidStart = {for (final e in entriesAtStart) e.localUid: e};
    final handledTodoistIds = <String>{};
    final removedUids = <String>{};
    var changeCount = 0;
    final now = DateTime.now();

    // --- 0: Kanban project renames, either direction. ---------------------
    changeCount +=
        await _syncProjectNames(client, projectsById, remoteProjects);
    // A pulled rename above updates ProjectService in place; refresh the
    // lookup so the task steps below (project-name trailers, fingerprints)
    // see it rather than the pre-rename snapshot.
    projectsById = {for (final p in ProjectService.instance.list) p.id: p};

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
          task,
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
          localProjectId: _targetProjectKey(task),
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
          task,
          projectsById,
          remoteProjectNameToId,
        );
        // updateTask can't move a task between projects (see its doc) — an
        // actual reassignment (e.g. a task toggling in/out of the wishlist,
        // or an undated task now routed to the Future project) needs the
        // dedicated move endpoint. Moving "to no project" means Inbox, a
        // real project on Todoist's side.
        if (todoistProjectId != entry.todoistProjectId) {
          final destination = todoistProjectId ?? inboxProjectId;
          if (destination != null) {
            await client.moveTask(entry.todoistId, projectId: destination);
          }
        }
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
        entry.localProjectId = _targetProjectKey(task);
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
        entry.localProjectId = _targetProjectKey(task);
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
          localProjectId: _targetProjectKey(task),
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

      final newTask = _taskFromRemote(remoteTask, todoistToLocalProject,
          remoteProjectNames: remoteProjectIdToName);
      allLocal.add(newTask);
      _taskMap.add(TodoistSyncMapEntry(
        localUid: newTask.uid,
        todoistId: id,
        localProjectId: _targetProjectKey(newTask),
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

    await ItemRepository.instance
        .saveItems(allLocal, source: TaskChangeSource.sync);
    await _persistState();
    return changeCount;
  }

  /// Key [_projectMap] is cached under for wishlist tasks — never a real
  /// [Project.id] (those are uuids), so it can't collide with one.
  static const String _wishlistProjectKey = '__wishlist__';

  /// Same, for an unprojected task with no due date (the Future tab bucket).
  static const String _futureProjectKey = '__future__';

  /// Which Todoist project a task should live in: its own Kanban project if
  /// it has one, else the dedicated Wishlist/Future project, else none
  /// (Todoist Inbox). See the class doc.
  String? _targetProjectKey(Task task) {
    if (task.isWish) return _wishlistProjectKey;
    if (task.projectId != null) return task.projectId;
    if (Task.isFutureBucketDue(task.dueDate)) return _futureProjectKey;
    return null;
  }

  String _projectNameForKey(String key, Map<String, Project> projectsById) {
    if (key == _wishlistProjectKey) return 'Wishlist';
    if (key == _futureProjectKey) return 'Future';
    return projectsById[key]?.name ?? key;
  }

  Future<String?> _todoistProjectFor(
    TodoistApiClient client,
    Task task,
    Map<String, Project> projectsById,
    Map<String, String> remoteProjectNameToId,
  ) async {
    final key = _targetProjectKey(task);
    if (key == null) return null;
    final cached = _projectMap[key];
    if (cached != null) return cached;
    final name = _projectNameForKey(key, projectsById);
    final existingId = remoteProjectNameToId[name.toLowerCase()];
    if (existingId != null) {
      _projectMap[key] = existingId;
      if (key != _wishlistProjectKey && key != _futureProjectKey) {
        _projectNameMap[key] = name;
      }
      return existingId;
    }
    final created = await client.createProject(name);
    final id = _idOf(created['id']);
    _projectMap[key] = id;
    if (key != _wishlistProjectKey && key != _futureProjectKey) {
      _projectNameMap[key] = name;
    }
    remoteProjectNameToId[name.toLowerCase()] = id;
    return id;
  }

  /// Reconciles a real Kanban project's name against its Todoist counterpart
  /// (never the Wishlist/Future sentinel projects, which aren't user-renamed
  /// as such). Same conflict rule as tasks: **local wins** if both sides
  /// changed since the baseline in [_projectNameMap]. A project whose
  /// mapping predates this feature (no baseline yet) just adopts its current
  /// local name as the baseline, without pushing — it starts tracking from
  /// here rather than assuming either side "changed".
  Future<int> _syncProjectNames(
    TodoistApiClient client,
    Map<String, Project> projectsById,
    List<Map<String, dynamic>> remoteProjects,
  ) async {
    final remoteById = {for (final p in remoteProjects) _idOf(p['id']): p};
    var changeCount = 0;
    for (final mapEntry in _projectMap.entries) {
      final key = mapEntry.key;
      if (key == _wishlistProjectKey || key == _futureProjectKey) continue;
      final project = projectsById[key];
      if (project == null) continue; // local project deleted
      final remoteProject = remoteById[mapEntry.value];
      if (remoteProject == null) continue; // gone on Todoist; next push recreates it
      final remoteName = remoteProject['name'] as String? ?? '';
      final lastName = _projectNameMap[key];
      if (lastName == null) {
        _projectNameMap[key] = project.name;
        continue;
      }
      final localChanged = project.name != lastName;
      final remoteChanged = remoteName != lastName;
      if (localChanged) {
        if (project.name != remoteName) {
          await client.updateProject(mapEntry.value, name: project.name);
        }
        _projectNameMap[key] = project.name;
        changeCount++;
      } else if (remoteChanged) {
        await ProjectService.instance.upsert(project.copyWith(name: remoteName));
        _projectNameMap[key] = remoteName;
        changeCount++;
      }
    }
    return changeCount;
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
      final kanban = meta['kanbanStatus'] as String?;
      if (kanban != null) task.kanbanStatus = kanban;
    }
    // Todoist's native `labels` field is the source of truth, not the
    // `label` key in the description trailer (a snapshot from whenever this
    // app last pushed) — otherwise a label added/removed via Todoist's own
    // label UI, which never touches the description, is invisible here.
    task.label = _labelsFromRemote(remoteTask);
    final remoteProjectId = remoteTask['project_id'] == null
        ? null
        : _idOf(remoteTask['project_id']);
    if (remoteProjectId == null) {
      task.projectId = null;
      task.isWish = false;
    } else {
      final mapped = todoistToLocalProject[remoteProjectId];
      if (mapped == _wishlistProjectKey) {
        task.projectId = null;
        task.isWish = true;
      } else if (mapped == _futureProjectKey) {
        task.projectId = null;
        task.isWish = false;
      } else if (mapped != null) {
        task.projectId = mapped;
        task.isWish = false;
      }
      // An unmapped Todoist project (one this app didn't create) leaves the
      // task's existing project assignment and wishlist status alone.
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

  /// Builds a brand-new local task from a Todoist-side task this app has
  /// never seen before — first-launch import and step 4's "brand-new
  /// Todoist tasks" pull both funnel through here. Every such task is a
  /// task "created with the Todoist workflow", so it gets stamped with
  /// [waitingApprovalToken] and stays out of every list until a human
  /// approves or denies it in the Waiting for Approval page.
  ///
  /// [remoteProjectNames] maps every fetched Todoist project id to its name
  /// (built once per sync run) — used to stamp [Task.pendingSourceTitle]
  /// with the project the task came from, a proxy for "which conversation
  /// created this" the Waiting for Approval page groups by (see that
  /// field's doc). Passed in rather than looked up here since building it
  /// needs the same `remoteProjects` fetch every call site already has.
  Task _taskFromRemote(
    Map<String, dynamic> remoteTask,
    Map<String, String> todoistToLocalProject, {
    Map<String, String> remoteProjectNames = const {},
  }) {
    final parts = TodoistMetadataCodec.parse(
      remoteTask['description'] as String? ?? '',
    );
    final meta = parts.meta;
    final remoteProjectId = remoteTask['project_id'] == null
        ? null
        : _idOf(remoteTask['project_id']);
    final mapped =
        remoteProjectId == null ? null : todoistToLocalProject[remoteProjectId];
    final task = Task(
      title: remoteTask['content'] as String? ?? '',
      description: parts.visible,
      note: meta?['note'] as String? ?? '',
      label: addLabelToken(_labelsFromRemote(remoteTask), waitingApprovalToken),
      createdAt: _remoteCreatedAt(remoteTask) ?? DateTime.now(),
      pendingSourceTitle: remoteProjectId == null
          ? null
          : remoteProjectNames[remoteProjectId],
      projectId: (mapped == _wishlistProjectKey || mapped == _futureProjectKey)
          ? null
          : mapped,
      isWish: mapped == _wishlistProjectKey,
      kanbanStatus: meta?['kanbanStatus'] as String? ?? Task.kanbanTodo,
    );
    _applyRemoteDue(task, remoteTask['due']);
    return task;
  }

  /// The task's own creation time on Todoist's side, when the API includes
  /// one — the unified API v1 (Sync-API-shaped) field is `added_at`; the
  /// older REST v2 spelling `created_at` is checked too in case Todoist ever
  /// serves either. Null (falling back to "now", the pull time) if neither
  /// parses.
  DateTime? _remoteCreatedAt(Map<String, dynamic> remoteTask) {
    final raw =
        remoteTask['added_at'] as String? ?? remoteTask['created_at'] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
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

  /// Normalizes a label token string (order/case/whitespace don't matter) so
  /// it's comparable across BestToDo's free-text field and Todoist's native
  /// `labels` array regardless of which order either side lists them in.
  String _labelKey(String label) {
    final tokens = splitLabelTokens(label)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return tokens.map((t) => t.toLowerCase()).join(',');
  }

  /// Everything pushed to Todoist for [task] — drives the push decision.
  String _localFingerprint(Task task) => [
        task.title,
        task.description.trim(),
        task.note.trim(),
        _labelKey(task.label),
        _targetProjectKey(task) ?? '',
        task.kanbanStatus,
        _dueKeyFromLocal(task),
      ].join(' ');

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
      _labelKey(_labelsFromRemote(remoteTask)),
    ].join(' ');
  }

  String _remoteFingerprintForLocal(Task task, String dueKey) => [
        task.title,
        task.description.trim(),
        dueKey,
        _targetProjectKey(task) ?? '',
        _labelKey(task.label),
      ].join(' ');

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
    final labels = splitLabelTokens(task.label);
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
          'projectNameMap': _projectNameMap,
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

/// Result of [TodoistSyncService.startFirstLaunchImport]: today's tasks are
/// already saved by the time this is returned, so the caller can open the
/// home screen immediately; [finishInBackground] pulls everything else and
/// should be fired and forgotten (or awaited in tests).
class TodoistFirstImport {
  final int todayCount;
  final Future<SyncLogEntry?> Function() finishInBackground;

  TodoistFirstImport({
    required this.todayCount,
    required this.finishInBackground,
  });
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
