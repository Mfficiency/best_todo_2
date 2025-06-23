import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
