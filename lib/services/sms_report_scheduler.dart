import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sms_report_config.dart';
import 'sms_report_config_service.dart';
import 'sms_report_service.dart';

/// Fixed alarm id so re-scheduling replaces the previous registration.
const int kSmsReportAlarmId = 0x517D;

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

  /// Requests the runtime permissions the background alarm needs to fire
  /// reliably. Call this when the user enables the report (needs a UI
  /// context so the system dialogs can appear):
  ///   • [Permission.scheduleExactAlarm] — Android 12+ gates exact alarms
  ///     behind a user grant; without it AndroidAlarmManager falls back to
  ///     inexact timing (or nothing).
  ///   • [Permission.ignoreBatteryOptimizations] — the big one: OEM Doze /
  ///     "Sleeping apps" (Samsung One UI, etc.) deep-sleep background apps
  ///     and silently drop their alarms unless the app is whitelisted.
  ///   • [Permission.notification] — so any user-facing report notice can
  ///     be shown.
  /// Each request is best-effort; a denial is logged by the caller's flow,
  /// not thrown.
  static Future<void> ensureBackgroundPermissions() async {
    if (!_isAndroidNative) return;
    try {
      if (!await Permission.scheduleExactAlarm.isGranted) {
        await Permission.scheduleExactAlarm.request();
      }
    } catch (_) {}
    try {
      if (!await Permission.ignoreBatteryOptimizations.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
    try {
      if (!await Permission.notification.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}
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

  static DateTime _nextFireTime(int hour, int minute) {
    final now = DateTime.now();
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}
