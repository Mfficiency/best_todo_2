import '../models/alarm.dart';

Future<void> initialize() async {}

Future<bool> showTaskNotification(
  String taskTitle, {
  int delaySeconds = 0,
}) async {
  return false;
}

Future<bool> showAlarmNotification(
  String title,
  String body, {
  bool vibrate = true,
}) async {
  return false;
}

Future<bool> ensureAlarmPermissions() async => false;

Future<void> scheduleAlarms(List<Alarm> alarms) async {}
