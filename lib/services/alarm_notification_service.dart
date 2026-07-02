import '../models/alarm.dart';
import 'notification_service.dart';

/// Schedules enabled alarms with the operating system so they fire at the exact
/// time even when the app process has been killed (and, on Android, after a
/// reboot). Delegates to the platform-specific notification implementation.
class AlarmNotificationService {
  AlarmNotificationService._();

  /// Requests the permissions needed to post and schedule exact alarms.
  static Future<bool> ensurePermissions() =>
      NotificationService.ensureAlarmPermissions();

  /// Cancels any previously scheduled alarms and schedules every enabled alarm
  /// in [alarms] at its next (and, for repeating alarms, recurring) fire time.
  static Future<void> rescheduleAll(List<Alarm> alarms) =>
      NotificationService.scheduleAlarms(alarms);
}
