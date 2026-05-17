import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

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

  static Future<void> _diag(String message, {bool success = true, String? error}) {
    return SmsReportLogService.append(SmsReportLogEntry(
      sentAt: DateTime.now(),
      kind: SmsLogKind.diag,
      message: message,
      success: success,
      error: error,
    ));
  }

  /// Loads config, computes summary, sends SMS to each recipient, logs each.
  /// Returns the number of successful sends.
  static Future<int> runDailyReport() async {
    await _diag('runDailyReport start');

    final config = await SmsReportConfigService.load();
    await _diag('config loaded: enabled=${config.enabled} '
        'time=${_two(config.hour)}:${_two(config.minute)} '
        'recipients=${config.recipients.length}');

    if (!config.enabled) {
      await _diag('aborted: report disabled', success: false);
      return 0;
    }
    if (config.recipients.isEmpty) {
      await _diag('aborted: no recipients configured', success: false);
      return 0;
    }

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      await _diag('aborted: not on Android (platform=$defaultTargetPlatform)',
          success: false);
      return 0;
    }

    SmsReportSummary summary;
    try {
      summary = await computeSummary();
      await _diag('summary computed: completed=${summary.completedCount} '
          'uncompleted=${summary.uncompletedCount}');
    } catch (e, st) {
      await _diag('summary failed', success: false, error: '$e\n$st');
      return 0;
    }

    PermissionStatus permStatus;
    try {
      permStatus = await Permission.sms.status;
      await _diag('sms permission status (pre-request): $permStatus');
      if (!permStatus.isGranted) {
        permStatus = await Permission.sms.request();
        await _diag('sms permission status (post-request): $permStatus');
      }
    } catch (e, st) {
      await _diag('permission check threw',
          success: false, error: '$e\n$st');
      return 0;
    }

    if (!permStatus.isGranted) {
      await _diag('aborted: sms permission not granted ($permStatus)',
          success: false);
      return 0;
    }

    final telephony = Telephony.instance;

    var sent = 0;
    for (final recipient in config.recipients) {
      final phone = recipient.phoneNumber.trim();
      final nick = recipient.nickname.trim();
      if (phone.isEmpty) {
        await _diag('skipped recipient "$nick": empty phone number',
            success: false);
        continue;
      }
      final message = renderTemplate(
        template: config.template,
        recipient: recipient,
        summary: summary,
      );

      var success = false;
      String? error;
      try {
        await telephony.sendSms(to: phone, message: message);
        success = true;
      } catch (e, st) {
        error = '$e\n$st';
      }

      await SmsReportLogService.append(SmsReportLogEntry(
        sentAt: DateTime.now(),
        kind: SmsLogKind.send,
        recipientNickname: nick,
        recipientPhone: phone,
        message: message,
        success: success,
        error: error,
        completedCount: summary.completedCount,
        uncompletedCount: summary.uncompletedCount,
      ));

      if (success) {
        sent++;
      } else {
        await _diag('send failed to $phone',
            success: false, error: error);
      }
    }

    await _diag('runDailyReport done: $sent/${config.recipients.length} sent');
    return sent;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static String _two(int n) => n.toString().padLeft(2, '0');
}
