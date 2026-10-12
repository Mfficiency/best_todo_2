/// Where updates come from.
enum UpdateProvider {
  /// GitHub Releases of [UpdateConfig.githubRepo].
  github,

  /// A JSON file at [UpdateConfig.manifestUrl]:
  /// `{"version": "1.2.0", "build": 12, "url": "…apk", "notes": "…"}`.
  manifest,
}

bool _yes() => true;

/// What the app is and where its updates come from. Everything the package
/// needs to know about the app; nothing else is read from it.
class UpdateConfig {
  const UpdateConfig({
    required this.appName,
    required this.version,
    required this.build,
    this.channel = 'main',
    this.provider = UpdateProvider.github,
    this.githubRepo = '',
    this.manifestUrl = '',
    this.tagPrefix = 'v',
    this.assetPattern,
    this.privateRepo = false,
    this.tokenProvider,
    this.autoCheck = _yes,
    this.includePrereleases = _yes,
    this.legacyBuildLimit = 0,
    this.checkInterval = const Duration(hours: 24),
    this.pollInterval = Duration.zero,
    this.firstCheckDelay = const Duration(seconds: 3),
    this.releasesPerPage = 30,
    this.releaseListCache = const Duration(hours: 1),
  });

  /// The app's name; the APK file is `<name without spaces>-<x.y.z>-<build>.apk`.
  final String appName;

  /// The running x.y.z.
  final String version;

  /// The running build number (Android's versionCode): a release with a
  /// higher one is an update, whatever its x.y.z or channel.
  final int build;

  /// The branch this build came from (main, staging, dev). Only shown next
  /// to the version: every channel is the same app.
  final String channel;

  final UpdateProvider provider;

  /// "owner/repo"; empty = not configured (for [UpdateProvider.github]).
  final String githubRepo;

  /// For [UpdateProvider.manifest]; empty = not configured.
  final String manifestUrl;

  /// Release tags of this app: `<tagPrefix><x.y.z>-<build>[-dev|-staging]`.
  /// Two apps in one repo use different prefixes ("v", "music-v").
  final String tagPrefix;

  /// The APK asset of a release: the first whose name matches; null = the
  /// first `.apk`.
  final Pattern? assetPattern;

  /// The repo is private: checks need a token ([tokenProvider]) and the APK
  /// downloads through the asset API (a short-lived signed link).
  final bool privateRepo;

  /// The GitHub token (read access to the repo), read at [UpdateController.init]
  /// and [UpdateController.reloadToken]. Null or empty = none. Sent as
  /// `Authorization: Bearer` to the GitHub API only.
  final Future<String?> Function()? tokenProvider;

  /// The user's "Check automatically" switch: automatic checks, polling
  /// and the silent background download.
  final bool Function() autoCheck;

  /// False: releases marked pre-release on GitHub are not offered.
  final bool Function() includePrereleases;

  /// staging/dev releases with a build number below this are never offered
  /// (from when they were separate apps). 0 = all.
  final int legacyBuildLimit;

  /// The check at start runs when the last one is older than this.
  final Duration checkInterval;

  /// While the app is in the foreground, check this often; zero = never.
  final Duration pollInterval;

  /// The check at start waits this long after the first frame.
  final Duration firstCheckDelay;

  /// Releases listed by a check (all channels, the highest build wins).
  final int releasesPerPage;

  /// The older-versions list may be served from a cache this young.
  final Duration releaseListCache;

  /// "1.2.0 (5)", plus " · dev" on a staging/dev build.
  String get versionLabel =>
      '$version ($build)${channel == 'main' ? '' : ' · $channel'}';

  bool get configured => switch (provider) {
        UpdateProvider.github => githubRepo.isNotEmpty,
        UpdateProvider.manifest => manifestUrl.isNotEmpty,
      };
}
