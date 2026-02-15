import 'dart:io';
import 'dart:convert';

import 'package:best_todo_2/models/task.dart';
import 'package:best_todo_2/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  test('loadTaskList removes completed tasks on new day', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    final service = StorageService();
    final tasks = [
      Task(title: 'done', isDone: true),
      Task(title: 'pending'),
    ];
    await service.saveTaskList(tasks);

    final dateFile = File('${tempDir.path}/last_opened.txt');
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await dateFile.writeAsString(yesterday.toIso8601String());

    final loaded = await service.loadTaskList();
    expect(loaded.length, 1);
    expect(loaded.first.title, 'pending');

    final deleted = await service.loadDeletedTaskList();
    expect(deleted.length, 1);
    expect(deleted.first.title, 'done');
  });

  test('importTaskList assigns unique ids when missing or duplicated', () async {
    final tempDir = await Directory.systemTemp.createTemp();
    final file = File('${tempDir.path}/tasks.json');
    final data = [
      {'title': 'a', 'uid': 'same'},
      {'title': 'b', 'uid': 'same'},
      {'title': 'c'},
    ];
    await file.writeAsString(jsonEncode(data));
    final service = StorageService();
    final tasks = await service.importTaskList(file.path);
    expect(tasks.length, 3);
    final ids = tasks.map((t) => t.uid).toSet();
    expect(ids.length, 3);
  });
}
