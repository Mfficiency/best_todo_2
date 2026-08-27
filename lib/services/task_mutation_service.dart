import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/task.dart';
import '../models/task_change_source.dart';
import 'item_repository.dart';

/// Snapshot of all three task lists — active, Archived Items, and the real
/// Deleted bin (see SPEC §4.2g) — as returned by [TaskMutationService.undo]
/// and [TaskMutationService.redo] for the caller to apply to its in-memory
/// state.
class TaskUndoState {
  final List<Task> active;
  final List<Task> deleted;
  final List<Task> bin;
  final String description;

  const TaskUndoState({
    required this.active,
    required this.deleted,
    required this.bin,
    required this.description,
  });

  TaskUndoState copyWith({String? description}) => TaskUndoState(
        active: active,
        deleted: deleted,
        bin: bin,
        description: description ?? this.description,
      );
}

typedef _Snapshot = Map<String, Map<String, dynamic>>;

class _UndoEntry {
  final _Snapshot beforeActive;
  final _Snapshot afterActive;
  final _Snapshot beforeDeleted;
  final _Snapshot afterDeleted;
  final _Snapshot beforeBin;
  final _Snapshot afterBin;
  final String description;
  final DateTime at;

  const _UndoEntry({
    required this.beforeActive,
    required this.afterActive,
    required this.beforeDeleted,
    required this.afterDeleted,
    required this.beforeBin,
    required this.afterBin,
    required this.description,
    required this.at,
  });
}

/// The single choke point every task-list mutation in the app should end up
/// going through: it turns the before/after snapshots each save already
/// produces (the same shape [ItemEventJournal] diffs into history) into one
/// bounded, app-wide Undo/Redo stack spanning all three lists a task can
/// live in — the active list, Archived Items, and the real Deleted bin (see
/// SPEC §4.2g).
///
/// Callers don't hand this class a mutation to run — the app already
/// mutates [Task] lists in place and persists them through [ItemRepository].
/// Instead they call `note*Change` right alongside that existing save,
/// *after* mutating and *before* awaiting the persist call. All three notes
/// are coalesced into a single microtask flush, so moving a task from the
/// archive to the bin (which touches both lists back to back, synchronously)
/// becomes exactly one undo entry — see "bulk changes undo as one action".
///
/// [undo]/[redo] persist directly through [ItemRepository] (tagged
/// [TaskChangeSource.undo]/[TaskChangeSource.redo]) rather than through
/// another note/flush round, so applying them is never itself undoable.
class TaskMutationService {
  TaskMutationService._();

  static final TaskMutationService instance = TaskMutationService._();

  /// Bounded so a long session's undo stack can't grow without limit; a
  /// todo app's edit history has no reason to keep more than this.
  static const int maxEntries = 30;

  final ItemRepository _repository = ItemRepository.instance;

  final List<_UndoEntry> _undoStack = <_UndoEntry>[];
  final List<_UndoEntry> _redoStack = <_UndoEntry>[];

  /// Bumped whenever the stacks change, so UI (the Undo/Redo buttons) can
  /// listen without this service depending on Flutter's widget layer.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  _Snapshot? _lastActive;
  _Snapshot? _lastDeleted;
  _Snapshot? _lastBin;

  List<Task>? _pendingActive;
  List<Task>? _pendingDeleted;
  List<Task>? _pendingBin;
  bool _flushScheduled = false;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  String? get undoDescription =>
      _undoStack.isEmpty ? null : _undoStack.last.description;
  String? get redoDescription =>
      _redoStack.isEmpty ? null : _redoStack.last.description;

  static _Snapshot _snapshot(List<Task> tasks) =>
      {for (final t in tasks) t.uid: t.toJson()};

  /// Establishes the known-good starting point — call once, right after the
  /// three task lists are loaded from disk and before any seeding/migration
  /// runs, so that first save doesn't get diffed against nothing and read
  /// as "every task was just created".
  void noteBaseline({
    required List<Task> active,
    required List<Task> deleted,
    required List<Task> bin,
  }) {
    _lastActive = _snapshot(active);
    _lastDeleted = _snapshot(deleted);
    _lastBin = _snapshot(bin);
  }

  /// Call after mutating [active] in place, alongside persisting it.
  void noteActiveChange(List<Task> active) {
    _pendingActive = List<Task>.of(active);
    _scheduleFlush();
  }

  /// Call after mutating [deleted] (Archived Items) in place, alongside
  /// persisting it.
  void noteDeletedChange(List<Task> deleted) {
    _pendingDeleted = List<Task>.of(deleted);
    _scheduleFlush();
  }

  /// Call after mutating [bin] (the real Deleted bin) in place, alongside
  /// persisting it.
  void noteBinChange(List<Task> bin) {
    _pendingBin = List<Task>.of(bin);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _flushScheduled = false;
    final pendingActive = _pendingActive;
    final pendingDeleted = _pendingDeleted;
    final pendingBin = _pendingBin;
    _pendingActive = null;
    _pendingDeleted = null;
    _pendingBin = null;
    if (pendingActive == null && pendingDeleted == null && pendingBin == null) {
      return;
    }

    final beforeActive = _lastActive ?? const <String, Map<String, dynamic>>{};
    final beforeDeleted =
        _lastDeleted ?? const <String, Map<String, dynamic>>{};
    final beforeBin = _lastBin ?? const <String, Map<String, dynamic>>{};
    final afterActive =
        pendingActive != null ? _snapshot(pendingActive) : beforeActive;
    final afterDeleted =
        pendingDeleted != null ? _snapshot(pendingDeleted) : beforeDeleted;
    final afterBin = pendingBin != null ? _snapshot(pendingBin) : beforeBin;

    _lastActive = afterActive;
    _lastDeleted = afterDeleted;
    _lastBin = afterBin;

    if (_snapshotsEqual(beforeActive, afterActive) &&
        _snapshotsEqual(beforeDeleted, afterDeleted) &&
        _snapshotsEqual(beforeBin, afterBin)) {
      return;
    }

    _undoStack.add(_UndoEntry(
      beforeActive: beforeActive,
      afterActive: afterActive,
      beforeDeleted: beforeDeleted,
      afterDeleted: afterDeleted,
      beforeBin: beforeBin,
      afterBin: afterBin,
      description: describeChange(
        beforeActive: beforeActive,
        afterActive: afterActive,
        beforeDeleted: beforeDeleted,
        afterDeleted: afterDeleted,
        beforeBin: beforeBin,
        afterBin: afterBin,
      ),
      at: DateTime.now(),
    ));
    if (_undoStack.length > maxEntries) _undoStack.removeAt(0);
    _redoStack.clear();
    revision.value++;
  }

  /// Reverts the most recent action. Returns the task lists to apply to the
  /// UI's in-memory state, or null when there is nothing to undo.
  Future<TaskUndoState?> undo() async {
    if (_undoStack.isEmpty) return null;
    final entry = _undoStack.removeLast();
    _redoStack.add(entry);
    _lastActive = entry.beforeActive;
    _lastDeleted = entry.beforeDeleted;
    _lastBin = entry.beforeBin;
    final active = _toTasks(entry.beforeActive);
    final deleted = _toTasks(entry.beforeDeleted);
    final bin = _toTasks(entry.beforeBin);
    await _persist(active, deleted, bin, source: TaskChangeSource.undo);
    revision.value++;
    return TaskUndoState(
        active: active,
        deleted: deleted,
        bin: bin,
        description: entry.description);
  }

  /// Re-applies the most recently undone action. Returns the task lists to
  /// apply to the UI's in-memory state, or null when there is nothing to
  /// redo.
  Future<TaskUndoState?> redo() async {
    if (_redoStack.isEmpty) return null;
    final entry = _redoStack.removeLast();
    _undoStack.add(entry);
    _lastActive = entry.afterActive;
    _lastDeleted = entry.afterDeleted;
    _lastBin = entry.afterBin;
    final active = _toTasks(entry.afterActive);
    final deleted = _toTasks(entry.afterDeleted);
    final bin = _toTasks(entry.afterBin);
    await _persist(active, deleted, bin, source: TaskChangeSource.redo);
    revision.value++;
    return TaskUndoState(
        active: active,
        deleted: deleted,
        bin: bin,
        description: entry.description);
  }

  static List<Task> _toTasks(_Snapshot snapshot) =>
      snapshot.values.map(Task.fromJson).toList();

  Future<void> _persist(List<Task> active, List<Task> deleted, List<Task> bin,
      {required String source}) async {
    await _repository.saveItems(active, source: source);
    await _repository.saveDeletedItems(deleted);
    await _repository.saveBinItems(bin);
  }

  static bool _snapshotsEqual(_Snapshot a, _Snapshot b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!mapEquals(b[entry.key], entry.value)) return false;
    }
    return true;
  }

  /// Clears every stack and cached baseline. Tests only.
  @visibleForTesting
  void resetForTest() {
    _undoStack.clear();
    _redoStack.clear();
    _lastActive = null;
    _lastDeleted = null;
    _lastBin = null;
    _pendingActive = null;
    _pendingDeleted = null;
    _pendingBin = null;
    _flushScheduled = false;
    revision.value = 0;
  }

  /// Human-readable label for a before/after triple of active/archived/bin
  /// snapshots, e.g. `Completed "Buy milk"` or `Archived 3 tasks`. Grouped
  /// by what happened to each task so one multi-task action reads as one
  /// sentence rather than one line per task; a top-level function so tests
  /// can cover the wording directly.
  static String describeChange({
    required _Snapshot beforeActive,
    required _Snapshot afterActive,
    required _Snapshot beforeDeleted,
    required _Snapshot afterDeleted,
    _Snapshot beforeBin = const <String, Map<String, dynamic>>{},
    _Snapshot afterBin = const <String, Map<String, dynamic>>{},
  }) {
    final beforeAll = <String, Map<String, dynamic>>{
      ...beforeBin,
      ...beforeDeleted,
      ...beforeActive,
    };
    final afterAll = <String, Map<String, dynamic>>{
      ...afterBin,
      ...afterDeleted,
      ...afterActive,
    };

    final created = <String>[];
    final permanentlyDeleted = <String>[];
    final archived = <String>[];
    final movedToBin = <String>[];
    final restored = <String>[];
    final completed = <String>[];
    final reopened = <String>[];
    final rescheduled = <String>[];
    final moved = <String>[];
    final labeled = <String>[];
    final edited = <String>[];

    String titleOf(Map<String, dynamic> json) =>
        (json['title'] as String?)?.trim().isNotEmpty == true
            ? json['title'] as String
            : 'task';

    for (final uid in afterAll.keys) {
      final after = afterAll[uid]!;
      final title = titleOf(after);
      final before = beforeAll[uid];
      if (before == null) {
        created.add(title);
        continue;
      }
      final wasActive = beforeActive.containsKey(uid);
      final wasDeleted = beforeDeleted.containsKey(uid);
      final isActive = afterActive.containsKey(uid);
      final isDeleted = afterDeleted.containsKey(uid);
      final isBin = afterBin.containsKey(uid);
      if (wasActive && !isActive && isDeleted && !isBin) {
        archived.add(title);
        continue;
      }
      if ((wasActive || wasDeleted) && !isActive && !isDeleted && isBin) {
        // Either an archived item sent on to the bin, or a Waiting for
        // Approval denial — which skips the archive and lands here
        // directly. Both read as "Deleted" from the outside.
        movedToBin.add(title);
        continue;
      }
      if (!wasActive && isActive) {
        restored.add(title);
        continue;
      }
      if (!isActive) continue;
      if (before['isDone'] != after['isDone']) {
        (after['isDone'] == true ? completed : reopened).add(title);
      } else if (before['endAt'] != after['endAt'] ||
          before['startAt'] != after['startAt']) {
        rescheduled.add(title);
      } else if (before['projectId'] != after['projectId'] ||
          before['kanbanStatus'] != after['kanbanStatus']) {
        moved.add(title);
      } else if (before['label'] != after['label']) {
        labeled.add(title);
      } else if (!mapEquals(before, after)) {
        edited.add(title);
      }
    }
    for (final uid in beforeAll.keys) {
      if (!afterAll.containsKey(uid)) {
        permanentlyDeleted.add(titleOf(beforeAll[uid]!));
      }
    }

    String phrase(String verb, List<String> items) {
      if (items.isEmpty) return '';
      if (items.length == 1) return '$verb "${items.first}"';
      return '$verb ${items.length} tasks';
    }

    final parts = <String>[
      phrase('Created', created),
      phrase('Completed', completed),
      phrase('Reopened', reopened),
      phrase('Rescheduled', rescheduled),
      phrase('Moved', moved),
      phrase('Relabeled', labeled),
      phrase('Archived', archived),
      phrase('Restored', restored),
      phrase('Deleted', movedToBin),
      phrase('Permanently deleted', permanentlyDeleted),
      phrase('Edited', edited),
    ].where((p) => p.isNotEmpty).toList();

    return parts.isEmpty ? 'Updated tasks' : parts.join(', ');
  }
}
