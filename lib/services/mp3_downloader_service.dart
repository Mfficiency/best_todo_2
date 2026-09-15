import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;

import 'log_service.dart';

/// One candidate track shown to the user when a search query is ambiguous —
/// title, channel, duration and play count are enough to tell tracks apart
/// (and to spot the "real" upload among reuploads) before picking one.
class Mp3SearchResult {
  const Mp3SearchResult({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.duration,
    this.viewCount,
  });

  final String videoId;
  final String title;
  final String channel;
  final Duration? duration;

  /// Lifetime play count, or null when YouTube didn't report one (live
  /// streams and some age-restricted videos omit it).
  final int? viewCount;
}

/// Formats a play count the way YouTube does — `1.2M`, `376M`, `12K` — so a
/// long number doesn't push the channel name off a narrow phone row.
String formatViewCount(int? views) {
  if (views == null) return '';
  if (views < 1000) return '$views';
  if (views < 1000000) {
    final k = views / 1000;
    return '${k < 10 ? k.toStringAsFixed(1) : k.round()}K';
  }
  if (views < 1000000000) {
    final m = views / 1000000;
    return '${m < 10 ? m.toStringAsFixed(1) : m.round()}M';
  }
  final b = views / 1000000000;
  return '${b.toStringAsFixed(1)}B';
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

/// YouTube's visionOS InnerTube client, transcribed from yt-dlp's client
/// table (`yt_dlp/extractor/youtube/_base.py`, the `visionos` entry).
///
/// This one matters a lot: it is the only client we found that YouTube will
/// serve a *whole* audio stream to without a PoToken. Every client shipped
/// in `youtube_explode_dart` 3.1.0 (`androidSdkless`, `android`, `ios`,
/// `androidVr`, `tv`, `mweb`, …) hands back a URL that serves the first
/// 1 MiB and then answers `403` for every byte after it — which is exactly
/// what made the downloader sit at 0% forever on label-protected music.
/// See [Mp3DownloaderService] for the measurements.
final yt_explode.YoutubeApiClient _visionOsClient = yt_explode.YoutubeApiClient(
  {
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'userAgent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 '
            'Safari/605.1.15',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
  },
  'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
);

/// Clients tried in order when resolving a stream, best first. visionOS is
/// the only one that reliably serves a complete stream, but the others are
/// kept as fallbacks for videos it refuses ("made for kids" videos are not
/// available to the visionOS client at all).
final List<yt_explode.YoutubeApiClient> _streamClients = [
  _visionOsClient,
  yt_explode.YoutubeApiClient.androidSdkless,
  yt_explode.YoutubeApiClient.android,
  yt_explode.YoutubeApiClient.androidVr,
];

/// How much of the stream to ask for per HTTP request. YouTube throttles a
/// single open response to ~31 KiB/s but serves ~1 MiB range requests at
/// full speed, so the download is issued as a series of these.
const int kAudioChunkBytes = 1 << 20;

/// Tools → MP3 Downloader: looks up a YouTube video — by pasted URL or by a
/// title search — and saves its audio track to a file.
///
/// Uses `youtube_explode_dart` (a pure-Dart YouTube client; no server
/// component, API key, or native code) to resolve metadata and the
/// audio-only stream, and saves it as delivered — YouTube's audio-only
/// streams are AAC (in an mp4 container, saved as `.m4a`) or Opus (in webm,
/// saved as `.webm`), not literal MP3.
///
/// ## Why the download is chunked by hand
///
/// The obvious implementation — `streamsClient.get(streamInfo)` — hung at 0%
/// forever on real music, and the naive fix (hand the URL to Android's
/// `DownloadManager`, like the app-update download does) is worse. Measured
/// against `ABBA - Mamma Mia` (3.4 MB of AAC) and `Rick Astley - Never Gonna
/// Give You Up`:
///
/// | approach                                    | result             |
/// |---------------------------------------------|--------------------|
/// | `streamsClient.get()`                       | 0 bytes in 300 s   |
/// | plain GET, no `Range` (= `DownloadManager`) | 200, but 31 KiB/s  |
/// | 1 MiB `Range` requests, stock clients       | `403` past 1 MiB   |
/// | 1 MiB `Range` requests, visionOS client     | ~4 MiB/s, complete |
///
/// So: resolve with [_visionOsClient], then pull the stream as a sequence of
/// [kAudioChunkBytes] range requests. That is ~125x faster than the single
/// throttled response `DownloadManager` would issue, and it is also why the
/// background download cannot simply be delegated to the OS the way an APK
/// download is — `DownloadManager` has no way to walk a file in ranges.
/// `Mp3DownloadManager` provides the app-level background behaviour instead.
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
    void Function(int received, int total)? onProgress,
  )? downloadOverride;

  void _log(String message) => LogService.add('MP3', message);

  Future<List<Mp3SearchResult>> search(String query, {int limit = 5}) async {
    if (searchOverride != null) return searchOverride!(query, limit);
    _log('Searching for "$query"');
    final client = yt_explode.YoutubeExplode();
    try {
      final results = await client.search.search(query);
      final mapped = results
          .take(limit)
          .map((v) => Mp3SearchResult(
                videoId: v.id.value,
                title: v.title,
                channel: v.author,
                duration: v.duration,
                viewCount: v.engagement.viewCount,
              ))
          .toList();
      _log('Search returned ${mapped.length} result(s) for "$query"');
      return mapped;
    } catch (e) {
      _log('Search for "$query" failed: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Resolves a pasted URL (or bare video id) to its title/channel/duration
  /// so the caller can show a confirmation before downloading.
  Future<Mp3SearchResult> resolve(String urlOrId) async {
    final id = extractYoutubeVideoId(urlOrId) ?? urlOrId.trim();
    if (resolveOverride != null) return resolveOverride!(id);
    _log('Resolving video $id');
    final client = yt_explode.YoutubeExplode();
    try {
      final video = await client.videos.get(id);
      _log('Resolved $id -> "${video.title}"');
      return Mp3SearchResult(
        videoId: video.id.value,
        title: video.title,
        channel: video.author,
        duration: video.duration,
        viewCount: video.engagement.viewCount,
      );
    } catch (e) {
      _log('Resolving $id failed: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Picks the best audio stream for [videoId], trying each client in
  /// [_streamClients] until one both returns audio streams *and* proves it
  /// will serve bytes past the 1 MiB PoToken wall.
  Future<_ResolvedStream> _resolveStream(
      String videoId, HttpClient http) async {
    Object? lastError;
    for (final apiClient in _streamClients) {
      final name = ((apiClient.payload['context']
              as Map)['client'] as Map)['clientName'] as String;
      final client = yt_explode.YoutubeExplode();
      try {
        final manifest = await client.videos.streamsClient
            .getManifest(videoId, ytClients: [apiClient]);
        final audioOnly = manifest.audioOnly.toList();
        if (audioOnly.isEmpty) {
          _log('Client $name: no audio-only streams');
          continue;
        }
        // Prefer an AAC/mp4 stream (saved as .m4a) over Opus/webm — much
        // more widely playable — falling back to whatever has the highest
        // bitrate.
        final mp4Streams = audioOnly
            .where((s) => s.container == yt_explode.StreamContainer.mp4)
            .toList();
        final info = (mp4Streams.isNotEmpty ? mp4Streams : audioOnly)
            .withHighestBitrate();
        final total = info.size.totalBytes;
        // Probe a byte well past the wall. A client that 403s here would
        // otherwise stall the download partway with no useful error.
        if (total > kAudioChunkBytes) {
          final ok = await _probeRange(http, info.url, total - 1024, total - 1);
          if (!ok) {
            _log('Client $name: serves only the first MiB (403 past the '
                'PoToken wall), trying next client');
            continue;
          }
        }
        _log('Client $name: using ${info.container.name} '
            '${info.bitrate}, $total bytes');
        return _ResolvedStream(info, total);
      } catch (e) {
        lastError = e;
        _log('Client $name failed: $e');
      } finally {
        client.close();
      }
    }
    throw Mp3DownloadException(
      'YouTube would not serve this track to any client'
      '${lastError == null ? '' : ' ($lastError)'}. '
      'It may be age-restricted, private, or region-locked.',
    );
  }

  /// True when a `Range` request for [start]-[end] is actually served.
  Future<bool> _probeRange(
      HttpClient http, Uri url, int start, int end) async {
    try {
      final request = await http.getUrl(url);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == 206 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Downloads [result]'s audio-only stream straight into [destinationDir]
  /// (as `<title>.m4a` or `<title>.webm`, whichever YouTube served),
  /// returning the final file path.
  ///
  /// [onProgress] is called with `(bytesReceived, totalBytes)` as chunks
  /// land. [cancelled] is polled between chunks so a queued download can be
  /// stopped without killing the isolate.
  Future<String> downloadMp3(
    Mp3SearchResult result,
    String destinationDir, {
    void Function(int received, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    if (downloadOverride != null) {
      return downloadOverride!(result, destinationDir, onProgress);
    }
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      _log('Download starting: "${result.title}" (${result.videoId})');
      final resolved = await _resolveStream(result.videoId, http);
      final info = resolved.info;
      final total = resolved.totalBytes;

      final extension = _extensionFor(info.container);
      final fileName = sanitizeAudioFileName(result.title, extension);
      final separator = Platform.pathSeparator;
      final destination = destinationDir.endsWith(separator)
          ? destinationDir
          : '$destinationDir$separator';
      await Directory(destinationDir).create(recursive: true);
      final outputFile = File('$destination$fileName');
      // Write to `<name>.part` and rename on success, so an interrupted
      // download never leaves a half file that looks playable.
      final partFile = File('${outputFile.path}.part');
      if (await partFile.exists()) await partFile.delete();

      final sink = partFile.openWrite();
      var received = 0;
      final stopwatch = Stopwatch()..start();
      try {
        while (received < total) {
          if (cancelled?.call() ?? false) {
            _log('Download cancelled: "${result.title}"');
            throw Mp3DownloadException('Cancelled');
          }
          final lastByte = received + kAudioChunkBytes - 1;
          final end = lastByte > total - 1 ? total - 1 : lastByte;
          final before = received;
          final request = await http.getUrl(info.url);
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$received-$end');
          final response = await request.close();
          if (response.statusCode != 206 && response.statusCode != 200) {
            await response.drain<void>();
            throw Mp3DownloadException(
              'YouTube refused the rest of this track '
              '(HTTP ${response.statusCode} at ${_mb(received)} of '
              '${_mb(total)}).',
            );
          }
          await for (final chunk in response) {
            sink.add(chunk);
            received += chunk.length;
          }
          if (received == before) {
            throw Mp3DownloadException(
              'YouTube stopped sending data at ${_mb(received)} of '
              '${_mb(total)}.',
            );
          }
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (await outputFile.exists()) await outputFile.delete();
      await partFile.rename(outputFile.path);
      final seconds = stopwatch.elapsedMilliseconds / 1000;
      final rate = received / 1024 / (seconds <= 0 ? 1 : seconds);
      _log('Download finished: "${result.title}" — ${_mb(received)} in '
          '${seconds.toStringAsFixed(1)}s (${rate.round()} KiB/s) '
          '-> ${outputFile.path}');
      onProgress?.call(total, total);
      return outputFile.path;
    } catch (e) {
      _log('Download failed for "${result.title}": $e');
      rethrow;
    } finally {
      http.close(force: true);
    }
  }

  static String _mb(int bytes) =>
      '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

class _ResolvedStream {
  _ResolvedStream(this.info, this.totalBytes);
  final yt_explode.AudioStreamInfo info;
  final int totalBytes;
}
