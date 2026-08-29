import 'package:home_widget/home_widget.dart';

import '../models/task.dart';
import 'item_views.dart';

/// Bridges today's food diary entries to the Android home-screen widget
/// (`FoodDiaryWidgetProvider`). Tapping the "+" opens the same "create
/// entry" dialog as the in-app Food Diary page (`besttodofood://add`);
/// tapping anywhere else opens the Food Diary list (`besttodofood://open`).
///
/// The widget turns red once a meal checkpoint (8:00, 13:00, 20:00 — after
/// breakfast/lunch/dinner) has passed with nothing logged in that window.
/// Because the widget can redraw on its own periodic schedule with the app
/// never running, only the "was anything logged in this window today"
/// booleans are pushed from here — whether a checkpoint has *passed* is
/// decided against the live clock natively in `FoodDiaryWidgetProvider`.
class FoodDiaryWidgetService {
  static const String appGroupId = 'group.homeScreenApp';
  static const String iOSWidgetName = 'FoodDiaryWidgetProvider';
  static const String androidWidgetName = 'FoodDiaryWidgetProvider';
  static const String androidButtonWidgetName = 'FoodDiaryButtonWidgetProvider';

  /// URI scheme of the clicks coming back from the widget.
  static const String scheme = 'besttodofood';
  static const String hostAdd = 'add';
  static const String hostOpen = 'open';

  /// Local hours the three meal checkpoints fall on: breakfast, lunch,
  /// dinner. Each window runs from its own checkpoint up to the next one
  /// (the last runs to midnight).
  static const List<int> checkpointHours = [8, 13, 20];

  static const String dateKey = 'food_data_date';
  static const List<String> hasEntryKeys = ['food_has_0', 'food_has_1', 'food_has_2'];

  static String _dateStamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static bool _inWindow(DateTime time, int i) {
    final startHour = checkpointHours[i];
    final endHour =
        i + 1 < checkpointHours.length ? checkpointHours[i + 1] : 24;
    return time.hour >= startHour && time.hour < endHour;
  }

  /// For each meal checkpoint, whether [tasks] has a food diary entry due
  /// on [today] (midnight-normalized) inside that checkpoint's window.
  /// Pure and platform-independent, so it is unit-testable without the
  /// `home_widget` plugin — [sync] is a thin wrapper pushing this to Android.
  static List<bool> computeHasEntry(List<Task> tasks, DateTime today) {
    final hasEntry = List<bool>.filled(checkpointHours.length, false);
    for (final entry in ItemViews.foodDiary(tasks)) {
      final due = entry.dueDate;
      if (due == null) continue;
      if (DateTime(due.year, due.month, due.day) != today) continue;
      for (var i = 0; i < checkpointHours.length; i++) {
        if (_inWindow(due, i)) hasEntry[i] = true;
      }
    }
    return hasEntry;
  }

  /// Whether at least one checkpoint that has started is still unlogged.
  /// Shared by in-app previews; Android providers mirror this against their
  /// live clock when they redraw without Flutter running.
  static bool hasMissedCheckpoint(List<bool> hasEntry, DateTime now) {
    for (var i = 0; i < checkpointHours.length; i++) {
      if (now.hour >= checkpointHours[i] && !hasEntry[i]) return true;
    }
    return false;
  }

  /// Recomputes today's per-window "logged something" flags from [tasks]
  /// and pushes them to the widget. Failures are swallowed like the other
  /// widget services: platforms without the plugin must keep working.
  static Future<void> sync(List<Task> tasks, {DateTime? now}) async {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final hasEntry = computeHasEntry(tasks, today);

    try {
      await HomeWidget.setAppGroupId(appGroupId);
      await HomeWidget.saveWidgetData<String>(dateKey, _dateStamp(today));
      for (var i = 0; i < hasEntryKeys.length; i++) {
        await HomeWidget.saveWidgetData<bool>(hasEntryKeys[i], hasEntry[i]);
      }
      await HomeWidget.updateWidget(
          iOSName: iOSWidgetName, androidName: androidWidgetName);
      await HomeWidget.updateWidget(androidName: androidButtonWidgetName);
    } catch (_) {}
  }
}
