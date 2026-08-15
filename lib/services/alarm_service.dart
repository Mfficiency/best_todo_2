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
  Future<void>? _loading;

  List<Alarm> get list => alarms.value;

  /// Loads alarms from disk (only once) and syncs the widget + schedule.
  /// Memoized: the app-start load runs deferred after the first frame and can
  /// race the alarms page's own load() — both must share one reload rather
  /// than rescheduling the OS alarms twice concurrently.
  Future<void> load() {
    if (_loaded) return Future<void>.value();
    return _loading ??= reload(persist: false, trigger: 'app start');
  }

  /// Re-reads alarms from disk, optionally persisting afterwards. Used after a
  /// background widget toggle modified the stored data.
  Future<void> reload({bool persist = true, String? trigger}) async {
    alarms.value = await _storage.loadAlarms();
    _loaded = true;
    await _afterChange(persist: persist, trigger: trigger ?? 'reload');
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
    await _afterChange(trigger: 'alarm saved');
  }

  Future<void> delete(String uid) async {
    alarms.value = alarms.value.where((a) => a.uid != uid).toList();
    await _afterChange(trigger: 'alarm deleted');
  }

  Future<void> setEnabled(String uid, bool value) async {
    final next = [...alarms.value];
    final idx = next.indexWhere((a) => a.uid == uid);
    if (idx < 0) return;
    next[idx].enabled = value;
    alarms.value = next;
    await _afterChange(
        trigger: 'alarm toggled ${value ? 'ON' : 'OFF'} in app');
  }

  /// Persists and re-syncs after an external bulk edit of [alarms]`.value`
  /// (used by the reminder sync, which rewrites linked alarms from their
  /// task's schedule).
  Future<void> commitExternalChange({String? trigger}) =>
      _afterChange(trigger: trigger ?? 'external change');

  Future<void> _afterChange({bool persist = true, String? trigger}) async {
    if (persist) {
      await _storage.saveAlarms(alarms.value);
    }
    await AlarmWidgetService.sync(alarms.value);
    // Awaited so callers running in short-lived background isolates don't get
    // torn down before the OS schedule is updated.
    await AlarmNotificationService.rescheduleAll(alarms.value,
        trigger: trigger);
  }

  /// Toggles an alarm directly against storage. Safe to call from a background
  /// isolate (the widget interactivity callback) where [instance] state may not
  /// be populated. Returns after persisting, re-syncing the widget and
  /// re-syncing the OS alarm schedule.
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
    }
    // ALWAYS re-sync the OS schedule — this often runs in the widget's
    // background isolate where the app never loaded. Skipping it there would
    // mean an alarm toggled ON from the widget never rings, and one toggled
    // OFF still fires.
    await AlarmNotificationService.rescheduleAll(alarms,
        trigger: 'home-screen widget toggle');
  }
}
