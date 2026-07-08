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
  String? uid,
  String? melody,
  double? volume,
  bool overrideDnd = false,
}) async {
  return false;
}

Future<void> silenceAlarmNotification(Map<String, dynamic> payload) async {}

void Function(Map<String, dynamic> payload)? onAlarmRing;

Future<Map<String, dynamic>?> getAlarmLaunchPayload() async => null;

Future<void> dismissAlarmFromRing(Map<String, dynamic> payload) async {}

Future<void> snoozeAlarmFromRing(Map<String, dynamic> payload) async {}

Future<bool> ensureAlarmPermissions() async => false;

Future<void> scheduleAlarms(List<Alarm> alarms,
    {String trigger = 'alarms changed'}) async {}

Future<void> scheduleTestAlarm({int delaySeconds = 60}) async {}

Future<void> runAlarmDiagnostics({String trigger = 'manual'}) async {}
