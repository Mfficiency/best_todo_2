import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controller.dart';
import 'downloader.dart';
import 'http.dart';
import 'other_apps_stub.dart' if (dart.library.io) 'other_apps_io.dart' as impl;
import 'platform.dart';
import 'release.dart';

/// One Mfficiency app the "Other apps" page offers: where its releases are
/// and how its tags look (the same scheme its own updater reads).
@immutable
class MfficiencyApp {
  const MfficiencyApp({
    required this.name,
    required this.appId,
    required this.repo,
    required this.description,
    required this.icon,
    this.tagFormat = const TagFormat(strict: true),
    this.privateRepo = false,
  });

  final String name;

  /// The Android applicationId (also listed in the plugin's manifest
  /// `<queries>`, or Android 11+ won't say whether it is installed).
  final String appId;

  /// "owner/repo" of its GitHub releases.
  final String repo;
  final String description;
  final IconData icon;
  final TagFormat tagFormat;

  /// Downloading needs a token that can read the repo (else: GitHub in the
  /// browser, where the owner is logged in).
  final bool privateRepo;

  String get releasesPage => 'https://github.com/$repo/releases';
}

/// Every Mfficiency Android app. A new app: add it here and its appId to
/// android/src/main/AndroidManifest.xml (`<queries>`), then sync the apps.
final mfficiencyApps = <MfficiencyApp>[
  const MfficiencyApp(
    name: 'BestToDo',
    appId: 'com.mfficiency.best_todo_2',
    repo: 'Mfficiency/best_todo_2',
    description: 'Swipe-first to-do list: tasks default to today, alarms, '
        'projects and tools.',
    icon: Icons.check_circle_outline,
  ),
  const MfficiencyApp(
    name: 'Best Music',
    appId: 'com.mfficiency.best_music',
    repo: 'Mfficiency/BestMusic',
    description: 'Music player, MP3 downloader and YouTube subscriptions '
        'feed.',
    icon: Icons.music_note_outlined,
    tagFormat: TagFormat(prefix: 'music-v', strict: true),
    privateRepo: true,
  ),
  const MfficiencyApp(
    name: 'BestCollage',
    appId: 'com.mfficiency.best_collage',
    repo: 'Mfficiency/BestCollage',
    description: 'Put 1 to 4 photos together into one picture.',
    icon: Icons.dashboard_outlined,
  ),
  const MfficiencyApp(
    name: 'BestFloory',
    appId: 'ch.mfficiency.bestfloory',
    repo: 'Mfficiency/BestFloory',
    description: 'Start, stop and schedule a Dreame robot vacuum.',
    icon: Icons.cleaning_services_outlined,
    privateRepo: true,
  ),
  const MfficiencyApp(
    name: 'Hally Remote',
    appId: 'ch.mfficiency.hallyremote',
    repo: 'Mfficiency/hally_remote',
    description: 'Remote control for the MagicMirror: screen, slideshow, '
        'timers, cameras.',
    icon: Icons.settings_remote_outlined,
    privateRepo: true,
  ),
  const MfficiencyApp(
    name: 'Vesta Immo',
    appId: 'com.mfficiency.vesta_immo',
    repo: 'Mfficiency/gods-eye-view-immo',
    description: 'Swiss property listings on a map, saved and compared.',
    icon: Icons.home_work_outlined,
    tagFormat:
        TagFormat(prefix: 'vesta-immo-v', buildPrefix: 'b', strict: true),
    privateRepo: true,
  ),
  MfficiencyApp(
    name: 'Best Watch',
    appId: 'com.bestwatchfeatures',
    repo: 'Mfficiency/BestWatchFeatures',
    description: 'Phone companion of the dashboard watch face and the watch '
        'voice recorder.',
    icon: Icons.watch_outlined,
    // Its versions have two or three parts: v1.29-3590851-dev, v2.0.1-….
    tagFormat: TagFormat(
      pattern: RegExp(
        r'^v(?<version>\d+(?:\.\d+){1,2})-(?<build>\d+)(?:-(?<channel>dev|staging))?$',
      ),
    ),
    privateRepo: true,
  ),
  MfficiencyApp(
    name: 'MostlyGoodNews',
    appId: 'app.mostlygoodnews',
    repo: 'Mfficiency/mostlygoodnews',
    description: 'News reader where you set the filter rules and the topic '
        'mix.',
    icon: Icons.newspaper_outlined,
    // release.yml: v<x.y.z> tags, the build after a dash when there is one.
    tagFormat: TagFormat(
      pattern: RegExp(
        r'^v(?<version>\d+\.\d+\.\d+)(?:[-+](?<build>\d+))?(?:-(?<channel>dev|staging))?$',
      ),
    ),
    privateRepo: true,
  ),
];

/// The newest release of an app that has an APK.
@immutable
class OtherAppRelease {
  const OtherAppRelease({
    required this.version,
    required this.build,
    required this.channel,
    required this.page,
    this.apkUrl,
    this.apkName,
  });

  final String version;
  final int build;
  final String channel;

  /// Its github.com page.
  final String page;

  /// The APK: a browser link (public repo) or the asset's API link (private,
  /// needs the token).
  final String? apkUrl;
  final String? apkName;

  String get label =>
      channel == 'main' ? '$version ($build)' : '$version ($build) · $channel';
}

enum OtherAppStatus {
  /// Still asking GitHub / Android.
  loading,

  /// GitHub answered, no release with an APK yet.
  noRelease,

  /// A private repo and no token (or one that can't read it): only the
  /// browser can get it.
  needsToken,

  /// GitHub couldn't be asked (offline, rate limit).
  failed,

  /// [OtherAppState.release] is known.
  ready,
}

/// What the page knows about one app.
@immutable
class OtherAppState {
  const OtherAppState({
    this.status = OtherAppStatus.loading,
    this.installed,
    this.release,
    this.downloading = false,
    this.progress,
  });

  final OtherAppStatus status;

  /// The installed version, null when it isn't installed (or unknown off
  /// Android).
  final ({String version, int build})? installed;
  final OtherAppRelease? release;
  final bool downloading;
  final double? progress;

  /// A newer build than the installed one is out.
  bool get hasUpdate =>
      installed != null && release != null && release!.build > installed!.build;

  OtherAppState copyWith({
    OtherAppStatus? status,
    ({String version, int build})? installed,
    OtherAppRelease? release,
    bool? downloading,
    double? progress,
    bool clearProgress = false,
  }) =>
      OtherAppState(
        status: status ?? this.status,
        installed: installed ?? this.installed,
        release: release ?? this.release,
        downloading: downloading ?? this.downloading,
        progress: clearProgress ? null : progress ?? this.progress,
      );
}

/// Where "Update all" is: downloading app [done] + 1 of [total]
/// ([current]), or, with [installing], waiting for Android's installer
/// ([left] still to come).
class UpdateAllProgress {
  const UpdateAllProgress({
    required this.done,
    required this.total,
    this.current,
    this.installing = false,
    this.left = 0,
  });

  final int done;
  final int total;
  final String? current;
  final bool installing;
  final int left;
}

/// What "Update all" did.
enum UpdateAllOutcome {
  /// Every app is up to date: nothing to do.
  upToDate,

  /// The newer versions are downloaded and Android's installer opened for
  /// the first; the others follow one after another.
  started,

  /// "Install unknown apps" has to be allowed first (its switch opened).
  needsPermission,

  /// Only on a phone.
  unsupported,

  /// Already running.
  running,
}

/// What a tap on an app's button did.
enum OtherAppAction {
  /// Android's installer was opened.
  installing,

  /// "Install unknown apps" had to be allowed first (its switch opened).
  needsPermission,

  /// Its page opened in the browser.
  openedInBrowser,

  /// The app was opened.
  opened,

  /// The download or the hand-over failed.
  failed,
}

/// The "Other apps" page's state: every other Mfficiency app, whether it is
/// installed, its newest release, and Install / Update / Open. Downloads are
/// the updater's (silent, into the cache, resumed), then Android's installer
/// asks; off a phone, or for a private app without a token, the release
/// page opens in the browser.
class OtherAppsController extends ChangeNotifier with WidgetsBindingObserver {
  OtherAppsController({
    List<MfficiencyApp>? apps,
    this.currentAppId,
    UpdateHttp? http,
    ApkDownloader? downloader,
    UpdatePlatform? platform,
    Future<String?> Function()? fallbackToken,
    Future<String?> Function()? readToken,
    Future<void> Function(String? token)? writeToken,
    String userAgent = 'Mfficiency-other-apps',
    Future<String?> Function(String path)? stageApk,
  })  : _apps = apps ?? mfficiencyApps,
        _http = http ?? UpdateHttp.io(userAgent: userAgent),
        downloader = downloader ??
            ApkDownloader.io(
                directory: impl.otherAppsDir, userAgent: userAgent),
        platform = platform ?? UpdatePlatform(),
        _fallbackToken = fallbackToken,
        _readToken = readToken ?? _prefsRead,
        _writeToken = writeToken ?? _prefsWrite,
        _stageApk = stageApk ?? impl.stageApk;

  final List<MfficiencyApp> _apps;

  /// This app (left out); null: asks Android.
  String? currentAppId;
  final UpdateHttp _http;
  final ApkDownloader downloader;
  final UpdatePlatform platform;
  final Future<String?> Function()? _fallbackToken;
  final Future<String?> Function() _readToken;
  final Future<void> Function(String?) _writeToken;
  final Future<String?> Function(String path) _stageApk;

  static const prefsKey = 'other_apps.github_token';

  /// This app's own updater: "Update all" updates this app too, last
  /// (installing it ends the app). Null: only the other apps.
  UpdateController? selfUpdates;

  /// "Update all" while it runs; null otherwise.
  final updateAllProgress = ValueNotifier<UpdateAllProgress?>(null);

  /// Apps whose download failed in the last "Update all".
  List<String> updateAllFailed = const [];

  final _installQueue = <String>[];
  UpdateResult? _selfPending;
  BuildContext? _updateAllContext;
  bool _observing = false;

  static Future<String?> _prefsRead() async =>
      (await SharedPreferences.getInstance()).getString(prefsKey);

  static Future<void> _prefsWrite(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove(prefsKey);
    } else {
      await prefs.setString(prefsKey, token);
    }
  }

  final _states = <String, OtherAppState>{};
  var _loaded = false;

  /// The other apps, in catalogue order (this one left out once known).
  List<MfficiencyApp> get apps => [
        for (final a in _apps)
          if (a.appId != currentAppId) a,
      ];

  OtherAppState stateOf(MfficiencyApp app) =>
      _states[app.appId] ?? const OtherAppState();

  void _set(MfficiencyApp app, OtherAppState s) {
    _states[app.appId] = s;
    notifyListeners();
  }

  /// The page's own token, else the app's (e.g. the problem-report token).
  Future<String?> token() async {
    final fallback = _fallbackToken;
    for (final read in [_readToken, if (fallback != null) fallback]) {
      try {
        final t = (await read())?.trim();
        if (t != null && t.isNotEmpty) return t;
      } on Object {
        // Try the next.
      }
    }
    return null;
  }

  /// The page's own token, null when none is saved.
  Future<String?> ownToken() async {
    try {
      final t = (await _readToken())?.trim();
      return t == null || t.isEmpty ? null : t;
    } on Object {
      return null;
    }
  }

  /// Saves the page's own token (empty removes it) and asks GitHub again.
  Future<void> setToken(String? token) async {
    final t = token?.trim();
    await _writeToken(t == null || t.isEmpty ? null : t);
    notifyListeners();
  }

  /// Asks Android and GitHub about every app once (again with [force]).
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    _loaded = true;
    currentAppId ??= await platform.appId();
    final token = await this.token();
    for (final app in apps) {
      _states[app.appId] = OtherAppState(installed: stateOf(app).installed);
    }
    notifyListeners();
    await Future.wait([for (final app in apps) _loadOne(app, token)]);
  }

  /// The installed versions again (after an install, coming back).
  Future<void> refreshInstalled() async {
    for (final app in apps) {
      final installed = await platform.packageInfo(app.appId);
      final s = stateOf(app);
      _states[app.appId] = OtherAppState(
        status: s.status,
        installed: installed,
        release: s.release,
        downloading: s.downloading,
        progress: s.progress,
      );
    }
    notifyListeners();
  }

  Future<void> _loadOne(MfficiencyApp app, String? token) async {
    final installed = await platform.packageInfo(app.appId);
    OtherAppState next;
    try {
      final json = await _http.getJson(
        Uri.parse(
            'https://api.github.com/repos/${app.repo}/releases?per_page=30'),
        headers: {
          'Accept': 'application/vnd.github+json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        cacheFor: const Duration(minutes: 10),
      );
      final releases = [
        for (final r in json is List ? json : const [])
          if (r is Map) r.cast<String, Object?>(),
      ];
      final best = ReleaseFilter(tagFormat: app.tagFormat).sort(releases);
      if (best.isEmpty) {
        next = OtherAppState(
            status: OtherAppStatus.noRelease, installed: installed);
      } else {
        final r = best.first;
        final tag = app.tagFormat.parse('${r['tag_name']}')!;
        final asset = apkAsset(r);
        next = OtherAppState(
          status: OtherAppStatus.ready,
          installed: installed,
          release: OtherAppRelease(
            version: tag.version,
            build: tag.build ?? 0,
            channel: tag.channel,
            page: '${r['html_url'] ?? app.releasesPage}',
            apkUrl: asset == null
                ? null
                : app.privateRepo
                    ? asset['url'] as String?
                    : asset['browser_download_url'] as String?,
            apkName: asset?['name'] as String?,
          ),
        );
      }
    } on UpdateHttpException catch (e) {
      final refused = e.status == 401 || e.status == 403 || e.status == 404;
      next = OtherAppState(
        // A private repo answers 404 to anyone who can't read it.
        status: app.privateRepo && refused && !e.isRateLimit()
            ? OtherAppStatus.needsToken
            : OtherAppStatus.failed,
        installed: installed,
      );
    } on Object {
      next = OtherAppState(status: OtherAppStatus.failed, installed: installed);
    }
    _set(app, next);
  }

  /// Install or update [app]: a silent download, then Android's installer.
  /// Off a phone, without an APK or without access: its page in the browser.
  Future<OtherAppAction> install(MfficiencyApp app) async {
    final s = stateOf(app);
    final release = s.release;
    final url = release?.apkUrl;
    if (!platform.isSupported || release == null || url == null) {
      return _browse(release?.page ?? app.releasesPage);
    }
    if (s.downloading) return OtherAppAction.installing;
    final (staged, noAccess) = await _downloadStaged(app);
    if (noAccess) return _browse(release.page);
    if (staged == null) return OtherAppAction.failed;
    return switch (await platform.installApk(staged)) {
      'ok' => OtherAppAction.installing,
      'needs-permission' => OtherAppAction.needsPermission,
      _ => OtherAppAction.failed,
    };
  }

  /// Downloads [app]'s newest APK (silently, resumed after an interruption,
  /// tried a few times) and stages it for Android's installer. `noAccess`:
  /// a private app without a token that can read it.
  Future<(String? staged, bool noAccess)> _downloadStaged(
    MfficiencyApp app,
  ) async {
    final release = stateOf(app).release;
    final url = release?.apkUrl;
    if (release == null || url == null) return (null, false);
    _set(app, stateOf(app).copyWith(downloading: true, clearProgress: true));
    try {
      final name = 'app-${app.appId}-${release.build}.apk';
      for (var attempt = 0; attempt < 3; attempt++) {
        // A fresh link each try: GitHub's signed asset links expire.
        Uri? from = Uri.parse(url);
        if (url.startsWith('https://api.github.com/')) {
          final token = await this.token();
          from = token == null
              ? null
              : await downloader.signedAssetUrl(from, token);
          if (from == null && token == null) return (null, true);
        }
        if (from != null) {
          final path = await downloader.download(
            from,
            name,
            onProgress: (f) => _set(app, stateOf(app).copyWith(progress: f)),
          );
          if (path != null) return (await _stageApk(path), false);
        }
        await Future<void>.delayed(retryWait * (attempt + 1));
      }
      return (null, false);
    } finally {
      _set(app, stateOf(app).copyWith(downloading: false, clearProgress: true));
    }
  }

  /// Between the tries of a cut-off download (it continues where it
  /// stopped).
  @visibleForTesting
  static Duration retryWait = const Duration(seconds: 5);

  // ── Update all ─────────────────────────────────────────────────────────

  /// About › Update all: every installed Mfficiency app with a newer
  /// release (and this app, through [selfUpdates], last) downloads
  /// silently, one after another; then Android's installer opens for the
  /// first, and for the next each time the user comes back from it. Android
  /// asks once per app; nothing installs without that tap.
  Future<UpdateAllOutcome> updateAll(BuildContext context) async {
    if (updateAllProgress.value != null) return UpdateAllOutcome.running;
    if (!platform.isSupported) return UpdateAllOutcome.unsupported;
    updateAllProgress.value = const UpdateAllProgress(done: 0, total: 0);
    updateAllFailed = const [];
    try {
      final self = selfUpdates;
      // Also starts this app's own silent download.
      final selfCheck = self?.check();
      await load(force: true);
      final others = [
        for (final a in apps)
          if (stateOf(a).hasUpdate && stateOf(a).release?.apkUrl != null) a,
      ];
      final selfResult = await selfCheck;
      final selfNew =
          selfResult?.status == UpdateStatus.available ? selfResult : null;
      final total = others.length + (selfNew == null ? 0 : 1);
      if (total == 0) return UpdateAllOutcome.upToDate;
      final failedNames = <String>[];
      var done = 0;
      for (final app in others) {
        updateAllProgress.value = UpdateAllProgress(
          done: done,
          total: total,
          current: app.name,
        );
        final (staged, _) = await _downloadStaged(app);
        if (staged == null) {
          failedNames.add(app.name);
        } else {
          _installQueue.add(staged);
        }
        done++;
      }
      updateAllFailed = failedNames;
      _selfPending = selfNew;
      _updateAllContext = context;
      if (_installQueue.isEmpty && _selfPending == null) {
        return UpdateAllOutcome.started; // every download failed
      }
      if (!_observing) {
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      }
      return await _nextInstall();
    } finally {
      if (_installQueue.isEmpty && _selfPending == null) _endUpdateAll();
    }
  }

  /// Opens Android's installer for the next queued app; this app last.
  Future<UpdateAllOutcome> _nextInstall() async {
    if (_installQueue.isNotEmpty) {
      updateAllProgress.value = UpdateAllProgress(
        done: 0,
        total: 0,
        installing: true,
        left: _installQueue.length + (_selfPending == null ? 0 : 1),
      );
      final path = _installQueue.first;
      final outcome = await platform.installApk(path);
      if (outcome == 'needs-permission') {
        return UpdateAllOutcome.needsPermission; // the same one when back
      }
      _installQueue.removeAt(0); // opened (or failed): the next one
      if (outcome != 'ok') return _nextInstall();
      return UpdateAllOutcome.started;
    }
    final self = _selfPending;
    _selfPending = null;
    final context = _updateAllContext;
    _endUpdateAll();
    if (self != null && context != null && context.mounted) {
      await selfUpdates?.install(context, self);
    }
    return UpdateAllOutcome.started;
  }

  void _endUpdateAll() {
    _installQueue.clear();
    _selfPending = null;
    _updateAllContext = null;
    updateAllProgress.value = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  /// Back from Android's installer: the next app's turn.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(refreshInstalled());
    if (_installQueue.isEmpty && _selfPending == null) {
      _endUpdateAll(); // back from the last one
      return;
    }
    unawaited(_nextInstall());
  }

  @override
  void dispose() {
    _endUpdateAll();
    updateAllProgress.dispose();
    super.dispose();
  }

  /// Opens an installed app.
  Future<OtherAppAction> open(MfficiencyApp app) async =>
      await platform.launchApp(app.appId)
          ? OtherAppAction.opened
          : OtherAppAction.failed;

  /// Its releases page in the browser.
  Future<OtherAppAction> browse(MfficiencyApp app) =>
      _browse(stateOf(app).release?.page ?? app.releasesPage);

  Future<OtherAppAction> _browse(String url) async =>
      await platform.openUrl(url)
          ? OtherAppAction.openedInBrowser
          : OtherAppAction.failed;
}
