import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'package:home_widget/home_widget.dart';

import 'services/storage_service.dart';

const String widgetUpdateTask = 'dailyWidgetUpdate';
const String appGroupId = 'group.homeScreenApp';
const String iOSWidgetName = 'SimpleWidgetProvider';
const String androidWidgetName = 'SimpleWidgetProvider';
const String dataKey = 'text_from_flutter_app';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    await HomeWidget.setAppGroupId(appGroupId).catchError((_) {});

    final storage = StorageService();
    final tasks = await storage.loadTaskList();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final data = tasks
        .where((t) {
          if (t.dueDate == null) return false;
          final due = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
          return !t.isDone && !due.isAfter(today);
        })
        .map((t) => '• ${t.title}')
        .join('\n');

    await HomeWidget.saveWidgetData(dataKey, data);
    await HomeWidget.updateWidget(
        iOSName: iOSWidgetName, androidName: androidWidgetName);
    return Future.value(true);
  });
}

void registerWidgetUpdate() {
  final now = DateTime.now();
  final nextMidnight = DateTime(now.year, now.month, now.day + 1);
  final initialDelay = nextMidnight.difference(now);
  Workmanager().registerPeriodicTask(
    widgetUpdateTask,
    widgetUpdateTask,
    frequency: const Duration(days: 1),
    initialDelay: initialDelay,
    constraints: const Constraints(networkType: NetworkType.not_required),
    existingWorkPolicy: ExistingWorkPolicy.keep,
  );
}

void cancelWidgetUpdate() {
  Workmanager().cancelByUniqueName(widgetUpdateTask);
}
