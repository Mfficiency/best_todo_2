import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/alarm.dart';

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
  } catch (_) {
    // Falls back to the default (UTC) location if the platform lookup fails.
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
  await _plugin.initialize(
    settings,
    onDidReceiveNotificationResponse: _onNotificationResponse,
    onDidReceiveBackgroundNotificationResponse:
        _onBackgroundNotificationResponse,
  );

  if (Platform.isAndroid) {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
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

/// Requests both the notification permission and the Android "alarms &
/// reminders" (exact alarm) permission so alarms can fire at the exact time.
/// Also asks for exemption from battery optimization: aggressive OEM power
/// savers (Samsung "Sleeping apps" & co.) deep-sleep the app and can delay or
/// drop even exact alarms unless the app is whitelisted.
Future<bool> ensureAlarmPermissions() async {
  final granted = await _ensurePermission();
  if (Platform.isAndroid) {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await androidPlugin?.requestExactAlarmsPermission();
    } catch (_) {}
    try {
      if (!await Permission.ignoreBatteryOptimizations.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
  }
  return granted;
}

// ---------------------------------------------------------------------------
// Exact alarm scheduling
// ---------------------------------------------------------------------------

/// Deterministic base notification id for an alarm. Repeating alarms occupy
/// [base + weekday] (1..7); one-off and snooze fires use [base + 0].
int _baseId(String uid) => (uid.hashCode & 0x1FFFFFF) * 8;

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
      'snoozeId': _baseId(alarm.uid),
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

Future<void> _scheduleOne(Alarm alarm) async {
  if (!alarm.enabled) return;
  final base = _baseId(alarm.uid);
  final title = alarm.name.isEmpty ? 'Alarm' : alarm.name;
  final body = alarm.description.isEmpty ? null : alarm.description;
  final details =
      _alarmDetails(vibrate: alarm.vibrate, snoozeEnabled: alarm.snoozeEnabled);
  final payload = _payloadFor(alarm);

  if (alarm.isRepeating) {
    if (alarm.repeatDays.isEmpty) return;
    for (final weekday in alarm.repeatDays) {
      final when = _nextInstanceOfWeekday(alarm.hour, alarm.minute, weekday);
      await _plugin.zonedSchedule(
        base + weekday,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: payload,
      );
    }
  } else {
    final next = alarm.nextOccurrence();
    if (next == null) return;
    final when = tz.TZDateTime.from(next, tz.local);
    await _plugin.zonedSchedule(
      base,
      title,
      body,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }
}

/// Cancels every previously scheduled alarm and re-schedules all enabled ones.
/// Tasks are shown immediately (never scheduled), so pending notifications
/// are all alarm-related.
///
/// Cancels individually rather than with `cancelAll()`: a blanket cancel runs
/// on every app open / alarm edit and would silently kill a pending SNOOZE.
/// The snooze slot (base id + 0) is kept for enabled alarms that don't
/// schedule anything there themselves — repeating alarms (they use +1..+7)
/// and one-off alarms whose original time already passed.
Future<void> scheduleAlarms(List<Alarm> alarms) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;
  await initialize();
  final preserve = <int>{
    for (final a in alarms)
      if (a.enabled && (a.isRepeating || a.nextOccurrence() == null))
        _baseId(a.uid),
  };
  final pending = await _plugin.pendingNotificationRequests();
  for (final p in pending) {
    if (!preserve.contains(p.id)) {
      await _plugin.cancel(p.id);
    }
  }
  for (final alarm in alarms) {
    try {
      await _scheduleOne(alarm);
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// Action handling (snooze / dismiss)
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
  if (response.actionId != _snoozeAction) return;
  final payload = response.payload;
  if (payload == null) return;
  Map<String, dynamic> data;
  try {
    data = jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  await initialize();
  final minutes = (data['snoozeMinutes'] as int?) ?? 9;
  final snoozeId = (data['snoozeId'] as int?) ?? 0;
  final when = tz.TZDateTime.now(tz.local).add(Duration(minutes: minutes));
  try {
    await _plugin.zonedSchedule(
      snoozeId,
      data['name'] as String? ?? 'Alarm',
      data['body'] as String?,
      when,
      _alarmDetails(
        vibrate: data['vibrate'] as bool? ?? true,
        snoozeEnabled: data['snoozeEnabled'] as bool? ?? true,
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Immediate notifications (tasks + manual alarm preview)
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
