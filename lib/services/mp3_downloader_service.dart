import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;

/// One candidate track shown to the user when a search query is ambiguous —
/// title, channel and duration are enough to tell tracks apart before
/// picking which one to download.
class Mp3SearchResult {
  const Mp3SearchResult({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.duration,
  });

  final String videoId;
  final String title;
  final String channel;
  final Duration? duration;
}

/// Thrown by [Mp3DownloaderService.downloadMp3] for a failure the caller
/// should show verbatim (no audio stream available, ffmpeg conversion
/// failed) rather than a generic error.
class Mp3DownloadException implements Exception {
  Mp3DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Matches a YouTube video URL (youtube.com/watch, youtu.be, m./music.
/// subdomains, and /shorts/) and captures the 11-character video id.
final RegExp _youtubeUrlPattern = RegExp(
  r'(?:youtube\.com/(?:watch\?(?:.*&)?v=|shorts/)|youtu\.be/)([A-Za-z0-9_-]{11})',
);

/// True when [input] looks like a YouTube URL rather than free-text search
/// terms — the caller should resolve it directly instead of searching.
bool looksLikeYoutubeUrl(String input) =>
    _youtubeUrlPattern.hasMatch(input.trim());

/// Pulls the 11-character video id out of a YouTube URL, or null if [input]
/// doesn't contain one.
String? extractYoutubeVideoId(String input) =>
    _youtubeUrlPattern.firstMatch(input.trim())?.group(1);

/// Turns a video title into a filesystem-safe .mp3 filename: strips
/// characters illegal on Windows/Android, collapses whitespace, and caps
/// the length so the save always succeeds.
String sanitizeMp3FileName(String title) {
  var name = title.trim();
  if (name.isEmpty) name = 'audio';
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.length > 120) name = name.substring(0, 120).trim();
  return '$name.mp3';
}

/// Tools → MP3 Downloader: looks up a YouTube video — by pasted URL or by a
/// title search — and saves its audio track as an .mp3 file.
///
/// Uses `youtube_explode_dart` (a pure-Dart YouTube client; no server
/// component or API key) to resolve metadata and the audio-only stream, then
/// `ffmpeg_kit_flutter_new_full` to transcode it into a real .mp3 — the raw
/// stream YouTube serves is AAC/Opus in an mp4/webm container, not MP3.
/// Both plugins run on Android, Windows, iOS, macOS and Linux but not web,
/// so callers should gate the tool on [isSupported].
class Mp3DownloaderService {
  Mp3DownloaderService._();

  static final Mp3DownloaderService instance = Mp3DownloaderService._();

  /// Neither `youtube_explode_dart`'s scraping nor the ffmpeg plugin has a
  /// web build, so the tool hides itself there instead of failing at runtime.
  bool get isSupported => !kIsWeb;

  /// Lets tests substitute fakes instead of hitting the network / native
  /// ffmpeg plugin.
  @visibleForTesting
  Future<List<Mp3SearchResult>> Function(String query, int limit)?
      searchOverride;
  @visibleForTesting
  Future<Mp3SearchResult> Function(String videoId)? resolveOverride;
  @visibleForTesting
  Future<String> Function(
    Mp3SearchResult result,
    String destinationDir,
    void Function(double progress)? onProgress,
  )? downloadOverride;

  Future<List<Mp3SearchResult>> search(String query, {int limit = 5}) async {
    if (searchOverride != null) return searchOverride!(query, limit);
    final client = yt_explode.YoutubeExplode();
    try {
      final results = await client.search.search(query);
      return results
          .take(limit)
          .map((v) => Mp3SearchResult(
                videoId: v.id.value,
                title: v.title,
                channel: v.author,
                duration: v.duration,
              ))
          .toList();
    } finally {
      client.close();
    }
  }

  /// Resolves a pasted URL (or bare video id) to its title/channel/duration
  /// so the caller can show a confirmation before downloading.
  Future<Mp3SearchResult> resolve(String urlOrId) async {
    final id = extractYoutubeVideoId(urlOrId) ?? urlOrId.trim();
    if (resolveOverride != null) return resolveOverride!(id);
    final client = yt_explode.YoutubeExplode();
    try {
      final video = await client.videos.get(id);
      return Mp3SearchResult(
        videoId: video.id.value,
        title: video.title,
        channel: video.author,
        duration: video.duration,
      );
    } finally {
      client.close();
    }
  }

  /// Downloads [result]'s audio and converts it to `<title>.mp3` inside
  /// [destinationDir], returning the final file path. [onProgress] is called
  /// with values in [0, 1] — the download makes up the first 90%, the ffmpeg
  /// conversion pass the last 10%.
  Future<String> downloadMp3(
    Mp3SearchResult result,
    String destinationDir, {
    void Function(double progress)? onProgress,
  }) async {
    if (downloadOverride != null) {
      return downloadOverride!(result, destinationDir, onProgress);
    }
    final client = yt_explode.YoutubeExplode();
    File? tempFile;
    try {
      final manifest =
          await client.videos.streamsClient.getManifest(result.videoId);
      if (manifest.audioOnly.isEmpty) {
        throw Mp3DownloadException('No audio stream found for this video');
      }
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
      final stream = client.videos.streamsClient.get(audioStreamInfo);

      final tempDir = await getTemporaryDirectory();
      final ext = audioStreamInfo.container.name;
      tempFile = File('${tempDir.path}${Platform.pathSeparator}'
          'yt_${result.videoId}_${DateTime.now().millisecondsSinceEpoch}.$ext');
      final sink = tempFile.openWrite();
      var received = 0;
      final total = audioStreamInfo.size.totalBytes;
      await for (final chunk in stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress((received / total) * 0.9);
        }
      }
      await sink.flush();
      await sink.close();

      final fileName = sanitizeMp3FileName(result.title);
      final separator = Platform.pathSeparator;
      final destination = destinationDir.endsWith(separator)
          ? destinationDir
          : '$destinationDir$separator';
      final outputPath = '$destination$fileName';
      final session = await FFmpegKit.execute(
        '-y -i "${tempFile.path}" -vn -ar 44100 -ac 2 -b:a 192k "$outputPath"',
      );
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw Mp3DownloadException(
          'Audio conversion failed: ${logs ?? 'unknown ffmpeg error'}',
        );
      }
      onProgress?.call(1.0);
      return outputPath;
    } finally {
      client.close();
      // Best-effort cleanup: a failure here must never mask whatever
      // exception (if any) is already propagating out of the try block.
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }
}
