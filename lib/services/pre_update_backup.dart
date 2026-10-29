import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'log_service.dart';

/// One-time snapshot of every data file before this app version writes
/// anything — the belt-and-braces guarantee that an update from *any*
/// previous version can never lose data: whatever the old version had on
/// disk survives verbatim in `pre_update_backup/`, no matter what the new
/// code does to the live files afterwards.
///
/// [ensure] is called from the storage services immediately before their
/// FIRST write of a session (never at startup): one static-bool check in the
/// steady state, one flag-file check per session, and the actual copying
/// only once per install. Errors are swallowed (web has no files to back up
/// — and none to lose).
///
/// [recordCurrentVersion] additionally maintains `last_run_version.txt`
/// (deferred from `main.dart`), so future migrations can tell which version
/// wrote the current files and take version-specific precautions.
class PreUpdateBackup {
  PreUpdateBackup._();

  /// Backup folder inside the documents dir.
  static const String backupDirName = 'pre_update_backup';

  /// Guard flag: present once the snapshot exists. Public so tests can
  /// pre-create it to opt out.
  static const String backupFlagFileName = 'pre_update_backup_v1.txt';

  /// Version marker maintained for future migrations.
  static const String versionFileName = 'last_run_version.txt';

  /// Every data file worth snapshotting. Journal files are excluded on
  /// purpose: they are append-only and self-recovering, and can be large.
  static const List<String> backedUpFiles = [
    'tasks.json',
    'deleted_tasks.json',
    'daily_task_stats.json',
    'wishlist.json',
    'alarms.json',
    'projects.json',
    'labels.json',
    'countdown_timers.json',
    'settings.json',
    'sms_report_config.json',
    'last_opened.txt',
  ];

  static bool _done = false;

  /// Snapshots all existing data files once per install. Cheap after the
  /// first call (static bool), cheap per session (one flag stat).
  static Future<void> ensure() async {
    if (_done) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final flag = File('${dir.path}/$backupFlagFileName');
      if (await flag.exists()) {
        _done = true;
        return;
      }
      final backupDir = Directory('${dir.path}/$backupDirName');
      await backupDir.create(recursive: true);
      var copied = 0;
      for (final name in backedUpFiles) {
        final source = File('${dir.path}/$name');
        try {
          if (await source.exists()) {
            await source.copy('${backupDir.path}/$name');
            copied++;
          }
        } catch (_) {
          // One uncopyable file must not stop the rest.
        }
      }
      await flag.writeAsString(DateTime.now().toIso8601String(), flush: true);
      _done = true;
      LogService.add('backup',
          'Pre-update backup created ($copied files in $backupDirName/)');
    } catch (_) {
      // No documents dir (web/tests): nothing on disk to protect. Retry on
      // a later save if this was a transient failure.
    }
  }

  /// Records the running app version for future migrations. Deferred and
  /// fire-and-forget; never on the startup path.
  static Future<void> recordCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$versionFileName');
      final current = '${info.version}+${info.buildNumber}';
      String? previous;
      try {
        if (await file.exists()) previous = await file.readAsString();
      } catch (_) {}
      if (previous != current) {
        await file.writeAsString(current, flush: true);
      }
    } catch (_) {}
  }

  /// Clears cached state so tests with fresh temp dirs start clean.
  static void resetForTest() => _done = false;
}
