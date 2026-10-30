import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mfficiency_updates/mfficiency_updates.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../utils/date_time_format.dart';
import 'log_service.dart';
import 'pre_update_backup.dart';
import 'problem_reports.dart';

export 'package:mfficiency_updates/mfficiency_updates.dart';

/// The app built from this repo and its release tags. (Best Music, the
/// other one until 0.2.111, moved to Mfficiency/BestMusic; its `music-v…`
/// tags in this repo's releases are never offered here.)
enum UpdatesApp {
  /// BestToDo (`lib/main.dart`): tags `v<x.y.z>-<build>[-dev|-staging]`.
  todo('BestToDo', 'v');

  const UpdatesApp(this.appName, this.tagPrefix);
  final String appName;
  final String tagPrefix;
}

/// The app's side of the shared updates package
/// (`packages/mfficiency_updates`, vendored from flutter_app_template — see
/// its README.md; never edit that copy). The behaviour (when to check, the
/// resume check, the "check automatically" switch, GitHub's rate limit,
/// silent download, install) is entirely the package's [UpdateController]
/// with its defaults; this file only holds what is BestToDo's own:
///
/// * [config]: repo `Mfficiency/best_todo_2` (public), the tag
///   prefix `v`, every 15 minutes while open (GitHub's anonymous limit is
///   60 requests/hour), the "Automatically update" switch
///   ([Config.autoUpdateCheckEnabled]);
/// * the optional GitHub token ([readToken]/[saveToken], Settings →
///   Updates) in secure storage, so updates keep working if the repo turns
///   private; without one everything works as before (anonymous API);
/// * the package's [FullBackup] ([backup], `Download/BestToDo/Backups`)
///   before every update as its `beforeInstall`, and [promptAllowed] (false
///   while the intro or a first-start picker is open) as its
///   `promptAllowed`;
/// * the app's date format ([strings]) and log ([LogService]);
/// * the update prefs from before the package ([migrateLegacyState]);
/// * About › Other apps ([otherApps], the package's
///   [OtherAppsController]) on the same HTTP client and platform.
class AppUpdates {
  AppUpdates._();

  static const String githubRepo = 'Mfficiency/best_todo_2';

  // ── Optional GitHub token ────────────────────────────────────────────

  /// Secure-storage key of the optional GitHub token (read access to
  /// [githubRepo]). Never in SharedPreferences, settings.json, the full
  /// backup or the log.
  static const String tokenKey = 'updates.github_token';

  /// Where the token lives: Android's Keystore-encrypted storage (the
  /// platform's secure store elsewhere). `resetOnError`: a value restored
  /// from Android's cloud backup onto another device can't be decrypted;
  /// it is dropped instead of failing every read. Tests use
  /// `FlutterSecureStorage.setMockInitialValues`.
  static const FlutterSecureStorage secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  /// The saved token, or null (none, or secure storage unavailable). The
  /// package's `tokenProvider`: with a token, checks and downloads go
  /// through GitHub's API with it (works for a public and a private repo);
  /// without, anonymously as before.
  static Future<String?> readToken() async {
    try {
      final t = (await secureStorage.read(key: tokenKey))?.trim();
      return t == null || t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  /// Saves [token] (trimmed), or removes it when null/empty, then has the
  /// running [controller] read it again (`reloadToken`, which checks at
  /// once). Errors from secure storage propagate (Settings shows them).
  static Future<void> saveToken(String? token) async {
    final t = token?.trim() ?? '';
    if (t.isEmpty) {
      await secureStorage.delete(key: tokenKey);
    } else {
      await secureStorage.write(key: tokenKey, value: t);
    }
    final c = controller;
    if (c != null) unawaited(c.reloadToken());
  }

  /// How often a running app checks (and how old the last check may be at
  /// start or when it comes back): GitHub's anonymous API allows 60
  /// requests/hour/IP.
  static const Duration interval = Duration(minutes: 15);

  /// The running app's updates; null until [create] ran (tests set it,
  /// pages without one show no update UI).
  static UpdateController? controller;

  /// The running app's full backup (the package's [FullBackup]): every
  /// file in the app's folders plus its SharedPreferences, in one file in
  /// `Download/BestToDo/Backups` that stays when the app is uninstalled;
  /// made before every update and from Settings → Backup & data, restored from
  /// there too. Null until [createBackup] ran (tests). Android only.
  static FullBackup? backup;

  /// [backup]'s settings. `pre_update_backup/` ([PreUpdateBackup], the
  /// once-per-install copy of the data files) is left out as a duplicate.
  /// Everything else BestToDo keeps is a file in its own folders or a
  /// SharedPreferences key, so there are no `extras`.
  static const FullBackupConfig backupConfig = FullBackupConfig(
    appName: 'BestToDo',
    excluded: {PreUpdateBackup.backupDirName},
  );

  /// BestToDo: false while the intro, the mode picker or another
  /// first-start chooser is open (`main.dart`), so Android's install
  /// dialog never opens over them; it opens once they are closed.
  static final ValueNotifier<bool> promptAllowed = ValueNotifier(true);

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
        // Public: privateRepo stays false (true without a token would stop
        // updates). With a token, package 1.6.3+ downloads through the
        // asset API too, so a repo turned private keeps updating.
        tokenProvider: readToken,
        tagPrefix: app.tagPrefix,
        autoCheck: () => Config.autoUpdateCheckEnabled,
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

  /// First thing in `main()`, before anything writes SharedPreferences (so
  /// [FullBackup.offerRestore] can tell a new install): builds [backup].
  /// The seams are for tests.
  static Future<FullBackup> createBackup({
    SharedPreferences? prefs,
    UpdatePlatform? platform,
    Future<Map<String, String>> Function()? roots,
    Future<String> Function(String name)? scratch,
  }) async {
    await Config.ensureVersionLoaded();
    final b = FullBackup(
      config: backupConfig,
      version: Config.version,
      build: int.tryParse(Config.buildNumber) ?? 0,
      prefs: prefs ?? await SharedPreferences.getInstance(),
      platform: platform,
      roots: roots,
      scratch: scratch,
      log: (event, data) => LogService.add('backup', '$event $data'),
    );
    await b.init();
    return backup = b;
  }

  /// The [UpdateController] for [app] with everything app-specific;
  /// [create] uses it, tests build theirs on fakes through it.
  static UpdateController controllerFor(
    UpdatesApp app, {
    required String version,
    required int build,
    required UpdateStore store,
    String? channel,
    UpdateHttp? http,
    ApkDownloader? downloader,
    UpdatePlatform? platform,
    DateTime Function()? clock,
    FullBackup? backup,
  }) =>
      UpdateController(
        config: config(app, version: version, build: build, channel: channel),
        store: store,
        http: http,
        downloader: downloader,
        platform: platform,
        strings: strings,
        log: _log,
        clock: clock,
        promptAllowed: promptAllowed,
        // Everything, to Downloads, before Android's "Update this app?".
        beforeInstall: backup?.beforeUpdate,
      );

  /// Before the first frame: builds [controller] for [app] (reads the
  /// version, migrates the stored state, no network), with [backup] (from
  /// [createBackup]) before every install. The seams are for tests.
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
    final c = controllerFor(
      app,
      version: version,
      build: build,
      store: SharedPreferencesUpdateStore(prefs),
      http: http,
      downloader: downloader,
      platform: platform ?? backup?.platform,
      clock: clock,
      backup: backup,
    );
    await c.init();
    return controller = c;
  }

  // ── About › Other apps ───────────────────────────────────────────────

  /// BestToDo's applicationId, left out of the other apps' list.
  static const String appId = 'com.mfficiency.best_todo_2';

  static OtherAppsController? _otherApps;

  /// About › Other apps (package README.md › Other apps): every other
  /// Mfficiency app, installed or not, its newest release and Install /
  /// Update / Open. Made on first use on [controller]'s HTTP client and
  /// platform (the package defaults before [create], e.g. in tests); the
  /// problem-report token ([ProblemReports]) also reads the private apps.
  static OtherAppsController get otherApps =>
      _otherApps ??= createOtherApps();

  @visibleForTesting
  static set otherApps(OtherAppsController? c) => _otherApps = c;

  static OtherAppsController createOtherApps({
    UpdateHttp? http,
    UpdatePlatform? platform,
  }) =>
      OtherAppsController(
        currentAppId: appId,
        http: http ?? controller?.http,
        platform: platform ??
            controller?.platform ??
            UpdatePlatform(openUrl: ProblemReports.openUrl),
        fallbackToken: () => ProblemReports.instance.token(),
        userAgent: 'BestToDo-other-apps',
      );

  /// After the first frame: Android's install time, the check when due,
  /// polling and the resume check. [context] is above every screen (the
  /// navigator's).
  static void start(BuildContext context) => controller?.start(context);

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

  /// The package's [migrateLegacyUpdateState] with the old update code's
  /// keys: the last check time, the last downloaded build (for
  /// "Downloaded …") and, for the running build, its first start (the
  /// "Installed …" fallback). A DownloadManager download in flight and the
  /// path of a finished APK are dropped (that update downloads once more,
  /// silently); the old APK folder (`<external files>/updates`) is deleted.
  static Future<void> migrateLegacyState(
    SharedPreferences prefs, {
    required String version,
    required int build,
  }) =>
      migrateLegacyUpdateState(
        prefs,
        legacyKeys: legacyKeys,
        deleteExternalUpdatesFolder: true,
        read: (p) {
          final checked = p.getInt(_legacyLastChecked);
          final download = _decode(p.getString(_legacyLastDownload));
          final downloadedAt = download?['at'];
          final downloaded = download?['version'] is String
              ? parseLegacyVersion(download!['version'] as String)
              : null;
          final seen = _decode(p.getString(_legacyFirstSeen));
          final seenAt = seen?['at'];
          final thisBuild =
              seen?['version'] == '$version+$build' && seenAt is int;
          return LegacyUpdateRecords(
            lastCheck: checked == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(checked),
            downloaded: downloaded != null && downloadedAt is int
                ? (
                    version: downloaded.version,
                    build: downloaded.build,
                    at: DateTime.fromMillisecondsSinceEpoch(downloadedAt),
                  )
                : null,
            installedBuild: thisBuild ? build : null,
            installedAt: thisBuild
                ? DateTime.fromMillisecondsSinceEpoch(seenAt)
                : null,
          );
        },
      );

  static Map<String, Object?>? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final v = jsonDecode(raw);
      return v is Map<String, Object?> ? v : null;
    } catch (_) {
      return null;
    }
  }
}

