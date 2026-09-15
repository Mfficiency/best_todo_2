import 'dart:io';

import 'package:flutter/foundation.dart';
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
/// should show verbatim (e.g. no audio stream available for this video).
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

/// Turns a video title into a filesystem-safe filename (without extension):
/// strips characters illegal on Windows/Android, collapses whitespace, and
/// caps the length so the save always succeeds.
String sanitizeAudioFileName(String title, String extension) {
  var name = title.trim();
  if (name.isEmpty) name = 'audio';
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (name.length > 120) name = name.substring(0, 120).trim();
  return '$name.$extension';
}

/// The saved file's container/extension: `m4a` for an AAC-in-MP4 stream
/// (the most widely compatible option), `webm` otherwise.
String _extensionFor(yt_explode.StreamContainer container) =>
    container == yt_explode.StreamContainer.mp4 ? 'm4a' : container.name;

/// Tools → MP3 Downloader: looks up a YouTube video — by pasted URL or by a
/// title search — and saves its audio track to a file.
///
/// Uses `youtube_explode_dart` (a pure-Dart YouTube client; no server
/// component, API key, or native code) to resolve metadata and the
/// audio-only stream, and saves it as delivered — YouTube's audio-only
/// streams are AAC (in an mp4 container, saved as `.m4a`) or Opus (in webm,
/// saved as `.webm`), not literal MP3.
///
/// An earlier version transcoded to a real `.mp3` with
/// `ffmpeg_kit_flutter_new_full`, but every ffmpeg-kit variant — even the
/// audio-only one — bundles the whole ffmpeg native library per Android ABI
/// and added 100+ MB to the APK (tripling it), so it was dropped. Getting an
/// actual `.mp3` file back without that cost needs a from-scratch decode
/// (platform `MediaCodec`/similar) + a small LAME encoder, which is real new
/// native-code work, not a dependency swap — flag it separately if still
/// wanted.
class Mp3DownloaderService {
  Mp3DownloaderService._();

  static final Mp3DownloaderService instance = Mp3DownloaderService._();

  /// `youtube_explode_dart`'s scraping doesn't work from a browser sandbox,
  /// so the tool hides itself on web instead of failing at runtime.
  bool get isSupported => !kIsWeb;

  /// Lets tests substitute fakes instead of hitting the network.
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

  /// Downloads [result]'s audio-only stream straight into [destinationDir]
  /// (as `<title>.m4a` or `<title>.webm`, whichever YouTube served),
  /// returning the final file path. [onProgress] is called with values in
  /// `[0, 1]` as bytes arrive.
  Future<String> downloadMp3(
    Mp3SearchResult result,
    String destinationDir, {
    void Function(double progress)? onProgress,
  }) async {
    if (downloadOverride != null) {
      return downloadOverride!(result, destinationDir, onProgress);
    }
    final client = yt_explode.YoutubeExplode();
    try {
      final manifest =
          await client.videos.streamsClient.getManifest(result.videoId);
      if (manifest.audioOnly.isEmpty) {
        throw Mp3DownloadException('No audio stream found for this video');
      }
      // Prefer an AAC/mp4 stream (saved as .m4a) over Opus/webm — much more
      // widely playable — falling back to whatever has the highest bitrate.
      final mp4Streams = manifest.audioOnly
          .where((s) => s.container == yt_explode.StreamContainer.mp4)
          .toList();
      final audioStreamInfo = (mp4Streams.isNotEmpty
              ? mp4Streams
              : manifest.audioOnly)
          .withHighestBitrate();
      final stream = client.videos.streamsClient.get(audioStreamInfo);

      final extension = _extensionFor(audioStreamInfo.container);
      final fileName = sanitizeAudioFileName(result.title, extension);
      final separator = Platform.pathSeparator;
      final destination = destinationDir.endsWith(separator)
          ? destinationDir
          : '$destinationDir$separator';
      final outputFile = File('$destination$fileName');
      final sink = outputFile.openWrite();
      try {
        var received = 0;
        final total = audioStreamInfo.size.totalBytes;
        await for (final chunk in stream) {
          sink.add(chunk);
          received += chunk.length;
          if (onProgress != null && total > 0) {
            onProgress(received / total);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      onProgress?.call(1.0);
      return outputFile.path;
    } finally {
      client.close();
    }
  }
}
