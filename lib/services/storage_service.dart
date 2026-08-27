import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/countdown_timer.dart';
import '../models/daily_task_stats.dart';
import '../models/item_event.dart';
import '../models/task.dart';
import '../models/task_change_source.dart';
import 'attachment_storage_service.dart';
import 'item_event_journal.dart';
import 'label_service.dart';
import 'pre_update_backup.dart';
import 'reminder_sync_service.dart';
import 'safe_file.dart';
import 'wishlist_migration.dart';
import 'wishlist_shipped.dart';

class TaskImportBundle {
  final List<Task> tasks;
  final List<Task> deletedTasks;
  final Map<String, DailyTaskStats> dailyStatsByDay;
  final List<String> warnings;

  const TaskImportBundle({
    required this.tasks,
    required this.deletedTasks,
    required this.dailyStatsByDay,
    this.warnings = const <String>[],
  });
}

class StorageService {
  static const _fileName = 'tasks.json';
  static const _deletedFileName = 'deleted_tasks.json';
  static const _binFileName = 'deleted_bin.json';
  static const _dailyStatsFileName = 'daily_task_stats.json';
  static const _dateFileName = 'last_opened.txt';
  static const _countdownFileName = 'countdown_timers.json';
  static const _wishlistFileName = 'wishlist.json';

  /// Marker written after the one-time Todo.md → wishlist import so it never
  /// re-adds items the user has since deleted. Public so tests can pre-create
  /// it to opt out of the import.
  static const String wishlistImportFlagFileName =
      'wishlist_todo_import_v1.txt';
  static const _maxDeletedTasks = 100;
  static const int exportVersion = 2;

  /// Last persisted state of the task list (`uid → task JSON`), shared across
  /// instances so every save can be diffed into the item-history journal.
  /// Null until the first load/save of a session; the first contact only
  /// snapshots (no events), so pre-seeding storage in tests stays silent.
  static Map<String, Map<String, dynamic>>? _journalBaseline;

  static Map<String, Map<String, dynamic>> _snapshotOf(List<Task> tasks) =>
      {for (final t in tasks) t.uid: t.toJson()};

  static void resetJournalBaselineForTest() => _journalBaseline = null;

  void _ensureUniqueIds(List<Task> tasks) {
    final ids = <String>{};
    for (final t in tasks) {
      if (t.uid.isEmpty || ids.contains(t.uid)) {
        t.uid = Task.newUid();
      }
      ids.add(t.uid);
    }
  }

  Future<File> _getLocalFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<File> _getDateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_dateFileName');
  }

  Future<File> _getDeletedFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_deletedFileName');
  }

  Future<File> _getBinFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_binFileName');
  }

  Future<File> _getDailyStatsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_dailyStatsFileName');
  }

  Future<File> _getWishlistFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_wishlistFileName');
  }

  void _trimDeletedTasks(List<Task> tasks) {
    if (tasks.length > _maxDeletedTasks) {
      tasks.removeRange(_maxDeletedTasks, tasks.length);
    }
  }

  Future<bool> _isNewDay() async {
    final file = await _getDateFile();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!await file.exists()) {
      await file.writeAsString(now.toIso8601String(), flush: true);
      return false;
    }
    try {
      final contents = await file.readAsString();
      final parsed = DateTime.tryParse(contents);
      if (parsed != null) {
        final last = DateTime(parsed.year, parsed.month, parsed.day);
        if (today.isAfter(last)) {
          await file.writeAsString(now.toIso8601String(), flush: true);
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> saveTaskList(
    List<Task> tasks, {
    String source = TaskChangeSource.user,
  }) async {
    // Before this version's first-ever write, snapshot whatever the previous
    // app version left on disk (no-op after the first call).
    await PreUpdateBackup.ensure();
    // Journal the change before writing: diff against the last persisted
    // state and hand the result to the journal's background write chain —
    // recordDiff returns immediately, so saves are as fast as before.
    final snapshot = _snapshotOf(tasks);
    final baseline = _journalBaseline;
    _journalBaseline = snapshot;
    if (baseline != null) {
      ItemEventJournal.instance
          .recordDiff(before: baseline, after: snapshot, source: source);
    }
    // Structured-label dual-write: make sure every token on any task exists
    // as a first-class Label. Fire-and-forget and write-free once all tokens
    // are known, so saves stay as fast as before.
    LabelService.instance
        .registerFromLabelStrings(tasks.map((t) => t.label));
    // Item-linked reminders follow their task (reschedule/complete/delete).
    // Free when no linked alarm exists in memory.
    ReminderSyncService.syncAfterSave(tasks);
    final file = await _getLocalFile();
    final jsonString = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await SafeFile.writeString(file, jsonString);
  }

  static List<Task> _parseTaskArray(String contents) =>
      (jsonDecode(contents) as List<dynamic>)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<void> saveDeletedTaskList(List<Task> tasks) async {
    await PreUpdateBackup.ensure();
    final file = await _getDeletedFile();
    _trimDeletedTasks(tasks);
    final jsonString = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await SafeFile.writeString(file, jsonString);
  }

  Future<List<Task>> loadDeletedTaskList() async {
    try {
      final file = await _getDeletedFile();
      final tasks =
          await SafeFile.readWithRecovery(file, _parseTaskArray) ?? <Task>[];
      _ensureUniqueIds(tasks);
      _trimDeletedTasks(tasks);
      return tasks;
    } catch (_) {
      return <Task>[];
    }
  }

  /// The real Deleted bin: tasks denied from Waiting for Approval, or moved
  /// on from Archived Items. Unlike the archive, entries here age out —
  /// [loadBinTaskList] purges anything older than
  /// [Config.deletedItemsRetentionDays] on every read and persists the
  /// trimmed list, so the purge applies even if the bin page is never opened.
  Future<void> saveBinTaskList(List<Task> tasks) async {
    await PreUpdateBackup.ensure();
    final file = await _getBinFile();
    _trimDeletedTasks(tasks);
    final jsonString = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await SafeFile.writeString(file, jsonString);
  }

  Future<List<Task>> loadBinTaskList() async {
    try {
      final file = await _getBinFile();
      final tasks =
          await SafeFile.readWithRecovery(file, _parseTaskArray) ?? <Task>[];
      _ensureUniqueIds(tasks);
      _trimDeletedTasks(tasks);
      final retentionDays = Config.deletedItemsRetentionDays;
      final cutoff =
          DateTime.now().subtract(Duration(days: retentionDays));
      final expired = tasks
          .where((t) => t.deletedAt != null && t.deletedAt!.isBefore(cutoff))
          .toList();
      if (expired.isNotEmpty) {
        tasks.removeWhere(expired.contains);
        await saveBinTaskList(tasks);
        for (final task in expired) {
          if (task.attachments.isNotEmpty) {
            await AttachmentStorageService.instance
                .deleteAttachmentsForTask(task.uid);
          }
        }
      }
      return tasks;
    } catch (_) {
      return <Task>[];
    }
  }

  /// Reads `tasks.json` exactly as it sits on disk — no new-day rollover, no
  /// wishlist migration, no journal baseline. For callers that only want to
  /// see what another isolate wrote (the home-screen widget completing a task
  /// while the app was in the background), where [loadTaskList]'s side effects
  /// would fight the in-memory list.
  Future<List<Task>> readTaskListRaw() async {
    try {
      final file = await _getLocalFile();
      final tasks =
          await SafeFile.readWithRecovery(file, _parseTaskArray) ?? <Task>[];
      _ensureUniqueIds(tasks);
      return tasks;
    } catch (_) {
      return <Task>[];
    }
  }

  Future<List<Task>> loadTaskList() async {
    try {
      final isNewDay = await _isNewDay();
      final file = await _getLocalFile();
      // An unparseable tasks.json falls back to tasks.json.bak (the corrupt
      // original is quarantined, never overwritten) — an update can no
      // longer turn a bad parse into an empty list that then gets saved.
      final tasks =
          await SafeFile.readWithRecovery(file, _parseTaskArray) ?? <Task>[];
      _ensureUniqueIds(tasks);
      // Give pre-0.1.232 backlog imports their stable uid before the journal
      // baseline is taken: re-identifying an item is bookkeeping, and the
      // journal diff would otherwise read the uid swap as delete + create.
      final backfilled = backfillLegacyWishUids(tasks);
      // Baseline for the journal is the state as it was on disk, set before
      // the rollover sweep below so swept tasks produce `deleted` events.
      _journalBaseline = _snapshotOf(tasks);
      if (isNewDay) {
        final doneTasks = tasks.where((t) => t.isDone).toList();
        if (doneTasks.isNotEmpty) {
          final deletedTasks = await loadDeletedTaskList();
          for (final task in doneTasks) {
            task.completedAt ??= DateTime.now();
            task.deletedAt ??= DateTime.now();
            deletedTasks.insert(0, task);
          }
          await saveDeletedTaskList(deletedTasks);
        }
        tasks.removeWhere((t) => t.isDone);
      }
      if (isNewDay || backfilled) {
        await saveTaskList(tasks, source: TaskChangeSource.automation);
      }
      await _migrateWishlistIntoTasks(tasks);
      // Wishes whose feature has since been built tick themselves off. Real
      // history (done + labelled), so this save is journalled normally.
      if (applyShippedWishes(tasks)) {
        await saveTaskList(tasks, source: TaskChangeSource.automation);
      }
      return tasks;
    } catch (_) {
      return <Task>[];
    }
  }

  /// Wishlist items live in the one task list (flagged [Task.isWish]) so the
  /// Wishlist tool is a pre-filtered view like a project. Merge any legacy
  /// wishlist.json content — including the one-time Todo.md import that
  /// [loadWishlist] performs — into [tasks] and empty the legacy file so
  /// nothing is merged twice. An unreadable wishlist.json is left untouched
  /// ([loadWishlist] returns an empty list for it), keeping this a no-op.
  Future<void> _migrateWishlistIntoTasks(List<Task> tasks) async {
    final wishItems = await loadWishlist();
    if (wishItems.isEmpty) return;
    final ids = tasks.map((t) => t.uid).toSet();
    for (final item in wishItems) {
      item.isWish = true;
      item.dueDate = null;
      if (ids.add(item.uid)) tasks.add(item);
    }
    // Save the merged list BEFORE emptying the legacy file: saveTaskList's
    // pre-update snapshot then still captures the original wishlist.json,
    // and a crash in between merely re-merges next load (deduped by uid).
    await saveTaskList(tasks, source: TaskChangeSource.automation);
    await saveWishlist(<Task>[]);
  }

  Future<void> saveWishlist(List<Task> items) async {
    await PreUpdateBackup.ensure();
    final file = await _getWishlistFile();
    final jsonString = jsonEncode(items.map((t) => t.toJson()).toList());
    await file.writeAsString(jsonString, flush: true);
  }

  Future<List<Task>> loadWishlist() async {
    List<Task> items;
    try {
      final file = await _getWishlistFile();
      if (await file.exists()) {
        final contents = await file.readAsString();
        final List<dynamic> data = jsonDecode(contents);
        items = data
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList();
        _ensureUniqueIds(items);
        // Stable uids here too, so an item still parked in the legacy file
        // dedupes against its already-migrated twin by uid.
        if (backfillLegacyWishUids(items)) await saveWishlist(items);
      } else {
        items = <Task>[];
      }
    } catch (_) {
      // An existing wishlist that fails to load must never be overwritten by
      // the legacy import below, so bail out without touching the file.
      return <Task>[];
    }
    await _maybeImportLegacyTodoItems(items);
    return items;
  }

  /// One-time merge of the historical Todo.md backlog into the wishlist
  /// (labelled [legacyTodoImportLabel]). Existing items are never modified or
  /// removed; entries whose normalized title is already present are skipped.
  /// Guarded by [wishlistImportFlagFileName] so user deletions stick.
  Future<void> _maybeImportLegacyTodoItems(List<Task> items) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final flag = File('${dir.path}/$wishlistImportFlagFileName');
      if (await flag.exists()) return;

      final existingTitles =
          items.map((t) => normalizeWishlistTitle(t.title)).toSet();
      final added = <Task>[];
      for (final legacy in legacyTodoWishlistItems) {
        if (!existingTitles.add(normalizeWishlistTitle(legacy.title))) {
          continue;
        }
        added.add(Task(
          // The backlog's stable uid, so the shipped-wish registry can tick
          // this item off once its feature is built.
          uid: legacy.uid,
          title: legacy.title,
          description: legacy.description,
          label: legacyTodoImportLabel,
          createdAt: DateTime.now(),
        ));
      }
      if (added.isNotEmpty) {
        items.addAll(added);
        await saveWishlist(items);
      }
      await flag.writeAsString(DateTime.now().toIso8601String(), flush: true);
    } catch (_) {
      // No documents dir (web/tests) or write failure: keep working with the
      // in-memory list; the import will be retried on a later load.
    }
  }

  Future<void> saveDailyTaskStats(
      Map<String, DailyTaskStats> dailyStatsByDay) async {
    await PreUpdateBackup.ensure();
    final file = await _getDailyStatsFile();
    final jsonString = jsonEncode(
      dailyStatsByDay.values.map((stats) => stats.toJson()).toList(),
    );
    await SafeFile.writeString(file, jsonString);
  }

  Future<Map<String, DailyTaskStats>> loadDailyTaskStats() async {
    try {
      final file = await _getDailyStatsFile();
      final values = await SafeFile.readWithRecovery(
            file,
            (contents) => (jsonDecode(contents) as List<dynamic>)
                .map((e) => DailyTaskStats.fromJson(e as Map<String, dynamic>))
                .where((stats) => stats.dayKey.isNotEmpty)
                .toList(),
          ) ??
          <DailyTaskStats>[];
      return {for (final item in values) item.dayKey: item};
    } catch (_) {
      return <String, DailyTaskStats>{};
    }
  }

  Future<File> _getCountdownFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_countdownFileName');
  }

  Future<void> saveCountdownTimers(List<CountdownTimerItem> timers) async {
    // Persistence is unavailable on platforms without a documents directory
    // (e.g. Flutter web), so swallow failures and keep working in-memory.
    try {
      await PreUpdateBackup.ensure();
      final file = await _getCountdownFile();
      final jsonString = jsonEncode(timers.map((t) => t.toJson()).toList());
      await SafeFile.writeString(file, jsonString);
    } catch (_) {}
  }

  /// Parses a decoded JSON list of countdown timers (e.g. from an imported
  /// backup) and persists them, replacing any existing timers. Returns the
  /// number of timers imported.
  Future<int> importCountdownTimersFromDecoded(dynamic decoded) async {
    if (decoded is! List) return 0;
    final timers = <CountdownTimerItem>[];
    for (final entry in decoded) {
      if (entry is Map) {
        try {
          timers.add(CountdownTimerItem.fromJson(
            Map<String, dynamic>.from(entry),
          ));
        } catch (_) {}
      }
    }
    await saveCountdownTimers(timers);
    return timers.length;
  }

  /// Loads saved countdown timers. Returns `null` when no timers file exists
  /// yet, so callers can distinguish a first run from an intentionally empty
  /// list.
  Future<List<CountdownTimerItem>?> loadCountdownTimers() async {
    try {
      final file = await _getCountdownFile();
      // `null` means "never had a timers file" (first run); a file that
      // exists but cannot be read — even via its backup — stays `[]` so the
      // first-run seeding never re-runs over real (if unreadable) data.
      final everExisted = await file.exists() ||
          await File('${file.path}.bak').exists();
      if (!everExisted) return null;
      return await SafeFile.readWithRecovery(
            file,
            (contents) => (jsonDecode(contents) as List<dynamic>)
                .map((e) =>
                    CountdownTimerItem.fromJson(e as Map<String, dynamic>))
                .toList(),
          ) ??
          <CountdownTimerItem>[];
    } catch (_) {
      return <CountdownTimerItem>[];
    }
  }

  Future<File?> exportTaskList(List<Task> tasks, String path) async {
    try {
      final file = File(path);
      final jsonString = jsonEncode(buildTaskExportPayload(
        tasks: tasks,
        deletedTasks: const <Task>[],
        dailyStatsByDay: const <String, DailyTaskStats>{},
      ));
      await file.writeAsString(jsonString, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<File?> exportTaskData({
    required List<Task> tasks,
    required List<Task> deletedTasks,
    required Map<String, DailyTaskStats> dailyStatsByDay,
    required String path,
  }) async {
    try {
      // The journal is the exact record; the derived task_events below stay
      // for consumers of the old shape.
      var itemEvents = const <ItemEvent>[];
      try {
        itemEvents = await ItemEventJournal.instance.allEvents();
      } catch (_) {}
      final file = File(path);
      final jsonString = jsonEncode(buildTaskExportPayload(
        tasks: tasks,
        deletedTasks: deletedTasks,
        dailyStatsByDay: dailyStatsByDay,
        itemEvents: itemEvents,
      ));
      await file.writeAsString(jsonString, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> buildTaskExportPayload({
    required List<Task> tasks,
    required List<Task> deletedTasks,
    required Map<String, DailyTaskStats> dailyStatsByDay,
    List<ItemEvent> itemEvents = const <ItemEvent>[],
  }) {
    final allTasks = <Task>[...tasks, ...deletedTasks];
    final labels = allTasks.map((t) => t.label.trim()).where((v) => v.isNotEmpty).toSet().toList()..sort();
    final projects = allTasks
        .map((t) => t.dueDate == null ? 'unscheduled' : '${t.dueDate!.year}-${t.dueDate!.month.toString().padLeft(2, '0')}-${t.dueDate!.day.toString().padLeft(2, '0')}')
        .toSet()
        .toList()
      ..sort();

    return <String, dynamic>{
      'export_version': exportVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'deleted_tasks': deletedTasks.map((t) => t.toJson()).toList(),
      'daily_stats': dailyStatsByDay.values.map((s) => s.toJson()).toList(),
      'task_events': _deriveTaskEvents(allTasks),
      'item_events': itemEvents.map((e) => e.toJson()).toList(),
      'labels': labels,
      'projects': projects,
    };
  }

  List<Map<String, dynamic>> _deriveTaskEvents(List<Task> tasks) {
    final events = <Map<String, dynamic>>[];
    for (final task in tasks) {
      void add(String type, DateTime? at, [Map<String, dynamic>? extra]) {
        if (at == null) return;
        events.add({
          'task_uid': task.uid,
          'event_type': type,
          'at': at.toIso8601String(),
          if (extra != null) ...extra,
        });
      }

      add('created', task.createdAt);
      add('updated', task.movedAt ?? task.rescheduledAt);
      add('completed', task.completedAt);
      add('deleted', task.deletedAt);
      add('moved', task.movedAt, {
        'to_due_date': task.dueDate?.toIso8601String(),
      });
      add('rescheduled', task.rescheduledAt, {
        'to_due_date': task.dueDate?.toIso8601String(),
      });
      if (task.deletedAt == null && task.completedAt != null && !task.isDone) {
        add('restored', task.completedAt);
      }
    }
    events.sort((a, b) {
      final left = DateTime.tryParse(a['at'] as String? ?? '');
      final right = DateTime.tryParse(b['at'] as String? ?? '');
      if (left == null && right == null) return 0;
      if (left == null) return -1;
      if (right == null) return 1;
      return left.compareTo(right);
    });
    return events;
  }

  Future<List<Task>> importTaskList(String path) async {
    final bundle = await importTaskData(path);
    return bundle.tasks;
  }

  Future<TaskImportBundle> importTaskData(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return const TaskImportBundle(
          tasks: <Task>[],
          deletedTasks: <Task>[],
          dailyStatsByDay: <String, DailyTaskStats>{},
          warnings: <String>['File does not exist'],
        );
      }
      final contents = await file.readAsString();
      final dynamic decoded = jsonDecode(contents);
      if (decoded is! List && decoded is! Map<String, dynamic>) {
        return const TaskImportBundle(
          tasks: <Task>[],
          deletedTasks: <Task>[],
          dailyStatsByDay: <String, DailyTaskStats>{},
          warnings: <String>['Unsupported export payload format'],
        );
      }
      return importTaskDataFromDecoded(decoded);
    } catch (_) {
      return const TaskImportBundle(
        tasks: <Task>[],
        deletedTasks: <Task>[],
        dailyStatsByDay: <String, DailyTaskStats>{},
        warnings: <String>['Failed to parse import file'],
      );
    }
  }

  TaskImportBundle importTaskDataFromDecoded(dynamic decoded) {
    if (decoded is List) {
      final tasks = decoded
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
      _ensureUniqueIds(tasks);
      return const TaskImportBundle(
        tasks: <Task>[],
        deletedTasks: <Task>[],
        dailyStatsByDay: <String, DailyTaskStats>{},
      ).copyWith(
        tasks: tasks,
        warnings: const <String>[
          'Legacy export format detected. Analytics history may be incomplete.',
        ],
      );
    }
    if (decoded is! Map<String, dynamic>) {
      return const TaskImportBundle(
        tasks: <Task>[],
        deletedTasks: <Task>[],
        dailyStatsByDay: <String, DailyTaskStats>{},
        warnings: <String>['Unsupported export payload format'],
      );
    }

    final warnings = <String>[];
    final version = decoded['export_version'];
    if (version == null) {
      warnings.add('Missing export_version. Attempting best-effort import.');
    } else if (version is! int || version > exportVersion) {
      warnings.add('Export version is unsupported or newer than this app.');
    }
    final exportedAt = decoded['exported_at'];
    if (exportedAt == null || DateTime.tryParse(exportedAt.toString()) == null) {
      warnings.add('Missing or invalid exported_at.');
    }

    List<Task> parseTasksField(String key) {
      final value = decoded[key];
      if (value is! List) return <Task>[];
      return value
          .whereType<Map>()
          .map((e) => Task.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    Map<String, DailyTaskStats> parseDailyStatsField() {
      final value = decoded['daily_stats'];
      if (value is! List) return <String, DailyTaskStats>{};
      final stats = value
          .whereType<Map>()
          .map((e) => DailyTaskStats.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.dayKey.isNotEmpty)
          .toList();
      return {for (final item in stats) item.dayKey: item};
    }

    final tasks = parseTasksField('tasks');
    final deletedTasks = parseTasksField('deleted_tasks');
    final dailyStatsByDay = parseDailyStatsField();
    if (!decoded.containsKey('task_events')) {
      warnings
          .add('Missing task_events in export; some lifecycle analytics may be incomplete.');
    }

    _ensureUniqueIds(tasks);
    _ensureUniqueIds(deletedTasks);
    _trimDeletedTasks(deletedTasks);

    return TaskImportBundle(
      tasks: tasks,
      deletedTasks: deletedTasks,
      dailyStatsByDay: dailyStatsByDay,
      warnings: warnings,
    );
  }
}

extension on TaskImportBundle {
  TaskImportBundle copyWith({
    List<Task>? tasks,
    List<Task>? deletedTasks,
    Map<String, DailyTaskStats>? dailyStatsByDay,
    List<String>? warnings,
  }) {
    return TaskImportBundle(
      tasks: tasks ?? this.tasks,
      deletedTasks: deletedTasks ?? this.deletedTasks,
      dailyStatsByDay: dailyStatsByDay ?? this.dailyStatsByDay,
      warnings: warnings ?? this.warnings,
    );
  }
}
