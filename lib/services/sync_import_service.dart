import 'dart:convert';
import 'dart:io';

import '../config.dart';
import '../models/sync_log_entry.dart';
import '../models/task.dart';
import 'safe_file.dart';
import 'storage_service.dart';
import 'sync_service.dart';

/// Tier 3 of the Obsidian integration (SPEC §4.7,
/// `.claude/notes/obsidian-integration.md`): imports `besttodo_changes.json`,
/// an append-only change journal the Obsidian plugin writes operations into.
/// The plugin never edits `besttodo_tasks.json`/`.md` directly — the app
/// overwrites both on every sync, so a direct edit would just be clobbered.
///
/// Runs on app **resume** (the mirror of [SyncService]'s quit-time sync):
/// read the journal, apply its ops by `uid` with last-writer-wins conflict
/// rules, truncate the journal, then re-run a sync so both sides converge.
///
/// **Fail-soft, same as [SyncService]:** every failure (folder gone,
/// malformed journal, unknown journal version) becomes a red history entry
/// in the same App Logs "Sync" history, never an exception into the app. A
/// malformed journal is left on disk untouched — only a successfully applied
/// journal is truncated, so a bad write never loses pending ops.
class SyncImportService {
  SyncImportService._();
  static SyncImportService instance = SyncImportService._();

  /// Fixed file name the Obsidian plugin appends operations to.
  static const String journalFileName = 'besttodo_changes.json';
  static const int supportedJournalVersion = 1;

  bool _importInFlight = false;

  /// Reads and applies the pending change journal, if any. Returns the
  /// recorded history entry, or null when sync is off, an import is already
  /// running, or there was simply nothing to import (no journal file, or one
  /// with an empty `ops` array — neither is worth a history entry). Never
  /// throws.
  Future<SyncLogEntry?> importPending({String trigger = 'import'}) async {
    if (!Config.syncEnabled) return null;
    if (_importInFlight) return null;
    _importInFlight = true;
    try {
      final stopwatch = Stopwatch()..start();
      SyncLogEntry entry;
      try {
        final applied = await _importOnce();
        if (applied == null) return null;
        stopwatch.stop();
        entry = SyncLogEntry(
          at: DateTime.now(),
          durationMs: stopwatch.elapsedMilliseconds,
          itemCount: applied,
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
          message: _describeError(e),
          trigger: trigger,
        );
      }
      await SyncService.instance.recordEntry(entry);
      // Re-sync so besttodo_tasks.json/.md reflect the imported changes —
      // without this the Obsidian view would show stale state until the app
      // is next backgrounded.
      if (entry.success && entry.itemCount > 0) {
        await SyncService.instance.syncNow(trigger: 'import');
      }
      return entry;
    } finally {
      _importInFlight = false;
    }
  }

  /// Reads the journal, applies its ops, truncates it, and returns the
  /// number of ops actually applied — or null when there is nothing to do
  /// (no folder chosen, no journal file, or an empty `ops` array). Throws on
  /// a malformed journal so the caller can record a failure without
  /// truncating it.
  Future<int?> _importOnce() async {
    final folder = Config.syncFolderPath.trim();
    if (folder.isEmpty) return null;
    final file = SyncService.resolveSyncFile(folder, journalFileName);
    if (!await file.exists()) return null;

    final contents = await file.readAsString();
    if (contents.trim().isEmpty) return null;
    final decoded = jsonDecode(contents);
    if (decoded is! Map) {
      throw const FormatException(
          'besttodo_changes.json is not a JSON object');
    }
    final version = decoded['journal_version'];
    if (version != supportedJournalVersion) {
      throw FormatException('Unsupported journal_version $version');
    }
    final rawOps = decoded['ops'];
    if (rawOps is! List || rawOps.isEmpty) return null;

    final tasks = await StorageService().readTaskListRaw();
    final byUid = <String, Task>{for (final t in tasks) t.uid: t};
    var applied = 0;
    var changed = false;
    for (final raw in rawOps) {
      if (raw is! Map) continue;
      final op = raw['op'];
      final at = DateTime.tryParse(raw['at'] as String? ?? '');
      if (op is! String || at == null) continue;
      final uid = raw['uid'] as String?;
      final fields = raw['fields'] is Map
          ? Map<String, dynamic>.from(raw['fields'] as Map)
          : const <String, dynamic>{};
      final didApply = switch (op) {
        'complete' => _applyComplete(byUid[uid], at),
        'reopen' => _applyReopen(byUid[uid], at),
        'edit' => _applyEdit(byUid[uid], at, fields),
        'delete' => _applyDelete(byUid[uid], at),
        'create' => _applyCreate(tasks, byUid, at, fields),
        _ => false, // unknown op type: ignore rather than fail the batch
      };
      if (didApply) {
        applied++;
        changed = true;
      }
    }

    if (changed) {
      await StorageService().saveTaskList(tasks);
    }
    // Truncate rather than delete: the plugin only ever appends, so an empty
    // envelope (not a missing file) is the well-defined "nothing pending"
    // state for its next write.
    await SafeFile.writeString(
      file,
      jsonEncode(<String, dynamic>{
        'journal_version': supportedJournalVersion,
        'device': decoded['device'],
        'ops': const <dynamic>[],
      }),
    );
    return applied;
  }

  /// Idempotent and monotonic: completing an already-done task never
  /// regresses it, and a stale op (older than the last completion) is
  /// silently dropped as a no-op rather than a conflict.
  bool _applyComplete(Task? task, DateTime at) {
    if (task == null || task.deletedAt != null) return false;
    if (task.isDone) {
      if (task.completedAt == null || at.isAfter(task.completedAt!)) {
        task.completedAt = at;
        return true;
      }
      return false;
    }
    task.isDone = true;
    task.completedAt = at;
    return true;
  }

  /// Last-writer-wins against the task's own `completedAt`: a reopen op
  /// older than a completion that already happened locally loses silently.
  bool _applyReopen(Task? task, DateTime at) {
    if (task == null || task.deletedAt != null) return false;
    if (!task.isDone) return false;
    if (task.completedAt != null && task.completedAt!.isAfter(at)) {
      return false;
    }
    task.isDone = false;
    task.completedAt = null;
    return true;
  }

  /// Deletions are tombstones ([Task.deletedAt]) — never a hard delete from
  /// an op, matching the app's own delete path.
  bool _applyDelete(Task? task, DateTime at) {
    if (task == null || task.deletedAt != null) return false;
    task.deletedAt = at;
    return true;
  }

  /// Text fields (title/description/note/label) have no per-field timestamp
  /// to arbitrate on, so an edit op applies unconditionally; the date fields
  /// are last-writer-wins against [Task.rescheduledAt], the timestamp the
  /// app itself sets on every reschedule.
  bool _applyEdit(Task? task, DateTime at, Map<String, dynamic> fields) {
    if (task == null || task.deletedAt != null || fields.isEmpty) {
      return false;
    }
    var changed = false;
    final title = fields['title'];
    if (title is String && title.trim().isNotEmpty && title != task.title) {
      task.title = title;
      changed = true;
    }
    final label = fields['label'];
    if (label is String && label != task.label) {
      task.label = label;
      changed = true;
    }
    final description = fields['description'];
    if (description is String && description != task.description) {
      task.description = description;
      changed = true;
    }
    final note = fields['note'];
    if (note is String && note != task.note) {
      task.note = note;
      changed = true;
    }
    if (fields.containsKey('dueDate')) {
      final stale =
          task.rescheduledAt != null && task.rescheduledAt!.isAfter(at);
      if (!stale) {
        final raw = fields['dueDate'];
        final parsed = raw is String ? DateTime.tryParse(raw) : null;
        if (parsed != task.dueDate) {
          task.dueDate = parsed;
          task.rescheduledAt = at;
          changed = true;
        }
        final hasExplicitTime = fields['hasExplicitTime'];
        if (hasExplicitTime is bool &&
            hasExplicitTime != task.hasExplicitTime) {
          task.hasExplicitTime = hasExplicitTime;
          changed = true;
        }
      }
    }
    return changed;
  }

  /// Creates bring their own uid ([fields]`['uid']`) so a replayed create op
  /// is idempotent: a uid already on the list is a no-op, not a duplicate.
  bool _applyCreate(List<Task> tasks, Map<String, Task> byUid, DateTime at,
      Map<String, dynamic> fields) {
    final uid = fields['uid'];
    if (uid is! String || uid.isEmpty || byUid.containsKey(uid)) {
      return false;
    }
    final title = fields['title'];
    final label = fields['label'];
    final dueDateRaw = fields['dueDate'];
    final task = Task(
      uid: uid,
      title: title is String && title.trim().isNotEmpty ? title : 'Untitled',
      label: label is String ? label : '',
      dueDate: dueDateRaw is String ? DateTime.tryParse(dueDateRaw) : null,
      createdAt: at,
    );
    tasks.add(task);
    byUid[uid] = task;
    return true;
  }

  String _describeError(Object error) {
    if (error is FileSystemException) {
      final path = error.path;
      return path == null || path.isEmpty
          ? error.message
          : '${error.message}: $path';
    }
    return error.toString();
  }

  /// Fresh instance for tests (mirrors `SyncService.resetForTest`).
  static void resetForTest() {
    instance = SyncImportService._();
  }
}
