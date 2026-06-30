import 'dart:async';

import 'package:another_telephony/telephony.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sms_recipient.dart';
import '../models/sms_report_config.dart';
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

  /// True if the report should fire given a summary and the configured
  /// completion-threshold. Returns the percentage and a human-readable
  /// reason for skipping (or null if it should send).
  static ({bool shouldSend, int percent, String? skipReason}) checkThreshold(
    SmsReportConfig config,
    SmsReportSummary summary,
  ) {
    final total = summary.completedCount + summary.uncompletedCount;
    final percent = total == 0
        ? 100
        : ((summary.completedCount * 100) / total).round();
    if (!config.thresholdEnabled) {
      return (shouldSend: true, percent: percent, skipReason: null);
    }
    if (total == 0) {
      return (
        shouldSend: false,
        percent: percent,
        skipReason: 'no tasks today',
      );
    }
    if (percent < config.completionThresholdPercent) {
      return (shouldSend: true, percent: percent, skipReason: null);
    }
    return (
      shouldSend: false,
      percent: percent,
      skipReason:
          'completion $percent% ≥ threshold ${config.completionThresholdPercent}%',
    );
  }

  /// Loads config, computes summary, sends SMS to each recipient, logs each.
  /// Returns the number of successful sends.
  static Future<int> runDailyReport() async {
    final config = await SmsReportConfigService.load();

    if (!config.enabled) {
      await _diag('Skipped — report disabled', success: false);
      return 0;
    }
    if (config.recipients.isEmpty) {
      await _diag('Skipped — no recipients configured', success: false);
      return 0;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      await _diag('Skipped — not on Android', success: false);
      return 0;
    }

    SmsReportSummary summary;
    try {
      summary = await computeSummary();
    } catch (e, st) {
      await _diag('Skipped — failed to read tasks',
          success: false, error: '$e\n$st');
      return 0;
    }

    final thresholdCheck = checkThreshold(config, summary);
    if (!thresholdCheck.shouldSend) {
      await _diag(
        'Skipped — ${thresholdCheck.skipReason} '
        '(${summary.completedCount}/${summary.completedCount + summary.uncompletedCount} done)',
        success: false,
      );
      return 0;
    }

    PermissionStatus permStatus;
    try {
      permStatus = await Permission.sms.status;
      if (!permStatus.isGranted) {
        permStatus = await Permission.sms.request();
      }
    } catch (e, st) {
      await _diag('Skipped — permission check failed',
          success: false, error: '$e\n$st');
      return 0;
    }
    if (!permStatus.isGranted) {
      await _diag('Skipped — SMS permission not granted ($permStatus)',
          success: false);
      return 0;
    }

    final telephony = Telephony.instance;
    try {
      final capable = await telephony.isSmsCapable;
      if (capable == false) {
        await _diag('Skipped — device not SMS-capable', success: false);
        return 0;
      }
    } catch (_) {
      // Non-fatal — fall through and attempt to send.
    }

    var sent = 0;
    for (final recipient in config.recipients) {
      final phone = recipient.phoneNumber.trim();
      final nick = recipient.nickname.trim();
      if (phone.isEmpty) {
        await _diag('Skipped recipient "$nick" — empty phone number',
            success: false);
        continue;
      }
      final message = renderTemplate(
        template: config.template,
        recipient: recipient,
        summary: summary,
      );

      final isNonAscii = message.runes.any((r) => r > 127);
      final isMultipart = message.length > (isNonAscii ? 70 : 160);

      final statusCompleter = Completer<String>();
      final statusEvents = <String>[];
      final timeoutTimer = Timer(const Duration(seconds: 20), () {
        if (!statusCompleter.isCompleted) {
          statusCompleter.complete('TIMEOUT (received: '
              '${statusEvents.isEmpty ? "none" : statusEvents.join(",")})');
        }
      });

      var dispatched = false;
      String? error;
      try {
        await telephony.sendSms(
          to: phone,
          message: message,
          subscriptionId: config.subscriptionId,
          isMultipart: isMultipart,
          statusListener: (SendStatus status) {
            statusEvents.add(status.toString());
            if (!statusCompleter.isCompleted) {
              statusCompleter.complete(status.toString());
            }
          },
        );
        dispatched = true;
      } catch (e, st) {
        error = '$e\n$st';
        timeoutTimer.cancel();
        if (!statusCompleter.isCompleted) {
          statusCompleter.complete('THROWN: $e');
        }
      }

      final statusResult = await statusCompleter.future;
      timeoutTimer.cancel();
      final success = dispatched &&
          !statusResult.startsWith('TIMEOUT') &&
          !statusResult.startsWith('THROWN');

      await SmsReportLogService.append(SmsReportLogEntry(
        sentAt: DateTime.now(),
        kind: SmsLogKind.send,
        recipientNickname: nick,
        recipientPhone: phone,
        message: message,
        success: success,
        error: success ? null : (error ?? statusResult),
        completedCount: summary.completedCount,
        uncompletedCount: summary.uncompletedCount,
      ));

      if (success) sent++;
    }

    final total = summary.completedCount + summary.uncompletedCount;
    await _diag('Sent $sent/${config.recipients.length} • '
        '${summary.completedCount}/$total done (${thresholdCheck.percent}%)');
    return sent;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static String _two(int n) => n.toString().padLeft(2, '0');
}
