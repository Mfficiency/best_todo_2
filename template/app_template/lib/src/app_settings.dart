import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';

/// How the app chooses light vs dark. `system` follows the OS setting; the
/// other two force it. Combine any of these with [AppSettings.minimalist] for
/// the calm monochrome variant (including a minimalist *dark* look).
enum AppThemeMode { system, light, dark }

/// Runtime, user-editable preferences for the shared features. A single
/// [instance] holds the live values; it is a [ChangeNotifier] so the root
/// [MaterialApp] rebuilds its theme the moment a setting changes.
///
/// Persistence is a plain JSON file in the app documents dir (errors swallowed
/// so web/tests keep working), mirroring the host app's Config. [toMap] /
/// [applyMap] are pure and drive both persistence *and* backups, so any new
/// setting is exported/imported for free.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  /// The app-wide live settings.
  static final AppSettings instance = AppSettings._();

  /// Selectable date display formats; the first is the default. Interpreted by
  /// [formatDate] in util/date_time_format.dart.
  static const List<String> dateFormats = [
    'dd.MM.yy',
    'dd.MM.yyyy',
    'dd/MM/yyyy',
    'MM/dd/yyyy',
    'yyyy-MM-dd',
    'd MMM yyyy',
  ];

  // --- Appearance -----------------------------------------------------------
  AppThemeMode themeMode = AppThemeMode.system;
  bool minimalist = false;
  bool use24HourFormat = true;
  String dateFormat = dateFormats.first;

  // --- Startup --------------------------------------------------------------
  /// Key into [AppConfig.startPages]. Defaults to the first configured page.
  String startPageKey = AppConfig.startPages.first.key;

  // --- Notifications --------------------------------------------------------
  bool notificationsEnabled = false;
  int notificationDelaySeconds = AppConfig.defaultNotificationDelaySeconds;
  bool quietHoursEnabled = AppConfig.quietHoursEnabledByDefault;
  int quietHoursStartMinutes = AppConfig.quietHoursStartMinutes;
  int quietHoursEndMinutes = AppConfig.quietHoursEndMinutes;

  ThemeMode get materialThemeMode => switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  static const _fileName = 'settings.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Loads persisted settings from disk, if present.
  Future<void> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        applyMap(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {}
  }

  /// Persists the current settings and notifies listeners so the UI/theme
  /// refresh. Call this after mutating any field.
  ///
  /// Listeners are notified *first* (optimistic: the UI updates instantly)
  /// and the file is written after. This also keeps widget tests from hanging
  /// on the plugin-backed write in the fake-async zone — the notify has already
  /// fired synchronously by the time the awaited I/O would stall.
  Future<void> save() async {
    notifyListeners();
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(toMap()), flush: true);
    } catch (_) {}
  }

  /// Serialises every setting. Also used as the `settings` block of a backup.
  Map<String, dynamic> toMap() => {
        'themeMode': themeMode.name,
        'minimalist': minimalist,
        'use24HourFormat': use24HourFormat,
        'dateFormat': dateFormat,
        'startPageKey': startPageKey,
        'notificationsEnabled': notificationsEnabled,
        'notificationDelaySeconds': notificationDelaySeconds,
        'quietHoursEnabled': quietHoursEnabled,
        'quietHoursStartMinutes': quietHoursStartMinutes,
        'quietHoursEndMinutes': quietHoursEndMinutes,
      };

  /// Applies a settings map tolerantly: unknown/missing keys keep the current
  /// value, out-of-range values are clamped, and unrecognised enum/format
  /// strings are ignored. Safe to feed a partial or older map (e.g. a backup).
  void applyMap(Map<String, dynamic> data) {
    final mode = data['themeMode'];
    if (mode is String) {
      for (final m in AppThemeMode.values) {
        if (m.name == mode) themeMode = m;
      }
    }
    minimalist = data['minimalist'] as bool? ?? minimalist;
    use24HourFormat = data['use24HourFormat'] as bool? ?? use24HourFormat;

    final fmt = data['dateFormat'] as String?;
    if (fmt != null && dateFormats.contains(fmt)) dateFormat = fmt;

    final startKey = data['startPageKey'] as String?;
    if (startKey != null &&
        AppConfig.startPages.any((p) => p.key == startKey)) {
      startPageKey = startKey;
    }

    notificationsEnabled =
        data['notificationsEnabled'] as bool? ?? notificationsEnabled;
    notificationDelaySeconds =
        (data['notificationDelaySeconds'] as num?)?.round() ??
            notificationDelaySeconds;
    quietHoursEnabled = data['quietHoursEnabled'] as bool? ?? quietHoursEnabled;
    quietHoursStartMinutes =
        (data['quietHoursStartMinutes'] as num?)?.round().clamp(0, 1439) ??
            quietHoursStartMinutes;
    quietHoursEndMinutes =
        (data['quietHoursEndMinutes'] as num?)?.round().clamp(0, 1439) ??
            quietHoursEndMinutes;
  }

  /// Resets to defaults (used between tests).
  void resetForTest() {
    themeMode = AppThemeMode.system;
    minimalist = false;
    use24HourFormat = true;
    dateFormat = dateFormats.first;
    startPageKey = AppConfig.startPages.first.key;
    notificationsEnabled = false;
    notificationDelaySeconds = AppConfig.defaultNotificationDelaySeconds;
    quietHoursEnabled = AppConfig.quietHoursEnabledByDefault;
    quietHoursStartMinutes = AppConfig.quietHoursStartMinutes;
    quietHoursEndMinutes = AppConfig.quietHoursEndMinutes;
  }
}
