import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'config.dart';
import 'downloader.dart';
import 'http.dart';
import 'platform.dart';
import 'release.dart';
import 'store.dart';
import 'strings.dart';
import 'widgets.dart' show showUpdateVersionSheet;

enum UpdateLogLevel { debug, info, warning }

/// Receives the package's log events ("update.check", data without user
/// content). Default: nothing.
typedef UpdateLogger = void Function(
    UpdateLogLevel level, String event, Map<String, Object?> data);

void _noLog(UpdateLogLevel level, String event, Map<String, Object?> data) {}

void _snackBar(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

UpdateStrings _english(BuildContext context) => const UpdateStrings();

/// In-app updates from GitHub Releases (or a JSON manifest), the same in
/// every app:
///
/// * checks on the first frame when due, every [UpdateConfig.pollInterval]
///   while in the foreground, on pull-down in the changelog and from "Check
///   for updates";
/// * a newer build (highest build number of any channel) downloads
///   silently into the cache (`.part`, renamed when complete, continued
///   after an interruption, reused after a restart);
/// * when complete, Android's own "Update this app?" opens (a
///   PackageInstaller session; the only confirm), by itself once per build
///   and start and only in the foreground, always after a tap. Cancelled:
///   the [UpdateBanner] offers Install until it is installed;
/// * records when the running build was downloaded and installed.
///
/// Listen to the controller (or its notifiers) for the state; the widgets
/// in widgets.dart show it.
class UpdateController extends ChangeNotifier with WidgetsBindingObserver {
  UpdateController({
    required this.config,
    required this.store,
    UpdateHttp? http,
    ApkDownloader? downloader,
    UpdatePlatform? platform,
    UpdateStrings Function(BuildContext context)? strings,
    void Function(BuildContext context, String text)? showMessage,
    UpdateLogger? log,
    DateTime Function()? clock,
  })  : http = http ?? UpdateHttp.io(),
        downloader = downloader ?? ApkDownloader.io(),
        platform = platform ?? UpdatePlatform(),
        _strings = strings ?? _english,
        _show = showMessage ?? _snackBar,
        _log = log ?? _noLog,
        _now = clock ?? DateTime.now {
    for (final n in _parts) {
      n.addListener(notifyListeners);
    }
  }

  List<Listenable> get _parts => [
        result,
        checking,
        installedAt,
        downloaded,
        downloading,
        downloadProgress,
        ready,
        failed,
        _resumed,
      ];

  static const lastCheckKey = 'state.updates.lastCheck';
  static const downloadedKey = 'state.updates.downloaded';
  static const installedBuildKey = 'state.updates.installedBuild';
  static const installedAtKey = 'state.updates.installedAt';

  final UpdateConfig config;
  final UpdateStore store;
  final UpdateHttp http;
  final ApkDownloader downloader;
  final UpdatePlatform platform;
  final UpdateStrings Function(BuildContext context) _strings;
  final void Function(BuildContext context, String text) _show;
  final UpdateLogger _log;
  final DateTime Function() _now;

  /// The app's strings for [context].
  UpdateStrings stringsOf(BuildContext context) => _strings(context);

  /// Latest result of this session (drives the banner).
  final result = ValueNotifier<UpdateResult?>(null);
  final checking = ValueNotifier(false);

  /// When the running build was installed: Android's own time on a phone,
  /// else its first start on this device. Shown in the changelog.
  final installedAt = ValueNotifier<DateTime?>(null);

  /// The last update APK that finished downloading (kept across restarts).
  final downloaded = ValueNotifier<DownloadRecord?>(null);

  /// An APK downloads silently ([downloadingUpdate]); [downloadProgress] is
  /// 0..1 (null: size unknown). Only passive text shows it.
  final downloading = ValueNotifier(false);
  final downloadProgress = ValueNotifier<double?>(null);

  /// Build ([UpdateResult.key]) whose APK is complete: Android's own
  /// "Update this app?" opens right away (the only confirm); cancelled, the
  /// banner offers Install.
  final ready = ValueNotifier<String?>(null);
  UpdateResult? _readyUpdate;

  /// The update whose APK is complete ([ready]).
  UpdateResult? get readyUpdate => _readyUpdate;

  /// Update whose download failed: the banner offers Try again, which
  /// downloads silently again.
  final failed = ValueNotifier<UpdateResult?>(null);

  /// Bumped when the app comes back to the foreground (the banner checks
  /// the APK is still there).
  final _resumed = ValueNotifier(0);

  /// Build ([UpdateResult.key]) whose "available" banner was dismissed
  /// (Later); a newer one shows it again.
  String? _dismissed;

  /// APK download of [_apkUpdate], always silent in the background.
  UpdateResult? _apkUpdate;
  String? get _apkVersion => _apkUpdate?.key;
  Future<String?>? _apk;
  String? _apkPath;

  /// The update being downloaded, if any.
  UpdateResult? get downloadingUpdate => downloading.value ? _apkUpdate : null;

  /// Builds Android's install dialog opened by itself this start: once
  /// each, so a cancel isn't answered with the same dialog again.
  final _asked = <String>{};

  /// Build the user tapped Install for before it was downloaded: its
  /// installer opens as soon as it is complete, even if asked before.
  String? _wantInstall;

  /// The user tapped Install and went to the "install unknown apps" switch
  /// first: install when the app is back.
  UpdateResult? _installOnResume;

  /// The app's context (above every screen) for messages about installs
  /// that start by themselves.
  BuildContext? _context;

  /// Where Install was tapped last: its messages show there.
  BuildContext? _tapContext;

  Timer? _poll;
  bool _observing = false;
  String? _token;
  Future<Map<String, UpdateResult>>? _versions;

  bool get hasToken => _token != null;

  /// A source is set (and, for a private repo, a token).
  bool get configured =>
      config.configured &&
      (config.provider != UpdateProvider.github ||
          !config.privateRepo ||
          _token != null);

  DateTime? get lastCheck =>
      DateTime.tryParse(store.getString(lastCheckKey) ?? '');

  ReleaseFilter get _filter => ReleaseFilter(
        tagPrefix: config.tagPrefix,
        includePrereleases: config.includePrereleases(),
        legacyBuildLimit: config.legacyBuildLimit,
      );

  // ── Start ──────────────────────────────────────────────────────────────

  /// Before the first frame: reads the token and the records. Fast (no
  /// network).
  Future<void> init() async {
    await _readToken();
    await _recordInstall();
    downloaded.value = _readDownloaded();
  }

  Future<void> _readToken() async {
    final t = (await config.tokenProvider?.call())?.trim();
    _token = t == null || t.isEmpty ? null : t;
  }

  /// The first start of a build stands in for its install time where
  /// Android's isn't available (tests, preview); [start] asks Android.
  Future<void> _recordInstall() async {
    var at = DateTime.tryParse(store.getString(installedAtKey) ?? '');
    if (at == null || store.getInt(installedBuildKey) != config.build) {
      at = _now();
      await store.setInt(installedBuildKey, config.build);
      await store.setString(installedAtKey, at.toIso8601String());
    }
    installedAt.value = at;
  }

  DownloadRecord? _readDownloaded() {
    try {
      final m = jsonDecode(store.getString(downloadedKey) ?? 'null');
      if (m is! Map) return null;
      final at = DateTime.tryParse('${m['at']}');
      return at == null
          ? null
          : (key: '${m['key']}', label: '${m['label']}', at: at);
    } on FormatException {
      return null;
    }
  }

  void _recordDownload(UpdateResult r) {
    final d = (key: r.key, label: r.label, at: _now());
    downloaded.value = d;
    unawaited(
      store.setString(
        downloadedKey,
        jsonEncode({
          'key': d.key,
          'label': d.label,
          'at': d.at.toIso8601String(),
        }),
      ),
    );
  }

  /// [key] ([UpdateResult.key]) is the running build; "+0" when the source
  /// knows no build number.
  bool isRunning(String key) =>
      key == '${config.version}+${config.build}' ||
      key == '${config.version}+0';

  /// [latest] has a higher build number than the running one (or, without
  /// one, a higher x.y.z).
  bool isNewer(UpdateResult latest) =>
      isNewerRelease(latest, version: config.version, build: config.build);

  /// After the first frame ([context] is above every screen): Android's
  /// install time, the check when due, polling. Automatic checks only on a
  /// device ([UpdatePlatform.isSupported]), not in tests or a browser.
  void start(BuildContext context) {
    _context = context;
    unawaited(_loadInstallTime());
    if (!platform.isSupported) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (!config.autoCheck() || !configured) return;
    final last = lastCheck;
    final due = last == null || _now().difference(last) >= config.checkInterval;
    if (due) Future<void>.delayed(config.firstCheckDelay, check);
    _startPolling();
  }

  Future<void> _loadInstallTime() async {
    final at = await platform.installTime();
    if (at != null) installedAt.value = at;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) handleResume();
  }

  /// Back in the app: after the "install unknown apps" switch the install
  /// starts; an APK completed while away opens Android's dialog now.
  @visibleForTesting
  void handleResume() {
    _resumed.value++;
    final r = _installOnResume;
    _installOnResume = null;
    final path = r == null ? null : _readyApk(r);
    if (r != null && path != null) {
      unawaited(_openInstaller(r, path));
    } else if (_readyUpdate case final done?) {
      unawaited(_offerInstall(done));
    }
  }

  void _startPolling() {
    if (!platform.isSupported || !config.autoCheck()) return;
    if (config.pollInterval > Duration.zero) {
      _poll ??= Timer.periodic(config.pollInterval, (_) => _pollTick());
    }
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// Polls while the app is in the foreground only (no battery or data use
  /// in the background).
  void _pollTick() {
    if (!config.autoCheck() || checking.value || !_inForeground) return;
    unawaited(check());
  }

  bool get _inForeground {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// Reads the token again (the app saved or removed it), then checks at
  /// once and polls if a token is there now.
  Future<UpdateResult> reloadToken() async {
    await _readToken();
    _versions = null;
    _log(UpdateLogLevel.info, 'update.token', {'set': _token != null});
    final r = await check();
    if (_token != null) _startPolling();
    return r;
  }

  // ── Check ──────────────────────────────────────────────────────────────

  Map<String, String> get _githubHeaders => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  /// Checks for a newer build. A newer APK downloads silently in the
  /// background; when it is complete Android's own "Update this app?"
  /// opens (the only confirm). Nothing installs without that tap.
  Future<UpdateResult> check() async {
    if (!configured) {
      return result.value = UpdateResult(
        config.configured
            ? UpdateStatus.needsToken
            : UpdateStatus.notConfigured,
      );
    }
    checking.value = true;
    final sw = Stopwatch()..start();
    try {
      final latest = config.provider == UpdateProvider.github
          ? await _fromGithub()
          : await _fromManifest();
      final r =
          isNewer(latest) ? latest : const UpdateResult(UpdateStatus.upToDate);
      await store.setString(lastCheckKey, _now().toIso8601String());
      _log(
        r.status == UpdateStatus.available
            ? UpdateLogLevel.info
            : UpdateLogLevel.debug,
        'update.check',
        {
          'status': r.status.name,
          'latest': latest.version,
          'ms': sw.elapsedMilliseconds,
        },
      );
      unawaited(_downloadInBackground(r));
      return result.value = r;
    } catch (e) {
      final status = e is UpdateHttpException ? e.status : null;
      final github = config.provider == UpdateProvider.github;
      if (github &&
          (config.privateRepo || _token != null) &&
          (status == 401 || status == 403 || status == 404)) {
        // A private repo answers 404 to a token without access to it.
        _stopPolling();
        _log(UpdateLogLevel.warning, 'update.token_refused', {
          'status': status,
        });
        return result.value = const UpdateResult(UpdateStatus.badToken);
      }
      if (!github && status == 404) {
        // Nothing published at the manifest URL (yet): stop polling until
        // the next start instead of logging a failure every minute.
        _stopPolling();
        _log(UpdateLogLevel.info, 'update.not_published', {'status': 404});
        return result.value = const UpdateResult(UpdateStatus.notConfigured);
      }
      _log(UpdateLogLevel.warning, 'update.check_failed', {
        'error': e.runtimeType.toString(),
        if (status != null) 'status': status,
      });
      return result.value = const UpdateResult(UpdateStatus.failed);
    } finally {
      checking.value = false;
    }
  }

  Uri _releasesUrl(int perPage) => Uri.parse(
        'https://api.github.com/repos/${config.githubRepo}/releases?per_page=$perPage',
      );

  Future<UpdateResult> _fromGithub() async {
    final json = await http.getJson(
      _releasesUrl(config.releasesPerPage),
      headers: _githubHeaders,
    );
    // Every channel (main, staging, dev): the highest build wins.
    final releases = _filter.sort(
      (json as List).whereType<Map<String, Object?>>(),
    );
    if (releases.isEmpty) return const UpdateResult(UpdateStatus.upToDate);
    return releaseResult(
      releases.first,
      tagPrefix: config.tagPrefix,
      assetPattern: config.assetPattern,
      privateRepo: config.privateRepo,
    );
  }

  Future<UpdateResult> _fromManifest() async {
    // The query defeats CDN caching (raw.githubusercontent.com caches 5 min).
    final url = Uri.parse(config.manifestUrl);
    final json = await http.getJson(
      url.replace(
        queryParameters: {
          ...url.queryParameters,
          't': '${_now().millisecondsSinceEpoch ~/ 60000}',
        },
      ),
    );
    return manifestResult((json as Map).cast<String, Object?>());
  }

  /// "Up to date", "Version 1.2.0 (5) available", …
  String statusLabel(UpdateStrings s, [UpdateResult? r]) {
    r ??= result.value;
    return switch (r?.status) {
      UpdateStatus.available => s.available(r!.label),
      UpdateStatus.notConfigured => s.notConfigured,
      UpdateStatus.failed => s.failed,
      UpdateStatus.upToDate => s.upToDate,
      UpdateStatus.needsToken => s.needsToken,
      UpdateStatus.badToken => s.badToken,
      null => configured ? s.upToDate : s.notConfigured,
    };
  }

  /// "Downloading version 1.2.0 (5)… 40 %" while an APK downloads
  /// silently, else null.
  String? progressLabel(UpdateStrings s) {
    final r = downloadingUpdate;
    if (r == null) return null;
    final f = downloadProgress.value;
    return [
      s.downloading(r.label),
      if (f != null) '${(f * 100).round()} %',
    ].join(' ');
  }

  // ── Download ───────────────────────────────────────────────────────────

  /// The background download takes care of [r] (or did): no "available"
  /// banner, only the "ready" one once it is complete.
  bool downloadsSilently(UpdateResult r) =>
      config.autoCheck() &&
      platform.isSupported &&
      isApkUrl(r.url) &&
      r.key != failed.value?.key;

  /// The downloaded APK of [r] if it is complete and still there.
  String? readyApk(UpdateResult r) => _readyApk(r);

  String? _readyApk(UpdateResult r) {
    final path = _apkVersion == r.key ? _apkPath : null;
    return path != null && downloader.exists(path) ? path : null;
  }

  /// One file per build: many builds share one x.y.z.
  String _apkName(UpdateResult r) =>
      '${config.appName.replaceAll(' ', '')}-${r.version}'
      '${r.build == null ? '' : '-${r.build}'}.apk';

  /// Downloads [r]'s APK once (concurrent callers share the download); a
  /// failed one is tried again on the next call. One downloaded before a
  /// restart is reused. Null on failure.
  Future<String?> _fetchApk(UpdateResult r) {
    if (_apk != null && _apkVersion == r.key) {
      if (_apkPath == null || _readyApk(r) != null) return _apk!;
    }
    _apkUpdate = r;
    _apkPath = null;
    late final Future<String?> f;
    f = _download(r).then((path) {
      if (_apk != f) return path; // another version took over
      if (path == null) _apk = null;
      _apkPath = path;
      return path;
    });
    return _apk = f;
  }

  Future<String?> _download(UpdateResult r) async {
    final earlier = await downloader.downloaded(_apkName(r));
    if (earlier != null) {
      _log(UpdateLogLevel.info, 'update.download', {
        'version': r.version,
        'cached': true,
      });
      // Downloaded before a restart: keep that time.
      if (downloaded.value?.key != r.key) _recordDownload(r);
      return earlier;
    }
    final url = await _downloadUrl(r);
    if (url == null) return null;
    _log(UpdateLogLevel.info, 'update.download', {'version': r.version});
    downloadProgress.value = null;
    downloading.value = true;
    final sw = Stopwatch()..start();
    final String? path;
    try {
      path = await downloader.download(
        Uri.parse(url),
        _apkName(r),
        onProgress: (f) => downloadProgress.value = f,
      );
    } finally {
      downloading.value = false;
    }
    _log(UpdateLogLevel.info, 'update.downloaded', {
      'ok': path != null,
      'ms': sw.elapsedMilliseconds,
    });
    if (path != null) _recordDownload(r);
    return path;
  }

  /// The release's download link; a private asset becomes a short-lived
  /// signed link that needs no GitHub login. Null when that fails.
  Future<String?> _downloadUrl(UpdateResult r) async {
    final url = r.url;
    if (url == null || !url.startsWith('https://api.github.com/')) return url;
    final token = _token;
    final signed = token == null
        ? null
        : await downloader.signedAssetUrl(Uri.parse(url), token);
    return signed?.toString();
  }

  /// Downloads [r] silently: no dialog, no banner, no notification. A
  /// check's newer version ([user] false) once; a tap on Install ([user])
  /// also after a failed try. When complete, Android's installer opens.
  Future<void> _downloadInBackground(
    UpdateResult r, {
    bool user = false,
  }) async {
    if (r.status != UpdateStatus.available ||
        !platform.isSupported ||
        !isApkUrl(r.url)) {
      return;
    }
    if (user) {
      _wantInstall = r.key;
    } else if (!config.autoCheck() ||
        r.key == ready.value ||
        r.key == failed.value?.key) {
      return;
    }
    failed.value = null;
    final path = await _fetchApk(r);
    // A newer build came out meanwhile: its own check downloads that one.
    if (!user && result.value?.key != r.key) return;
    if (path == null) {
      failed.value = r; // the banner's Try again downloads it again
      if (user) _message((s) => s.installFailed);
      return;
    }
    if (ready.value != r.key) {
      _log(UpdateLogLevel.info, 'update.ready', {'version': r.key});
    }
    _readyUpdate = r;
    ready.value = r.key;
    await _offerInstall(r);
  }

  // ── Install ────────────────────────────────────────────────────────────

  /// The APK of [r] is complete: Android's own "Update this app?" opens,
  /// the only confirm. By itself only while the app is in the foreground
  /// (else when it is back) and once per build and start; cancelled, the
  /// banner's Install opens it again. A tap on Install ([user], or one
  /// before the download was complete) always opens it.
  Future<void> _offerInstall(UpdateResult r, {bool user = false}) async {
    final path = _readyApk(r);
    if (path == null) return;
    if (!user) {
      if (!_inForeground) return; // handleResume
      if (_wantInstall != r.key && _asked.contains(r.key)) return;
    }
    _asked.add(r.key);
    _wantInstall = null;
    final outcome = await _openInstaller(r, path);
    if (outcome == 'needs-permission') {
      _message((s) => s.allowInstall);
    } else if (outcome != 'ok') {
      _message((s) => s.installFailed);
    }
  }

  /// A SnackBar where Install was tapped last, else on the app's screen.
  void _message(String Function(UpdateStrings s) text) {
    final tap = _tapContext;
    final c = tap != null && tap.mounted ? tap : _context;
    if (c != null && c.mounted) _show(c, text(_strings(c)));
  }

  /// Hands the APK to a PackageInstaller session: Android shows its own
  /// "Update this app?". Without the one-time "install unknown apps"
  /// permission, its switch opens instead and the install starts when the
  /// user comes back.
  Future<String> _openInstaller(UpdateResult r, String path) async {
    final outcome = await platform.installApk(path);
    _log(UpdateLogLevel.info, 'update.install', {'outcome': outcome});
    if (outcome == 'needs-permission') _installOnResume = r;
    return outcome;
  }

  /// Install on the banner, in the changelog, in Settings or for an older
  /// version: opens Android's installer for a complete APK. Otherwise it
  /// downloads silently (one SnackBar says so) and the installer opens when
  /// it is complete. Builds signed with the same key update in place, data
  /// kept. Without an APK (a release page), or off a phone, the link opens
  /// in the browser instead.
  Future<void> install(BuildContext context, UpdateResult r) async {
    final s = _strings(context);
    _tapContext = context;
    if (!platform.isSupported || !isApkUrl(r.url)) {
      _log(UpdateLogLevel.info, 'update.open_download', {
        'version': r.version,
      });
      final url = await _downloadUrl(r);
      if (!context.mounted) return;
      if (url == null) {
        _show(context, s.downloadLinkFailed);
        return;
      }
      final ok = await platform.openUrl(url);
      if (!ok && context.mounted) _show(context, s.notAvailableInPreview);
      return;
    }
    if (_readyApk(r) != null) {
      await _offerInstall(r, user: true);
      return;
    }
    _log(UpdateLogLevel.info, 'update.download_tap', {'version': r.key});
    _show(context, s.downloadingBackground(r.label));
    await _downloadInBackground(r, user: true);
  }

  /// "Check for updates" tapped: checks now; a newer build downloads
  /// silently (one SnackBar says so) and Android's installer opens when it
  /// is complete, at once if it already is. Otherwise a SnackBar says the
  /// status.
  Future<UpdateResult> checkNow(BuildContext context) async {
    final r = await check();
    if (!context.mounted) return r;
    if (r.status == UpdateStatus.available) {
      _dismissed = null;
      await install(context, r);
    } else {
      _show(context, statusLabel(_strings(context), r));
    }
    return r;
  }

  /// Pull-down in the changelog: the same check as the automatic one, and
  /// the older-versions list is read again.
  Future<void> refresh() async {
    _versions = null;
    final r = await check();
    if (r.status == UpdateStatus.available) _dismissed = null;
  }

  /// The "available" banner's Later: hidden until a newer build is found.
  void dismiss(UpdateResult r) {
    _dismissed = r.key;
    notifyListeners();
  }

  /// The "available" banner shows for [r]: no background download takes
  /// care of it and it wasn't dismissed.
  bool showsAvailableBanner(UpdateResult r) =>
      r.status == UpdateStatus.available &&
      !downloadsSilently(r) &&
      r.key != _dismissed;

  // ── Older versions ─────────────────────────────────────────────────────

  /// version (x.y.z) -> its highest build with an APK, for every release of
  /// any channel still listed. Read once until [refresh]; empty on failure.
  Future<Map<String, UpdateResult>> releasesByVersionList() =>
      _versions ??= _readVersions().catchError((Object _) {
        _versions = null;
        return const <String, UpdateResult>{};
      });

  Future<Map<String, UpdateResult>> _readVersions() async {
    if (!configured) return const {};
    // A GitHub repo lists every release, whatever the update provider.
    if (config.githubRepo.isEmpty) {
      final r = await _fromManifest();
      return {if (r.version != null && r.url != null) r.version!: r};
    }
    final json = await http.getJson(
      _releasesUrl(100),
      headers: _githubHeaders,
      cacheFor: config.releaseListCache,
    );
    return releasesByVersion(
      (json as List).whereType<Map<String, Object?>>(),
      ReleaseFilter(
        tagPrefix: config.tagPrefix,
        legacyBuildLimit: config.legacyBuildLimit,
      ),
      assetPattern: config.assetPattern,
      privateRepo: config.privateRepo,
    );
  }

  /// A version in the changelog was tapped: a sheet offers its download
  /// (an older one: rollback, which downloads silently and installs).
  Future<void> onVersionTap(BuildContext context, String version) {
    _log(UpdateLogLevel.info, 'update.version_tap', {'version': version});
    return showUpdateVersionSheet(context, this, version);
  }

  @override
  void dispose() {
    _stopPolling();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    // The notifiers stay usable: a download still running finishes quietly.
    for (final n in _parts) {
      n.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
