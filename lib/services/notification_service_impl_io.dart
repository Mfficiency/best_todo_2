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
import 'alarm_fullscreen.dart';
import 'alarm_ids.dart';
import 'alarm_log_service.dart';
import 'alarm_storage_service.dart';
import 'alarm_watchdog.dart';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
const String _channelId = 'task_notifications';
const String _channelName = 'Task Notifications';
const String _channelDescription = 'Manual task notifications';
const String _alarmChannelId = 'alarm_notifications_v2';
const String _alarmChannelName = 'Alarms';
const String _alarmChannelDescription = 'Alarm alerts';
// Sound-less variant used while the app itself plays the alarm's melody (at
// the alarm's own volume): the notification stays on screen with its actions
// and keeps vibrating, but no longer plays the channel's default sound on top.
const String _alarmSilentChannelId = 'alarm_notifications_silent_v1';
const String _alarmSilentChannelName = 'Alarms (silent, in-app sound)';
const String _alarmSilentChannelDescription =
    'Alarm alerts whose sound is played by the app at the alarm\'s own volume';

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
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _alarmSilentChannelId,
          _alarmSilentChannelName,
          description: _alarmSilentChannelDescription,
          importance: Importance.max,
          playSound: false,
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

  // Android 14+ can revoke the full-screen-intent special access that lets a
  // ringing alarm cover the lock screen. When it is revoked, send the user to
  // the system toggle for it (an alarm still rings without it, but only as a
  // banner).
  try {
    final before = await AlarmFullScreen.canUseFullScreenIntent();
    if (before == false) {
      await AlarmLog.warn(
          'PERM',
          'full-screen intent: revoked — opening the system setting so the '
          'full-screen alarm screen can show over the lock screen');
      await androidPlugin?.requestFullScreenIntentPermission();
      final after = await AlarmFullScreen.canUseFullScreenIntent();
      if (after == true) {
        await AlarmLog.ok('PERM', 'full-screen intent: granted just now');
      } else {
        await AlarmLog.warn(
            'PERM',
            'full-screen intent: still revoked — while locked, alarms show a '
            'banner instead of the full-screen alarm screen. Fix: system '
            'Settings → Apps → BestToDo → Manage full screen intents');
      }
    } else if (before == true) {
      await AlarmLog.ok('PERM', 'full-screen intent: allowed');
    }
  } catch (e) {
    await AlarmLog.warn('PERM', 'full-screen-intent check threw: $e');
  }

  return granted;
}

// ---------------------------------------------------------------------------
// Exact alarm scheduling
// ---------------------------------------------------------------------------

AndroidNotificationDetails _androidAlarmDetails({
  required bool vibrate,
  required bool snoozeEnabled,
  bool silent = false,
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
    silent ? _alarmSilentChannelId : _alarmChannelId,
    silent ? _alarmSilentChannelName : _alarmChannelName,
    channelDescription:
        silent ? _alarmSilentChannelDescription : _alarmChannelDescription,
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    fullScreenIntent: true,
    enableVibration: vibrate,
    playSound: !silent,
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
  bool silent = false,
}) {
  return NotificationDetails(
    android: _androidAlarmDetails(
        vibrate: vibrate, snoozeEnabled: snoozeEnabled, silent: silent),
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
      'color': alarm.color,
      'melody': alarm.melody,
      'volume': alarm.volume,
      'overrideDnd': alarm.overrideDnd,
    });

/// Parses a notification payload and returns it when it belongs to an alarm
/// (identified by a non-empty uid); null for anything else.
Map<String, dynamic>? _decodeAlarmPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final data = jsonDecode(payload);
    if (data is Map<String, dynamic> &&
        (data['uid'] as String? ?? '').isNotEmpty) {
      return data;
    }
  } catch (_) {}
  return null;
}

/// Invoked on the main isolate with the alarm payload when a ringing alarm
/// should present the full-screen ring UI: the app was opened by tapping the
/// alarm notification, or its full-screen intent fired while the app was
/// alive. Registered by the app shell; null in background isolates.
void Function(Map<String, dynamic> payload)? onAlarmRing;

/// Payload of the alarm notification that launched the app (tap or
/// full-screen intent over the lock screen), or null when the app was started
/// normally. Used on cold start to open the full-screen ring UI immediately.
Future<Map<String, dynamic>?> getAlarmLaunchPayload() async {
  await initialize();
  try {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final response = details!.notificationResponse;
    // Action buttons (snooze/dismiss) already handled the alarm — only a
    // plain open of the notification should ring the full-screen UI.
    if (response == null || response.actionId != null) return null;
    return _decodeAlarmPayload(response.payload);
  } catch (e) {
    await AlarmLog.warn(
        'FIRE', 'could not read notification launch details: $e');
    return null;
  }
}

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

// ---------------------------------------------------------------------------
// Dice timer ring (the countdown's end, delivered by the OS)
// ---------------------------------------------------------------------------

/// Schedules the dice timer's end-of-countdown ring as a real alarm, so it
/// fires whether or not the app is running — full-screen intent, insistent
/// until answered, stoppable from the alarm screen. Replaces any previously
/// scheduled dice ring (only one timer exists at a time).
///
/// [melody]/[volume] ride along when the timer should play a melody; without
/// them the notification goes on the sound-less alarm channel, which is how
/// the vibration-only and notification alert modes stay quiet while still
/// taking over the screen.
Future<void> scheduleDiceTimerAlarm({
  required DateTime fireAt,
  required String taskTitle,
  required bool vibrate,
  String? melody,
  double? volume,
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await initialize();
  await _ensureTimezone();
  final when = tz.TZDateTime.from(fireAt, tz.local);
  if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
  await cancelDiceTimerAlarm();

  final data = diceRingPayload(
    taskTitle,
    melody: melody,
    volume: volume,
    vibrate: vibrate,
  );
  final title = data['name'] as String;
  final body = data['body'] as String;
  final payload = jsonEncode(data);
  await AlarmLog.section('DICE TIMER — ring scheduled for "$body"');
  final method = await _zonedScheduleLayered(
    id: kDiceTimerNotificationId,
    title: title,
    body: body,
    when: when,
    details: _alarmDetails(
      vibrate: vibrate,
      snoozeEnabled: false,
      // A melody is played by the ring page itself; without one the channel
      // must stay silent, or a "quiet" alert would ring the default alarm
      // sound anyway.
      silent: melody == null,
    ),
    payload: payload,
    describe: '"$title" for the dice timer',
  );
  if (method != null && Platform.isAndroid) {
    await AlarmWatchdog.armDiceTimer(
      fireAt: when,
      title: title,
      body: body,
      vibrate: vibrate,
      melody: melody,
      volume: volume,
    );
  }
}

/// Drops the scheduled dice ring (and any copy of it already on screen) when
/// the countdown is paused, rewound, extended or finished early.
Future<void> cancelDiceTimerAlarm() async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await initialize();
  try {
    await _plugin.cancel(kDiceTimerNotificationId);
  } catch (e) {
    await AlarmLog.warn('SCHEDULE', 'cancelling the dice ring failed: $e');
  }
  if (Platform.isAndroid) await AlarmWatchdog.cancelDiceTimer();
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
    await AlarmLog.ok(
        'ACTION', '"$name": notification opened — showing full-screen alarm UI');
    // Ring UI can only be shown from the main isolate; in the background
    // isolate the handler is null and the notification stays interactive.
    final ring = _decodeAlarmPayload(payload);
    if (ring != null) onAlarmRing?.call(ring);
    return;
  }
  if (response.actionId != _snoozeAction) return;

  await _scheduleSnoozeFromData(data, payload, how: 'notification action');
}

/// Schedules the snoozed re-fire for an alarm payload and arms the snooze
/// watchdog. Shared by the notification's Snooze action and the full-screen
/// ring page's Snooze button.
Future<void> _scheduleSnoozeFromData(
  Map<String, dynamic> data,
  String payload, {
  required String how,
}) async {
  final uid = data['uid'] as String? ?? '';
  final name = data['name'] as String? ?? 'Alarm';
  final minutes = (data['snoozeMinutes'] as int?) ?? 9;
  final snoozeId = (data['snoozeId'] as int?) ?? 0;
  final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
  await AlarmLog.ok('ACTION', '"$name": snoozed for $minutes min ($how)');
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
      melody: data['melody'] as String?,
      volume: (data['volume'] as num?)?.toDouble(),
      overrideDnd: data['overrideDnd'] as bool? ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// Full-screen ring page actions
// ---------------------------------------------------------------------------

/// Cancels the alarm's notifications that are currently on screen (stops the
/// insistent sound/vibration). `cancel` also removes any pending schedule
/// with the same id (e.g. the auto-rearmed next weekly fire), so callers must
/// re-register schedules from storage afterwards.
/// Every notification id a ring with [uid] may be showing under. The test
/// alarm and the dice timer each own a single fixed slot; saved alarms own
/// their derived one-off/snooze + weekday slots.
Set<int> _notificationIdsForUid(String uid) {
  if (uid == kTestAlarmUid) return <int>{kTestAlarmNotificationId};
  if (uid == kDiceTimerUid) return <int>{kDiceTimerNotificationId};
  return alarmNotificationIds(uid).toSet();
}

/// True for rings that have nothing in alarm storage to restore afterwards.
bool _isStandaloneRing(String uid) =>
    uid == kTestAlarmUid || uid == kDiceTimerUid;

Future<void> _cancelActiveAlarmNotifications(String uid) async {
  final ids = _notificationIdsForUid(uid);
  try {
    final active = await _plugin.getActiveNotifications();
    for (final n in active) {
      final id = n.id;
      if (id != null && ids.contains(id)) {
        await _plugin.cancel(id);
      }
    }
  } catch (e) {
    await AlarmLog.warn(
        'ACTION', 'could not clear the ringing notification: $e');
  }
}

Future<void> _rescheduleFromStorage(String trigger) async {
  try {
    final alarms = await AlarmStorageService().loadAlarms();
    await scheduleAlarms(alarms, trigger: trigger);
  } catch (e) {
    await AlarmLog.warn('SCHEDULE', 'reschedule after ring action failed: $e');
  }
}

/// Stop button on the full-screen ring page: acknowledges delivery (so the
/// watchdog doesn't re-ring), silences the notification and restores the OS
/// schedules that cancelling may have removed.
Future<void> dismissAlarmFromRing(Map<String, dynamic> data) async {
  await initialize();
  final uid = data['uid'] as String? ?? '';
  final name = data['name'] as String? ?? 'Alarm';
  if (uid.isNotEmpty) await AlarmWatchdog.recordAck(uid, 'ring_dismiss');
  await AlarmLog.ok(
      'ACTION', '"$name": stopped on the full-screen alarm screen');
  await _cancelActiveAlarmNotifications(uid);
  if (uid == kDiceTimerUid) await AlarmWatchdog.cancelDiceTimer();
  if (!_isStandaloneRing(uid)) {
    await _rescheduleFromStorage('alarm stopped on ring screen');
  }
}

/// Snooze button on the full-screen ring page. Restores the regular
/// schedules first and registers the snooze last, so the reschedule cannot
/// clear the snooze slot.
Future<void> snoozeAlarmFromRing(Map<String, dynamic> data) async {
  await initialize();
  final uid = data['uid'] as String? ?? '';
  if (uid.isNotEmpty) await AlarmWatchdog.recordAck(uid, 'ring_snooze');
  await _cancelActiveAlarmNotifications(uid);
  if (!_isStandaloneRing(uid)) {
    await _rescheduleFromStorage('alarm snoozed on ring screen');
  }
  await _scheduleSnoozeFromData(data, jsonEncode(data),
      how: 'full-screen alarm screen');
}

// ---------------------------------------------------------------------------
// Immediate notifications (tasks + manual alarm preview + watchdog backup)
// ---------------------------------------------------------------------------

Future<bool> showAlarmNotification(
  String title,
  String body, {
  bool vibrate = true,
  String? uid,
  String? melody,
  double? volume,
  bool overrideDnd = false,
}) async {
  final hasPermission = await _ensurePermission();
  if (!hasPermission) return false;

  final safeTitle = title.trim().isEmpty ? 'Alarm' : title.trim();
  // With a uid (watchdog backup ring) use the alarm's own notification slot
  // and attach the alarm payload, so the full-screen ring UI opens for it and
  // its Stop button can find and silence this notification.
  final baseId = uid == null
      ? null
      : (uid == kTestAlarmUid
          ? kTestAlarmNotificationId
          : (uid == kDiceTimerUid
              ? kDiceTimerNotificationId
              : alarmNotificationBaseId(uid)));
  final id = baseId ?? DateTime.now().millisecondsSinceEpoch % 2147483647;
  final payload = uid == null
      ? null
      : jsonEncode({
          'uid': uid,
          'name': safeTitle,
          'body': body,
          'vibrate': vibrate,
          'snoozeEnabled': false,
          'snoozeMinutes': 9,
          'snoozeId': baseId,
          if (melody != null) 'melody': melody,
          if (volume != null) 'volume': volume,
          'overrideDnd': overrideDnd,
        });
  await _plugin.show(
    id,
    safeTitle,
    body.isEmpty ? null : body,
    _alarmDetails(vibrate: vibrate, snoozeEnabled: false),
    payload: payload,
  );
  return true;
}

/// Moves a ringing alarm's notification onto the sound-less channel: the
/// notification (with its Snooze/Dismiss actions and looping vibration) stays
/// on screen, but the channel's default alarm sound stops. Called by the
/// full-screen ring page once it has started playing the alarm's own melody
/// at the alarm's own volume, so the two sounds don't stack.
Future<void> silenceAlarmNotification(Map<String, dynamic> data) async {
  if (!Platform.isAndroid) return;
  await initialize();
  final uid = data['uid'] as String? ?? '';
  if (uid.isEmpty) return;
  final ids = _notificationIdsForUid(uid);
  try {
    final active = await _plugin.getActiveNotifications();
    var replaced = false;
    for (final n in active) {
      final id = n.id;
      if (id == null || !ids.contains(id)) continue;
      await _plugin.cancel(id);
      if (replaced) continue;
      replaced = true;
      final body = data['body'] as String? ?? '';
      await _plugin.show(
        id,
        data['name'] as String? ?? 'Alarm',
        body.isEmpty ? null : body,
        _alarmDetails(
          vibrate: data['vibrate'] as bool? ?? true,
          snoozeEnabled: data['snoozeEnabled'] as bool? ?? false,
          silent: true,
        ),
        payload: jsonEncode(data),
      );
    }
    if (replaced) {
      await AlarmLog.info(
          'ACTION',
          '"${data['name'] ?? 'Alarm'}": notification sound handed over to '
          'in-app melody playback');
    }
  } catch (e) {
    await AlarmLog.warn(
        'ACTION', 'could not silence the ringing notification: $e');
  }
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

/// Schedules the one-shot streak reminder on the task-notification channel.
/// Deliberately NOT on the alarm ladder: a nudge may be minutes late, so the
/// inexact mode is enough and needs no exact-alarm permission. Everything is
/// guarded so headless/test runs (no platform channels) stay silent.
Future<void> scheduleStreakReminder({
  required DateTime fireAt,
  required String body,
}) async {
  try {
    final hasPermission = await _ensurePermission();
    if (!hasPermission) return;
    await _ensureTimezone();
    final when = tz.TZDateTime.from(fireAt, tz.local);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
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
    await _plugin.zonedSchedule(
      kStreakReminderNotificationId,
      'Keep your streak going 🔥',
      body,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  } catch (_) {}
}

Future<void> cancelStreakReminder() async {
  try {
    await _plugin.cancel(kStreakReminderNotificationId);
  } catch (_) {}
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
