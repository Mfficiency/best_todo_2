import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/daily_task_stats.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

Map<DateTime, int> _deletedHeatMap(List<Task> deleted) {
  final result = <DateTime, int>{};
  for (final t in deleted) {
    final at = t.deletedAt;
    if (at == null) continue;
    final day = _dateOnly(at);
    result[day] = (result[day] ?? 0) + 1;
  }
  return result;
}

void main() {
  test('export/import preserves analytics data structures', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    final service = StorageService();
    final now = DateTime.now();
    final tasks = <Task>[
      Task(
        uid: 't1',
        title: 'Open task',
        createdAt: now.subtract(const Duration(days: 2, hours: 3)),
        dueDate: now,
        movedAt: now.subtract(const Duration(days: 1, hours: 1)),
        rescheduledAt: now.subtract(const Duration(days: 1, hours: 1)),
      ),
      Task(
        uid: 't2',
        title: 'Done task',
        createdAt: now.subtract(const Duration(days: 1, hours: 4)),
        completedAt: now.subtract(const Duration(hours: 6)),
        isDone: true,
        dueDate: now,
      ),
    ];
    final deleted = <Task>[
      Task(
        uid: 'd1',
        title: 'Deleted task',
        createdAt: now.subtract(const Duration(days: 4)),
        completedAt: now.subtract(const Duration(days: 3)),
        movedAt: now.subtract(const Duration(days: 2)),
        deletedAt: now.subtract(const Duration(days: 1)),
        isDone: true,
      ),
    ];
    final key = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final daily = <String, DailyTaskStats>{
      key: DailyTaskStats(
        dayKey: key,
        openingTaskIds: {'t1', 't2'},
        movedFromOpeningTaskIds: {'t1'},
        completedFromOpeningTaskIds: {'t2'},
        createdDuringDayTaskIds: {'t3'},
        completedFromCreatedTaskIds: {'t3'},
      ),
    };

    final exportFile = File('${tempDir.path}/export_v2.json');
    final written = await service.exportTaskData(
      tasks: tasks,
      deletedTasks: deleted,
      dailyStatsByDay: daily,
      path: exportFile.path,
    );
    expect(written, isNotNull);

    final imported = await service.importTaskData(exportFile.path);
    expect(imported.warnings, isEmpty);
    expect(imported.tasks.map((t) => t.uid).toSet(), {'t1', 't2'});
    expect(imported.deletedTasks.map((t) => t.uid).toSet(), {'d1'});
    expect(imported.dailyStatsByDay.keys, daily.keys);
    expect(
      imported.dailyStatsByDay[key]!.movedFromOpeningTaskIds,
      {'t1'},
    );
    expect(
      _deletedHeatMap(imported.deletedTasks),
      _deletedHeatMap(deleted),
    );
  });

  test('legacy list export still imports with warnings', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    final file = File('${tempDir.path}/legacy.json');
    await file.writeAsString(jsonEncode([
      {'uid': 'x', 'title': 'legacy item'}
    ]));

    final service = StorageService();
    final imported = await service.importTaskData(file.path);
    expect(imported.tasks.length, 1);
    expect(imported.tasks.first.uid, 'x');
    expect(imported.deletedTasks, isEmpty);
    expect(imported.dailyStatsByDay, isEmpty);
    expect(imported.warnings, isNotEmpty);
  });

  test('versioned export contains lifecycle and analytics fields', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    final service = StorageService();
    final file = File('${tempDir.path}/schema_check.json');

    await service.exportTaskData(
      tasks: [Task(uid: 'a', title: 'A', createdAt: DateTime.now())],
      deletedTasks: [Task(uid: 'b', title: 'B', deletedAt: DateTime.now())],
      dailyStatsByDay: const <String, DailyTaskStats>{},
      path: file.path,
    );
    final payload = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(payload['export_version'], 2);
    expect(payload.containsKey('exported_at'), isTrue);
    expect(payload.containsKey('tasks'), isTrue);
    expect(payload.containsKey('deleted_tasks'), isTrue);
    expect(payload.containsKey('daily_stats'), isTrue);
    expect(payload.containsKey('task_events'), isTrue);
    expect(payload.containsKey('labels'), isTrue);
    expect(payload.containsKey('projects'), isTrue);
  });
}

