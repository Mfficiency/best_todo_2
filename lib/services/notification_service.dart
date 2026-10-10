import '../config.dart';
import '../models/alarm.dart';
import 'notification_service_impl_stub.dart'
    if (dart.library.io) 'notification_service_impl_io.dart'
    if (dart.library.html) 'notification_service_impl_web.dart' as impl;

class NotificationService {
  static Future<void> initialize() => impl.initialize();

  static bool _isMinuteInQuietHours(
    int minuteOfDay,
    int startMinute,
    int endMinute,
  ) {
    if (startMinute == endMinute) return true;
    if (startMinute < endMinute) {
      return minuteOfDay >= startMinute && minuteOfDay < endMinute;
    }
    return minuteOfDay >= startMinute || minuteOfDay < endMinute;
  }

  static DateTime _shiftOutOfQuietHours(DateTime dateTime) {
    if (!Config.quietHoursEnabled) return dateTime;

    final startMinute = Config.quietHoursStartMinutes.clamp(0, 1439);
    final endMinute = Config.quietHoursEndMinutes.clamp(0, 1439);
    final minuteOfDay = dateTime.hour * 60 + dateTime.minute;
    final inQuietHours = _isMinuteInQuietHours(
      minuteOfDay,
      startMinute,
      endMinute,
    );
    if (!inQuietHours) return dateTime;

    final day = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final endHour = endMinute ~/ 60;
    final endMin = endMinute % 60;

    if (startMinute <= endMinute) {
      return DateTime(day.year, day.month, day.day, endHour, endMin);
    }

    if (minuteOfDay >= startMinute) {
      final tomorrow = day.add(const Duration(days: 1));
      return DateTime(
          tomorrow.year, tomorrow.month, tomorrow.day, endHour, endMin);
    }

    return DateTime(day.year, day.month, day.day, endHour, endMin);
  }

  static Future<bool> showTaskNotification(
    String taskTitle, {
    int? delaySeconds,
  }) async {
    if (!Config.enableNotifications) return false;
    final requestedDelay =
        delaySeconds ?? Config.defaultNotificationDelaySeconds;
    final fireAt = DateTime.now().add(Duration(seconds: requestedDelay));
    final shiftedFireAt = _shiftOutOfQuietHours(fireAt);
    final effectiveDelay =
        shiftedFireAt.difference(DateTime.now()).inSeconds.clamp(0, 1 << 30);
    return impl.showTaskNotification(taskTitle, delaySeconds: effectiveDelay);
  }

  /// Schedules one of the user's streak reminders as a one-shot notification.
  /// [slot] is its index in the reminder list and picks the fixed
  /// notification id; [loud] chooses sound and vibration over a silent
  /// notification. The streak service cancels every slot and re-arms them on
  /// every app start, recorded event and settings change, so one pending
  /// schedule per reminder is always enough.
  static Future<void> scheduleStreakReminderSlot({
    required int slot,
    required DateTime fireAt,
    required String body,
    required bool loud,
  }) =>
      impl.scheduleStreakReminderSlot(
        slot: slot,
        fireAt: fireAt,
        body: body,
        loud: loud,
      );

  /// Cancels every pending streak reminder (streak hidden, reminders off, or
  /// about to be re-armed), including the single reminder older versions
  /// scheduled under its own id.
  static Future<void> cancelStreakReminders() => impl.cancelStreakReminders();

  /// Arms the dice timer's end-of-countdown ring as a real OS alarm, so zero
  /// rings (full screen, insistent, stoppable with one button) even when the
  /// app is closed or the phone is locked. Pass [melody]/[volume] only when
  /// the timer should play a melody — without them the ring stays silent.
  static Future<void> scheduleDiceTimerAlarm({
    required DateTime fireAt,
    required String taskTitle,
    required bool vibrate,
    String? melody,
    double? volume,
  }) =>
      impl.scheduleDiceTimerAlarm(
        fireAt: fireAt,
        taskTitle: taskTitle,
        vibrate: vibrate,
        melody: melody,
        volume: volume,
      );

  /// Drops the armed dice ring (paused, rewound, extended or finished early).
  static Future<void> cancelDiceTimerAlarm() => impl.cancelDiceTimerAlarm();

  /// Shows an alarm alert immediately. Used by the watchdog backup path when
  /// an alarm's fire time was missed. With [uid] the notification carries the
  /// alarm payload so the full-screen ring UI can open for it. [melody],
  /// [volume] and [overrideDnd] ride along in the payload so the ring UI can
  /// play the alarm's own sound at its own loudness.
  static Future<bool> showAlarmNotification(
    String title,
    String body, {
    bool vibrate = true,
    String? uid,
    String? melody,
    double? volume,
    bool overrideDnd = false,
  }) {
    return impl.showAlarmNotification(
      title,
      body,
      vibrate: vibrate,
      uid: uid,
      melody: melody,
      volume: volume,
      overrideDnd: overrideDnd,
    );
  }

  /// Moves a ringing alarm's notification onto a sound-less channel (keeping
  /// its actions and vibration) once the full-screen ring UI has taken over
  /// sound playback, so the channel's default sound and the alarm's melody
  /// don't play on top of each other.
  static Future<void> silenceAlarmNotification(Map<String, dynamic> payload) =>
      impl.silenceAlarmNotification(payload);

  /// Registers the handler invoked (on the main isolate) with the alarm
  /// payload when a ringing alarm should present the full-screen ring UI.
  static void setOnAlarmRing(
      void Function(Map<String, dynamic> payload)? handler) {
    impl.onAlarmRing = handler;
  }

  /// Payload of the alarm notification that launched the app (tap or
  /// full-screen intent over the lock screen); null on a normal start.
  static Future<Map<String, dynamic>?> getAlarmLaunchPayload() =>
      impl.getAlarmLaunchPayload();

  /// Stops a ringing alarm from the full-screen ring page.
  static Future<void> dismissAlarmFromRing(Map<String, dynamic> payload) =>
      impl.dismissAlarmFromRing(payload);

  /// Snoozes a ringing alarm from the full-screen ring page.
  static Future<void> snoozeAlarmFromRing(Map<String, dynamic> payload) =>
      impl.snoozeAlarmFromRing(payload);

  /// Requests the permissions required to fire exact alarms.
  static Future<bool> ensureAlarmPermissions() => impl.ensureAlarmPermissions();

  /// Cancels existing scheduled alarms and schedules all enabled ones at their
  /// exact fire time. Survives app termination and device reboot on Android.
  /// [trigger] is written to the alarm log so the file shows WHY a reschedule
  /// ran (app start, alarm saved, widget toggle, ...).
  static Future<void> scheduleAlarms(List<Alarm> alarms, {String? trigger}) =>
      impl.scheduleAlarms(alarms, trigger: trigger ?? 'alarms changed');

  /// Schedules a one-off test alarm ~1 minute out through the full pipeline
  /// (method ladder + OS verify + watchdog) so the user can exercise the whole
  /// chain and read the outcome in the alarm log.
  static Future<void> scheduleTestAlarm({int delaySeconds = 60}) =>
      impl.scheduleTestAlarm(delaySeconds: delaySeconds);

  /// Writes a full device/permission/schedule snapshot to the alarm log.
  static Future<void> runAlarmDiagnostics({String trigger = 'manual'}) =>
      impl.runAlarmDiagnostics(trigger: trigger);
}
