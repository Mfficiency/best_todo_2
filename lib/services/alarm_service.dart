import 'package:flutter/foundation.dart';

import '../models/alarm.dart';
import 'alarm_notification_service.dart';
import 'alarm_storage_service.dart';
import 'alarm_widget_service.dart';

/// Single source of truth for alarms shared between the alarms page and the
/// home-screen widget click handling. Holds the alarms in a [ValueNotifier] so
/// the UI rebuilds when an alarm is toggled from the widget.
class AlarmService {
  AlarmService._();

  static final AlarmService instance = AlarmService._();

  final AlarmStorageService _storage = AlarmStorageService();
  final ValueNotifier<List<Alarm>> alarms = ValueNotifier<List<Alarm>>(<Alarm>[]);
  bool _loaded = false;

  List<Alarm> get list => alarms.value;

  /// Loads alarms from disk (only once) and syncs the widget + schedule.
  Future<void> load() async {
    if (_loaded) return;
    await reload(persist: false);
    _loaded = true;
  }

  /// Re-reads alarms from disk, optionally persisting afterwards. Used after a
  /// background widget toggle modified the stored data.
  Future<void> reload({bool persist = true}) async {
    alarms.value = await _storage.loadAlarms();
    _loaded = true;
    await _afterChange(persist: persist);
  }

  Future<void> upsert(Alarm alarm) async {
    final next = [...alarms.value];
    final idx = next.indexWhere((a) => a.uid == alarm.uid);
    if (idx >= 0) {
      next[idx] = alarm;
    } else {
      next.add(alarm);
    }
    alarms.value = next;
    await _afterChange();
  }

  Future<void> delete(String uid) async {
    alarms.value = alarms.value.where((a) => a.uid != uid).toList();
    await _afterChange();
  }

  Future<void> setEnabled(String uid, bool value) async {
    final next = [...alarms.value];
    final idx = next.indexWhere((a) => a.uid == uid);
    if (idx < 0) return;
    next[idx].enabled = value;
    alarms.value = next;
    await _afterChange();
  }

  Future<void> _afterChange({bool persist = true}) async {
    if (persist) {
      await _storage.saveAlarms(alarms.value);
    }
    await AlarmWidgetService.sync(alarms.value);
    AlarmNotificationService.rescheduleAll(alarms.value);
  }

  /// Toggles an alarm directly against storage. Safe to call from a background
  /// isolate (the widget interactivity callback) where [instance] state may not
  /// be populated. Returns after persisting and re-syncing the widget.
  static Future<void> toggleInStorage(String uid) async {
    final storage = AlarmStorageService();
    final alarms = await storage.loadAlarms();
    final idx = alarms.indexWhere((a) => a.uid == uid);
    if (idx < 0) return;
    alarms[idx].enabled = !alarms[idx].enabled;
    await storage.saveAlarms(alarms);
    await AlarmWidgetService.sync(alarms);
    // Keep the in-memory list aligned if it has been loaded in this isolate.
    if (instance._loaded) {
      instance.alarms.value = alarms;
      AlarmNotificationService.rescheduleAll(alarms);
    }
  }
}
