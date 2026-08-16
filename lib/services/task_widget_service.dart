import 'package:home_widget/home_widget.dart';

import '../config.dart';
import '../models/task.dart';
import 'storage_service.dart';
import 'streak_service.dart';

/// Bridges today's task list to the Android home-screen widget
/// (`SimpleWidgetProvider`).
///
/// The widget has two looks, picked by [Config.widgetCheckboxes]:
///  * off (default) — the read-only text summary it always had
///    ([textKey]) plus the progress line;
///  * on — one tappable row per task ([maxRows] slots of id/title/done), each
///    wired on the native side to `besttodotask://toggle?id=…`, which lands in
///    the background isolate and comes back here as [toggleInStorage].
///
/// Both looks share the same payload, so the provider can switch between them
/// without the app pushing different data.
class TaskWidgetService {
  static const String appGroupId = 'group.homeScreenApp';
  static const String iOSWidgetName = 'SimpleWidgetProvider';
  static const String androidWidgetName = 'SimpleWidgetProvider';

  static const String textKey = 'text_from_flutter_app';
  static const String progressVisibleKey = 'widget_progress_visible';
  static const String progressPercentKey = 'widget_progress_percent';
  static const String progressColorKey = 'widget_progress_color';

  /// Whether the widget draws checkbox rows instead of the text summary.
  static const String checkableKey = 'widget_checkable';

  /// Number of row slots actually filled, and how many tasks did not fit.
  static const String rowCountKey = 'widget_task_count';
  static const String overflowKey = 'widget_task_overflow';

  /// Row slots the widget layout provides.
  static const int maxRows = 5;

  /// URI scheme of the clicks coming back from the widget.
  static const String scheme = 'besttodotask';
  static const String hostToggle = 'toggle';

  /// Today's list as the widget shows it: everything due today or earlier,
  /// open tasks first (in list order) so a full slate still shows what is
  /// left, with the completed ones after them for un-checking.
  static List<Task> todayTasks(List<Task> tasks, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final due = tasks.where((t) {
      if (t.dueDate == null) return false;
      final d = DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
      return !d.isAfter(today);
    }).toList()
      ..sort((a, b) =>
          (a.listRanking ?? 1 << 31).compareTo(b.listRanking ?? 1 << 31));
    return [
      ...due.where((t) => !t.isDone),
      ...due.where((t) => t.isDone),
    ];
  }

  /// Recomputes the whole widget payload from [tasks] and asks the widget to
  /// redraw. Failures are swallowed: platforms without the plugin (web,
  /// desktop, tests) must keep working.
  static Future<void> sync(List<Task> tasks, {DateTime? now}) async {
    final rows = todayTasks(tasks, now: now);
    final openTasks = rows.where((t) => !t.isDone).toList();
    final totalCount = rows.length;
    final completedCount = totalCount - openTasks.length;
    final remainingCount = openTasks.length;
    final percent = totalCount == 0
        ? 0
        : ((completedCount / totalCount) * 100).round().clamp(0, 100);

    String progressColor = 'green';
    if (completedCount == totalCount && totalCount > 0) {
      progressColor = 'green';
    } else if (remainingCount >= 5) {
      progressColor = 'red';
    } else if (remainingCount == 4) {
      progressColor = 'orange';
    }

    final text = openTasks.isEmpty
        ? 'Well done!\nNo more tasks for today!'
        : openTasks.map((t) => '- ${t.title}').join('\n');

    try {
      await HomeWidget.setAppGroupId(appGroupId);
      await HomeWidget.saveWidgetData<String>(textKey, text);
      await HomeWidget.saveWidgetData<bool>(
          progressVisibleKey, Config.showWidgetProgressLine);
      await HomeWidget.saveWidgetData<int>(progressPercentKey, percent);
      await HomeWidget.saveWidgetData<String>(progressColorKey, progressColor);
      await HomeWidget.saveWidgetData<bool>(
          checkableKey, Config.widgetCheckboxes);

      final shown = rows.length > maxRows ? maxRows : rows.length;
      await HomeWidget.saveWidgetData<int>(rowCountKey, shown);
      await HomeWidget.saveWidgetData<int>(overflowKey, rows.length - shown);
      for (var i = 0; i < maxRows; i++) {
        if (i < shown) {
          final task = rows[i];
          await HomeWidget.saveWidgetData<String>('widget_task_${i}_id', task.uid);
          await HomeWidget.saveWidgetData<String>(
              'widget_task_${i}_title',
              task.title.trim().isEmpty ? '(no title)' : task.title.trim());
          await HomeWidget.saveWidgetData<bool>(
              'widget_task_${i}_done', task.isDone);
        } else {
          await HomeWidget.saveWidgetData<String>('widget_task_${i}_id', '');
        }
      }

      await HomeWidget.updateWidget(
          iOSName: iOSWidgetName, androidName: androidWidgetName);
    } catch (_) {}
  }

  /// Flips one task's done state straight in storage. Runs in the widget's
  /// background isolate (the app may not even be running), so it works against
  /// the files rather than any in-memory list, and pushes the fresh payload
  /// back to the widget afterwards.
  static Future<void> toggleInStorage(String uid, {DateTime? now}) async {
    final storage = StorageService();
    final tasks = await storage.loadTaskList();
    final index = tasks.indexWhere((t) => t.uid == uid);
    if (index < 0) return;
    final task = tasks[index];
    final at = now ?? DateTime.now();
    task.toggleDone();
    task.completedAt = task.isDone ? at : null;
    await storage.saveTaskList(tasks);

    // The flame counts widget completions too. Wrapped: in the background
    // isolate the reminder re-sync talks to the notification plugin, which is
    // allowed to fail there without losing the completion itself.
    if (!task.isWish && Config.isFeatureEnabled('streak')) {
      try {
        await StreakService.instance.load();
        if (task.isDone) {
          StreakService.instance.recordCompletion(at);
        } else {
          StreakService.instance.recordUncompletion(at);
        }
        await StreakService.instance.saveNow();
      } catch (_) {}
    }

    await sync(tasks, now: at);
  }
}
