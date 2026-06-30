import 'package:home_widget/home_widget.dart';

import '../models/alarm.dart';

/// Bridges the alarm list to the Android home-screen widget. The widget can
/// show a handful of alarms, toggle them on/off and open the editor, so we push
/// a fixed number of slots of data and wire the click URIs on the native side.
class AlarmWidgetService {
  static const String appGroupId = 'group.homeScreenApp';
  static const String iOSWidgetName = 'AlarmsWidgetProvider';
  static const String androidWidgetName = 'AlarmsWidgetProvider';

  /// Number of alarm rows the widget can render.
  static const int maxRows = 4;

  /// URI scheme used for clicks coming back from the widget.
  static const String scheme = 'besttodoalarm';
  static const String hostToggle = 'toggle';
  static const String hostEdit = 'edit';
  static const String hostOpen = 'open';

  static Future<void> _ready() async {
    await HomeWidget.setAppGroupId(appGroupId).catchError((_) {});
  }

  /// Pushes the current alarm list to the widget and asks it to redraw.
  static Future<void> sync(List<Alarm> alarms) async {
    try {
      await _ready();
      final sorted = [...alarms]..sort((a, b) {
          final am = a.hour * 60 + a.minute;
          final bm = b.hour * 60 + b.minute;
          return am.compareTo(bm);
        });

      await HomeWidget.saveWidgetData<int>('alarm_count', sorted.length);
      for (var i = 0; i < maxRows; i++) {
        if (i < sorted.length) {
          final a = sorted[i];
          await HomeWidget.saveWidgetData<String>('alarm_${i}_id', a.uid);
          await HomeWidget.saveWidgetData<String>('alarm_${i}_time', a.timeLabel);
          await HomeWidget.saveWidgetData<String>(
              'alarm_${i}_name', a.name.isEmpty ? 'Alarm' : a.name);
          await HomeWidget.saveWidgetData<String>(
              'alarm_${i}_sub', a.scheduleLabel);
          await HomeWidget.saveWidgetData<bool>('alarm_${i}_on', a.enabled);
          await HomeWidget.saveWidgetData<int>('alarm_${i}_color', a.color);
        } else {
          await HomeWidget.saveWidgetData<String>('alarm_${i}_id', '');
        }
      }
      await HomeWidget.updateWidget(
        iOSName: iOSWidgetName,
        androidName: androidWidgetName,
      );
    } catch (_) {}
  }
}
