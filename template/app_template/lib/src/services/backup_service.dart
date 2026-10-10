import 'dart:convert';
import 'dart:io';

import '../app_config.dart';
import '../app_settings.dart';
import '../util/app_version.dart';

/// A named block of app data that participates in backups. Register one per
/// data store your app owns (tasks, notes, timers, …). Settings are handled
/// separately and always included.
class BackupSection {
  /// Stable JSON key under the backup's `data` object. Never rename.
  final String key;

  /// Produces this section's JSON at export time.
  final Object? Function() export;

  /// Restores this section from its JSON at import time. Never called with null.
  final void Function(Object json) import;

  const BackupSection({
    required this.key,
    required this.export,
    required this.import,
  });
}

/// Outcome of an import: whether it applied and any human-readable warnings
/// (wrong app, newer format, skipped sections).
class ImportResult {
  final bool applied;
  final List<String> warnings;
  const ImportResult({required this.applied, this.warnings = const []});
}

/// Versioned export / import of **all** app data and settings.
///
/// Backup shape (a single JSON object):
/// ```json
/// {
///   "schema_version": 1,
///   "app_id": "app_template",
///   "app_version": "1.2.3+4",
///   "exported_at": "2026-07-26T...Z",
///   "settings": { ... AppSettings.toMap() ... },
///   "data": { "<section key>": <json>, ... }
/// }
/// ```
///
/// The version fields make the format future-proof: [importMap] refuses a file
/// from a different app, warns (but still tries) on a newer schema, and skips
/// unknown sections — so old backups keep restoring after the app evolves.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  final List<BackupSection> _sections = [];

  /// Registers a data section (idempotent by key). Call during app start-up,
  /// before offering export/import.
  void registerSection(BackupSection section) {
    _sections.removeWhere((s) => s.key == section.key);
    _sections.add(section);
  }

  void clearSectionsForTest() => _sections.clear();

  /// Builds the full backup map. Pure (no file I/O) so it is unit-testable.
  /// When [includeData] is false, only settings are exported.
  Map<String, dynamic> buildBackup({bool includeData = true}) {
    final data = <String, dynamic>{};
    if (includeData) {
      for (final s in _sections) {
        data[s.key] = s.export();
      }
    }
    return {
      'schema_version': AppConfig.backupSchemaVersion,
      'app_id': AppConfig.backupAppId,
      'app_version': AppVersion.versionWithBuild,
      'exported_at': DateTime.now().toIso8601String(),
      'settings': AppSettings.instance.toMap(),
      if (includeData) 'data': data,
    };
  }

  /// Writes a backup file into [directoryPath] and returns it. The filename is
  /// `<app_id>_<kind>_<timestamp>.json`. Returns null on failure.
  Future<File?> exportToDirectory(
    String directoryPath, {
    bool includeData = true,
  }) async {
    try {
      final sep = Platform.pathSeparator;
      final base = directoryPath.endsWith(sep)
          ? directoryPath
          : '$directoryPath$sep';
      final kind = includeData ? 'backup' : 'settings';
      final file = File('$base${AppConfig.backupAppId}_${kind}_'
          '${_timestamp()}.json');
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(buildBackup(
          includeData: includeData,
        )),
        flush: true,
      );
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Applies a decoded backup map. Tolerant and defensive: verifies identity,
  /// warns on a newer schema, restores settings then each known data section.
  ImportResult importMap(Map<String, dynamic> map) {
    final warnings = <String>[];

    final appId = map['app_id'];
    if (appId is String && appId != AppConfig.backupAppId) {
      return ImportResult(
        applied: false,
        warnings: ['This backup is from "$appId", not this app.'],
      );
    }

    final schema = (map['schema_version'] as num?)?.round();
    if (schema != null && schema > AppConfig.backupSchemaVersion) {
      warnings.add('Backup is a newer format (v$schema); imported best-effort.');
    }

    final settings = map['settings'];
    if (settings is Map) {
      AppSettings.instance.applyMap(Map<String, dynamic>.from(settings));
    } else {
      warnings.add('No settings block found.');
    }

    final data = map['data'];
    if (data is Map) {
      for (final s in _sections) {
        final raw = data[s.key];
        if (raw == null) continue;
        try {
          s.import(raw);
        } catch (_) {
          warnings.add('Could not import "${s.key}".');
        }
      }
      for (final key in data.keys) {
        if (!_sections.any((s) => s.key == key)) {
          warnings.add('Skipped unknown section "$key".');
        }
      }
    }

    return ImportResult(applied: true, warnings: warnings);
  }

  /// Reads and imports a backup file. Returns a not-applied result on any
  /// read/parse error.
  Future<ImportResult> importFile(String path) async {
    try {
      final decoded = jsonDecode(await File(path).readAsString());
      if (decoded is! Map<String, dynamic>) {
        return const ImportResult(
          applied: false,
          warnings: ['Unrecognised backup file.'],
        );
      }
      return importMap(decoded);
    } catch (_) {
      return const ImportResult(
        applied: false,
        warnings: ['Could not read backup file.'],
      );
    }
  }

  /// `yyyyMMdd_HHmmss` for filenames.
  static String _timestamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }
}
