import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/sms_report_config.dart';
import '../models/sms_report_log_entry.dart';
import 'sms_report_config_service.dart';
import 'sms_report_log_service.dart';
import 'sms_report_service.dart';

/// Fixed alarm id so re-scheduling replaces the previous registration.
const int kSmsReportAlarmId = 0x517D;

/// Separate id for the one-shot background self-test so it never disturbs the
/// real daily schedule.
const int kSmsReportTestAlarmId = 0x517E;

bool get _isAndroidNative =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Top-level entry point invoked from the background isolate when the daily
/// alarm fires. Must be a top-level/static function and annotated
/// `@pragma('vm:entry-point')`.
@pragma('vm:entry-point')
Future<void> smsReportAlarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    await SmsReportService.runDailyReport();
  } catch (_) {}
}

/// Entry point for the one-shot background self-test. It runs in the *same*
/// kind of background isolate as [smsReportAlarmCallback], so if this delivers
/// an SMS while the app is swiped away, the real daily report will too.
///
/// It first writes a diagnostic log entry as unambiguous proof the isolate
/// actually woke up (independent of whether an SMS is later sent/skipped),
/// then runs the identical report path.
@pragma('vm:entry-point')
Future<void> smsReportTestAlarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    await SmsReportLogService.append(SmsReportLogEntry(
      sentAt: DateTime.now(),
      kind: SmsLogKind.diag,
      message: 'Background self-test: alarm fired, isolate is awake. '
          'Running report path now…',
      success: true,
    ));
  } catch (_) {}
  try {
    await SmsReportService.runDailyReport();
  } catch (e, st) {
    try {
      await SmsReportLogService.append(SmsReportLogEntry(
        sentAt: DateTime.now(),
        kind: SmsLogKind.diag,
        message: 'Background self-test: report path threw',
        success: false,
        error: '$e\n$st',
      ));
    } catch (_) {}
  }
}

class SmsReportScheduler {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized || !_isAndroidNative) return;
    await AndroidAlarmManager.initialize();
    _initialized = true;
  }

  /// Reads config and schedules / cancels the daily alarm accordingly.
  static Future<void> applyFromConfig() async {
    if (!_isAndroidNative) return;
    await initialize();
    final config = await SmsReportConfigService.load();
    if (!config.enabled || config.recipients.isEmpty) {
      await cancel();
      return;
    }
    await schedule(config);
  }

  static Future<void> schedule(SmsReportConfig config) async {
    if (!_isAndroidNative) return;
    await initialize();
    await AndroidAlarmManager.cancel(kSmsReportAlarmId);
    final fireAt = _nextFireTime(config.hour, config.minute);
    await AndroidAlarmManager.periodic(
      const Duration(days: 1),
      kSmsReportAlarmId,
      smsReportAlarmCallback,
      startAt: fireAt,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      allowWhileIdle: true,
    );
  }

  static Future<void> cancel() async {
    if (!_isAndroidNative) return;
    await initialize();
    await AndroidAlarmManager.cancel(kSmsReportAlarmId);
  }

  /// Schedules a one-shot real alarm [delay] from now that drives the exact
  /// same background-isolate report path as the daily report. Use this to
  /// verify, end-to-end, that SMS is delivered while the app is not running:
  /// tap the test, immediately swipe the app away from Recents, and wait.
  ///
  /// Returns false when not on Android native (nothing scheduled).
  static Future<bool> scheduleTestIn(Duration delay) async {
    if (!_isAndroidNative) return false;
    await initialize();
    await AndroidAlarmManager.cancel(kSmsReportTestAlarmId);
    await AndroidAlarmManager.oneShotAt(
      DateTime.now().add(delay),
      kSmsReportTestAlarmId,
      smsReportTestAlarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: false,
      allowWhileIdle: true,
    );
    return true;
  }

  /// Cancels a pending background self-test alarm, if any.
  static Future<void> cancelTest() async {
    if (!_isAndroidNative) return;
    await initialize();
    await AndroidAlarmManager.cancel(kSmsReportTestAlarmId);
  }

  static DateTime _nextFireTime(int hour, int minute) {
    final now = DateTime.now();
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}
