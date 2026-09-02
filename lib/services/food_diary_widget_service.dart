import 'package:home_widget/home_widget.dart';

import '../models/task.dart';
import 'item_views.dart';

/// Bridges today's food diary entries to the Android home-screen widget
/// (`FoodDiaryWidgetProvider`). Tapping the "+" opens the same "create
/// entry" dialog as the in-app Food Diary page (`besttodofood://add`);
/// tapping anywhere else opens the Food Diary list (`besttodofood://open`).
///
/// The widget turns red once today's running entry count falls behind the
/// checkpoint schedule: at least 1 entry by 8:00, 2 by 13:00, 3 by 16:30 and
/// 4 by 20:00 ([checkpointMinutes] / [requiredCounts]). Because the widget
/// can redraw on its own periodic schedule with the app never running, only
/// the raw "how many entries today" count is pushed from here — whether a
/// checkpoint has *passed*, and so whether the count is behind, is decided
/// against the live clock natively in `FoodDiaryWidgetProvider`
/// ([isBehindSchedule] mirrors that check for the in-app widget previews).
///
/// [checkpointMinutes] also marks off the four meal windows (breakfast
/// before 8:00, lunch 8:00-13:00, snack 13:00-16:30, dinner from 16:30) used
/// by the Food Diary page's "copy from yesterday" shortcuts —
/// [latestEntryPerMealWindow].
class FoodDiaryWidgetService {
  static const String appGroupId = 'group.homeScreenApp';
  static const String iOSWidgetName = 'FoodDiaryWidgetProvider';
  static const String androidWidgetName = 'FoodDiaryWidgetProvider';
  static const String androidButtonWidgetName = 'FoodDiaryButtonWidgetProvider';

  /// URI scheme of the clicks coming back from the widget.
  static const String scheme = 'besttodofood';
  static const String hostAdd = 'add';
  static const String hostOpen = 'open';

  /// Local minute-of-day for each checkpoint: 8:00, 13:00, 16:30, 20:00. At
  /// and after checkpoint `i`, today's log should hold at least
  /// [requiredCounts]`[i]` entries.
  static const List<int> checkpointMinutes = [
    8 * 60,
    13 * 60,
    16 * 60 + 30,
    20 * 60,
  ];

  /// Cumulative entry count required by the matching [checkpointMinutes].
  static const List<int> requiredCounts = [1, 2, 3, 4];

  /// Meal names for the four windows [checkpointMinutes] carves the day
  /// into — see [latestEntryPerMealWindow].
  static const List<String> mealNames = ['Breakfast', 'Lunch', 'Snack', 'Dinner'];

  static const String dateKey = 'food_data_date';
  static const String entryCountKey = 'food_entry_count';

  static String _dateStamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Total food diary entries due on [day] (midnight-normalized), regardless
  /// of what time of day they fall in. Pure and platform-independent, so it
  /// is unit-testable without the `home_widget` plugin — [sync] is a thin
  /// wrapper pushing this to Android.
  static int computeEntryCount(List<Task> tasks, DateTime day) {
    var count = 0;
    for (final entry in ItemViews.foodDiary(tasks)) {
      final due = entry.dueDate;
      if (due == null) continue;
      if (!_isSameDay(due, day)) continue;
      count++;
    }
    return count;
  }

  /// The most recent entry due on [day] within each of the four meal
  /// windows [checkpointMinutes] carves the day into (breakfast, lunch,
  /// snack, dinner) — `null` where nothing was logged in that window. Used
  /// by the "copy from yesterday" shortcuts in the add-entry dialog.
  static List<Task?> latestEntryPerMealWindow(List<Task> tasks, DateTime day) {
    final latest = List<Task?>.filled(mealNames.length, null);
    for (final entry in ItemViews.foodDiary(tasks)) {
      final due = entry.dueDate;
      if (due == null) continue;
      if (!_isSameDay(due, day)) continue;
      final minuteOfDay = due.hour * 60 + due.minute;
      for (var i = 0; i < mealNames.length; i++) {
        final start = i == 0 ? 0 : checkpointMinutes[i - 1];
        final end = i < mealNames.length - 1 ? checkpointMinutes[i] : 24 * 60;
        if (minuteOfDay < start || minuteOfDay >= end) continue;
        final existing = latest[i];
        if (existing?.dueDate == null || due.isAfter(existing!.dueDate!)) {
          latest[i] = entry;
        }
        break;
      }
    }
    return latest;
  }

  /// Whether [entryCount] is behind the cumulative schedule as of [now]:
  /// the requirement of the latest checkpoint that has already passed, or
  /// `false` before the first checkpoint. Shared by the in-app widget
  /// previews; the Android providers mirror this against their own live
  /// clock when they redraw without Flutter running.
  static bool isBehindSchedule(int entryCount, DateTime now) {
    final nowMinutes = now.hour * 60 + now.minute;
    var required = 0;
    for (var i = 0; i < checkpointMinutes.length; i++) {
      if (nowMinutes >= checkpointMinutes[i]) required = requiredCounts[i];
    }
    return entryCount < required;
  }

  /// Recomputes today's total entry count from [tasks] and pushes it to the
  /// widget. Failures are swallowed like the other widget services:
  /// platforms without the plugin must keep working.
  static Future<void> sync(List<Task> tasks, {DateTime? now}) async {
    final current = now ?? DateTime.now();
    final today = DateTime(current.year, current.month, current.day);
    final entryCount = computeEntryCount(tasks, today);

    try {
      await HomeWidget.setAppGroupId(appGroupId);
      await HomeWidget.saveWidgetData<String>(dateKey, _dateStamp(today));
      await HomeWidget.saveWidgetData<int>(entryCountKey, entryCount);
      await HomeWidget.updateWidget(
          iOSName: iOSWidgetName, androidName: androidWidgetName);
      await HomeWidget.updateWidget(androidName: androidButtonWidgetName);
    } catch (_) {}
  }
}
