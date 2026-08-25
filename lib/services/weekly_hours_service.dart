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
class WeeklyHoursService {
  WeeklyHoursService._();

  static final WeeklyHoursService instance = WeeklyHoursService._();

  static const _fileName = 'weekly_hours_plan.json';

  final ValueNotifier<WeeklyHoursPlan> plan =
      ValueNotifier<WeeklyHoursPlan>(WeeklyHoursPlan.defaultPlan());
  bool _loaded = false;

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

  /// Resets in-memory state (for tests).
  @visibleForTesting
  void resetForTest() {
    plan.value = WeeklyHoursPlan.defaultPlan();
    _loaded = false;
  }
}
