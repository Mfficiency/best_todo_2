import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'controller.dart';
import 'legacy_files_stub.dart' if (dart.library.io) 'legacy_files_io.dart'
    as files;
import 'release.dart';

/// What an app's own updater stored before it used this package, read by
/// the app (each app had its own keys and formats) for
/// [migrateLegacyUpdateState].
class LegacyUpdateRecords {
  const LegacyUpdateRecords({
    this.lastCheck,
    this.installedBuild,
    this.installedAt,
    this.downloaded,
    this.files = const [],
  });

  /// The last check ("Last checked …").
  final DateTime? lastCheck;

  /// The build whose first start is [installedAt] (the "Installed …"
  /// fallback where Android doesn't say). Both or neither.
  final int? installedBuild;
  final DateTime? installedAt;

  /// The last APK that finished downloading ("Downloaded …").
  final ({String version, int? build, DateTime at})? downloaded;

  /// Old APK files to delete (the package keeps its own in the cache).
  final List<String> files;
}

/// "0.2.106+414", "v0.2.106-414", "0.1.19 (build 123) · dev" ->
/// version and build; null without an x.y.z.
({String version, int? build})? parseLegacyVersion(String text) {
  final m = RegExp(r'(\d+\.\d+\.\d+)(?:[+-]|\s*\((?:build\s*)?)?(\d+)?')
      .firstMatch(text);
  if (m == null) return null;
  return (version: m.group(1)!, build: int.tryParse(m.group(2) ?? ''));
}

/// Moves an app's update records from before this package into the
/// package's keys ([UpdateController.lastCheckKey], …) once, then removes
/// every key in [legacyKeys]:
///
/// * nothing happens unless one of [legacyKeys] is still there, so call it
///   on every start, before [UpdateController.init];
/// * [read] turns the old keys into [LegacyUpdateRecords] (app-specific
///   parsing; a throw only skips the carry-over); a package key that
///   already has a value is never overwritten;
/// * the old APKs go: [LegacyUpdateRecords.files] and, with
///   [deleteExternalUpdatesFolder], `<external files>/updates` (where
///   Android's DownloadManager put them; Android only);
/// * an update downloaded but not yet installed isn't carried over: the
///   package downloads that build once more, silently.
///
/// Returns whether old keys were found (and removed).
Future<bool> migrateLegacyUpdateState(
  SharedPreferences prefs, {
  required Iterable<String> legacyKeys,
  required LegacyUpdateRecords Function(SharedPreferences prefs) read,
  bool deleteExternalUpdatesFolder = false,
}) async {
  final keys = legacyKeys.toList();
  if (!keys.any(prefs.containsKey)) return false;
  var old = const LegacyUpdateRecords();
  try {
    old = read(prefs);
  } on Object {
    // Unreadable: the package starts fresh.
  }
  bool empty(String key) => !prefs.containsKey(key);
  if (old.lastCheck case final at? when empty(UpdateController.lastCheckKey)) {
    await prefs.setString(UpdateController.lastCheckKey, at.toIso8601String());
  }
  final build = old.installedBuild, installedAt = old.installedAt;
  if (build != null &&
      installedAt != null &&
      empty(UpdateController.installedAtKey)) {
    await prefs.setInt(UpdateController.installedBuildKey, build);
    await prefs.setString(
      UpdateController.installedAtKey,
      installedAt.toIso8601String(),
    );
  }
  if (old.downloaded case final d? when empty(UpdateController.downloadedKey)) {
    final r = UpdateResult(
      UpdateStatus.available,
      version: d.version,
      build: d.build,
    );
    await prefs.setString(
      UpdateController.downloadedKey,
      jsonEncode({
        'key': r.key,
        'label': r.label,
        'at': d.at.toIso8601String(),
      }),
    );
  }
  for (final key in keys) {
    await prefs.remove(key);
  }
  await files.deleteLegacyFiles(
    old.files,
    externalUpdatesFolder: deleteExternalUpdatesFolder,
  );
  return true;
}
