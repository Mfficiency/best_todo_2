import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import '../models/task.dart';
import '../services/storage_service.dart';

const String _taskName = 'widgetRefresh';
const String _appGroupId = 'group.homeScreenApp';
const String _iOSWidgetName = 'SimpleWidgetProvider';
const String _androidWidgetName = 'SimpleWidgetProvider';
const String _dataKey = 'text_from_flutter_app';

class WidgetRefreshService {
  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );
  }

  static Future<void> schedule() async {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final delay = nextMidnight.difference(now);
    await Workmanager().cancelByUniqueName(_taskName);
    await Workmanager().registerOneOffTask(
      _taskName,
      _taskName,
      initialDelay: delay,
      constraints: Constraints(
        networkType: NetworkType.not_required,
      ),
    );
  }

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(_taskName);
  }
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == _taskName) {
      final storage = StorageService();
      final tasks = await storage.loadTaskList();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dueTasks = tasks
          .where((t) {
            final due = t.dueDate;
            if (due == null) return false;
            final d = DateTime(due.year, due.month, due.day);
            return !t.isDone && !d.isAfter(today);
          })
          .toList()
        ..sort((a, b) => (a.listRanking ?? (1 << 31))
            .compareTo(b.listRanking ?? (1 << 31)));
      final data = dueTasks.map((t) => '• ${t.title}').join('\n');
      try {
        await HomeWidget.setAppGroupId(_appGroupId);
        await HomeWidget.saveWidgetData(_dataKey, data);
        await HomeWidget.updateWidget(
          iOSName: _iOSWidgetName,
          androidName: _androidWidgetName,
        );
      } catch (_) {}

      final now2 = DateTime.now();
      final next = DateTime(now2.year, now2.month, now2.day + 1);
      final delay = next.difference(now2);
      await Workmanager().registerOneOffTask(
        _taskName,
        _taskName,
        initialDelay: delay,
        constraints: Constraints(
          networkType: NetworkType.not_required,
        ),
      );
    }
    return Future.value(true);
  });
}

