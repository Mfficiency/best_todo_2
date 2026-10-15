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

  /// GitHub's API rate limit: automatic checks pause until it resets
  /// ([UpdateController.pausedUntil]); a tap still checks.
  rateLimited,
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
    this.browserUrl,
    this.builtAt,
    this.buildDuration,
    this.apkSize,
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

  /// The same APK as a plain github.com link (needs a GitHub login for a
  /// private repo), else the release page; null for a manifest. Opened
  /// off a phone when [url] can't be turned into a link a browser can use.
  final String? browserUrl;

  /// When the APK was built (local time): the release notes' "Built:" line,
  /// else when the release was published. Null for a manifest.
  final DateTime? builtAt;

  /// How long the build took (the release notes' "Built: … in 3m 12s" or
  /// "Build duration: 3m 12s"); null when the notes don't say.
  final Duration? buildDuration;

  /// The APK's size in bytes (the release asset's size).
  final int? apkSize;

  /// Whether [builtAt], [buildDuration] or [apkSize] is known.
  bool get hasBuildInfo =>
      builtAt != null || buildDuration != null || apkSize != null;

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

/// A release tag taken apart.
typedef ReleaseTagParts = ({String version, int? build, String channel});

/// The release tags of one app:
/// `<prefix><x.y.z>-<buildPrefix><build>[-dev|-staging]`.
///
/// Lenient (the default): any tag that starts with [prefix] followed by a
/// digit counts; the build is the number after the version (without
/// [buildPrefix]), the channel the `-dev` / `-staging` suffix.
///
/// [strict]: the whole tag must be exactly that format (so tags of an
/// older scheme, e.g. a CI-era `vesta-immo-v0.1.13-b1019-00d2e9d`, are
/// never offered). [pattern]: the app's own format instead, a RegExp with
/// the named groups `version` (required), `build` and `channel`
/// (optional); it is strict by nature (use `^…$`).
class TagFormat {
  const TagFormat({
    this.prefix = 'v',
    this.buildPrefix = '',
    this.strict = false,
    this.pattern,
  });

  /// "v", "music-v", "vesta-immo-v". Case-insensitive.
  final String prefix;

  /// Text before the build number: "b" for `…-b3600000`.
  final String buildPrefix;
  final bool strict;
  final RegExp? pattern;

  /// The tag's version, build and channel; null when it isn't a tag of
  /// this app.
  ReleaseTagParts? parse(String tag) {
    final t = tag.trim();
    final custom = pattern;
    if (custom != null) return _named(custom.firstMatch(t));
    if (strict) {
      String esc(String s) => RegExp.escape(s);
      return _named(
        RegExp(
          '^${esc(prefix)}(?<version>\\d+\\.\\d+\\.\\d+)[-+]'
          '${esc(buildPrefix)}(?<build>\\d+)(?:-(?<channel>dev|staging))?\$',
          caseSensitive: false,
        ).firstMatch(t),
      );
    }
    if (!matchesTagPrefix(t, prefix)) return null;
    final rest = _strip(t, prefix);
    final parts = rest.split(RegExp(r'[-+]'));
    var build = parts.skip(1).firstOrNull ?? '';
    if (buildPrefix.isNotEmpty &&
        build.toLowerCase().startsWith(buildPrefix.toLowerCase())) {
      build = build.substring(buildPrefix.length);
    }
    return (
      version: parts.first.replaceFirst(RegExp(r'^[vV]'), ''),
      build: int.tryParse(build),
      channel: releaseChannel(t),
    );
  }

  static ReleaseTagParts? _named(RegExpMatch? m) {
    if (m == null) return null;
    String? group(String name) =>
        m.groupNames.contains(name) ? m.namedGroup(name) : null;
    final version = group('version');
    if (version == null || version.isEmpty) return null;
    final channel = group('channel')?.toLowerCase();
    return (
      version: version,
      build: int.tryParse(group('build') ?? ''),
      channel: channel == 'dev' || channel == 'staging' ? channel! : 'main',
    );
  }
}

/// On equal build numbers (a commit merged dev → staging → main is built
/// with the same number on each): main first, then staging, then dev.
int channelRank(String? channel) => switch (channel) {
      'main' || null => 0,
      'staging' => 1,
      'dev' => 2,
      _ => 3,
    };

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
    this.tagFormat,
    this.includePrereleases = true,
    this.legacyBuildLimit = 0,
    this.requireApk = true,
    this.assetPattern,
  });

  /// Only tags `<tagPrefix><x.y.z>…` (several apps can share one repo, e.g.
  /// "v" and "music-v"). Ignored when [tagFormat] is set.
  final String tagPrefix;

  /// The app's tag format (build prefix, strict); default: lenient
  /// [tagPrefix] tags.
  final TagFormat? tagFormat;

  /// False: releases marked pre-release are skipped.
  final bool includePrereleases;

  /// staging/dev releases with a build number below this are skipped (they
  /// were separate apps once); main releases always count.
  final int legacyBuildLimit;

  /// Releases without an APK asset ([assetPattern]) are skipped: a release
  /// whose APK is still uploading, or that was published without one, is
  /// never offered. False: offered with its release page.
  final bool requireApk;

  /// The APK asset: the first whose name matches; null = the first `.apk`.
  final Pattern? assetPattern;

  TagFormat get format => tagFormat ?? TagFormat(prefix: tagPrefix);

  /// A published release (never a draft) of this app that may be offered.
  bool accepts(Map<String, Object?> r) {
    if (r['draft'] == true) return false;
    if (!includePrereleases && r['prerelease'] == true) return false;
    final tag = format.parse('${r['tag_name']}');
    if (tag == null) return false;
    if (requireApk && apkAsset(r, assetPattern) == null) return false;
    return tag.channel == 'main' || (tag.build ?? 0) >= legacyBuildLimit;
  }

  /// The releases of all channels (main, staging, dev) the app may update
  /// to, highest build number first (the versionCode Android compares; not
  /// newest by date: a re-run may publish an older build later). Equal
  /// builds: main before staging before dev, then the higher x.y.z.
  List<Map<String, Object?>> sort(Iterable<Map<String, Object?>> releases) {
    final f = format;
    final parsed = [
      for (final r in releases.where(accepts))
        (r, f.parse('${r['tag_name']}')!),
    ];
    parsed.sort((a, b) {
      final c = (b.$2.build ?? 0).compareTo(a.$2.build ?? 0);
      if (c != 0) return c;
      final ch = channelRank(a.$2.channel).compareTo(channelRank(b.$2.channel));
      return ch != 0 ? ch : compareVersions(b.$2.version, a.$2.version);
    });
    return [for (final p in parsed) p.$1];
  }
}

/// The APK asset of a GitHub release: the first whose name matches
/// [assetPattern] (default: ends with ".apk"); null without one.
Map<Object?, Object?>? apkAsset(
  Map<String, Object?> r, [
  Pattern? assetPattern,
]) {
  bool isApk(String name) => assetPattern == null
      ? name.endsWith('.apk')
      : assetPattern.allMatches(name).isNotEmpty;
  return (r['assets'] as List? ?? const [])
      .whereType<Map<Object?, Object?>>()
      .where((a) => isApk('${a['name']}'))
      .firstOrNull;
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
/// [tagFormat] reads the tag (default: lenient [tagPrefix] tags).
UpdateResult releaseResult(
  Map<String, Object?> r, {
  String tagPrefix = 'v',
  TagFormat? tagFormat,
  Pattern? assetPattern,
  bool privateRepo = false,
}) {
  final tagName = '${r['tag_name']}';
  final format = tagFormat ?? TagFormat(prefix: tagPrefix);
  final tag = format.parse(tagName) ??
      (
        version: releaseVersion(tagName, prefix: format.prefix),
        build: releaseBuild(tagName, prefix: format.prefix),
        channel: releaseChannel(tagName),
      );
  final apk = apkAsset(r, assetPattern);
  final String url;
  final String browserUrl;
  if (apk == null) {
    url = browserUrl = '${r['html_url']}';
  } else {
    browserUrl = '${apk['browser_download_url']}';
    url = privateRepo && apk['url'] is String
        ? apk['url']! as String
        : browserUrl;
  }
  return UpdateResult(
    UpdateStatus.available,
    version: tag.version,
    build: tag.build,
    url: url,
    browserUrl: browserUrl,
    notes: r['body'] as String?,
    channel: tag.channel,
    builtAt: buildTime(r['body'] as String?) ??
        DateTime.tryParse('${r['published_at'] ?? r['created_at']}')
            ?.toLocal(),
    buildDuration: buildDuration(r['body'] as String?),
    apkSize: (apk?['size'] as num?)?.toInt(),
  );
}

// The build footer the apps' tool/build.ps1 (or tool/publish_apk.dart)
// writes into the release notes, in its variants:
//   - Built: 2026-10-15 14:02 in 3m 12s, APK 19.4 MB
//   Built: 2026-10-15 14:02 in 3m 5s
//   - Built: 2026-10-15 14:02 UTC+02:00
//   - Build duration: 3m 12s
final _builtLine = RegExp(
  r'^[-*]?\s*Built:\s*(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})'
  r'(?:\s*(?:UTC|GMT)?\s*([+-])(\d{1,2}):?(\d{2}))?(?:\s+in\s+([^,\n]+))?',
  multiLine: true,
);
final _durationLine = RegExp(
  r'^[-*]?\s*Build duration[^:\n]*:\s*([^,\n]+)',
  multiLine: true,
);

/// When the release notes say the APK was built, in local time (a time
/// with a UTC offset is converted; one without is the builder's local
/// time, taken as is). Null when they don't say.
DateTime? buildTime(String? notes) {
  final m = notes == null ? null : _builtLine.firstMatch(notes);
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  if (m.group(6) == null) return DateTime(g(1), g(2), g(3), g(4), g(5));
  final offset = Duration(hours: g(7), minutes: g(8));
  final utc = DateTime.utc(g(1), g(2), g(3), g(4), g(5));
  return (m.group(6) == '-' ? utc.add(offset) : utc.subtract(offset))
      .toLocal();
}

/// How long the build took, from the release notes ("in 3m 12s" on the
/// "Built:" line, or a "Build duration:" line). Null when they don't say.
Duration? buildDuration(String? notes) {
  if (notes == null) return null;
  final text = _builtLine.firstMatch(notes)?.group(9) ??
      _durationLine.firstMatch(notes)?.group(1);
  return text == null ? null : parseBuildDuration(text);
}

/// "1h 03m", "3m 12s", "42s" (also "3m 5s", "3 min") as a [Duration]; null
/// for anything else.
Duration? parseBuildDuration(String text) {
  final parts = RegExp(r'(\d+)\s*(h|m|min|s|sec)\b').allMatches(text);
  if (parts.isEmpty) return null;
  var seconds = 0;
  for (final p in parts) {
    final n = int.parse(p.group(1)!);
    seconds += switch (p.group(2)!) {
      'h' => n * 3600,
      'm' || 'min' => n * 60,
      _ => n,
    };
  }
  return Duration(seconds: seconds);
}

/// "45s", "3m 12s", "1h 03m".
String formatBuildDuration(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (h > 0) return '${h}h ${two(m)}m';
  if (m > 0) return '${m}m ${two(sec)}s';
  return '${sec}s';
}

/// "19.4 MB", "812 KB".
String formatApkSize(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).round()} KB';

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
      tagFormat: filter.format,
      assetPattern: assetPattern ?? filter.assetPattern,
      privateRepo: privateRepo,
    );
    if (isApkUrl(u.url)) out.putIfAbsent(u.version!, () => u);
  }
  return out;
}
