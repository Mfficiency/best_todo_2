import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_stub.dart' if (dart.library.io) 'backup_io.dart' as io;
import 'platform.dart';
import 'release.dart';

/// Data an app keeps outside its folders and SharedPreferences (e.g.
/// `SharedPreferencesAsync`, a database elsewhere): [export] returns
/// something `jsonEncode` takes, [restore] gets it back after the files and
/// preferences are restored, before the restart.
class FullBackupExtra {
  const FullBackupExtra({required this.export, required this.restore});
  final Future<Object?> Function() export;
  final Future<void> Function(Object? data) restore;
}

/// One backup that was written.
class FullBackupRecord {
  const FullBackupRecord({
    required this.at,
    required this.location,
    required this.files,
    required this.bytes,
    required this.reason,
  });

  final DateTime at;

  /// Where it is, e.g. "Download/BestToDo/Backups/BestToDo-….tar.gz".
  final String location;
  final int files;

  /// Size of the data before compression.
  final int bytes;

  /// `manual`, `before-update`, `before-restore`.
  final String reason;

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'location': location,
        'files': files,
        'bytes': bytes,
        'reason': reason,
      };

  static FullBackupRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = DateTime.tryParse('${json['at']}');
    if (at == null) return null;
    return FullBackupRecord(
      at: at,
      location: '${json['location'] ?? ''}',
      files: (json['files'] as num?)?.toInt() ?? 0,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      reason: '${json['reason'] ?? ''}',
    );
  }
}

/// How a restore ended.
enum FullBackupRestore {
  /// Restored; the app restarts.
  restored,

  /// No file picked.
  cancelled,

  /// Not a backup of this package's format.
  notABackup,

  /// A backup of another app.
  otherApp,

  /// Reading or writing failed (the app's data is as before when the
  /// failure came before anything was replaced).
  failed,
}

/// A full backup of everything an app keeps on the phone, in one file in
/// the public Downloads folder (`Download/<appName>/Backups/`), so it
/// survives uninstalling the app: every file in the app's documents,
/// support and app-specific external folders, its SharedPreferences, and
/// the app's [FullBackupConfig.extras]. Not in it: secrets kept natively
/// (Android Keystore) and caches. Restore replaces all of it with a backup
/// file the user picks, then restarts the app.
///
/// Android only ([isSupported]); elsewhere nothing happens.
class FullBackupConfig {
  const FullBackupConfig({
    required this.appName,
    this.keep = 10,
    this.excluded = const {},
    this.excludedPrefixes = const {},
    this.extras = const {},
  });

  /// Folder name in Downloads and the start of the file name.
  final String appName;

  /// Backups of this install kept in the folder (older ones deleted).
  final int keep;

  /// Paths below every root never backed up nor replaced by a restore
  /// (folders or files, `/` separated), e.g. `{'pre_update_backup'}`.
  final Set<String> excluded;

  /// SharedPreferences keys starting with one of these are neither backed
  /// up nor touched by a restore.
  final Set<String> excludedPrefixes;

  /// Data outside the folders and SharedPreferences, by name.
  final Map<String, FullBackupExtra> extras;
}

class FullBackup {
  FullBackup({
    required this.config,
    required this.version,
    required this.build,
    required SharedPreferences prefs,
    UpdatePlatform? platform,
    Future<Map<String, String>> Function()? roots,
    Future<String> Function(String name)? scratch,
    DateTime Function()? clock,
    void Function(String event, Map<String, Object?> data)? log,
  })  : _prefs = prefs,
        platform = platform ?? UpdatePlatform(),
        _roots = roots ?? io.backupRoots,
        _scratch = scratch ?? io.scratchDir,
        _now = clock ?? DateTime.now,
        _log = log ?? _noLog;

  static const format = 1;
  static const lastKey = 'state.backup.last';
  static const offeredKey = 'state.backup.restoreOffered';

  /// Prefixes always left alone: the update state and this class's own.
  static const ownPrefixes = {'state.updates.', 'state.backup.'};

  final FullBackupConfig config;
  final String version;
  final int build;
  final UpdatePlatform platform;
  final SharedPreferences _prefs;
  final Future<Map<String, String>> Function() _roots;
  final Future<String> Function(String name) _scratch;
  final DateTime Function() _now;
  final void Function(String event, Map<String, Object?> data) _log;

  /// The newest backup this install wrote.
  late final last = ValueNotifier<FullBackupRecord?>(
    FullBackupRecord.fromJson(_decode(_prefs.getString(lastKey))),
  );

  /// True while a backup or restore runs.
  final busy = ValueNotifier(false);

  bool _freshAtStart = false;

  bool get isSupported => platform.isSupported;

  /// True when [init] found a new install: [offerRestore] will ask.
  bool get looksFresh => _freshAtStart;

  /// "Download/<appName>/Backups".
  String get folder => 'Download/${config.appName}/Backups';

  Set<String> get _prefixes => {...ownPrefixes, ...config.excludedPrefixes};

  bool _keep(String key) => !_prefixes.any(key.startsWith);

  /// Call before the app writes anything at start (before runApp): notes
  /// whether this looks like a new install, for [offerRestore].
  Future<void> init() async {
    if (!isSupported) return;
    if (_prefs.getBool(offeredKey) ?? false) return;
    _freshAtStart = !_prefs.getKeys().any(_keep);
  }

  /// Writes a full backup to Downloads. Throws when it can't (the caller
  /// decides whether that matters; [beforeUpdate] logs it).
  Future<FullBackupRecord> backupNow({String reason = 'manual'}) async {
    if (!isSupported) throw UnsupportedError('Full backups are Android only');
    busy.value = true;
    try {
      final now = _now();
      final roots = await _roots();
      final dir = await _scratch('mfficiency_backup');
      final stamp = _stamp(now);
      final name = '${_safe(config.appName)}-$stamp-$version+$build.tar.gz';
      final out = '$dir/$name';
      final manifest = {
        'format': format,
        'app': config.appName,
        'appId': await platform.appId(),
        'version': version,
        'build': build,
        'createdAt': now.toIso8601String(),
        'reason': reason,
        'roots': roots.keys.toList(),
      };
      final extras = <String, List<int>>{};
      for (final e in config.extras.entries) {
        extras['extras/${e.key}.json'] = utf8.encode(jsonEncode(await e.value.export()));
      }
      final stats = await io.writeArchive(
        outPath: out,
        entries: {
          'manifest.json': utf8.encode(jsonEncode(manifest)),
          'prefs.json': utf8.encode(jsonEncode(_dumpPrefs())),
          ...extras,
        },
        roots: roots,
        excluded: config.excluded,
      );
      final location = await platform.saveToDownloads(
        out,
        folder: '${config.appName}/Backups',
        name: name,
        keep: config.keep,
      );
      io.deletePath(dir);
      final record = FullBackupRecord(
        at: now,
        location: location,
        files: stats.files,
        bytes: stats.bytes,
        reason: reason,
      );
      await _prefs.setString(lastKey, jsonEncode(record.toJson()));
      last.value = record;
      _log('backup.full', {'reason': reason, 'files': stats.files, 'bytes': stats.bytes});
      return record;
    } finally {
      busy.value = false;
    }
  }

  /// For `UpdateController(beforeInstall: backup.beforeUpdate)`: a full
  /// backup before every update.
  Future<void> beforeUpdate(UpdateResult update, String apkPath) async {
    if (!isSupported) return;
    await backupNow(reason: 'before-update');
  }

  /// Lets the user pick a backup file and restores it ([restoreFile]).
  Future<FullBackupRestore> restoreFromPicker() async {
    if (!isSupported) return FullBackupRestore.failed;
    final path = await platform.pickFile();
    if (path == null) return FullBackupRestore.cancelled;
    return restoreFile(path);
  }

  /// Replaces the app's data with the backup at [path]: first a backup of
  /// the current data ("before-restore"), then the folders, the
  /// SharedPreferences and the extras. On [FullBackupRestore.restored] call
  /// [restart] (the running app still holds the old data in memory).
  Future<FullBackupRestore> restoreFile(String path) async {
    busy.value = true;
    String? staged;
    try {
      staged = await _scratch('mfficiency_restore');
      final memory = <String, Uint8List>{};
      try {
        await io.readArchive(
          path,
          onEntry: (name) {
            if (name == 'manifest.json' || name == 'prefs.json' || name.startsWith('extras/')) {
              return null;
            }
            if (name.contains('..') || name.startsWith('/')) return '';
            return '$staged/files/$name';
          },
          onBytes: (name, bytes) => memory[name] = bytes,
        );
      } on Object catch (e) {
        _log('backup.restore_unreadable', {'error': e.runtimeType.toString()});
        return FullBackupRestore.notABackup;
      }
      final manifest = _decode(memory['manifest.json']);
      if (manifest is! Map || manifest['format'] != format) {
        return FullBackupRestore.notABackup;
      }
      final appId = await platform.appId();
      if (appId != null && manifest['appId'] != null && manifest['appId'] != appId) {
        return FullBackupRestore.otherApp;
      }
      try {
        await backupNow(reason: 'before-restore');
      } on Object catch (e) {
        // Without the safety copy the restore would be one-way.
        _log('backup.before_restore_failed', {'error': e.runtimeType.toString()});
        return FullBackupRestore.failed;
      }
      busy.value = true;
      final roots = await _roots();
      await io.replaceRoots('$staged/files', roots, excluded: config.excluded);
      await _restorePrefs(_decode(memory['prefs.json']));
      for (final e in config.extras.entries) {
        final bytes = memory['extras/${e.key}.json'];
        if (bytes != null) await e.value.restore(_decode(bytes));
      }
      await _prefs.setBool(offeredKey, true);
      _log('backup.restored', {'from': manifest['createdAt'], 'version': manifest['version']});
      return FullBackupRestore.restored;
    } on Object catch (e) {
      _log('backup.restore_failed', {'error': e.runtimeType.toString()});
      return FullBackupRestore.failed;
    } finally {
      if (staged != null) {
        try {
          io.deletePath(staged);
        } on Object {
          // Cache; Android clears it.
        }
      }
      busy.value = false;
    }
  }

  /// Starts the app again (after [FullBackupRestore.restored]).
  Future<void> restart() => platform.restartApp();

  /// On a new install (nothing in SharedPreferences at [init]), asks once
  /// whether to restore a backup from Downloads.
  Future<void> offerRestore(BuildContext context, {FullBackupStrings strings = const FullBackupStrings()}) async {
    if (!_freshAtStart || !isSupported) return;
    _freshAtStart = false;
    await _prefs.setBool(offeredKey, true);
    if (!context.mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(strings.offerTitle),
        content: Text(strings.offerBody(folder)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(strings.offerNo)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(strings.offerYes)),
        ],
      ),
    );
    if (yes == true && context.mounted) {
      await runRestore(context, strings: strings, confirm: false);
    }
  }

  /// Restore with the UI: confirm, pick, restore, restart or say why not.
  Future<void> runRestore(
    BuildContext context, {
    FullBackupStrings strings = const FullBackupStrings(),
    bool confirm = true,
  }) async {
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(strings.restoreTitle),
          content: Text(strings.restoreConfirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(strings.cancel)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(strings.restoreAction)),
          ],
        ),
      );
      if (ok != true) return;
    }
    final outcome = await restoreFromPicker();
    if (outcome == FullBackupRestore.restored) {
      await restart();
      return;
    }
    if (outcome == FullBackupRestore.cancelled || !context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(switch (outcome) {
        FullBackupRestore.notABackup => strings.notABackup,
        FullBackupRestore.otherApp => strings.otherApp,
        _ => strings.restoreFailed,
      }),
    ));
  }

  /// Backup with the UI: a SnackBar with where it went, or why not.
  Future<void> runBackup(BuildContext context, {FullBackupStrings strings = const FullBackupStrings()}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final r = await backupNow();
      messenger?.showSnackBar(SnackBar(content: Text(strings.saved(r.location))));
    } on PlatformException catch (e) {
      messenger?.showSnackBar(SnackBar(
        content: Text(e.code == 'no-storage' ? strings.noStorage : strings.backupFailed),
      ));
    } on Object {
      messenger?.showSnackBar(SnackBar(content: Text(strings.backupFailed)));
    }
  }

  Map<String, Object?> _dumpPrefs() {
    final out = <String, Object?>{};
    for (final key in _prefs.getKeys()) {
      if (!_keep(key)) continue;
      final v = _prefs.get(key);
      out[key] = switch (v) {
        bool b => {'t': 'b', 'v': b},
        int i => {'t': 'i', 'v': i},
        double d => {'t': 'd', 'v': d},
        String s => {'t': 's', 'v': s},
        List l => {'t': 'l', 'v': l.map((e) => '$e').toList()},
        _ => null,
      };
    }
    out.removeWhere((_, v) => v == null);
    return out;
  }

  Future<void> _restorePrefs(Object? dump) async {
    if (dump is! Map) return;
    for (final key in _prefs.getKeys().toList()) {
      if (_keep(key)) await _prefs.remove(key);
    }
    for (final e in dump.entries) {
      final key = '${e.key}';
      final v = e.value;
      if (!_keep(key) || v is! Map) continue;
      final value = v['v'];
      switch (v['t']) {
        case 'b':
          await _prefs.setBool(key, value == true);
        case 'i':
          await _prefs.setInt(key, (value as num).toInt());
        case 'd':
          await _prefs.setDouble(key, (value as num).toDouble());
        case 's':
          await _prefs.setString(key, '$value');
        case 'l':
          await _prefs.setStringList(key, [for (final x in value as List) '$x']);
      }
    }
  }

  static Object? _decode(Object? source) {
    if (source == null) return null;
    try {
      return jsonDecode(source is String ? source : utf8.decode(source as List<int>));
    } on Object {
      return null;
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _stamp(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}-${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');

  static void _noLog(String event, Map<String, Object?> data) {}
}

/// The texts of [FullBackupTiles] and the restore dialogs, English by
/// default.
class FullBackupStrings {
  const FullBackupStrings({
    this.backupTitle = 'Back up everything',
    this.backupSubtitle = _backupSubtitle,
    this.lastBackup = _lastBackup,
    this.restoreTitle = 'Restore from a backup',
    this.restoreSubtitle =
        'Replaces all data in this app with a backup file, then restarts it.',
    this.restoreConfirm =
        'Everything in this app is replaced by the backup you pick (a backup '
            'of the current data is made first). Tokens and passwords are not '
            'in backups: enter them again afterwards.',
    this.restoreAction = 'Pick backup',
    this.cancel = 'Cancel',
    this.saved = _saved,
    this.backupFailed = "The backup couldn't be written.",
    this.noStorage =
        'Allow storage access for this app in Android settings to save backups '
            'to Downloads.',
    this.notABackup = 'That file is not a backup of this app.',
    this.otherApp = 'That backup belongs to another app.',
    this.restoreFailed = "The backup couldn't be restored.",
    this.offerTitle = 'Restore a backup?',
    this.offerBody = _offerBody,
    this.offerYes = 'Pick backup',
    this.offerNo = 'Start fresh',
    this.dateTime = _dateTime,
  });

  final String backupTitle;
  final String Function(String folder) backupSubtitle;
  final String Function(String when, String folder) lastBackup;
  final String restoreTitle;
  final String restoreSubtitle;
  final String restoreConfirm;
  final String restoreAction;
  final String cancel;
  final String Function(String location) saved;
  final String backupFailed;
  final String noStorage;
  final String notABackup;
  final String otherApp;
  final String restoreFailed;
  final String offerTitle;
  final String Function(String folder) offerBody;
  final String offerYes;
  final String offerNo;
  final String Function(DateTime t) dateTime;

  static String _backupSubtitle(String folder) =>
      'All data in one file in $folder, kept when the app is uninstalled. '
      'Also made before every update.';
  static String _lastBackup(String when, String folder) =>
      'Last backup $when · $folder';
  static String _saved(String location) => 'Backup saved: $location';
  static String _offerBody(String folder) =>
      'If you used this app before, pick a backup from $folder to get all '
      'your data back.';
  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _dateTime(DateTime t) =>
      '${_two(t.day)}.${_two(t.month)}.${t.year} ${_two(t.hour)}:${_two(t.minute)}';
}

/// "Back up everything" and "Restore from a backup" for the app's
/// settings. Nothing off Android.
class FullBackupTiles extends StatelessWidget {
  const FullBackupTiles({
    super.key,
    required this.backup,
    this.strings = const FullBackupStrings(),
  });

  final FullBackup backup;
  final FullBackupStrings strings;

  @override
  Widget build(BuildContext context) {
    if (!backup.isSupported) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: backup.busy,
      builder: (context, busy, _) => ValueListenableBuilder<FullBackupRecord?>(
        valueListenable: backup.last,
        builder: (context, last, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.backup_outlined),
              title: Text(strings.backupTitle),
              subtitle: Text(last == null
                  ? strings.backupSubtitle(backup.folder)
                  : strings.lastBackup(strings.dateTime(last.at), backup.folder)),
              enabled: !busy,
              onTap: () => backup.runBackup(context, strings: strings),
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: Text(strings.restoreTitle),
              subtitle: Text(strings.restoreSubtitle),
              enabled: !busy,
              onTap: () => backup.runRestore(context, strings: strings),
            ),
          ],
        ),
      ),
    );
  }
}
