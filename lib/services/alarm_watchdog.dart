import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/alarm.dart';
import 'alarm_ids.dart';
import 'alarm_log_service.dart';
import 'alarm_storage_service.dart';
import 'notification_service.dart';

/// Independent backup delivery path for alarms.
///
/// The primary path schedules alarms through flutter_local_notifications
/// (AlarmManager posting a notification natively). This watchdog arms a
/// SECOND, fully independent AlarmManager registration (android_alarm_manager
/// _plus, which wakes a Dart isolate) for ~90 seconds AFTER each alarm's fire
/// time. When it wakes it checks whether the alarm actually rang:
///
///   • notification still on screen, or the user already tapped / snoozed /
///     dismissed it  →  log [OK] FIRE — primary path delivered.
///   • neither       →  log [FAIL] FIRE and ring the alarm NOW via a direct
///     notification (about 1½ minutes late, but it rings), then log whether
///     that worked.
///
/// So even if one OS mechanism silently drops the alarm, the other still
/// fires — and the log records exactly which one failed. The only thing that
/// kills both is the user force-stopping the app (Android then cancels every
/// alarm of the app until it is opened again).
class AlarmWatchdog {
  AlarmWatchdog._();

  static const String _registryKey = 'alarm_watchdogs_v1';
  static const String _acksKey = 'alarm_fire_acks_v1';

  /// How long after the scheduled fire time the watchdog checks delivery.
  static const Duration grace = Duration(seconds: 90);

  static bool _managerReady = false;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> _ensureManager() async {
    if (!_isAndroid) return false;
    if (_managerReady) return true;
    try {
      await AndroidAlarmManager.initialize();
      _managerReady = true;
      return true;
    } catch (e) {
      await AlarmLog.fail(
          'BACKUP', 'AndroidAlarmManager init failed: $e — watchdog disabled');
      return false;
    }
  }

  static Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Other isolates (action handlers, alarm callbacks) write these keys too;
    // reload so a long-lived isolate doesn't act on a stale cache.
    try {
      await prefs.reload();
    } catch (_) {}
    return prefs;
  }

  static Map<String, dynamic> _readRegistry(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_registryKey);
      if (raw == null || raw.isEmpty) return <String, dynamic>{};
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  // ---------------------------------------------------------------------
  // Arming
  // ---------------------------------------------------------------------

  /// Re-arms one watchdog per enabled alarm (for its next occurrence),
  /// cancelling all previously armed ones first. Called after every
  /// (re)scheduling run so the registry always mirrors the alarm list.
  static Future<void> armAll(List<Alarm> alarms) async {
    if (!await _ensureManager()) return;
    final prefs = await _prefs();

    final old = _readRegistry(prefs);
    for (final key in old.keys) {
      final id = int.tryParse(key);
      if (id == null) continue;
      try {
        await AndroidAlarmManager.cancel(id);
      } catch (_) {}
    }
    if (old.isNotEmpty) {
      await AlarmLog.info(
          'BACKUP', 'cleared ${old.length} previously armed watchdog(s)');
    }

    final registry = <String, dynamic>{};
    for (final alarm in alarms) {
      if (!alarm.enabled) continue;
      final next = alarm.nextOccurrence();
      if (next == null) continue;
      final entry = await _armOne(
        watchdogId: alarmWatchdogId(alarm.uid),
        uid: alarm.uid,
        title: alarm.name.isEmpty ? 'Alarm' : alarm.name,
        body: alarm.description,
        vibrate: alarm.vibrate,
        notifIds: alarmNotificationIds(alarm.uid),
        fireAt: next,
        melody: alarm.melody,
        volume: alarm.volume,
        overrideDnd: alarm.overrideDnd,
      );
      if (entry != null) registry['${alarmWatchdogId(alarm.uid)}'] = entry;
    }
    await prefs.setString(_registryKey, jsonEncode(registry));
  }

  /// Watchdog for a snoozed fire. Reuses the alarm's watchdog slot; when it
  /// runs, [alarmWatchdogCallback] re-arms coverage for the alarm's next
  /// regular occurrence from storage, so nothing stays uncovered.
  static Future<void> armSnooze({
    required String uid,
    required String title,
    required String body,
    required bool vibrate,
    required DateTime fireAt,
    String? melody,
    double? volume,
    bool overrideDnd = false,
  }) async {
    if (!await _ensureManager()) return;
    final prefs = await _prefs();
    final registry = _readRegistry(prefs);
    final id = uid == kTestAlarmUid ? kTestAlarmWatchdogId : alarmWatchdogId(uid);
    final notifIds = uid == kTestAlarmUid
        ? [kTestAlarmNotificationId]
        : alarmNotificationIds(uid);
    final entry = await _armOne(
      watchdogId: id,
      uid: uid,
      title: title,
      body: body,
      vibrate: vibrate,
      notifIds: notifIds,
      fireAt: fireAt,
      label: 'snooze of ',
      melody: melody,
      volume: volume,
      overrideDnd: overrideDnd,
    );
    if (entry != null) {
      registry['$id'] = entry;
      await prefs.setString(_registryKey, jsonEncode(registry));
    }
  }

  /// Watchdog for the dice timer's end-of-countdown ring, so a dropped
  /// primary schedule still rings ~90 s late instead of never.
  static Future<void> armDiceTimer({
    required DateTime fireAt,
    required String title,
    required String body,
    required bool vibrate,
    String? melody,
    double? volume,
  }) async {
    if (!await _ensureManager()) return;
    final prefs = await _prefs();
    final registry = _readRegistry(prefs);
    final entry = await _armOne(
      watchdogId: kDiceTimerWatchdogId,
      uid: kDiceTimerUid,
      title: title,
      body: body,
      vibrate: vibrate,
      notifIds: [kDiceTimerNotificationId],
      fireAt: fireAt,
      melody: melody,
      volume: volume,
    );
    if (entry != null) {
      registry['$kDiceTimerWatchdogId'] = entry;
      await prefs.setString(_registryKey, jsonEncode(registry));
    }
  }

  /// Drops the dice timer watchdog when the countdown is paused, extended or
  /// finished early — nothing to verify once the ring is off the table.
  static Future<void> cancelDiceTimer() async {
    if (!_isAndroid) return;
    try {
      if (_managerReady) await AndroidAlarmManager.cancel(kDiceTimerWatchdogId);
    } catch (_) {}
    try {
      final prefs = await _prefs();
      final registry = _readRegistry(prefs);
      if (registry.remove('$kDiceTimerWatchdogId') != null) {
        await prefs.setString(_registryKey, jsonEncode(registry));
      }
    } catch (_) {}
  }

  /// Watchdog for the in-app test alarm.
  static Future<void> armTest({required DateTime fireAt}) async {
    if (!await _ensureManager()) return;
    final prefs = await _prefs();
    final registry = _readRegistry(prefs);
    final entry = await _armOne(
      watchdogId: kTestAlarmWatchdogId,
      uid: kTestAlarmUid,
      title: 'Test alarm',
      body: 'BestToDo alarm pipeline test',
      vibrate: true,
      notifIds: [kTestAlarmNotificationId],
      fireAt: fireAt,
    );
    if (entry != null) {
      registry['$kTestAlarmWatchdogId'] = entry;
      await prefs.setString(_registryKey, jsonEncode(registry));
    }
  }

  static Future<Map<String, dynamic>?> _armOne({
    required int watchdogId,
    required String uid,
    required String title,
    required String body,
    required bool vibrate,
    required List<int> notifIds,
    required DateTime fireAt,
    String label = '',
    String? melody,
    double? volume,
    bool overrideDnd = false,
  }) async {
    final checkAt = fireAt.add(grace);
    try {
      final ok = await AndroidAlarmManager.oneShotAt(
        checkAt,
        watchdogId,
        alarmWatchdogCallback,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: true,
      );
      if (ok) {
        await AlarmLog.ok(
            'BACKUP',
            '"$title": watchdog armed for $label${_fmt(fireAt)} '
            '(verifies delivery at ${_fmt(checkAt)}; rings itself if the '
            'primary path failed)');
        return <String, dynamic>{
          'uid': uid,
          'title': title,
          'body': body,
          'vibrate': vibrate,
          'notifIds': notifIds,
          'fireAt': fireAt.toIso8601String(),
          if (melody != null) 'melody': melody,
          if (volume != null) 'volume': volume,
          'overrideDnd': overrideDnd,
        };
      }
      await AlarmLog.fail(
          'BACKUP', '"$title": OS rejected the watchdog registration');
    } catch (e) {
      await AlarmLog.fail('BACKUP', '"$title": arming watchdog threw: $e');
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Delivery acknowledgements
  // ---------------------------------------------------------------------

  /// Records that the user interacted with alarm [uid]'s notification, so a
  /// watchdog waking after the user already dismissed it doesn't ring again.
  static Future<void> recordAck(String uid, String how) async {
    if (!_isAndroid) return;
    try {
      final prefs = await _prefs();
      Map<String, dynamic> acks;
      try {
        acks = jsonDecode(prefs.getString(_acksKey) ?? '{}')
            as Map<String, dynamic>;
      } catch (_) {
        acks = <String, dynamic>{};
      }
      acks[uid] = DateTime.now().toIso8601String();
      // Drop stale entries so the map can't grow without bound.
      final cutoff = DateTime.now().subtract(const Duration(days: 2));
      acks.removeWhere((_, v) {
        final t = DateTime.tryParse(v as String? ?? '');
        return t == null || t.isBefore(cutoff);
      });
      await prefs.setString(_acksKey, jsonEncode(acks));
    } catch (_) {}
  }

  static DateTime? _ackTime(SharedPreferences prefs, String uid) {
    try {
      final acks =
          jsonDecode(prefs.getString(_acksKey) ?? '{}') as Map<String, dynamic>;
      return DateTime.tryParse(acks[uid] as String? ?? '');
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // The check itself (runs in a background isolate)
  // ---------------------------------------------------------------------

  static String _fmt(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  /// Body of [alarmWatchdogCallback]; kept on the class for access to the
  /// private helpers.
  static Future<void> handleWatchdogFire(int watchdogId) async {
    final prefs = await _prefs();
    final registry = _readRegistry(prefs);
    final entry = registry.remove('$watchdogId') as Map<String, dynamic>?;
    await prefs.setString(_registryKey, jsonEncode(registry));

    if (entry == null) {
      await AlarmLog.warn(
          'FIRE',
          'watchdog #$watchdogId woke but has no registry entry '
          '(alarm was probably edited/disabled meanwhile) — nothing to do');
      return;
    }

    final uid = entry['uid'] as String? ?? '';
    final title = entry['title'] as String? ?? 'Alarm';
    final body = entry['body'] as String? ?? '';
    final vibrate = entry['vibrate'] as bool? ?? true;
    final notifIds = ((entry['notifIds'] as List<dynamic>?) ?? const [])
        .map((e) => e as int)
        .toSet();
    final fireAt = DateTime.tryParse(entry['fireAt'] as String? ?? '');

    await AlarmLog.info(
        'FIRE',
        'watchdog woke for "$title" (was due ${fireAt != null ? _fmt(fireAt) : 'unknown'}) '
        '— checking whether it actually rang');

    // 1. Did the user already interact with it (tap / snooze / dismiss)?
    final ack = _ackTime(prefs, uid);
    final ackValid = ack != null &&
        fireAt != null &&
        ack.isAfter(fireAt.subtract(const Duration(minutes: 5)));
    if (ackValid) {
      await AlarmLog.ok(
          'FIRE',
          '"$title": DELIVERED — user already interacted with the '
          'notification at ${_fmt(ack)}');
    }

    // 2. Is the notification still on screen?
    bool onScreen = false;
    if (!ackValid) {
      try {
        final active =
            await FlutterLocalNotificationsPlugin().getActiveNotifications();
        onScreen = active.any((n) => n.id != null && notifIds.contains(n.id));
        if (onScreen) {
          await AlarmLog.ok(
              'FIRE',
              '"$title": DELIVERED — primary path worked, notification is '
              'on screen right now');
        }
      } catch (e) {
        await AlarmLog.warn(
            'FIRE', 'could not query active notifications: $e');
      }
    }

    // 3. Neither → the primary path failed. Ring NOW through this isolate.
    if (!ackValid && !onScreen) {
      await AlarmLog.fail(
          'FIRE',
          '"$title": primary path did NOT deliver (no notification on '
          'screen, no user interaction). The OS suppressed or dropped the '
          'scheduled alarm — see PERM/ENV lines above for the likely cause '
          '(battery optimization / exact-alarm permission / OEM app sleep). '
          'Ringing via BACKUP path now, ~${grace.inSeconds}s late.');
      try {
        final shown = await NotificationService.showAlarmNotification(
          title,
          body,
          vibrate: vibrate,
          uid: uid,
          melody: entry['melody'] as String?,
          volume: (entry['volume'] as num?)?.toDouble(),
          overrideDnd: entry['overrideDnd'] as bool? ?? false,
        );
        if (shown) {
          await AlarmLog.ok('BACKUP', '"$title": backup ring posted');
        } else {
          await AlarmLog.fail(
              'BACKUP',
              '"$title": backup ring was BLOCKED — notification permission '
              'is off. Fix: system Settings → Apps → BestToDo → '
              'Notifications → allow.');
        }
      } catch (e) {
        await AlarmLog.fail('BACKUP', '"$title": backup ring threw: $e');
      }
    }

    // 4. Re-arm coverage for the alarm's next occurrence (repeating alarms
    // repeat natively on the primary path, but each watchdog is one-shot).
    // The test alarm and the dice timer are one-offs with nothing in alarm
    // storage, so there is nothing to re-arm for them.
    if (uid == kTestAlarmUid || uid == kDiceTimerUid) return;
    try {
      final alarms = await AlarmStorageService().loadAlarms();
      final matches = alarms.where((a) => a.uid == uid);
      final alarm = matches.isEmpty ? null : matches.first;
      final next = alarm != null && alarm.enabled ? alarm.nextOccurrence() : null;
      if (alarm == null || next == null) {
        await AlarmLog.info(
            'BACKUP', '"$title": no future occurrence — watchdog not re-armed');
        return;
      }
      final newEntry = await _armOne(
        watchdogId: alarmWatchdogId(uid),
        uid: uid,
        title: title,
        body: alarm.description,
        vibrate: alarm.vibrate,
        notifIds: alarmNotificationIds(uid),
        fireAt: next,
        melody: alarm.melody,
        volume: alarm.volume,
        overrideDnd: alarm.overrideDnd,
      );
      if (newEntry != null) {
        final reg = _readRegistry(await _prefs());
        reg['${alarmWatchdogId(uid)}'] = newEntry;
        await prefs.setString(_registryKey, jsonEncode(reg));
      }
    } catch (e) {
      await AlarmLog.fail('BACKUP', '"$title": re-arming watchdog failed: $e');
    }
  }
}

/// Entry point android_alarm_manager_plus invokes in a background isolate
/// when a watchdog alarm fires. Must stay a top-level function annotated
/// `@pragma('vm:entry-point')` or the callback is stripped in release builds.
@pragma('vm:entry-point')
Future<void> alarmWatchdogCallback(int watchdogId) async {
  // Fresh isolate: without these the plugins (prefs, notifications, alarm
  // manager) have no method channels and everything below silently fails.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    await AlarmWatchdog.handleWatchdogFire(watchdogId);
  } catch (e) {
    try {
      await AlarmLog.fail('FIRE', 'watchdog #$watchdogId crashed: $e');
    } catch (_) {}
  }
}
