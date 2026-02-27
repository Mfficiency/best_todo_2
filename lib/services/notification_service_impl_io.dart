import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
const String _channelId = 'task_notifications';
const String _channelName = 'Task Notifications';
const String _channelDescription = 'Manual task notifications';
bool _initialized = false;

Future<void> initialize() async {
  if (_initialized) return;

  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await _plugin.initialize(settings);

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
  }

  _initialized = true;
}

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
