import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config.dart';
import 'log_service.dart';
import 'notification_service.dart';

/// Asks for every runtime permission the app can use, at the two moments the
/// user expects the question instead of lazily when a feature first needs it:
///
///   • when the user picks the **full experience** — "Use everything" on the
///     mode picker, or turning simple mode off in Settings;
///   • on the **first open after an app update** (also the first open after
///     updating to the version that introduced this flow).
///
/// A version marker file (`permissions_prompted_version.txt` in the documents
/// dir) makes the after-update ask one-time per installed version; picking
/// simple mode writes the marker without asking, so the next open is not
/// mistaken for an update. The actual dialogs are Android-only; everywhere
/// else only the marker is maintained.
class PermissionFlow {
  PermissionFlow._();

  /// Marker holding the last `version+build` the flow ran (or was settled) for.
  static const String markerFileName = 'permissions_prompted_version.txt';

  static bool _ranThisSession = false;

  /// Whether [requestAll] already ran in this app session (test hook).
  static bool get requestedThisSession => _ranThisSession;

  /// Requests every permission in one pass, at most once per app session:
  /// notifications, exact alarms, the battery-optimization exemption and
  /// full-screen intent (via [NotificationService.ensureAlarmPermissions],
  /// which logs each one to the alarm log), then SMS for the daily report.
  /// Finishes by recording the current version in the marker.
  static Future<void> requestAll({required String trigger}) async {
    if (_ranThisSession) return;
    _ranThisSession = true;
    if (!kIsWeb && Platform.isAndroid) {
      LogService.add('permissions', 'Requesting all permissions ($trigger)');
      try {
        await NotificationService.ensureAlarmPermissions();
      } catch (_) {}
      try {
        if (!await Permission.sms.isGranted) {
          await Permission.sms.request();
        }
      } catch (_) {}
    }
    await markVersionHandled();
  }

  /// Runs [requestAll] when the recorded marker version differs from the
  /// running app version — i.e. on the first open after an update. Skipped
  /// while the mode picker has never been answered: on a fresh install the
  /// picker choice settles the permission question instead.
  static Future<void> maybeRequestAfterUpdate() async {
    if (!Config.modeChosen) return;
    final current = await _currentVersion();
    if (current == null) return;
    String? prompted;
    try {
      final marker = await _markerFile();
      if (marker != null && await marker.exists()) {
        prompted = (await marker.readAsString()).trim();
      }
    } catch (_) {}
    if (prompted == current) return;
    await requestAll(
        trigger: prompted == null
            ? 'first open with the permission flow'
            : 'first open after update ($prompted → $current)');
  }

  /// Records the current version without asking anything — used when the
  /// user picks simple mode, so their next open is not treated as the first
  /// open after an update.
  static Future<void> markVersionHandled() async {
    try {
      final current = await _currentVersion();
      final marker = await _markerFile();
      if (current == null || marker == null) return;
      await marker.writeAsString(current, flush: true);
    } catch (_) {
      // No documents dir (web/tests): nothing to record.
    }
  }

  static Future<String?> _currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return null;
    }
  }

  static Future<File?> _markerFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$markerFileName');
    } catch (_) {
      return null;
    }
  }

  /// Clears the once-per-session latch so tests start clean.
  static void resetForTest() => _ranThisSession = false;
}
