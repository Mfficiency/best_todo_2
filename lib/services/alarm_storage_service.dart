import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/alarm.dart';

/// Persists the list of alarms to a JSON file in the application documents
/// directory, mirroring [StorageService] used for tasks.
class AlarmStorageService {
  static const _fileName = 'alarms.json';

  Future<File> _getLocalFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  void _ensureUniqueIds(List<Alarm> alarms) {
    final ids = <String>{};
    for (final a in alarms) {
      if (a.uid.isEmpty || ids.contains(a.uid)) {
        a.uid = Alarm.newUid();
      }
      ids.add(a.uid);
    }
  }

  Future<void> saveAlarms(List<Alarm> alarms) async {
    final file = await _getLocalFile();
    final jsonString = jsonEncode(alarms.map((a) => a.toJson()).toList());
    await file.writeAsString(jsonString, flush: true);
  }

  Future<List<Alarm>> loadAlarms() async {
    try {
      final file = await _getLocalFile();
      if (!await file.exists()) {
        return <Alarm>[];
      }
      final contents = await file.readAsString();
      final List<dynamic> data = jsonDecode(contents);
      final alarms =
          data.map((e) => Alarm.fromJson(e as Map<String, dynamic>)).toList();
      _ensureUniqueIds(alarms);
      return alarms;
    } catch (_) {
      return <Alarm>[];
    }
  }
}
