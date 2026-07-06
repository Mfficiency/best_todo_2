import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data' show Int32List;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/alarm.dart';
import 'alarm_diagnostics.dart';
import 'alarm_ids.dart';
import 'alarm_log_service.dart';
import 'alarm_watchdog.dart';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
const String _channelId = 'task_notifications';
const String _channelName = 'Task Notifications';
const String _channelDescription = 'Manual task notifications';
const String _alarmChannelId = 'alarm_notifications_v2';
const String _alarmChannelName = 'Alarms';
const String _alarmChannelDescription = 'Alarm alerts';

const String _snoozeAction = 'alarm_snooze';
const String _dismissAction = 'alarm_dismiss';

bool _initialized = false;
bool _timezoneReady = false;

Future<void> _ensureTimezone() async {
  if (_timezoneReady) return;
  tz_data.initializeTimeZones();
  try {
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
  } catch (e) {
    // Falls back to the default (UTC) location if the platform lookup fails —
    // alarms would then fire at the wrong wall-clock time, so make it loud.
    await AlarmLog.warn(
        'ENV',
        'timezone lookup failed ($e) — falling back to UTC; alarm times may '
        'be shifted by your UTC offset');
  }
  _timezoneReady = true;
}

Future<void> initialize() async {
  if (_initialized) return;

  await _ensureTimezone();

  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  try {
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationResponse,
    );
  } catch (e) {
    await AlarmLog.fail('ENV', 'notification plugin init failed: $e');
    rethrow;
  }

  if (Platform.isAndroid) {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _alarmChannelId,
          _alarmChannelName,
          description: _alarmChannelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        ),
      );
    } catch (e) {
      await AlarmLog.fail('ENV', 'creating notification channels failed: $e');
    }
  }

  _initialized = true;
}

// ---------------------------------------------------------------------------
// Permissions
// ---------------------------------------------------------------------------

Future<bool> _ensurePermission() async {
  await initialize();

  if (Platform.isAndroid) {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await androidPlugin?.areNotificationsEnabled();
    if (enabled == true) return true;
    return await androidPlugin?.requestNotificationsPermission() ?? false;
  }

  if (Platform.isIOS) {
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  return true;
}

/// Requests every permission alarms rely on, logging the before/after state
/// of each one:
///   • notifications (nothing shows or rings without it)
///   • exact alarms — Android 12 gates them; 13+ auto-grants via
///     USE_EXACT_ALARM, but the user can still revoke in settings
///   • battery-optimization exemption — aggressive OEM power savers
///     (Samsung "Sleeping apps" & co.) deep-sleep the app and can delay or
///     drop even exact alarms unless the app is whitelisted
Future<bool> ensureAlarmPermissions() async {
  await initialize();
  if (!Platform.isAndroid) {
    final granted = await _ensurePermission();
    await AlarmLog.info(
        'PERM', 'notification permission on this platform: $granted');
    return granted;
  }

  final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();

  var granted = false;
  try {
    final before = await androidPlugin?.areNotificationsEnabled() ?? false;
    granted = before || await _ensurePermission();
    if (granted) {
      await AlarmLog.ok('PERM',
          'notifications: ${before ? 'already enabled' : 'granted just now'}');
    } else {
      await AlarmLog.fail(
          'PERM',
          'notifications: DENIED — alarms cannot show or ring. Fix: system '
          'Settings → Apps → BestToDo → Notifications → allow');
    }
  } catch (e) {
    await AlarmLog.warn('PERM', 'notification permission check threw: $e');
  }

  try {
    final before = await androidPlugin?.canScheduleExactNotifications() ?? false;
    if (before) {
      await AlarmLog.ok('PERM', 'exact alarms: already allowed');
    } else {
      await androidPlugin?.requestExactAlarmsPermission();
      final after =
          await androidPlugin?.canScheduleExactNotifications() ?? false;
      if (after) {
        await AlarmLog.ok('PERM', 'exact alarms: granted just now');
      } else {
        await AlarmLog.fail(
            'PERM',
            'exact alarms: NOT allowed — alarms will be late or dropped. '
            'Fix: system Settings → Apps → Special app access → '
            'Alarms & reminders → BestToDo');
      }
    }
  } catch (e) {
    await AlarmLog.warn('PERM', 'exact-alarm permission request threw: $e');
  }

  try {
    if (await Permission.ignoreBatteryOptimizations.isGranted) {
      await AlarmLog.ok('PERM', 'battery optimization: already exempted');
    } else {
      final status = await Permission.ignoreBatteryOptimizations.request();
      if (status.isGranted) {
        await AlarmLog.ok('PERM', 'battery optimization: exempted just now');
      } else {
        await AlarmLog.warn(
            'PERM',
            'battery optimization: exemption declined — deep sleep can delay '
            'or drop alarms. Fix: system Settings → Apps → BestToDo → '
            'Battery → Unrestricted');
      }
    }
  } catch (e) {
    await AlarmLog.warn('PERM', 'battery-optimization request threw: $e');
  }

  return granted;
}

// ---------------------------------------------------------------------------
// Exact alarm scheduling
// ---------------------------------------------------------------------------

AndroidNotificationDetails _androidAlarmDetails({
  required bool vibrate,
  required bool snoozeEnabled,
}) {
  final actions = <AndroidNotificationAction>[
    if (snoozeEnabled)
      const AndroidNotificationAction(
        _snoozeAction,
        'Snooze',
        cancelNotification: true,
      ),
    const AndroidNotificationAction(
      _dismissAction,
      'Dismiss',
      cancelNotification: true,
    ),
  ];

  return AndroidNotificationDetails(
    _alarmChannelId,
    _alarmChannelName,
    channelDescription: _alarmChannelDescription,
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    enableVibration: vibrate,
    playSound: true,
    ongoing: true,
    autoCancel: false,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    // FLAG_INSISTENT: loop the alarm sound/vibration until the notification
    // is acted on, instead of playing it once — a one-shot ding is easy to
    // sleep through.
    additionalFlags: Int32List.fromList(const <int>[4]),
    actions: actions,
  );
}

NotificationDetails _alarmDetails({
  required bool vibrate,
  required bool snoozeEnabled,
}) {
  return NotificationDetails(
    android: _androidAlarmDetails(vibrate: vibrate, snoozeEnabled: snoozeEnabled),
    iOS: const DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    ),
  );
}

String _payloadFor(Alarm alarm) => jsonEncode({
      'uid': alarm.uid,
      'name': alarm.name.isEmpty ? 'Alarm' : alarm.name,
      'body': alarm.description,
      'vibrate': alarm.vibrate,
      'snoozeEnabled': alarm.snoozeEnabled,
      'snoozeMinutes': alarm.snoozeDurationMinutes,
      'snoozeId': alarmNotificationBaseId(alarm.uid),
    });

tz.TZDateTime _nextInstanceOfWeekday(int hour, int minute, int weekday) {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled =
      tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  // Step by rebuilding the wall-clock time instead of add(Duration(days: 1)):
  // adding 24h across a DST change shifts the local hour, so the alarm would
  // fire an hour early/late in the week of the transition.
  var offset = 0;
  while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
    offset++;
    scheduled = tz.TZDateTime(
        tz.local, now.year, now.month, now.day + offset, hour, minute);
  }
  return scheduled;
}

String _fmtWhen(tz.TZDateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// The escalation ladder: every scheduling method we can try, strongest
/// first. Each alarm slot walks down the ladder until one method is accepted
/// by the OS, logging every attempt. On iOS the mode is ignored and the first
/// attempt succeeds.
const List<(AndroidScheduleMode, String)> _scheduleModes = [
  (
    AndroidScheduleMode.alarmClock,
    'METHOD 1/3 setAlarmClock (alarm-clock class: immune to Doze and app '
        'standby, shows the status-bar alarm icon)'
  ),
  (
    AndroidScheduleMode.exactAllowWhileIdle,
    'METHOD 2/3 setExactAndAllowWhileIdle (exact, allowed to fire in Doze)'
  ),
  (
    AndroidScheduleMode.inexactAllowWhileIdle,
    'METHOD 3/3 inexact allow-while-idle (LAST RESORT: the OS may delay it '
        'by minutes)'
  ),
];

/// Schedules one notification, walking down the method ladder. Returns the
/// description of the method that worked, or null when everything failed.
Future<String?> _zonedScheduleLayered({
  required int id,
  required String title,
  String? body,
  required tz.TZDateTime when,
  required NotificationDetails details,
  required String payload,
  DateTimeComponents? matchDateTimeComponents,
  required String describe,
}) async {
  for (final (mode, label) in _scheduleModes) {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
        payload: payload,
      );
      await AlarmLog.ok(
          'SCHEDULE', '$describe: $label → accepted for ${_fmtWhen(when)} (id $id)');
      return label;
    } catch (e) {
      await AlarmLog.fail(
          'SCHEDULE', '$describe: $label REJECTED ($e) — trying next method');
    }
  }
  await AlarmLog.fail(
      'SCHEDULE',
      '$describe: ALL scheduling methods rejected — the OS holds no schedule '
      'for this alarm. The BACKUP watchdog is the only remaining path.');
  return null;
}

Future<void> _scheduleOne(Alarm alarm) async {
  if (!alarm.enabled) return;
  final base = alarmNotificationBaseId(alarm.uid);
  final title = alarm.name.isEmpty ? 'Alarm' : alarm.name;
  final body = alarm.description.isEmpty ? null : alarm.description;
  final details =
      _alarmDetails(vibrate: alarm.vibrate, snoozeEnabled: alarm.snoozeEnabled);
  final payload = _payloadFor(alarm);

  if (alarm.isRepeating) {
    if (alarm.repeatDays.isEmpty) {
      await AlarmLog.warn(
          'SCHEDULE', '"$title": repeating but no weekdays selected — skipped');
      return;
    }
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    for (final weekday in alarm.repeatDays) {
      final when = _nextInstanceOfWeekday(alarm.hour, alarm.minute, weekday);
      await _zonedScheduleLayered(
        id: base + weekday,
        title: title,
        body: body,
        when: when,
        details: details,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        describe: '"$title" ${alarm.timeLabel} every ${dayNames[weekday - 1]}',
      );
    }
  } else {
    final next = alarm.nextOccurrence();
    if (next == null) {
      await AlarmLog.info(
          'SCHEDULE', '"$title": one-off time already passed — nothing to schedule');
      return;
    }
    final when = tz.TZDateTime.from(next, tz.local);
    await _zonedScheduleLayered(
      id: base,
      title: title,
      body: body,
      when: when,
      details: details,
      payload: payload,
      describe: '"$title" ${alarm.timeLabel} once',
    );
  }
}

/// Cancels every previously scheduled alarm and re-schedules all enabled ones,
/// then VERIFIES the OS actually holds the schedules and arms the independent
/// watchdog backup for each alarm. Every step is written to the alarm log.
///
/// Cancels individually rather than with `cancelAll()`: a blanket cancel runs
/// on every app open / alarm edit and would silently kill a pending SNOOZE.
/// The snooze slot (base id + 0) is kept for enabled alarms that don't
/// schedule anything there themselves — repeating alarms (they use +1..+7)
/// and one-off alarms whose original time already passed.
Future<void> scheduleAlarms(List<Alarm> alarms,
    {String trigger = 'alarms changed'}) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await initialize();

  final enabled = alarms.where((a) => a.enabled).length;
  await AlarmLog.section(
      'RESCHEDULE ($trigger) — ${alarms.length} alarm(s), $enabled enabled');

  final preserve = <int>{
    for (final a in alarms)
      if (a.enabled && (a.isRepeating || a.nextOccurrence() == null))
        alarmNotificationBaseId(a.uid),
  };
  try {
    final pending = await _plugin.pendingNotificationRequests();
    var cancelled = 0;
    for (final p in pending) {
      if (!preserve.contains(p.id)) {
        await _plugin.cancel(p.id);
        cancelled++;
      }
    }
    await AlarmLog.info(
        'SCHEDULE',
        'cleared $cancelled old OS schedule(s), kept ${preserve.length} '
        'possible snooze slot(s)');
  } catch (e) {
    await AlarmLog.warn('SCHEDULE', 'clearing old schedules failed: $e');
  }

  for (final alarm in alarms) {
    try {
      await _scheduleOne(alarm);
    } catch (e) {
      await AlarmLog.fail(
          'SCHEDULE', '"${alarm.name}": unexpected error while scheduling: $e');
    }
  }

  await _verifyPendingSchedules(alarms);

  // Fully independent second delivery path + delivery verification.
  if (Platform.isAndroid) {
    try {
      await AlarmWatchdog.armAll(alarms);
    } catch (e) {
      await AlarmLog.fail('BACKUP', 'arming watchdogs failed: $e');
    }
  }
}

/// Reads back what the OS reports as pending and compares it with what each
/// enabled alarm should have registered — the difference between "we called
/// schedule()" and "the OS actually kept it".
Future<void> _verifyPendingSchedules(List<Alarm> alarms) async {
  try {
    final pending = await _plugin.pendingNotificationRequests();
    final pendingIds = pending.map((p) => p.id).toSet();
    for (final alarm in alarms) {
      if (!alarm.enabled) continue;
      final title = alarm.name.isEmpty ? 'Alarm' : alarm.name;
      final base = alarmNotificationBaseId(alarm.uid);
      final expected = <int>{
        if (alarm.isRepeating)
          for (final d in alarm.repeatDays) base + d
        else if (alarm.nextOccurrence() != null) base,
      };
      if (expected.isEmpty) continue;
      final missing = expected.difference(pendingIds);
      if (missing.isEmpty) {
        await AlarmLog.ok(
            'VERIFY',
            '"$title": OS confirms ${expected.length} pending schedule(s) '
            '(ids ${expected.join(', ')})');
      } else {
        await AlarmLog.fail(
            'VERIFY',
            '"$title": OS is MISSING schedule id(s) ${missing.join(', ')} — '
            'the schedule call did not stick; see SCHEDULE lines above');
      }
    }
  } catch (e) {
    await AlarmLog.warn('VERIFY', 'could not read back pending schedules: $e');
  }
}

// ---------------------------------------------------------------------------
// Test alarm (fired from the in-app alarm log page)
// ---------------------------------------------------------------------------

/// Schedules a one-off test alarm [delaySeconds] from now through the exact
/// same pipeline as a real alarm (method ladder + verify + watchdog), so the
/// whole chain can be exercised on demand and read back in the log.
Future<void> scheduleTestAlarm({int delaySeconds = 60}) async {
  await initialize();
  await AlarmLog.section('TEST ALARM — requested from the log page');
  final when = tz.TZDateTime.now(tz.local).add(Duration(seconds: delaySeconds));
  final payload = jsonEncode({
    'uid': kTestAlarmUid,
    'name': 'Test alarm',
    'body': 'BestToDo alarm pipeline test',
    'vibrate': true,
    'snoozeEnabled': false,
    'snoozeMinutes': 9,
    'snoozeId': kTestAlarmNotificationId,
  });
  await _zonedScheduleLayered(
    id: kTestAlarmNotificationId,
    title: 'Test alarm',
    body: 'BestToDo alarm pipeline test — it works!',
    when: when,
    details: _alarmDetails(vibrate: true, snoozeEnabled: false),
    payload: payload,
    describe: '"Test alarm" in ${delaySeconds}s',
  );
  try {
    final pending = await _plugin.pendingNotificationRequests();
    final held = pending.any((p) => p.id == kTestAlarmNotificationId);
    if (held) {
      await AlarmLog.ok('VERIFY', '"Test alarm": OS confirms the pending schedule');
    } else {
      await AlarmLog.fail(
          'VERIFY', '"Test alarm": OS did NOT keep the schedule');
    }
  } catch (_) {}
  if (Platform.isAndroid) {
    await AlarmWatchdog.armTest(fireAt: when);
  }
  await AlarmLog.info(
      'FIRE',
      'now LOCK the phone and wait ~${delaySeconds + AlarmWatchdog.grace.inSeconds}s '
      '— the ring should come at ${_fmtWhen(when)} and the delivery verdict '
      'appears below shortly after');
}

Future<void> runAlarmDiagnostics({String trigger = 'manual'}) =>
    AlarmDiagnostics.run(trigger: trigger);

// ---------------------------------------------------------------------------
// Action handling (snooze / dismiss / tap)
// ---------------------------------------------------------------------------

void _onNotificationResponse(NotificationResponse response) {
  _processAction(response);
}

@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  // Runs in a dedicated isolate with no plugin registrations; without these
  // the timezone lookup and re-scheduling inside _processAction can't reach
  // the platform and Snooze does nothing when the app is closed.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  _processAction(response);
}

Future<void> _processAction(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null) return;
  Map<String, dynamic> data;
  try {
    data = jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  await initialize();
  final uid = data['uid'] as String? ?? '';
  final name = data['name'] as String? ?? 'Alarm';

  // Every interaction proves the alarm reached the user — record it so the
  // watchdog doesn't treat an already-dismissed alarm as undelivered and
  // ring it a second time.
  if (uid.isNotEmpty) {
    await AlarmWatchdog.recordAck(uid, response.actionId ?? 'tap');
  }

  if (response.actionId == _dismissAction) {
    await AlarmLog.ok('ACTION', '"$name": dismissed by user');
    return;
  }
  if (response.actionId == null) {
    await AlarmLog.ok('ACTION', '"$name": notification tapped (app opened)');
    return;
  }
  if (response.actionId != _snoozeAction) return;

  final minutes = (data['snoozeMinutes'] as int?) ?? 9;
  final snoozeId = (data['snoozeId'] as int?) ?? 0;
  final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
  await AlarmLog.ok('ACTION', '"$name": snoozed for $minutes min');
  final method = await _zonedScheduleLayered(
    id: snoozeId,
    title: name,
    body: data['body'] as String?,
    when: when,
    details: _alarmDetails(
      vibrate: data['vibrate'] as bool? ?? true,
      snoozeEnabled: data['snoozeEnabled'] as bool? ?? true,
    ),
    payload: payload,
    describe: '"$name" snooze',
  );
  if (method != null && Platform.isAndroid && uid.isNotEmpty) {
    await AlarmWatchdog.armSnooze(
      uid: uid,
      title: name,
      body: data['body'] as String? ?? '',
      vibrate: data['vibrate'] as bool? ?? true,
      fireAt: when,
    );
  }
}

// ---------------------------------------------------------------------------
// Immediate notifications (tasks + manual alarm preview + watchdog backup)
// ---------------------------------------------------------------------------

Future<bool> showAlarmNotification(
  String title,
  String body, {
  bool vibrate = true,
}) async {
  final hasPermission = await _ensurePermission();
  if (!hasPermission) return false;

  final safeTitle = title.trim().isEmpty ? 'Alarm' : title.trim();
  final id = DateTime.now().millisecondsSinceEpoch % 2147483647;
  await _plugin.show(
    id,
    safeTitle,
    body.isEmpty ? null : body,
    _alarmDetails(vibrate: vibrate, snoozeEnabled: false),
  );
  return true;
}

Future<void> _showNow(String taskTitle) async {
  final title = taskTitle.trim().isEmpty ? 'Task' : taskTitle.trim();
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  final id = DateTime.now().millisecondsSinceEpoch % 2147483647;
  await _plugin.show(id, title, null, details);
}

Future<bool> showTaskNotification(
  String taskTitle, {
  int delaySeconds = 0,
}) async {
  final hasPermission = await _ensurePermission();
  if (!hasPermission) return false;

  if (delaySeconds > 0) {
    Future.delayed(Duration(seconds: delaySeconds), () async {
      await _showNow(taskTitle);
    });
    return true;
  }

  await _showNow(taskTitle);
  return true;
}
