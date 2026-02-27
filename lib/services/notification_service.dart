import '../config.dart';
import 'notification_service_impl_stub.dart'
    if (dart.library.io) 'notification_service_impl_io.dart'
    if (dart.library.html) 'notification_service_impl_web.dart' as impl;

class NotificationService {
  static Future<void> initialize() => impl.initialize();

  static Future<bool> showTaskNotification(
    String taskTitle, {
    int? delaySeconds,
  }) async {
    if (!Config.enableNotifications) return false;
    final effectiveDelay = delaySeconds ?? Config.defaultNotificationDelaySeconds;
    return impl.showTaskNotification(taskTitle, delaySeconds: effectiveDelay);
  }
}
