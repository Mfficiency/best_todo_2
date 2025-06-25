import 'dart:convert';
import 'package:home_widget/home_widget.dart';
import 'models/task.dart';
import 'services/storage_service.dart';

class HomeWidgetHelper {
  static const String widgetName = 'TodayWidgetProvider';

  static Future<void> updateTodayWidget(List<Task> tasks) async {
    final today = DateTime.now();
    final todayTasks = tasks.where((t) {
      if (t.dueDate == null) return false;
      return !t.dueDate!.isAfter(DateTime(today.year, today.month, today.day));
    }).map((t) => t.title).toList();

    await HomeWidget.saveWidgetData<String>('tasks', jsonEncode(todayTasks));
    await HomeWidget.updateWidget(name: widgetName);
  }
}
