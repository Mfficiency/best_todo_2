import 'dart:async';
import 'dart:html' as html;

import '../models/alarm.dart';

Future<void> initialize() async {}

Future<bool> _ensurePermission() async {
  if (!html.Notification.supported) return false;
  if (html.Notification.permission == 'granted') return true;
  final permission = await html.Notification.requestPermission();
  return permission == 'granted';
}

void _showNow(String taskTitle) {
  final title = taskTitle.trim().isEmpty ? 'Task' : taskTitle.trim();
  html.Notification(title);
}

Future<bool> showTaskNotification(
  String taskTitle, {
  int delaySeconds = 0,
}) async {
  final hasPermission = await _ensurePermission();
  if (!hasPermission) return false;

  if (delaySeconds > 0) {
    Future.delayed(Duration(seconds: delaySeconds), () {
      _showNow(taskTitle);
    });
    return true;
  }

  _showNow(taskTitle);
  return true;
}

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
  html.Notification(safeTitle, body: body.isEmpty ? null : body);
  return true;
}

Future<void> silenceAlarmNotification(Map<String, dynamic> payload) async {}

Future<bool> ensureAlarmPermissions() async => _ensurePermission();

Future<void> scheduleAlarms(List<Alarm> alarms,
    {String trigger = 'alarms changed'}) async {}

Future<void> scheduleTestAlarm({int delaySeconds = 60}) async {}

Future<void> runAlarmDiagnostics({String trigger = 'manual'}) async {}

void Function(Map<String, dynamic> payload)? onAlarmRing;

Future<Map<String, dynamic>?> getAlarmLaunchPayload() async => null;

Future<void> dismissAlarmFromRing(Map<String, dynamic> payload) async {}

Future<void> snoozeAlarmFromRing(Map<String, dynamic> payload) async {}
