import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/sms_report_log_entry.dart';

class SmsReportLogService {
  static const _fileName = 'sms_report_log.json';
  static const int _maxEntries = 500;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<SmsReportLogEntry>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <SmsReportLogEntry>[];
      final data = jsonDecode(await file.readAsString());
      if (data is! List) return <SmsReportLogEntry>[];
      return data
          .whereType<Map>()
          .map((e) =>
              SmsReportLogEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return <SmsReportLogEntry>[];
    }
  }

  static Future<void> append(SmsReportLogEntry entry) async {
    final existing = await load();
    existing.insert(0, entry);
    if (existing.length > _maxEntries) {
      existing.removeRange(_maxEntries, existing.length);
    }
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode(existing.map((e) => e.toJson()).toList()),
        flush: true,
      );
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
