import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/sms_report_config.dart';
import '../models/sms_report_log_entry.dart';
import 'sms_report_config_service.dart';
import 'sms_report_log_service.dart';
import 'sms_report_service.dart';

/// Fixed alarm id so re-scheduling replaces the previous registration.
const int kSmsReportAlarmId = 0x517D;

bool get _isAndroidNative =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Top-level entry point invoked from the background isolate when the daily
/// alarm fires. Must be a top-level/static function and annotated
/// `@pragma('vm:entry-point')`.
///
/// Re-arms the next day's one-shot alarm FIRST, so a crash in the report
/// itself can't break the daily chain, then runs the report.
@pragma('vm:entry-point')
Future<void> smsReportAlarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    await SmsReportLogService.append(SmsReportLogEntry(
      sentAt: DateTime.now(),
      kind: SmsLogKind.diag,
      message: 'Alarm fired — running report in background',
      success: true,
    ));
  } catch (_) {}
  try {
    await SmsReportScheduler.applyFromConfig();
  } catch (_) {}
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
  ///   • [Permission.sms] — must be granted HERE, in the foreground: the
  ///     background isolate has no Activity, so permission_handler cannot
  ///     show the dialog when the alarm fires and the send is skipped.
  /// Each request is best-effort; a denial is logged by the caller's flow,
  /// not thrown.
  static Future<void> ensureBackgroundPermissions() async {
    if (!_isAndroidNative) return;
    try {
      if (!await Permission.sms.isGranted) {
        await Permission.sms.request();
      }
    } catch (_) {}
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

  /// Schedules the next report as a one-shot alarm instead of a repeating
  /// one. `AndroidAlarmManager.periodic(exact: true)` maps to
  /// `AlarmManager.setRepeating`, which Android treats as INEXACT since
  /// API 19 and which ignores `allowWhileIdle` — in Doze / OEM deep sleep
  /// the alarm is deferred indefinitely, so it never fires while the app
  /// isn't running. A one-shot with exact+wakeup+allowWhileIdle maps to
  /// `setExactAndAllowWhileIdle`, which fires even in Doze. The callback
  /// re-arms the next day's alarm (see [smsReportAlarmCallback]), and
  /// [applyFromConfig] on every app launch restores the chain if it was
  /// ever lost (e.g. after a force-stop, which clears all alarms).
  static Future<void> schedule(SmsReportConfig config) async {
    if (!_isAndroidNative) return;
    await initialize();
    await AndroidAlarmManager.cancel(kSmsReportAlarmId);
    final fireAt = _nextFireTime(config.hour, config.minute);
    await AndroidAlarmManager.oneShotAt(
      fireAt,
      kSmsReportAlarmId,
      smsReportAlarmCallback,
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
    // Require at least a minute of headroom: when the callback re-arms the
    // chain right as the alarm fires, an alarm delivered a moment early
    // must not re-schedule (and re-fire) for the same day.
    if (!candidate.isAfter(now.add(const Duration(minutes: 1)))) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate;
  }
}
