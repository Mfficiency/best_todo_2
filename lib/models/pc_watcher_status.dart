/// The laptop builder's status as the PC Watcher tool shows it: every build
/// it ran (time, duration, result, APK sizes, error) and what is still to
/// build. Written by `dev-build-watch.ps1` in Mfficiency/laptop-builder and
/// read from that repo's `status` branch (`pc_watcher.json`). Parsing is
/// tolerant of missing keys, like the other models.
library;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

String _string(Object? value) => value is String ? value : '';

String? _optString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList()
    : const [];

/// One APK a build published as a GitHub release.
class PcWatcherApk {
  final String app;
  final String version;
  final String channel;
  final String tag;
  final String repo;
  final int? sizeBytes;

  const PcWatcherApk({
    required this.app,
    required this.version,
    required this.channel,
    required this.tag,
    required this.repo,
    this.sizeBytes,
  });

  factory PcWatcherApk.fromJson(Map<String, dynamic> json) => PcWatcherApk(
        app: _string(json['app']),
        version: _string(json['version']),
        channel: _string(json['channel']),
        tag: _string(json['tag']),
        repo: _string(json['repo']),
        sizeBytes: _int(json['apkSizeBytes']),
      );
}

/// What a build ended as.
enum PcBuildResult { building, published, unchanged, failed, unknown }

PcBuildResult _result(Object? value) {
  switch (value) {
    case 'building':
      return PcBuildResult.building;
    case 'published':
      return PcBuildResult.published;
    case 'unchanged':
      return PcBuildResult.unchanged;
    case 'failed':
      return PcBuildResult.failed;
  }
  return PcBuildResult.unknown;
}

/// One run of an app's build script for one branch (channel).
class PcWatcherBuild {
  final String id;
  final String app;
  final String branch;
  final String sha;
  final int? buildNumber;

  /// 'push' (asked for by a push), 'catch-up' (the 10-minute task) or
  /// 'unknown' (rebuilt from the old text logs).
  final String trigger;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? durationSeconds;
  final PcBuildResult result;
  final List<PcWatcherApk> published;
  final String? error;

  /// The end of the build output, for failed builds.
  final String? log;

  const PcWatcherBuild({
    required this.id,
    required this.app,
    required this.branch,
    required this.sha,
    this.buildNumber,
    this.trigger = 'unknown',
    this.startedAt,
    this.finishedAt,
    this.durationSeconds,
    this.result = PcBuildResult.unknown,
    this.published = const [],
    this.error,
    this.log,
  });

  factory PcWatcherBuild.fromJson(Map<String, dynamic> json) => PcWatcherBuild(
        id: _string(json['id']),
        app: _string(json['app']),
        branch: _string(json['branch']),
        sha: _string(json['sha']),
        buildNumber: _int(json['buildNumber']),
        trigger: _optString(json['trigger']) ?? 'unknown',
        startedAt: _date(json['startedAt']),
        finishedAt: _date(json['finishedAt']),
        durationSeconds: _int(json['durationSeconds']),
        result: _result(json['result']),
        published:
            _maps(json['published']).map(PcWatcherApk.fromJson).toList(),
        error: _optString(json['error']),
        log: _optString(json['log']),
      );

  /// Sum of the published APKs' sizes; null when none is known.
  int? get apkSizeBytes {
    final sizes = published.map((a) => a.sizeBytes).whereType<int>();
    return sizes.isEmpty ? null : sizes.reduce((a, b) => a + b);
  }
}

/// One app + branch the laptop builds, and where it stands.
class PcWatcherChannel {
  final String app;
  final String key;
  final String branch;
  final String repo;

  /// 'idle' (newest commit built), 'pending' (a new commit waits),
  /// 'queued' (waits for a running build of the same channel), 'building'
  /// or 'failed' (its newest commit failed; retried by the next check).
  final String state;
  final String remoteHead;
  final String builtHead;
  final DateTime? since;
  final DateTime? lastCheckAt;
  final String? lastError;

  const PcWatcherChannel({
    required this.app,
    required this.key,
    required this.branch,
    this.repo = '',
    this.state = 'idle',
    this.remoteHead = '',
    this.builtHead = '',
    this.since,
    this.lastCheckAt,
    this.lastError,
  });

  factory PcWatcherChannel.fromJson(Map<String, dynamic> json) =>
      PcWatcherChannel(
        app: _string(json['app']),
        key: _string(json['key']),
        branch: _string(json['branch']),
        repo: _string(json['repo']),
        state: _optString(json['state']) ?? 'idle',
        remoteHead: _string(json['remoteHead']),
        builtHead: _string(json['builtHead']),
        since: _date(json['since']),
        lastCheckAt: _date(json['lastCheckAt']),
        lastError: _optString(json['lastError']),
      );

  /// Still has work to do, failed at it, or couldn't even be checked.
  bool get isPending => state != 'idle' || lastError != null;
}

class PcWatcherStatus {
  /// The builder PC's name.
  final String machine;
  final DateTime? updatedAt;

  /// When the laptop last looked for new commits: its heartbeat.
  final DateTime? lastCheckAt;
  final List<PcWatcherChannel> channels;

  /// Newest first.
  final List<PcWatcherBuild> builds;

  const PcWatcherStatus({
    this.machine = '',
    this.updatedAt,
    this.lastCheckAt,
    this.channels = const [],
    this.builds = const [],
  });

  factory PcWatcherStatus.fromJson(Map<String, dynamic> json) {
    final builds = _maps(json['builds']).map(PcWatcherBuild.fromJson).toList()
      ..sort((a, b) {
        final at = a.startedAt, bt = b.startedAt;
        if (at == null || bt == null) return at == null ? 1 : -1;
        return bt.compareTo(at);
      });
    return PcWatcherStatus(
      machine: _string(json['machine']),
      updatedAt: _date(json['updatedAt']),
      lastCheckAt: _date(json['lastCheckAt']),
      channels: _maps(json['channels']).map(PcWatcherChannel.fromJson).toList(),
      builds: builds,
    );
  }

  List<PcWatcherChannel> get pending =>
      channels.where((c) => c.isPending).toList();

  /// Apps in the order they last built.
  List<String> get apps {
    final seen = <String>{};
    for (final b in builds) {
      seen.add(b.app);
    }
    for (final c in channels) {
      seen.add(c.app);
    }
    return seen.where((a) => a.isNotEmpty).toList();
  }
}

/// A job of the laptop's GitHub Actions runner that hasn't finished: a build
/// asked for by a push, waiting for (or running on) the laptop.
class PcRunnerJob {
  final String title;
  final String status;
  final DateTime? createdAt;

  const PcRunnerJob({required this.title, required this.status, this.createdAt});

  factory PcRunnerJob.fromJson(Map<String, dynamic> json) => PcRunnerJob(
        title: _optString(json['display_title']) ??
            _optString(json['name']) ??
            'Laptop build',
        status: _string(json['status']),
        createdAt: _date(json['created_at']),
      );

  bool get isRunning => status == 'in_progress';
}

/// "45s", "4m 05s", "1h 02m".
String formatBuildDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    return '${minutes}m ${(seconds % 60).toString().padLeft(2, '0')}s';
  }
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// "22.4 MB" (MiB, as the build scripts report APK sizes).
String formatApkSize(int bytes) {
  final mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(1)} MB';
}
