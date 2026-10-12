/// Release logic without Flutter or I/O: tags, versions, which release is an
/// update. Unit-tested in test/release_test.dart.
library;

enum UpdateStatus {
  upToDate,
  available,
  notConfigured,
  failed,

  /// The repo is private and no GitHub token is saved yet.
  needsToken,

  /// GitHub refused the token (wrong, expired or no access).
  badToken,
}

/// The outcome of a check, or one release offered for download.
class UpdateResult {
  const UpdateResult(
    this.status, {
    this.version,
    this.build,
    this.url,
    this.notes,
    this.channel,
  });
  final UpdateStatus status;

  /// x.y.z.
  final String? version;

  /// Build number (Android's versionCode) when the source knows it, else
  /// null.
  final int? build;

  /// The APK (a direct link, or a private asset's API link) or, without an
  /// APK, the release page.
  final String? url;
  final String? notes;

  /// main, staging or dev (from the tag); null for a manifest.
  final String? channel;

  /// Identifies this exact build: many builds share one x.y.z.
  String get key => '$version+${build ?? 0}';

  /// "1.2.0 (12)" for messages, "1.2.0" when the build is unknown.
  String get label => build == null ? '$version' : '$version ($build)';

  @override
  String toString() => 'UpdateResult(${status.name}, $key)';
}

/// An update APK that finished downloading: which build ([UpdateResult.key]
/// and [UpdateResult.label]) and when.
typedef DownloadRecord = ({String key, String label, DateTime at});

/// [tag] without [prefix] ("v1.2.0-5" -> "1.2.0-5"), case-insensitive. A tag
/// without the prefix is returned unchanged.
String _strip(String tag, String prefix) {
  final t = tag.trim();
  return prefix.isNotEmpty && t.toLowerCase().startsWith(prefix.toLowerCase())
      ? t.substring(prefix.length)
      : t;
}

/// Whether [tag] is a release of the app with this tag [prefix]: the prefix
/// (optional) followed by a version, so with "v", "v1.2.0-5" and "1.2.0+5"
/// match but "music-v1.2.0-5" doesn't.
bool matchesTagPrefix(String tag, String prefix) =>
    RegExp(r'^\d').hasMatch(_strip(tag, prefix));

/// "v1.2.0-5" / "1.2.0+5" -> "1.2.0" (tags are
/// `<prefix><version>-<build>[-<channel>]`).
String releaseVersion(String tag, {String prefix = 'v'}) => _strip(
      tag,
      prefix,
    ).replaceFirst(RegExp(r'^[vV]'), '').split(RegExp(r'[-+]')).first;

/// "v1.2.0-12345-dev" -> 12345; null without a build number.
int? releaseBuild(String tag, {String prefix = 'v'}) => int.tryParse(
      _strip(tag, prefix).split(RegExp(r'[-+]')).skip(1).firstOrNull ?? '',
    );

/// Channel (branch) a release tag was built from: "-dev" / "-staging"
/// suffix, else main. Only informative: every channel is the same app.
String releaseChannel(String tag) =>
    RegExp(r'-(dev|staging)$').firstMatch(tag.trim())?.group(1) ?? 'main';

/// Compares dotted versions ("1.10.0" > "1.9.3"). Ignores "v" prefixes and
/// pre-release/build suffixes. Returns <0, 0 or >0 like compareTo.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Whether [latest] is newer than the running build: a higher build number
/// (the versionCode Android compares), whatever its x.y.z or channel.
/// Without a build number (a manifest without "build"), a higher x.y.z.
bool isNewerRelease(
  UpdateResult latest, {
  required String version,
  required int build,
}) {
  if (latest.version == null) return false;
  final b = latest.build;
  if (b != null) return b > build;
  return compareVersions(latest.version!, version) > 0;
}

/// Which GitHub releases count as updates of an app.
class ReleaseFilter {
  const ReleaseFilter({
    this.tagPrefix = 'v',
    this.includePrereleases = true,
    this.legacyBuildLimit = 0,
  });

  /// Only tags `<tagPrefix><x.y.z>…` (several apps can share one repo, e.g.
  /// "v" and "music-v").
  final String tagPrefix;

  /// False: releases marked pre-release are skipped.
  final bool includePrereleases;

  /// staging/dev releases with a build number below this are skipped (they
  /// were separate apps once); main releases always count.
  final int legacyBuildLimit;

  /// A published release (never a draft) of this app that may be offered.
  bool accepts(Map<String, Object?> r) {
    if (r['draft'] == true) return false;
    if (!includePrereleases && r['prerelease'] == true) return false;
    final tag = '${r['tag_name']}';
    if (!matchesTagPrefix(tag, tagPrefix)) return false;
    return releaseChannel(tag) == 'main' ||
        (releaseBuild(tag, prefix: tagPrefix) ?? 0) >= legacyBuildLimit;
  }

  /// The releases of all channels (main, staging, dev) the app may update
  /// to, highest build number first (the versionCode Android compares; not
  /// newest by date: a re-run may publish an older build later). Equal
  /// builds: higher x.y.z first.
  List<Map<String, Object?>> sort(Iterable<Map<String, Object?>> releases) {
    final list = releases.where(accepts).toList();
    int build(Map<String, Object?> r) =>
        releaseBuild('${r['tag_name']}', prefix: tagPrefix) ?? 0;
    String version(Map<String, Object?> r) =>
        releaseVersion('${r['tag_name']}', prefix: tagPrefix);
    list.sort((a, b) {
      final c = build(b).compareTo(build(a));
      return c != 0 ? c : compareVersions(version(b), version(a));
    });
    return list;
  }
}

/// A release asset (a private one's API link) or a direct `.apk` link, not a
/// release page.
bool isApkUrl(String? url) =>
    url != null &&
    (url.startsWith('https://api.github.com/') ||
        Uri.parse(url).path.endsWith('.apk'));

/// A GitHub release as an update. Its APK is the first asset whose name
/// matches [assetPattern] (default: ends with ".apk"); a private repo's
/// ([privateRepo]) downloads through its API link (with the token), a public
/// one's through the plain browser link. Without an APK: the release page.
UpdateResult releaseResult(
  Map<String, Object?> r, {
  String tagPrefix = 'v',
  Pattern? assetPattern,
  bool privateRepo = false,
}) {
  final tag = '${r['tag_name']}';
  bool isApk(String name) => assetPattern == null
      ? name.endsWith('.apk')
      : assetPattern.allMatches(name).isNotEmpty;
  final apk = (r['assets'] as List? ?? const [])
      .whereType<Map<Object?, Object?>>()
      .where((a) => isApk('${a['name']}'))
      .firstOrNull;
  final String url;
  if (apk == null) {
    url = '${r['html_url']}';
  } else if (privateRepo && apk['url'] is String) {
    url = apk['url']! as String;
  } else {
    url = '${apk['browser_download_url']}';
  }
  return UpdateResult(
    UpdateStatus.available,
    version: releaseVersion(tag, prefix: tagPrefix),
    build: releaseBuild(tag, prefix: tagPrefix),
    url: url,
    notes: r['body'] as String?,
    channel: releaseChannel(tag),
  );
}

/// A JSON manifest `{"version", "build", "url", "notes"}` as an update.
UpdateResult manifestResult(Map<String, Object?> json) => UpdateResult(
      UpdateStatus.available,
      version: json['version'] as String?,
      build: (json['build'] as num?)?.toInt(),
      url: json['url'] as String?,
      notes: json['notes'] as String?,
    );

/// version (x.y.z) -> its highest build with an APK, for every release the
/// [filter] accepts (the older-versions sheet).
Map<String, UpdateResult> releasesByVersion(
  Iterable<Map<String, Object?>> releases,
  ReleaseFilter filter, {
  Pattern? assetPattern,
  bool privateRepo = false,
}) {
  final out = <String, UpdateResult>{};
  // Highest build first, so the first of each x.y.z is kept.
  for (final r in filter.sort(releases)) {
    final u = releaseResult(
      r,
      tagPrefix: filter.tagPrefix,
      assetPattern: assetPattern,
      privateRepo: privateRepo,
    );
    if (isApkUrl(u.url)) out.putIfAbsent(u.version!, () => u);
  }
  return out;
}
