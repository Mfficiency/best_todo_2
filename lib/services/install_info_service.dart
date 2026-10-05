import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// The running version and when it was installed, shown at the top of the
/// Changelog so the user can tell when an (automatic) update came through.
class InstallInfo {
  InstallInfo({required this.version, required this.installedAt});

  final String version;
  final DateTime installedAt;
}

/// Reads when the running build was installed: Android's own
/// `PackageInfo.lastUpdateTime` (via the `besttodo/update` channel, shared
/// by both apps), or — where that isn't available (Windows, tests, an older
/// native side) — the first time this version was seen running, recorded by
/// [recordLaunch] on startup.
class InstallInfoService {
  InstallInfoService._();

  static const MethodChannel _channel = MethodChannel('besttodo/update');
  static const String _firstSeenPrefsKey = 'install_info_first_seen';

  /// Replaces the native lookup in tests; return null to fall back to the
  /// first-seen record.
  static Future<DateTime?> Function()? nativeOverride;

  static Future<DateTime?> _nativeLastUpdateTime() async {
    final override = nativeOverride;
    if (override != null) return override();
    try {
      final ms = await _channel.invokeMethod<int>('lastUpdateTime');
      return ms == null || ms <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static Future<String> _currentVersion() async {
    await Config.ensureVersionLoaded();
    return Config.versionWithBuild;
  }

  /// Remembers when the current version was first seen running, unless it
  /// already is. Errors are swallowed, like the rest of the app's storage.
  static Future<DateTime?> recordLaunch({DateTime? now}) async {
    try {
      final version = await _currentVersion();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_firstSeenPrefsKey);
      if (raw != null) {
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        if (saved['version'] == version) {
          return DateTime.fromMillisecondsSinceEpoch(saved['at'] as int);
        }
      }
      final at = now ?? DateTime.now();
      await prefs.setString(_firstSeenPrefsKey,
          jsonEncode({'version': version, 'at': at.millisecondsSinceEpoch}));
      return at;
    } catch (_) {
      return null;
    }
  }

  /// The running version and its install time; null when neither source
  /// knows (e.g. no version could be read).
  static Future<InstallInfo?> load() async {
    final version = await _currentVersion();
    if (version.isEmpty || version == 'unknown') return null;
    final at = await _nativeLastUpdateTime() ?? await recordLaunch();
    if (at == null) return null;
    return InstallInfo(version: version, installedAt: at);
  }
}

/// "2026-10-04 18:40 (2 hours ago)" — the Changelog's install line.
String formatInstalledAt(DateTime at, {DateTime? now}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${at.year}-${two(at.month)}-${two(at.day)} '
      '${two(at.hour)}:${two(at.minute)}';
  final diff = (now ?? DateTime.now()).difference(at);
  String ago;
  if (diff.inMinutes < 1) {
    ago = 'just now';
  } else if (diff.inHours < 1) {
    ago = '${diff.inMinutes} min ago';
  } else if (diff.inDays < 1) {
    ago = '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  } else {
    ago = '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }
  return '$stamp ($ago)';
}
