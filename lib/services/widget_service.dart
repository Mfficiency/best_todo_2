import 'package:home_widget/home_widget.dart';

/// Utility methods for updating the Android home screen widget.
class WidgetService {
  static const _androidWidgetName = 'SimpleWidgetProvider';
  static const _dataKey = 'task_summary';

  /// Send the given summary text to the home screen widget and refresh it.
  static Future<void> updateTaskSummary(String summary) async {
    await HomeWidget.saveWidgetData(_dataKey, summary);
    await HomeWidget.updateWidget(androidName: _androidWidgetName);
  }
}
