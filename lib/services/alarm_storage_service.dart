import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/alarm.dart';
import 'pre_update_backup.dart';
import 'safe_file.dart';

/// Persists the list of alarms to a JSON file in the application documents
/// directory, mirroring [StorageService] used for tasks — including the
/// upgrade-safety guarantees (atomic writes with a .bak of the previous
/// content, corrupt-file quarantine + backup fallback on load, and the
/// one-time pre-update snapshot before the first write).
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
    await PreUpdateBackup.ensure();
    final file = await _getLocalFile();
    for (final alarm in alarms) {
      alarm.tags = Alarm.ensureAlarmTag(alarm.tags);
    }
    final jsonString = jsonEncode(alarms.map((a) => a.toJson()).toList());
    await SafeFile.writeString(file, jsonString);
  }

  Future<List<Alarm>> loadAlarms() async {
    try {
      final file = await _getLocalFile();
      final alarms = await SafeFile.readWithRecovery(
            file,
            (contents) => (jsonDecode(contents) as List<dynamic>)
                .map((e) => Alarm.fromJson(e as Map<String, dynamic>))
                .toList(),
          ) ??
          <Alarm>[];
      _ensureUniqueIds(alarms);
      return alarms;
    } catch (_) {
      return <Alarm>[];
    }
  }
}
