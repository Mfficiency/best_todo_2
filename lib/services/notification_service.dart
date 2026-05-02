import '../config.dart';
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
}
