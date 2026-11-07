import 'package:home_widget/home_widget.dart';

import '../config.dart';
import '../models/streak_kind.dart';
import '../models/task.dart';
import '../models/view_filter_rules.dart';
import 'item_views.dart';
import 'storage_service.dart';
import 'streak_service.dart';
import 'wear_sync_service.dart';

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
  static const String hostComplete = 'complete';

  /// Today's list as the widget shows it: everything due today or earlier,
  /// open tasks first (in list order) so a full slate still shows what is
  /// left, with the completed ones after them for un-checking.
  ///
  /// Deleted tasks (denying one in the Waiting for Approval page
  /// soft-deletes it) and tasks still waiting for approval belong to no
  /// list, so they never reach the widget either.
  ///
  /// The widget is the Today tab on the launcher, so it filters through the
  /// same Home view rules (Settings → Filtering rules) the tab itself uses —
  /// a task hidden from Home must not reappear on the home screen. [rules]
  /// overrides them for tests; otherwise they are read from [Config].
  static List<Task> todayTasks(
    List<Task> tasks, {
    DateTime? now,
    ViewFilterRules? rules,
  }) =>
      _homeDay(tasks, now: now, rules: rules, include: (diff) => diff <= 0);

  /// Tomorrow's tasks (the Tomorrow tab: due exactly one day after today),
  /// through the same gates and in the same order as [todayTasks]. Only the
  /// Wear OS companion shows them ([WearSyncService]).
  static List<Task> tomorrowTasks(
    List<Task> tasks, {
    DateTime? now,
    ViewFilterRules? rules,
  }) =>
      _homeDay(tasks, now: now, rules: rules, include: (diff) => diff == 1);

  /// The widget's gate (deleted, [ItemViews.isVisibleInMainViews] incl. the
  /// Worklist-only `mlr` tag, the Home filter rules) for the tasks whose due
  /// day is [include]d by its distance in days from today; open ones first.
  static List<Task> _homeDay(
    List<Task> tasks, {
    DateTime? now,
    ViewFilterRules? rules,
    required bool Function(int diff) include,
  }) {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final homeRules = rules ?? Config.viewFilterRules[ViewFilterRules.home];
    final due = tasks.where((t) {
      if (t.deletedAt != null ||
          !ItemViews.isVisibleInMainViews(t) ||
          !ItemViews.passesFilterRules(t, homeRules)) {
        return false;
      }
      if (t.dueDate == null) return false;
      // Calendar days in UTC, so a DST switch can't make a 23 h "day".
      final d = t.dueDate!;
      return include(DateTime.utc(d.year, d.month, d.day)
          .difference(DateTime.utc(today.year, today.month, today.day))
          .inDays);
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
    // The Wear OS companion shows the same list (and tomorrow's).
    WearSyncService.publishTasks(tasks, now: now);
  }

  /// Flips one task's done state straight in storage. Runs in the widget's
  /// background isolate (the app may not even be running), so it works against
  /// the files rather than any in-memory list, and pushes the fresh payload
  /// back to the widget afterwards.
  static Future<void> toggleInStorage(String uid, {DateTime? now}) =>
      _setDoneInStorage(uid, null, now: now);

  /// Completes one task straight in storage (never un-completes it): the
  /// Wear OS companion's "done" when the app isn't running
  /// (`besttodotask://complete?id=`, fired by `WearCommandService.kt`), so a
  /// stale watch can't flip back a task finished on the phone. Same isolate
  /// and same steps as [toggleInStorage].
  static Future<void> completeInStorage(String uid, {DateTime? now}) =>
      _setDoneInStorage(uid, true, now: now);

  /// [done] null toggles.
  static Future<void> _setDoneInStorage(String uid, bool? done,
      {DateTime? now}) async {
    final storage = StorageService();
    final tasks = await storage.loadTaskList();
    final index = tasks.indexWhere((t) => t.uid == uid);
    if (index < 0) {
      // The row is stale — the task was deleted (or denied) while the
      // widget still showed it. Redraw from the current list so it goes.
      await sync(tasks, now: now);
      return;
    }
    final task = tasks[index];
    final at = now ?? DateTime.now();
    if (done != null && task.isDone == done) {
      await sync(tasks, now: at);
      return;
    }
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
          for (final kind in const [StreakKind.create, StreakKind.plan]) {
            final goal = Config.streakGoals[kind.id];
            if (goal != null && goal.matches(task)) {
              StreakService.instance.recordGoal(kind, at);
            }
          }
        } else {
          StreakService.instance.recordUncompletion(at);
          for (final kind in const [StreakKind.create, StreakKind.plan]) {
            final goal = Config.streakGoals[kind.id];
            if (goal != null && goal.matches(task)) {
              StreakService.instance.recordUncompletion(at, kind: kind);
            }
          }
        }
        await StreakService.instance.saveNow();
      } catch (_) {}
    }

    await sync(tasks, now: at);
  }
}
