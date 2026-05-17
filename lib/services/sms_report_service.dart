import 'dart:io' show Platform;

import 'package:another_telephony/telephony.dart';

import '../models/sms_recipient.dart';
import '../models/sms_report_log_entry.dart';
import '../models/task.dart';
import 'sms_report_config_service.dart';
import 'sms_report_log_service.dart';
import 'storage_service.dart';

class SmsReportSummary {
  final int completedCount;
  final int uncompletedCount;
  final List<String> uncompletedTitles;

  const SmsReportSummary({
    required this.completedCount,
    required this.uncompletedCount,
    required this.uncompletedTitles,
  });
}

class SmsReportService {
  /// Compute today's summary from the persisted task list.
  static Future<SmsReportSummary> computeSummary({DateTime? now}) async {
    final today = _dateOnly(now ?? DateTime.now());
    final tasks = await StorageService().loadTaskList();

    final completed = <Task>[];
    final uncompleted = <Task>[];
    for (final t in tasks) {
      final due = t.dueDate;
      if (due == null) continue;
      if (_dateOnly(due).isAfter(today)) continue;
      if (t.isDone) {
        final c = t.completedAt;
        if (c != null && _isSameDay(c, today)) completed.add(t);
      } else {
        uncompleted.add(t);
      }
    }

    return SmsReportSummary(
      completedCount: completed.length,
      uncompletedCount: uncompleted.length,
      uncompletedTitles: uncompleted.map((t) => t.title.trim()).toList(),
    );
  }

  /// Render the template with token substitutions for a recipient.
  static String renderTemplate({
    required String template,
    required SmsRecipient recipient,
    required SmsReportSummary summary,
    DateTime? now,
  }) {
    final date = now ?? DateTime.now();
    final dateStr =
        '${date.year}-${_two(date.month)}-${_two(date.day)}';
    final nick = recipient.nickname.trim();
    final hello = nick.isEmpty ? '' : 'Hello $nick';
    final list = summary.uncompletedTitles.isEmpty
        ? '(none)'
        : summary.uncompletedTitles.map((t) => '- $t').join('\n');

    return template
        .replaceAll('{hello}', hello)
        .replaceAll('{nickname}', nick)
        .replaceAll('{completed}', summary.completedCount.toString())
        .replaceAll('{uncompleted}', summary.uncompletedCount.toString())
        .replaceAll('{date}', dateStr)
        .replaceAll('{list}', list);
  }

  /// Loads config, computes summary, sends SMS to each recipient, logs each.
  /// Returns the number of successful sends.
  static Future<int> runDailyReport() async {
    final config = await SmsReportConfigService.load();
    if (!config.enabled || config.recipients.isEmpty) return 0;

    final summary = await computeSummary();
    final telephony =
        Platform.isAndroid ? Telephony.instance : null;
    if (telephony == null) return 0;

    final permitted = await telephony.requestPhoneAndSmsPermissions ?? false;

    var sent = 0;
    for (final recipient in config.recipients) {
      final phone = recipient.phoneNumber.trim();
      if (phone.isEmpty) continue;
      final message = renderTemplate(
        template: config.template,
        recipient: recipient,
        summary: summary,
      );

      var success = false;
      String? error;
      if (!permitted) {
        error = 'SMS permission denied';
      } else {
        try {
          await telephony.sendSms(to: phone, message: message);
          success = true;
        } catch (e) {
          error = e.toString();
        }
      }

      await SmsReportLogService.append(SmsReportLogEntry(
        sentAt: DateTime.now(),
        recipientNickname: recipient.nickname,
        recipientPhone: phone,
        message: message,
        success: success,
        error: error,
        completedCount: summary.completedCount,
        uncompletedCount: summary.uncompletedCount,
      ));

      if (success) sent++;
    }

    return sent;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static String _two(int n) => n.toString().padLeft(2, '0');
}
