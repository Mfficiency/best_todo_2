import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:home_widget/home_widget.dart';

import '../models/task.dart';

class StorageService {
  static const _fileName = 'tasks.json';

  Future<File> _getLocalFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> saveTaskList(List<Task> tasks) async {
    final file = await _getLocalFile();
    final jsonString = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await file.writeAsString(jsonString, flush: true);
    final dueTasks = _buildDueTasksString(tasks);
    await HomeWidget.saveWidgetData('due_tasks', dueTasks);
    await HomeWidget.updateWidget(
      androidName: 'VersionWidgetProvider',
    );
  }

  Future<List<Task>> loadTaskList() async {
    try {
      final file = await _getLocalFile();
      if (!await file.exists()) {
        return <Task>[];
      }
      final contents = await file.readAsString();
      final List<dynamic> data = jsonDecode(contents);
      return data
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <Task>[];
    }
  }
}

String _buildDueTasksString(List<Task> tasks) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final lines = tasks.where((t) {
    final due = t.dueDate;
    return due != null && !t.isDone && !due.isAfter(today);
  }).map((t) => '• ${t.title}').toList();
  if (lines.isEmpty) {
    return '• cow';
  }
  return lines.join('\n');
}
