import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'log_service.dart';
import 'media_scanner_service.dart';
import 'mp3_downloader_service.dart';

/// Where a job is in its life. [queued] jobs are waiting for the one running
/// download to finish — downloads run one at a time so several large tracks
/// can't starve each other of bandwidth.
enum Mp3DownloadStatus { queued, running, completed, failed, cancelled }

/// One download, past or present. Completed and failed jobs are kept as the
/// history shown on the downloads page.
class Mp3DownloadJob {
  Mp3DownloadJob({
    required this.id,
    required this.videoId,
    required this.title,
    required this.channel,
    required this.destinationDir,
    this.status = Mp3DownloadStatus.queued,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.filePath,
    this.error,
    this.uploadDate,
    DateTime? queuedAt,
    this.finishedAt,
  }) : queuedAt = queuedAt ?? DateTime.now();

  final String id;
  final String videoId;
  final String title;
  final String channel;
  final String destinationDir;

  /// When the source video was uploaded, if known — carried through so a
  /// resumed/re-run job can still tag the file with the right year.
  final DateTime? uploadDate;

  Mp3DownloadStatus status;
  int receivedBytes;
  int totalBytes;
  String? filePath;
  String? error;
  final DateTime queuedAt;
  DateTime? finishedAt;

  /// `[0, 1]`, or null while the total size isn't known yet (which makes the
  /// UI show an indeterminate spinner rather than a misleading 0%).
  double? get progress =>
      totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : null;

  bool get isActive =>
      status == Mp3DownloadStatus.queued || status == Mp3DownloadStatus.running;

  Map<String, dynamic> toJson() => {
        'id': id,
        'videoId': videoId,
        'title': title,
        'channel': channel,
        'destinationDir': destinationDir,
        'status': status.name,
        'receivedBytes': receivedBytes,
        'totalBytes': totalBytes,
        'filePath': filePath,
        'error': error,
        'uploadDate': uploadDate?.toIso8601String(),
        'queuedAt': queuedAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
      };

  static Mp3DownloadJob fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String? ?? 'failed';
    var status = Mp3DownloadStatus.values.firstWhere(
      (s) => s.name == rawStatus,
      orElse: () => Mp3DownloadStatus.failed,
    );
    // A job that was still running when the app was killed cannot be
    // resumed from disk — record it as interrupted instead of showing a
    // progress bar that will never move.
    var error = json['error'] as String?;
    if (status == Mp3DownloadStatus.queued ||
        status == Mp3DownloadStatus.running) {
      status = Mp3DownloadStatus.failed;
      error ??= 'Interrupted when the app closed';
    }
    return Mp3DownloadJob(
      id: json['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      videoId: json['videoId'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown',
      channel: json['channel'] as String? ?? '',
      destinationDir: json['destinationDir'] as String? ?? '',
      status: status,
      receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      filePath: json['filePath'] as String?,
      error: error,
      uploadDate: DateTime.tryParse(json['uploadDate'] as String? ?? ''),
      queuedAt:
          DateTime.tryParse(json['queuedAt'] as String? ?? '') ?? DateTime.now(),
      finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
    );
  }
}

/// App-level queue for MP3 downloads.
///
/// This is what makes downloads behave like the app-update download: the
/// queue lives on the service, not on [Mp3DownloaderPage], so leaving the
/// page — or backgrounding the app — doesn't touch a transfer in flight, and
/// the downloads button shows what is still running when you come back.
///
/// It is *not* an OS-level download the way an APK fetch is. YouTube
/// throttles a single un-ranged response to ~31 KiB/s, so audio has to be
/// pulled as a series of range requests (see [Mp3DownloaderService]), and
/// Android's `DownloadManager` cannot do that — it only knows how to fetch
/// one URL straight through. The practical difference: a download survives
/// navigating away and the app being backgrounded, but not the app being
/// force-stopped or evicted, in which case the job is marked interrupted on
/// the next launch rather than silently resumed.
class Mp3DownloadManager {
  Mp3DownloadManager._();

  static final Mp3DownloadManager instance = Mp3DownloadManager._();

  /// Newest first. Widgets listen to this to redraw progress.
  final ValueNotifier<List<Mp3DownloadJob>> jobs =
      ValueNotifier<List<Mp3DownloadJob>>(<Mp3DownloadJob>[]);

  /// How many finished jobs to keep in the history file.
  static const int _historyLimit = 100;

  final Set<String> _cancelRequests = <String>{};
  bool _draining = false;
  bool _loaded = false;

  Mp3DownloaderService get _service => Mp3DownloaderService.instance;

  int get activeCount => jobs.value.where((j) => j.isActive).length;

  void _log(String message) => LogService.add('MP3', message);

  Future<File?> _historyFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}${Platform.pathSeparator}mp3_downloads.json');
    } catch (_) {
      // Web/tests without a path provider — history just isn't persisted.
      return null;
    }
  }

  /// Reads the saved history. Safe to call repeatedly; only the first call
  /// does any work.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _historyFile();
      if (file == null || !await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      jobs.value = decoded
          .whereType<Map>()
          .map((e) => Mp3DownloadJob.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      _log('Could not read download history: $e');
    }
  }

  Future<void> _save() async {
    try {
      final file = await _historyFile();
      if (file == null) return;
      final keep = jobs.value.take(_historyLimit).toList();
      await file.writeAsString(
        jsonEncode(keep.map((j) => j.toJson()).toList()),
        flush: true,
      );
    } catch (e) {
      _log('Could not save download history: $e');
    }
  }

  /// Republishes the list so [ValueNotifier] listeners rebuild. The jobs are
  /// mutable, so the list identity has to change for the notifier to fire.
  void _publish() {
    jobs.value = List<Mp3DownloadJob>.from(jobs.value);
  }

  /// Queues [result] for download into [destinationDir] and returns the job.
  /// The returned job updates in place as the download runs.
  Mp3DownloadJob enqueue(Mp3SearchResult result, String destinationDir) {
    final job = Mp3DownloadJob(
      id: '${DateTime.now().microsecondsSinceEpoch}-${result.videoId}',
      videoId: result.videoId,
      title: result.title,
      channel: result.channel,
      destinationDir: destinationDir,
      uploadDate: result.uploadDate,
    );
    jobs.value = [job, ...jobs.value];
    _log('Queued "${job.title}" -> $destinationDir');
    unawaited(_drain());
    return job;
  }

  /// Asks the running (or queued) job to stop at the next chunk boundary.
  void cancel(String jobId) {
    final job = jobs.value.firstWhere(
      (j) => j.id == jobId,
      orElse: () => Mp3DownloadJob(
          id: '', videoId: '', title: '', channel: '', destinationDir: ''),
    );
    if (job.id.isEmpty || !job.isActive) return;
    _cancelRequests.add(jobId);
    _log('Cancel requested for "${job.title}"');
    if (job.status == Mp3DownloadStatus.queued) {
      job.status = Mp3DownloadStatus.cancelled;
      job.finishedAt = DateTime.now();
      _cancelRequests.remove(jobId);
      _publish();
      unawaited(_save());
    }
  }

  /// Drops a finished job from the history list.
  Future<void> remove(String jobId) async {
    jobs.value = jobs.value.where((j) => j.id != jobId).toList();
    await _save();
  }

  /// Clears every finished job, leaving anything still running.
  Future<void> clearFinished() async {
    jobs.value = jobs.value.where((j) => j.isActive).toList();
    await _save();
  }

  /// Runs queued jobs one at a time until none are left.
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (true) {
        final next = jobs.value.cast<Mp3DownloadJob?>().lastWhere(
              (j) => j!.status == Mp3DownloadStatus.queued,
              orElse: () => null,
            );
        if (next == null) break;
        await _run(next);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _run(Mp3DownloadJob job) async {
    job.status = Mp3DownloadStatus.running;
    _publish();
    final result = Mp3SearchResult(
      videoId: job.videoId,
      title: job.title,
      channel: job.channel,
      duration: null,
      uploadDate: job.uploadDate,
    );
    try {
      final path = await _service.downloadMp3(
        result,
        job.destinationDir,
        onProgress: (received, total) {
          job.receivedBytes = received;
          job.totalBytes = total;
          _publish();
        },
        cancelled: () => _cancelRequests.contains(job.id),
      );
      job.status = Mp3DownloadStatus.completed;
      job.filePath = path;
      // Written with plain File I/O, so the OS media database doesn't know
      // it exists yet — nudge it so the track shows up in Music/My Files
      // apps right away instead of after the next full device scan.
      await MediaScannerService.scanFile(path);
    } catch (e) {
      if (_cancelRequests.contains(job.id)) {
        job.status = Mp3DownloadStatus.cancelled;
      } else {
        job.status = Mp3DownloadStatus.failed;
        job.error = e is Mp3DownloadException ? e.message : e.toString();
      }
    } finally {
      _cancelRequests.remove(job.id);
      job.finishedAt = DateTime.now();
      _publish();
      await _save();
    }
  }

  @visibleForTesting
  void resetForTest() {
    jobs.value = <Mp3DownloadJob>[];
    _cancelRequests.clear();
    _draining = false;
    _loaded = false;
  }
}
