import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/task.dart';

class StorageService {
  static const _fileName = 'tasks.json';
  static const _dateFileName = 'last_opened.txt';

  Future<File> _getLocalFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<File> _getDateFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_dateFileName');
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
      Task.ensureUniqueIds(tasks);
      if (isNewDay) {
        tasks.removeWhere((t) => t.isDone);
        await saveTaskList(tasks);
      }
      return tasks;
    } catch (_) {
      return <Task>[];
    }
  }

  Future<File?> exportTaskList(List<Task> tasks, String path) async {
    try {
      final file = File(path);
      final jsonString = jsonEncode(tasks.map((t) => t.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<List<Task>> importTaskList(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return <Task>[];
      final contents = await file.readAsString();
      final List<dynamic> data = jsonDecode(contents);
      final tasks = data
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
      Task.ensureUniqueIds(tasks);
      return tasks;
    } catch (_) {
      return <Task>[];
    }
  }
}
