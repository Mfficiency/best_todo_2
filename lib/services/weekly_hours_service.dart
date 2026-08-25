import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/weekly_hours_plan.dart';

/// Persists the Weekly Hours Planner's [WeeklyHoursPlan] to
/// `weekly_hours_plan.json` in the app documents directory. Seeded with
/// [WeeklyHoursPlan.defaultPlan] on first run. Persistence is unavailable on
/// platforms without a documents directory (e.g. Flutter web and widget
/// tests), so failures are swallowed and the seeded plan keeps working
/// in-memory.
///
/// Also persists per-week [WeeklyActual] records (`weekly_hours_actuals.json`)
/// — the manual over/undertime entry that goes with whichever week the
/// planner page is navigated to, since the plan itself carries no date.
class WeeklyHoursService {
  WeeklyHoursService._();

  static final WeeklyHoursService instance = WeeklyHoursService._();

  static const _fileName = 'weekly_hours_plan.json';
  static const _actualsFileName = 'weekly_hours_actuals.json';

  final ValueNotifier<WeeklyHoursPlan> plan =
      ValueNotifier<WeeklyHoursPlan>(WeeklyHoursPlan.defaultPlan());
  bool _loaded = false;

  final ValueNotifier<List<WeeklyActual>> actuals =
      ValueNotifier<List<WeeklyActual>>(<WeeklyActual>[]);
  bool _actualsLoaded = false;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Loads the plan from disk (only once). Seeds and persists the default
  /// plan when no file exists yet.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        await _save();
        return;
      }
      final data = jsonDecode(await file.readAsString());
      if (data is Map) {
        plan.value = WeeklyHoursPlan.fromJson(Map<String, dynamic>.from(data));
      }
    } catch (_) {}
  }

  Future<void> updatePlan(WeeklyHoursPlan next) async {
    plan.value = next;
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(plan.value.toJson()), flush: true);
    } catch (_) {}
  }

  Future<File> _getActualsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_actualsFileName');
  }

  /// Loads the per-week actuals from disk (only once; empty until then).
  Future<void> loadActuals() async {
    if (_actualsLoaded) return;
    _actualsLoaded = true;
    try {
      final file = await _getActualsFile();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (data is List) {
        actuals.value = [
          for (final entry in data)
            if (entry is Map)
              WeeklyActual.fromJson(Map<String, dynamic>.from(entry)),
        ];
      }
    } catch (_) {}
  }

  /// The actual over/undertime recorded for the week containing [date], or a
  /// zeroed, unpersisted record if none exists yet.
  WeeklyActual actualFor(DateTime date) {
    final weekStart = WeeklyActual.mondayOf(date);
    for (final actual in actuals.value) {
      if (actual.weekStart == weekStart) return actual;
    }
    return WeeklyActual(weekStart: weekStart);
  }

  /// Persists [actual] (insert or replace by week), dropping it instead when
  /// it goes back to zero so an untouched week never gets a stale row.
  Future<void> saveActual(WeeklyActual actual) async {
    final next = [...actuals.value];
    final idx = next.indexWhere((a) => a.weekStart == actual.weekStart);
    if (actual.overUndertimeMinutes == 0) {
      if (idx >= 0) next.removeAt(idx);
    } else if (idx >= 0) {
      next[idx] = actual;
    } else {
      next.add(actual);
    }
    actuals.value = next;
    await _saveActuals();
  }

  Future<void> _saveActuals() async {
    try {
      final file = await _getActualsFile();
      final jsonString =
          jsonEncode(actuals.value.map((a) => a.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {}
  }

  /// Resets in-memory state (for tests).
  @visibleForTesting
  void resetForTest() {
    plan.value = WeeklyHoursPlan.defaultPlan();
    _loaded = false;
    actuals.value = <WeeklyActual>[];
    _actualsLoaded = false;
  }
}
