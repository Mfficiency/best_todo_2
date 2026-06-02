import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/countdown_timer.dart';
import '../models/daily_task_stats.dart';
import '../models/task.dart';

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
  static const _dailyStatsFileName = 'daily_task_stats.json';
  static const _dateFileName = 'last_opened.txt';
  static const _countdownFileName = 'countdown_timers.json';
  static const _maxDeletedTasks = 100;
  static const int exportVersion = 2;

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

  Future<File> _getDailyStatsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_dailyStatsFileName');
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

  Future<void> saveTaskList(List<Task> tasks) async {
    final file = await _getLocalFile();
    final jsonString = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await file.writeAsString(jsonString, flush: true);
  }

  Future<void> saveDeletedTaskList(List<Task> tasks) async {
    final file = await _getDeletedFile();
    _trimDeletedTasks(tasks);
    final jsonString = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await file.writeAsString(jsonString, flush: true);
  }

  Future<List<Task>> loadDeletedTaskList() async {
    try {
      final file = await _getDeletedFile();
      if (!await file.exists()) {
        return <Task>[];
      }
      final contents = await file.readAsString();
      final List<dynamic> data = jsonDecode(contents);
      final tasks = data
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
      _ensureUniqueIds(tasks);
      _trimDeletedTasks(tasks);
      return tasks;
    } catch (_) {
      return <Task>[];
    }
  }

  Future<List<Task>> loadTaskList() async {
    try {
      final isNewDay = await _isNewDay();
      final file = await _getLocalFile();
      if (!await file.exists()) {
        return <Task>[];
      }
      final contents = await file.readAsString();
      final List<dynamic> data = jsonDecode(contents);
      final tasks = data
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
      _ensureUniqueIds(tasks);
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
        await saveTaskList(tasks);
      }
      return tasks;
    } catch (_) {
      return <Task>[];
    }
  }

  Future<void> saveDailyTaskStats(
      Map<String, DailyTaskStats> dailyStatsByDay) async {
    final file = await _getDailyStatsFile();
    final jsonString = jsonEncode(
      dailyStatsByDay.values.map((stats) => stats.toJson()).toList(),
    );
    await file.writeAsString(jsonString, flush: true);
  }

  Future<Map<String, DailyTaskStats>> loadDailyTaskStats() async {
    try {
      final file = await _getDailyStatsFile();
      if (!await file.exists()) {
        return <String, DailyTaskStats>{};
      }
      final contents = await file.readAsString();
      final List<dynamic> data = jsonDecode(contents);
      final values = data
          .map((e) => DailyTaskStats.fromJson(e as Map<String, dynamic>))
          .where((stats) => stats.dayKey.isNotEmpty)
          .toList();
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
    final file = await _getCountdownFile();
    final jsonString = jsonEncode(timers.map((t) => t.toJson()).toList());
    await file.writeAsString(jsonString, flush: true);
  }

  /// Loads saved countdown timers. Returns `null` when no timers file exists
  /// yet, so callers can distinguish a first run from an intentionally empty
  /// list.
  Future<List<CountdownTimerItem>?> loadCountdownTimers() async {
    try {
      final file = await _getCountdownFile();
      if (!await file.exists()) {
        return null;
      }
      final contents = await file.readAsString();
      final List<dynamic> data = jsonDecode(contents);
      return data
          .map((e) => CountdownTimerItem.fromJson(e as Map<String, dynamic>))
          .toList();
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
      final file = File(path);
      final jsonString = jsonEncode(buildTaskExportPayload(
        tasks: tasks,
        deletedTasks: deletedTasks,
        dailyStatsByDay: dailyStatsByDay,
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
          .map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    Map<String, DailyTaskStats> parseDailyStatsField() {
      final value = decoded['daily_stats'];
      if (value is! List) return <String, DailyTaskStats>{};
      final stats = value
          .whereType<Map>()
          .map((e) => DailyTaskStats.fromJson(Map<String, dynamic>.from(e as Map)))
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
