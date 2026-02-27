import 'dart:async';
import 'dart:html' as html;

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
