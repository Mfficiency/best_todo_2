import 'dart:convert';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../models/sms_report_config.dart';
import '../models/sms_report_log_entry.dart';
import '../models/sms_recipient.dart';
import 'sms_report_config_service.dart';
import 'sms_report_log_service.dart';
import 'sms_report_service.dart';

/// Legacy fixed id of the single daily alarm used before per-recipient
/// timing existed. Kept only so `schedule()`/`cancel()` can clear any alarm
/// still pending under it on an app that just updated.
const int kSmsReportAlarmId = 0x517D;

/// Base of the per-time-slot alarm id range: one alarm per distinct
/// (hour, minute) any active recipient is currently scheduled at (recipients
/// without their own time share the config's global slot). `id = base +
/// minuteOfDay`, minuteOfDay in 0..1439, so ids span
/// [0x20002000, 0x20002597] — inside the app's fixed-id space (see
/// alarm_ids.dart) and clear of the per-task alarm/watchdog id ranges used by
/// the primary (non-SMS) alarm pipeline.
const int _kSmsSlotAlarmBase = 0x20002000;

int _smsSlotAlarmId(int minuteOfDay) => _kSmsSlotAlarmBase + minuteOfDay;

int? _smsSlotMinuteOfDay(int alarmId) {
  final delta = alarmId - _kSmsSlotAlarmBase;
  if (delta < 0 || delta > 1439) return null;
  return delta;
}

const String _kSlotRegistryPrefsKey = 'sms_report_slot_alarm_ids_v1';

bool get _isAndroidNative =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Top-level entry point invoked from the background isolate when one of the
/// daily per-time-slot alarms fires. Must be a top-level/static function and
/// annotated `@pragma('vm:entry-point')`. `id` is the specific alarm that
/// fired (`android_alarm_manager_plus` passes it through), decoded back into
/// the (hour, minute) slot it represents.
///
/// Re-arms every slot's next occurrence FIRST, so a crash in the report
/// itself can't break the daily chain, then runs the report scoped to just
/// this slot's recipients.
@pragma('vm:entry-point')
Future<void> smsReportAlarmCallback(int id) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final slotMinuteOfDay = _smsSlotMinuteOfDay(id);
  try {
    await SmsReportLogService.append(SmsReportLogEntry(
      sentAt: DateTime.now(),
      kind: SmsLogKind.diag,
      message: slotMinuteOfDay == null
          ? 'Alarm fired — running report in background'
          : 'Alarm fired for slot '
              '${(slotMinuteOfDay ~/ 60).toString().padLeft(2, '0')}:'
              '${(slotMinuteOfDay % 60).toString().padLeft(2, '0')}'
              ' — running report in background',
      success: true,
    ));
  } catch (_) {}
  try {
    await SmsReportScheduler.applyFromConfig();
  } catch (_) {}
  try {
    await SmsReportService.runDailyReport(slotMinuteOfDay: slotMinuteOfDay);
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
    // The feature can be switched off wholesale in Settings → Mode & features
    // (and always is in simple mode); that must also stop the daily alarm,
    // not just hide its settings.
    if (!Config.isFeatureEnabled('sms_report') ||
        !config.enabled ||
        config.recipients.isEmpty) {
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

  /// Distinct (hour, minute) slots, as minute-of-day, that at least one
  /// active recipient is currently scheduled at — a recipient with no
  /// [SmsRecipient.hour]/`.minute` of their own uses the config's global
  /// slot ([SmsReportConfig.hour]/`.minute`).
  static Set<int> activeSlotMinutes(SmsReportConfig config) {
    final slots = <int>{};
    for (final r in config.activeRecipients) {
      final t = config.timeFor(r);
      slots.add(t.hour * 60 + t.minute);
    }
    return slots;
  }

  static Future<Set<int>> _readSlotRegistry() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSlotRegistryPrefsKey);
      if (raw == null || raw.isEmpty) return <int>{};
      return (jsonDecode(raw) as List).map((e) => e as int).toSet();
    } catch (_) {
      return <int>{};
    }
  }

  static Future<void> _writeSlotRegistry(Set<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kSlotRegistryPrefsKey, jsonEncode(ids.toList()));
    } catch (_) {}
  }

  /// Schedules one one-shot alarm per distinct time slot in use instead of a
  /// repeating one. `AndroidAlarmManager.periodic(exact: true)` maps to
  /// `AlarmManager.setRepeating`, which Android treats as INEXACT since
  /// API 19 and which ignores `allowWhileIdle` — in Doze / OEM deep sleep
  /// the alarm is deferred indefinitely, so it never fires while the app
  /// isn't running. A one-shot with exact+wakeup+allowWhileIdle maps to
  /// `setExactAndAllowWhileIdle`, which fires even in Doze. Firing a slot's
  /// alarm re-arms every slot's next occurrence (see [smsReportAlarmCallback]),
  /// and [applyFromConfig] on every app launch restores the whole chain if it
  /// was ever lost (e.g. after a force-stop, which clears all alarms).
  static Future<void> schedule(SmsReportConfig config) async {
    if (!_isAndroidNative) return;
    await initialize();
    // Migration: drop any alarm still pending under the pre-per-recipient-
    // timing single-id scheme.
    await AndroidAlarmManager.cancel(kSmsReportAlarmId);

    final oldIds = await _readSlotRegistry();
    final slots = activeSlotMinutes(config);
    final newIds = slots.map(_smsSlotAlarmId).toSet();

    for (final id in oldIds) {
      if (!newIds.contains(id)) {
        await AndroidAlarmManager.cancel(id);
      }
    }

    final armed = <int>{};
    for (final minuteOfDay in slots) {
      final id = _smsSlotAlarmId(minuteOfDay);
      await AndroidAlarmManager.cancel(id);
      final ok = await AndroidAlarmManager.oneShotAt(
        _nextFireTime(minuteOfDay ~/ 60, minuteOfDay % 60),
        id,
        smsReportAlarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
        allowWhileIdle: true,
      );
      if (ok) armed.add(id);
    }
    await _writeSlotRegistry(armed);
  }

  static Future<void> cancel() async {
    if (!_isAndroidNative) return;
    await initialize();
    await AndroidAlarmManager.cancel(kSmsReportAlarmId);
    final ids = await _readSlotRegistry();
    for (final id in ids) {
      await AndroidAlarmManager.cancel(id);
    }
    await _writeSlotRegistry(<int>{});
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
