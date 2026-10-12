import 'package:flutter/foundation.dart';

import 'release.dart';

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
    this.buildPrefix = '',
    this.strictTags = false,
    this.tagPattern,
    this.assetPattern,
    this.requireApk = true,
    this.privateRepo = false,
    this.tokenProvider,
    this.autoCheck = _yes,
    this.autoCheckChanges,
    this.includePrereleases = _yes,
    this.legacyBuildLimit = 0,
    this.checkInterval = const Duration(hours: 24),
    this.pollInterval = Duration.zero,
    this.firstCheckDelay = const Duration(seconds: 3),
    this.releasesPerPage = 30,
    this.releaseListCache = const Duration(hours: 1),
    this.checkOnResume = true,
    this.rateLimitPause = const Duration(minutes: 30),
    this.userAgent,
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

  /// Release tags of this app:
  /// `<tagPrefix><x.y.z>-<buildPrefix><build>[-dev|-staging]`. Two apps in
  /// one repo use different prefixes ("v", "music-v").
  final String tagPrefix;

  /// Text before the build number in the tag: "b" for Vesta's
  /// `vesta-immo-v0.1.19-b3600000-dev`. Default none.
  final String buildPrefix;

  /// Only tags in exactly that format count (older schemes, e.g. CI-era
  /// tags with a commit sha, are never offered). Default: any tag that
  /// starts with [tagPrefix] and a version.
  final bool strictTags;

  /// The app's own tag format instead of [tagPrefix]/[buildPrefix]: named
  /// groups `version` (required), `build` and `channel`; strict by nature.
  final RegExp? tagPattern;

  /// The APK asset of a release: the first whose name matches; null = the
  /// first `.apk`.
  final Pattern? assetPattern;

  /// Releases without an APK asset are never offered (one whose APK is
  /// still uploading, or a release published without one). False: such a
  /// release is offered with its release page, which Install opens in the
  /// browser.
  final bool requireApk;

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

  /// Notifies when [autoCheck] changes (e.g. the settings object, or a
  /// ValueNotifier<bool> of the switch): turned on, polling starts and a
  /// check runs when due; turned off, polling stops. Without it, call
  /// [UpdateController.autoCheckChanged].
  final Listenable? autoCheckChanges;

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

  /// Back in the foreground, check (silently, like the poll) when the last
  /// check is older than [dueAfter].
  final bool checkOnResume;

  /// GitHub's rate limit pauses the automatic checks until the reset its
  /// answer names, else for this long. Taps still check.
  final Duration rateLimitPause;

  /// `User-Agent` of the default dart:io requests; null =
  /// `<appName without spaces>-update-check`.
  final String? userAgent;

  /// The `User-Agent` header actually sent by the default HTTP.
  String get httpUserAgent =>
      userAgent ?? '${appName.replaceAll(' ', '')}-update-check';

  /// How old the last check may be before coming back to the app (or
  /// turning [autoCheck] on) checks: [pollInterval], or [checkInterval]
  /// without polling.
  Duration get dueAfter =>
      pollInterval > Duration.zero ? pollInterval : checkInterval;

  /// How this app's release tags are read.
  TagFormat get tagFormat => TagFormat(
        prefix: tagPrefix,
        buildPrefix: buildPrefix,
        strict: strictTags,
        pattern: tagPattern,
      );

  /// "1.2.0 (5)", plus " · dev" on a staging/dev build.
  String get versionLabel =>
      '$version ($build)${channel == 'main' ? '' : ' · $channel'}';

  bool get configured => switch (provider) {
        UpdateProvider.github => githubRepo.isNotEmpty,
        UpdateProvider.manifest => manifestUrl.isNotEmpty,
      };
}
