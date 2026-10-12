import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../utils/date_time_format.dart';
import 'log_service.dart';
import 'pre_update_backup.dart';

export 'package:mfficiency_updates/mfficiency_updates.dart';

/// The two apps built from this repo; each has its own release tags.
enum UpdatesApp {
  /// BestToDo (`lib/main.dart`): tags `v<x.y.z>-<build>[-dev|-staging]`.
  todo('BestToDo', 'v'),

  /// Best Music (`lib/main_music.dart`): tags `music-v<x.y.z>-<build>…`.
  music('Best Music', 'music-v');

  const UpdatesApp(this.appName, this.tagPrefix);
  final String appName;
  final String tagPrefix;
}

/// The app's side of the shared updates package
/// (`packages/mfficiency_updates`, vendored from flutter_app_template — see
/// its README.md; never edit that copy). Everything about checking,
/// downloading and installing is the package's [UpdateController]; this
/// file only adapts it to BestToDo / Best Music:
///
/// * [UpdateConfig] for the running app: repo `Mfficiency/best_todo_2`
///   (public, no token), its tag prefix (`v` / `music-v`), checks every
///   15 minutes while open (GitHub's anonymous limit is 60 requests/hour),
///   BestToDo's "Automatically update" switch ([Config.autoUpdateCheckEnabled];
///   Best Music has none, it always checks);
/// * the app's stored update state from before the package
///   ([migrateLegacyState]);
/// * BestToDo's pre-update backup right before Android's installer opens
///   ([BackupFirstPlatform]);
/// * the app's date format and log ([LogService]);
/// * the automatic checks start only once the intro/pickers are done
///   ([start]), and again when the switch is turned on ([autoCheckChanged]).
class AppUpdates {
  AppUpdates._();

  static const String githubRepo = 'Mfficiency/best_todo_2';

  /// How often a running app checks (and how old the last check may be at
  /// start): GitHub's anonymous API allows 60 requests/hour/IP.
  static const Duration interval = Duration(minutes: 15);

  /// The running app's updates; null until [create] ran (tests set it,
  /// pages without one show no update UI).
  static UpdateController? controller;

  /// The context [start] was called with (above every screen).
  static BuildContext? _appContext;

  /// The running app's [UpdateConfig].
  static UpdateConfig config(
    UpdatesApp app, {
    required String version,
    required int build,
    String? channel,
  }) =>
      UpdateConfig(
        appName: app.appName,
        version: version,
        build: build,
        channel: channel ?? Config.channel,
        githubRepo: githubRepo,
        tagPrefix: app.tagPrefix,
        autoCheck: app == UpdatesApp.todo
            ? () => Config.autoUpdateCheckEnabled
            : () => true,
        checkInterval: interval,
        pollInterval: interval,
      );

  /// The app's texts: the package's English ones in the app's date format.
  static UpdateStrings strings(BuildContext context) => const UpdateStrings(
        dateTime: formatTimerDateTime,
        date: formatTimerDate,
      );

  static void _log(
      UpdateLogLevel level, String event, Map<String, Object?> data) {
    // A check every 15 minutes that finds nothing isn't worth a log line.
    if (level == UpdateLogLevel.debug) return;
    LogService.add('update', data.isEmpty ? event : '$event $data');
  }

  /// Before the first frame: builds [controller] for [app] (reads the
  /// version, migrates the stored state, no network). The seams are for
  /// tests.
  static Future<UpdateController> create(
    UpdatesApp app, {
    SharedPreferences? prefs,
    UpdateHttp? http,
    ApkDownloader? downloader,
    UpdatePlatform? platform,
    DateTime Function()? clock,
  }) async {
    await Config.ensureVersionLoaded();
    final version = Config.version;
    final build = int.tryParse(Config.buildNumber) ?? 0;
    prefs ??= await SharedPreferences.getInstance();
    await migrateLegacyState(prefs, version: version, build: build);
    final c = UpdateController(
      config: config(app, version: version, build: build),
      store: SharedPreferencesUpdateStore(prefs),
      http: http,
      downloader: downloader,
      platform: platform ??
          (app == UpdatesApp.todo ? BackupFirstPlatform() : UpdatePlatform()),
      strings: strings,
      log: _log,
      clock: clock,
    );
    await c.init();
    _appContext = null;
    return controller = c;
  }

  /// After the first frame, once nothing else owns the screen (BestToDo's
  /// intro and pickers): Android's install time, the check when due,
  /// polling. [context] is above every screen (the navigator's).
  static void start(BuildContext context) {
    final c = controller;
    if (c == null) return;
    _appContext = context;
    c.start(context);
  }

  /// BestToDo's "Automatically update" was switched: turned on, the checks
  /// and polling start now (the package reads the switch at [start]);
  /// turned off, the next poll does nothing.
  static void autoCheckChanged() {
    final c = controller;
    final context = _appContext;
    if (c == null || context == null || !context.mounted) return;
    if (Config.autoUpdateCheckEnabled) c.start(context);
  }

  // ── State from before the package (0.2.106 and older) ────────────────

  static const String _legacyLastChecked = 'update_last_checked';
  static const String _legacyLastDownload = 'update_last_download';
  static const String _legacyFirstSeen = 'install_info_first_seen';

  /// Every key the old update code wrote.
  @visibleForTesting
  static const List<String> legacyKeys = [
    _legacyLastChecked,
    _legacyLastDownload,
    _legacyFirstSeen,
    'update_pending_download',
    'update_downloaded_version',
    'update_downloaded_apk',
  ];

  /// Moves what the old update code stored into the package's keys, once:
  /// the last check time, the last downloaded build (for "Downloaded …")
  /// and, for the running build, its first start (the "Installed …"
  /// fallback). The rest (a DownloadManager download in flight, the path of
  /// a finished APK) is dropped: an update downloaded before but not yet
  /// installed downloads once more, silently, into the package's cache
  /// folder. The old APK folder (`<external files>/updates`) is deleted.
  static Future<void> migrateLegacyState(
    SharedPreferences prefs, {
    required String version,
    required int build,
  }) async {
    if (!legacyKeys.any(prefs.containsKey)) return;
    try {
      final checked = prefs.getInt(_legacyLastChecked);
      if (checked != null &&
          prefs.getString(UpdateController.lastCheckKey) == null) {
        await prefs.setString(UpdateController.lastCheckKey,
            DateTime.fromMillisecondsSinceEpoch(checked).toIso8601String());
      }
      final download = _decode(prefs.getString(_legacyLastDownload));
      final downloadedVersion = download?['version'];
      final downloadedAt = download?['at'];
      if (downloadedVersion is String &&
          downloadedAt is int &&
          prefs.getString(UpdateController.downloadedKey) == null) {
        await prefs.setString(
            UpdateController.downloadedKey,
            jsonEncode({
              'key': _key(downloadedVersion),
              'label': _label(downloadedVersion),
              'at': DateTime.fromMillisecondsSinceEpoch(downloadedAt)
                  .toIso8601String(),
            }));
      }
      final seen = _decode(prefs.getString(_legacyFirstSeen));
      final seenAt = seen?['at'];
      if (seen?['version'] == '$version+$build' &&
          seenAt is int &&
          prefs.getString(UpdateController.installedAtKey) == null) {
        await prefs.setInt(UpdateController.installedBuildKey, build);
        await prefs.setString(UpdateController.installedAtKey,
            DateTime.fromMillisecondsSinceEpoch(seenAt).toIso8601String());
      }
    } catch (_) {
      // Unreadable old state: the package starts fresh.
    }
    for (final key in legacyKeys) {
      await prefs.remove(key);
    }
    unawaited(_deleteOldApkFolder());
  }

  static Map<String, Object?>? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, Object?> ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// "0.2.106+414" (the old records) -> the package's key: the same.
  static String _key(String version) =>
      version.contains('+') ? version : '$version+0';

  /// "0.2.106+414" -> "0.2.106 (414)", the package's label.
  static String _label(String version) {
    final plus = version.indexOf('+');
    return plus < 0
        ? version
        : '${version.substring(0, plus)} (${version.substring(plus + 1)})';
  }

  /// Android's DownloadManager put the old update APKs into the app's
  /// external files folder; the package downloads into its cache instead.
  static Future<void> _deleteOldApkFolder() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final base = await getExternalStorageDirectory();
      if (base == null) return;
      final dir = Directory('${base.path}/updates');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// BestToDo's installer: the data files are snapshotted
/// ([PreUpdateBackup.ensure]) before Android's "Update this app?" opens,
/// so whatever the next version does to them, this one's copy survives.
class BackupFirstPlatform extends UpdatePlatform {
  BackupFirstPlatform({super.supported});

  @override
  Future<String> installApk(String path) async {
    await PreUpdateBackup.ensure();
    return super.installApk(path);
  }
}
