import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/sms_report_config.dart';

class SmsReportConfigService {
  static const _fileName = 'sms_report_config.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<SmsReportConfig> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return SmsReportConfig();
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return SmsReportConfig.fromJson(data);
    } catch (_) {
      return SmsReportConfig();
    }
  }

  static Future<void> save(SmsReportConfig config) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(config.toJson()), flush: true);
    } catch (_) {}
  }
}
