import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

// StreamAudioSource is marked experimental in just_audio, but it is the
// only hook that lets the app (rather than ExoPlayer) issue the HTTP
// requests, which is the whole point here.
// ignore_for_file: experimental_member_use
import 'package:just_audio/just_audio.dart' as ja;

import 'log_service.dart';
import 'mp3_downloader_service.dart';

/// Streams a YouTube video's audio for `MusicAudioHandler`.
///
/// Why not just hand ExoPlayer the stream URL: YouTube throttles a single
/// open-ended response to ~31 KiB/s and, for most clients, refuses anything
/// past the first MiB (see `Mp3DownloaderService`'s measurements). This
/// source resolves the URL with the same client walk the MP3 Downloader
/// uses and serves just_audio's local proxy from a series of
/// [kAudioChunkBytes] range requests, which YouTube serves at full speed.
///
/// Two guards keep that from downloading more than playback needs:
/// - **Generations**: ExoPlayer drops its connection and opens a new range
///   on every seek, but just_audio's proxy never cancels the old response
///   stream. Each [request] bumps a counter and an older stream stops at
///   its next chunk boundary.
/// - **Read-ahead cap**: the proxy never applies back-pressure, so chunks
///   are fetched at most [_maxReadAhead] bytes ahead of where real-time
///   playback (estimated from the stream's average byte rate) should be,
///   instead of pulling a two-hour podcast into memory up front.
class YoutubeAudioSource extends ja.StreamAudioSource {
  YoutubeAudioSource(this.videoId, {this.duration, super.tag});

  final String videoId;

  /// Used to pace read-ahead; a sensible default byte rate is assumed when
  /// unknown.
  final Duration? duration;

  static const int _maxReadAhead = 6 * kAudioChunkBytes;

  Future<ResolvedAudioStream>? _resolved;
  int _generation = 0;

  Future<ResolvedAudioStream> _resolve() => _resolved ??=
      Mp3DownloaderService.instance.resolveAudioStream(videoId).then(
        (r) {
          LogService.add(
              'Feed', 'Streaming $videoId (${r.contentType}, ${r.totalBytes} B)');
          return r;
        },
        onError: (Object e) {
          _resolved = null; // let a retry resolve again
          LogService.add('Feed', 'Could not stream $videoId: $e');
          throw e;
        },
      );

  @override
  Future<ja.StreamAudioResponse> request([int? start, int? end]) async {
    final resolved = await _resolve();
    final total = resolved.totalBytes;
    final from = (start ?? 0).clamp(0, total);
    final to = (end ?? total).clamp(from, total);
    final generation = ++_generation;
    return ja.StreamAudioResponse(
      sourceLength: total,
      contentLength: to - from,
      offset: from,
      contentType: resolved.contentType,
      stream: _chunks(resolved, from, to, generation),
    );
  }

  Stream<List<int>> _chunks(
    ResolvedAudioStream resolved,
    int from,
    int to,
    int generation,
  ) async* {
    final seconds = duration?.inSeconds ?? 0;
    // ~160 kbps when the duration is unknown.
    final bytesPerSecond =
        seconds > 0 ? math.max(1, resolved.totalBytes ~/ seconds) : 20 * 1024;
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    final clock = Stopwatch()..start();
    var position = from;
    try {
      while (position < to) {
        if (generation != _generation) return; // superseded by a seek
        final consumed = clock.elapsed.inSeconds * bytesPerSecond;
        if (position - from > consumed + _maxReadAhead) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }
        final last = math.min(position + kAudioChunkBytes, to) - 1;
        final request = await http.getUrl(resolved.url);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$position-$last');
        final response = await request.close().timeout(kChunkTimeout);
        if (response.statusCode != 206 && response.statusCode != 200) {
          await response.drain<void>();
          throw HttpException(
              'YouTube answered HTTP ${response.statusCode} at byte $position');
        }
        await for (final bytes in response.timeout(kChunkTimeout)) {
          yield bytes;
          position += bytes.length;
        }
        if (position <= last) {
          throw const HttpException('YouTube stopped sending data');
        }
      }
    } finally {
      http.close(force: true);
    }
  }
}
