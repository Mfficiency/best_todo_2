import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/sync_log_entry.dart';
import 'log_service.dart';
import 'safe_file.dart';
import 'storage_service.dart';
import 'sync_import_service.dart';
import 'sync_markdown.dart';

/// One-way background sync of the task list into a user-chosen folder
/// ("synced mode", Settings → Sync & export).
///
/// Design constraints, in order:
///  * **Never touch startup.** Nothing here runs at launch beyond a lazy read
///    of `sync_log.json` (kicked off fire-and-forget the first time the UI
///    asks for sync state).
///  * **Sync when the app is left**, not while it is used: the lifecycle hook
///    in `main.dart` calls [onLifecycleChanged]; the first
///    hidden/paused/detached state after a resume triggers exactly one sync.
///  * **Fail soft.** Every failure (folder gone, drive unmounted, write
///    denied, overlapping run) becomes a red log entry and the unseen-error
///    flag for the drawer dot — never an exception into the app.
///
/// The write itself is atomic ([SafeFile]: tmp + rename), so a reader of the
/// synced file — or a crash mid-sync — can never observe a half-written file.
class SyncService {
  SyncService._();
  static SyncService instance = SyncService._();

  /// Fixed file name written into the chosen folder on every sync.
  static const String syncFileName = 'besttodo_tasks.json';

  /// Human-readable companion written next to [syncFileName]: an
  /// Obsidian-friendly Markdown checklist ([SyncMarkdown]). Point the sync
  /// folder into an Obsidian vault and the list renders natively.
  static const String syncMarkdownFileName = 'besttodo_tasks.md';
  static const _logFileName = 'sync_log.json';
  static const _maxLogEntries = 100;

  /// Newest-first history of sync runs, persisted in `sync_log.json`.
  final ValueNotifier<List<SyncLogEntry>> entries =
      ValueNotifier<List<SyncLogEntry>>(<SyncLogEntry>[]);

  /// True while the latest sync failed and the App Logs page has not been
  /// opened since — drives the red dot on the drawer's App Logs entry.
  final ValueNotifier<bool> hasUnseenError = ValueNotifier<bool>(false);

  Future<void>? _loadFuture;
  bool _syncInFlight = false;
  bool _syncedThisBackground = false;

  /// The sync started by the last quit-shaped lifecycle change; tests await
  /// it, production fires and forgets.
  @visibleForTesting
  Future<SyncLogEntry?>? pendingQuitSync;

  /// The Tier 3 change-journal import started by the last resume; tests
  /// await it, production fires and forgets.
  @visibleForTesting
  Future<SyncLogEntry?>? pendingResumeImport;

  /// Loads the persisted sync history once; safe to call from anywhere the
  /// UI first needs sync state (drawer badge, App Logs page).
  Future<void> ensureLoaded() {
    _loadFuture ??= _load();
    return _loadFuture!;
  }

  Future<void> _load() async {
    try {
      final file = await _logFile();
      final data = await SafeFile.readWithRecovery(
          file, (contents) => jsonDecode(contents));
      if (data is! Map) return;
      final rawEntries = data['entries'];
      if (rawEntries is List) {
        entries.value = [
          for (final e in rawEntries)
            if (e is Map) SyncLogEntry.fromJson(Map<String, dynamic>.from(e)),
        ];
      }
      hasUnseenError.value = data['unseen_error'] as bool? ?? false;
    } catch (_) {
      // No documents dir (web/tests) or unreadable history: start empty.
    }
  }

  Future<File> _logFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_logFileName');
  }

  /// Lifecycle hook, called from the root widget's observer. The first
  /// backgrounded-looking state after a resume starts one background sync;
  /// hidden → paused → detached arriving in a row must not sync three times.
  void onLifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncedThisBackground = false;
      // Tier 3: pick up edits made in Obsidian since the app was last open
      // (SPEC §4.7, .claude/notes/obsidian-integration.md). Same fail-soft
      // contract as the quit-time sync — never throws into the app.
      if (Config.syncEnabled) {
        pendingResumeImport = SyncImportService.instance.importPending();
      }
      return;
    }
    final quitting = state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (!quitting || _syncedThisBackground) return;
    _syncedThisBackground = true;
    if (!Config.syncEnabled) return;
    pendingQuitSync = syncNow(trigger: 'app quit');
  }

  /// Writes the current task list into the chosen folder and records the run.
  /// Returns the recorded entry, or null when sync is off or one is already
  /// running. Never throws.
  Future<SyncLogEntry?> syncNow({String trigger = 'manual'}) async {
    if (!Config.syncEnabled) return null;
    if (_syncInFlight) return null;
    _syncInFlight = true;
    try {
      await ensureLoaded();
      final stopwatch = Stopwatch()..start();
      SyncLogEntry entry;
      try {
        final count = await _writeSyncFile();
        stopwatch.stop();
        entry = SyncLogEntry(
          at: DateTime.now(),
          durationMs: stopwatch.elapsedMilliseconds,
          itemCount: count,
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
      await _record(entry);
      return entry;
    } finally {
      _syncInFlight = false;
    }
  }

  /// Resolves [fileName] against a sync-folder path, the way every file this
  /// feature writes or reads is located. Shared by [_writeSyncFile] and
  /// [SyncImportService] so the two never drift on separator handling.
  static File resolveSyncFile(String folder, String fileName) {
    final sep = Platform.pathSeparator;
    final prefix = '$folder${folder.endsWith(sep) ? '' : sep}';
    return File('$prefix$fileName');
  }

  Future<int> _writeSyncFile() async {
    final folder = Config.syncFolderPath.trim();
    if (folder.isEmpty) {
      throw const FileSystemException(
          'No sync folder chosen (Settings → Sync & export)');
    }
    final dir = Directory(folder);
    if (!await dir.exists()) {
      throw FileSystemException('Sync folder not found', folder);
    }
    // Raw read straight from disk: every change is already saved there, and
    // this keeps the sync independent of whatever page is open.
    final tasks = await StorageService().readTaskListRaw();
    final now = DateTime.now();
    final payload = jsonEncode(<String, dynamic>{
      'sync_version': 1,
      'synced_at': now.toIso8601String(),
      'app_version': Config.versionWithBuild,
      'task_count': tasks.length,
      'tasks': [for (final t in tasks) t.toJson()],
    });
    await SafeFile.writeString(
        resolveSyncFile(folder, syncFileName), payload);
    await SafeFile.writeString(
      resolveSyncFile(folder, syncMarkdownFileName),
      SyncMarkdown.build(tasks, now, Config.versionWithBuild),
    );
    return tasks.length;
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

  Future<void> _record(SyncLogEntry entry) async {
    final updated = <SyncLogEntry>[entry, ...entries.value];
    if (updated.length > _maxLogEntries) {
      updated.removeRange(_maxLogEntries, updated.length);
    }
    entries.value = updated;
    // A successful sync means the trouble is over; the dot only lingers while
    // the latest run failed.
    hasUnseenError.value = !entry.success;
    final isImport = entry.trigger == 'import';
    LogService.add(
      'Sync',
      entry.success
          ? (isImport
              ? 'Imported ${entry.itemCount} change(s) from Obsidian in '
                  '${entry.durationMs} ms'
              : 'Synced ${entry.itemCount} tasks in ${entry.durationMs} ms '
                  '(${entry.trigger})')
          : (isImport
              ? 'Import from Obsidian failed: ${entry.message}'
              : 'Sync failed (${entry.trigger}): ${entry.message}'),
    );
    await _persist();
  }

  /// Records a history entry from a sync-adjacent service — currently just
  /// [SyncImportService] — into the same App Logs "Sync" history as a
  /// regular sync run, with the same fail-soft persistence.
  Future<void> recordEntry(SyncLogEntry entry) async {
    await ensureLoaded();
    await _record(entry);
  }

  /// Called when the App Logs page opens: the error has been seen, so the
  /// drawer dot goes away (the failed entry itself stays in the history).
  Future<void> markErrorSeen() async {
    if (!hasUnseenError.value) return;
    hasUnseenError.value = false;
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final file = await _logFile();
      await SafeFile.writeString(
        file,
        jsonEncode(<String, dynamic>{
          'unseen_error': hasUnseenError.value,
          'entries': [for (final e in entries.value) e.toJson()],
        }),
      );
    } catch (_) {
      // No documents dir (web/tests): history stays in-memory only.
    }
  }

  /// Fresh instance for tests (mirrors `ProjectService.resetForTest`).
  static void resetForTest() {
    instance = SyncService._();
  }
}
