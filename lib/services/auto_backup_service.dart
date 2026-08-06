import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../config.dart';
import '../models/item_event.dart';
import 'item_event_journal.dart';
import 'log_service.dart';
import 'storage_service.dart';

/// Scheduled full backups to a folder the user picked in Settings → Backup.
///
/// Each backup is one timestamped JSON file with the exact "Export
/// Everything" shape (settings + task bundle + countdown timers), so any
/// backup file can be restored through the regular Import button.
///
/// [maybeRun] is called when the home page has loaded and whenever the app
/// resumes; it is a no-op unless [Config.autoBackupFrequency] and
/// [Config.autoBackupDirectory] are set and the schedule says a backup is
/// due. The time of the last successful backup lives in its own marker file
/// (not in settings.json), so importing an old settings export can never
/// fake a recent backup. Errors are swallowed and logged — a missing SD
/// card or revoked folder must never break the app.
class AutoBackupService {
  AutoBackupService._();

  /// Marker file in the documents dir holding the ISO timestamp of the last
  /// successful backup.
  static const String markerFileName = 'last_auto_backup.txt';

  static Future<File> _markerFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$markerFileName');
  }

  /// When the last automatic backup was written, or null for never.
  static Future<DateTime?> lastRun() async {
    try {
      final file = await _markerFile();
      if (!await file.exists()) return null;
      return DateTime.tryParse((await file.readAsString()).trim());
    } catch (_) {
      return null;
    }
  }

  /// Whether the configured schedule calls for a backup at [now] given the
  /// [last] successful run. Daily backs up on the first check of each
  /// calendar day; weekly once seven days have passed since the last one.
  static bool isDue(DateTime? last, DateTime now) {
    switch (Config.autoBackupFrequency) {
      case 'daily':
        if (last == null) return true;
        return DateTime(last.year, last.month, last.day) !=
            DateTime(now.year, now.month, now.day);
      case 'weekly':
        if (last == null) return true;
        return DateTime(now.year, now.month, now.day)
                .difference(DateTime(last.year, last.month, last.day))
                .inDays >=
            7;
      default:
        return false;
    }
  }

  /// Runs a backup if one is due, otherwise does nothing. Cheap when
  /// automatic backups are off. Returns the written file, or null when
  /// nothing was due or the write failed.
  static Future<File?> maybeRun({DateTime? now}) async {
    if (Config.autoBackupFrequency == 'off') return null;
    if (Config.autoBackupDirectory.isEmpty) return null;
    final moment = now ?? DateTime.now();
    if (!isDue(await lastRun(), moment)) return null;
    return runNow(now: moment);
  }

  /// Writes a full backup to [Config.autoBackupDirectory] regardless of the
  /// schedule (the "Back up now" button) and records it as the last run.
  static Future<File?> runNow({DateTime? now}) async {
    final directory = Config.autoBackupDirectory;
    if (directory.isEmpty) return null;
    try {
      final moment = now ?? DateTime.now();
      // Read straight from disk instead of the home page's in-memory list,
      // so a backup is complete even when triggered before/without the UI.
      final storage = StorageService();
      final tasks = await storage.readTaskListRaw();
      final deletedTasks = await storage.loadDeletedTaskList();
      final dailyStats = await storage.loadDailyTaskStats();
      final timers = await storage.loadCountdownTimers();
      var itemEvents = const <ItemEvent>[];
      try {
        itemEvents = await ItemEventJournal.instance.allEvents();
      } catch (_) {}
      final payload = <String, dynamic>{
        'export_version': 1,
        'exported_at': moment.toIso8601String(),
        'settings': Config.toMap(),
        'tasks_bundle': storage.buildTaskExportPayload(
          tasks: tasks,
          deletedTasks: deletedTasks,
          dailyStatsByDay: dailyStats,
          itemEvents: itemEvents,
        ),
        'countdown_timers': (timers ?? []).map((t) => t.toJson()).toList(),
      };
      final sep = Platform.pathSeparator;
      final path = '$directory${directory.endsWith(sep) ? '' : sep}'
          'besttodo_backup_${_timestampForFilename(moment)}.json';
      final file = File(path);
      await file.writeAsString(jsonEncode(payload), flush: true);
      try {
        final marker = await _markerFile();
        await marker.writeAsString(moment.toIso8601String(), flush: true);
      } catch (_) {}
      LogService.add('backup', 'Automatic backup written to $path');
      return file;
    } catch (e) {
      LogService.add('backup', 'Automatic backup failed: $e');
      return null;
    }
  }

  static String _timestampForFilename(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
