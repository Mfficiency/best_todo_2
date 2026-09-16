import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;

import 'log_service.dart';
import 'mp4_metadata_writer.dart';
import 'playlist_video_ids.dart';
import 'track_title.dart';

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
    this.uploadDate,
  });

  final String videoId;
  final String title;
  final String channel;
  final Duration? duration;

  /// Lifetime play count, or null when YouTube didn't report one (live
  /// streams and some age-restricted videos omit it).
  final int? viewCount;

  /// When the video was uploaded, if YouTube reported one — used to tag a
  /// downloaded track's year.
  final DateTime? uploadDate;
}

/// A resolved YouTube playlist: its title and every video in it, mapped to
/// the same [Mp3SearchResult] shape a search/direct-URL lookup produces so
/// the rest of the pipeline (queueing, filename formatting, tagging)
/// doesn't need to know a track came from a playlist.
class Mp3PlaylistInfo {
  const Mp3PlaylistInfo({required this.title, required this.tracks});

  final String title;
  final List<Mp3SearchResult> tracks;
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

/// Matches a YouTube playlist URL — `youtube.com/playlist?list=...` or a
/// video's own URL carrying `&list=...` (what sharing "the playlist" from a
/// video that's part of one actually sends) — and captures the playlist id.
///
/// Deliberately anchored to an actual YouTube URL rather than accepting a
/// bare id: `youtube_explode_dart`'s own [yt_explode.PlaylistId] parser
/// treats *any* short alphanumeric string as a "valid" raw playlist id,
/// which would misfire on an ordinary one-word search query.
final RegExp _youtubePlaylistUrlPattern = RegExp(
  r'(?:youtube\.[a-z.]+|youtu\.be)/\S*[?&]list=([A-Za-z0-9_-]+)',
);

/// True when [input] is a link to a YouTube playlist (checked before
/// [looksLikeYoutubeUrl] so a video-within-a-playlist link is treated as the
/// playlist, since that's what "share the list" actually sends).
bool looksLikeYoutubePlaylistUrl(String input) =>
    _youtubePlaylistUrlPattern.hasMatch(input.trim());

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

/// How long one chunk may take before the download is declared stalled.
/// Generous enough for a slow mobile connection (a 1 MiB chunk at 20 KiB/s
/// takes ~50 s) but bounded, so a wedged socket surfaces as an error the
/// user can read instead of a progress bar that never moves — which is
/// exactly how the original `streamsClient.get()` failure presented.
const Duration kChunkTimeout = Duration(seconds: 90);

/// Ceiling on working out which client can serve a video. Resolving walks
/// several clients, each a network round trip, so this bounds the whole walk
/// rather than any one request.
const Duration kResolveTimeout = Duration(seconds: 90);

/// Turns a filesystem failure on [dir] into something a user can act on.
///
/// The case worth spelling out is Android scoped storage: from Android 10 an
/// app can't write to a shared folder like `/storage/emulated/0/Music` by
/// path, and this app declares no storage permission — but
/// `file_selector`'s directory picker happily hands back exactly such a path
/// (`FileUtils.getPathFromUri` maps the tree URI onto the raw path). Left
/// alone that surfaces as a bare `OS Error: Permission denied, errno = 13`.
String describeFolderProblem(String dir, Object error) {
  final permissionDenied = error is FileSystemException &&
      (error.osError?.errorCode == 13 || error.osError?.errorCode == 1);
  if (permissionDenied && Platform.isAndroid) {
    return "Android won't let the app write to $dir. Pick a folder inside "
        "the app's own storage in Settings → MP3 Downloader, or choose "
        'another location.';
  }
  return "Can't save to $dir: $error";
}

/// True when [dir] can actually be written to, checked by creating and
/// deleting a probe file. Cheap, and the only reliable answer on Android —
/// a path existing there says nothing about being writable.
Future<bool> canWriteToFolder(String dir) async {
  try {
    final directory = Directory(dir);
    await directory.create(recursive: true);
    final probe = File(
        '${dir}${dir.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}'
        '.besttodo_write_test');
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}

/// Recursively collects the filename (without extension, lowercased) of
/// every audio file already saved under [folder] and its subfolders — used
/// to skip playlist tracks that are already downloaded. Matches on name
/// rather than video id: a `.webm`/`.mp3` file predating this app's own
/// metadata tagging carries no reliable back-reference to its source video,
/// but the "Artist - Title" it's saved under is exactly what a duplicate
/// download would be named too.
Future<Set<String>> existingTrackBaseNames(String folder) async {
  final names = <String>{};
  try {
    final dir = Directory(folder);
    if (!await dir.exists()) return names;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      final dot = name.lastIndexOf('.');
      if (dot <= 0) continue;
      final ext = name.substring(dot + 1).toLowerCase();
      if (ext != 'm4a' && ext != 'webm' && ext != 'mp3') continue;
      names.add(name.substring(0, dot).toLowerCase());
    }
  } catch (_) {
    // Best-effort: if the folder can't be scanned, nothing gets skipped.
  }
  return names;
}

/// A folder the app can always write to without any storage permission:
/// the app-specific external directory on Android
/// (`Android/data/<pkg>/files`), the OS downloads folder elsewhere.
Future<String?> defaultDownloadFolder() async {
  try {
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir.path;
    }
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads.path;
    return (await getApplicationDocumentsDirectory()).path;
  } catch (_) {
    return null;
  }
}

/// Tools → MP3 Downloader: looks up a YouTube video — by pasted URL or by a
/// title search — and saves its audio track to a file.
///
/// Uses `youtube_explode_dart` (a pure-Dart YouTube client; no server
/// component, API key, or native code) to resolve metadata and the
/// audio-only stream, and saves it as delivered — YouTube's audio-only
/// streams are AAC (in an mp4 container, saved as `.m4a`) or Opus (in webm,
/// saved as `.webm`), not literal MP3.
///
/// The saved file is named `Artist - Title.<ext>` (see [parseTrackTitle]):
/// the title/channel are split on an `Artist - Title` separator when
/// present, falling back to the channel name as the artist, and
/// promotional clutter like "(Official Video)" or "(Lyrics)" is stripped
/// from both. An `.m4a` file is then tagged in place with that title,
/// artist, the source URL as a comment, the upload year, and the video
/// thumbnail as cover art — see [Mp4MetadataWriter] for how that's done
/// without a native encoder. `.webm` files aren't tagged; embedding
/// metadata in Matroska/Opus is a different format this doesn't cover.
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
  Future<Mp3PlaylistInfo> Function(String input)? playlistOverride;
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
                uploadDate: v.uploadDate,
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
        uploadDate: video.uploadDate,
      );
    } catch (e) {
      _log('Resolving $id failed: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Resolves a playlist URL (or bare id) to its title and every video in
  /// it, in playlist order.
  ///
  /// `youtube_explode_dart`'s own `PlaylistClient.getVideos` silently
  /// *skips* an entry whose uploader channel id it can't parse off the page
  /// (it tries three known JSON paths; a newer @handle-style byline layout
  /// misses all three), so a real, fully public playlist can come back with
  /// a title and zero tracks — reported against a 3-track playlist that
  /// otherwise resolved fine. When that happens, [fetchPlaylistVideoIdsFromPage]
  /// walks the same page structure for just the video ids (which don't need
  /// a byline to parse) and each is resolved individually — slower, but
  /// immune to that specific gap.
  Future<Mp3PlaylistInfo> resolvePlaylist(String input) async {
    if (playlistOverride != null) return playlistOverride!(input);
    _log('Resolving playlist from "$input"');
    final client = yt_explode.YoutubeExplode();
    try {
      final playlist = await client.playlists.get(input);
      _log('Playlist metadata: title="${playlist.title}" author="${playlist.author}" '
          'videoCount=${playlist.videoCount}');
      var videos = await client.playlists.getVideos(input).toList();
      _log('getVideos() returned ${videos.length} track(s)');
      if (videos.isEmpty) {
        _log('getVideos() found no tracks for "${playlist.title}" — '
            'falling back to raw page parsing');
        videos = await _resolvePlaylistVideosFallback(input, client);
        _log('Fallback resolved ${videos.length} track(s)');
      }
      final tracks = videos
          .map((v) => Mp3SearchResult(
                videoId: v.id.value,
                title: v.title,
                channel: v.author,
                duration: v.duration,
                viewCount: v.engagement.viewCount,
                uploadDate: v.uploadDate,
              ))
          .toList();
      _log('Playlist "${playlist.title}" has ${tracks.length} video(s)');
      return Mp3PlaylistInfo(title: playlist.title, tracks: tracks);
    } catch (e) {
      _log('Resolving playlist "$input" failed: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Resolves each video id found by directly parsing the playlist page,
  /// skipping (and logging) any single video that fails to resolve rather
  /// than failing the whole playlist over one bad entry.
  Future<List<yt_explode.Video>> _resolvePlaylistVideosFallback(
    String input,
    yt_explode.YoutubeExplode client,
  ) async {
    final ids = await fetchPlaylistVideoIdsFromPage(input);
    _log('Fallback page parsing found ${ids.length} video id(s): $ids');
    final videos = <yt_explode.Video>[];
    for (final id in ids) {
      try {
        final video = await client.videos.get(id);
        _log('Fallback resolved $id -> "${video.title}"');
        videos.add(video);
      } catch (e) {
        _log('Skipping unresolved playlist video $id: $e');
      }
    }
    return videos;
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

  /// Fetches `bytes=[start]-[end]` into [sink] and returns the new byte
  /// offset. Pulled out of the download loop so the whole request/read pair
  /// can carry one [kChunkTimeout] — a timeout around only `close()` would
  /// still let a half-open response hang forever mid-body.
  Future<int> _fetchChunk({
    required HttpClient http,
    required Uri url,
    required int start,
    required int end,
    required int total,
    required IOSink sink,
    required _Flag abandoned,
  }) async {
    final request = await http.getUrl(url);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final response = await request.close();
    if (response.statusCode != 206 && response.statusCode != 200) {
      await response.drain<void>();
      throw Mp3DownloadException(
        'YouTube refused the rest of this track '
        '(HTTP ${response.statusCode} at ${_mb(start)} of ${_mb(total)}).',
      );
    }
    var received = start;
    await for (final chunk in response) {
      if (abandoned.value) return received;
      sink.add(chunk);
      received += chunk.length;
    }
    return received;
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
      final resolved = await _resolveStream(result.videoId, http)
          .timeout(kResolveTimeout, onTimeout: () {
        throw Mp3DownloadException(
          'Timed out working out how to download this track. Check your '
          'connection and try again.',
        );
      });
      final info = resolved.info;
      final total = resolved.totalBytes;

      final extension = _extensionFor(info.container);
      final trackTitle = parseTrackTitle(result.title, result.channel);
      final fileName = sanitizeAudioFileName(trackTitle.fileBaseName, extension);
      final separator = Platform.pathSeparator;
      final destination = destinationDir.endsWith(separator)
          ? destinationDir
          : '$destinationDir$separator';
      try {
        await Directory(destinationDir).create(recursive: true);
      } on FileSystemException catch (e) {
        throw Mp3DownloadException(describeFolderProblem(destinationDir, e));
      }
      final outputFile = File('$destination$fileName');
      // Write to `<name>.part` and rename on success, so an interrupted
      // download never leaves a half file that looks playable.
      final partFile = File('${outputFile.path}.part');
      if (await partFile.exists()) await partFile.delete();

      final sink = partFile.openWrite();
      var received = 0;
      final stopwatch = Stopwatch()..start();
      // Set when a chunk times out: the abandoned fetch may still be mid-flight
      // and must not write into a sink the `finally` below is about to close.
      final abandoned = _Flag();
      try {
        while (received < total) {
          if (cancelled?.call() ?? false) {
            _log('Download cancelled: "${result.title}"');
            throw Mp3DownloadException('Cancelled');
          }
          final lastByte = received + kAudioChunkBytes - 1;
          final end = lastByte > total - 1 ? total - 1 : lastByte;
          final before = received;
          received = await _fetchChunk(
            http: http,
            url: info.url,
            start: received,
            end: end,
            total: total,
            sink: sink,
            abandoned: abandoned,
          ).timeout(kChunkTimeout, onTimeout: () {
            abandoned.value = true;
            throw Mp3DownloadException(
              'Download stalled at ${_mb(before)} of ${_mb(total)} — no data '
              'from YouTube for ${kChunkTimeout.inSeconds}s. Check your '
              'connection and try again.',
            );
          });
          if (received == before) {
            throw Mp3DownloadException(
              'YouTube stopped sending data at ${_mb(received)} of '
              '${_mb(total)}.',
            );
          }
          onProgress?.call(received, total);
        }
        await sink.flush();
      } catch (_) {
        // Never leave a half-written file behind that looks like a playable
        // track — the next attempt starts clean.
        try {
          await sink.close();
          if (await partFile.exists()) await partFile.delete();
        } catch (_) {}
        rethrow;
      } finally {
        try {
          await sink.close();
        } catch (_) {}
      }

      if (await outputFile.exists()) await outputFile.delete();
      await partFile.rename(outputFile.path);
      final seconds = stopwatch.elapsedMilliseconds / 1000;
      final rate = received / 1024 / (seconds <= 0 ? 1 : seconds);
      _log('Download finished: "${result.title}" — ${_mb(received)} in '
          '${seconds.toStringAsFixed(1)}s (${rate.round()} KiB/s) '
          '-> ${outputFile.path}');
      onProgress?.call(total, total);
      if (extension == 'm4a') {
        // Best-effort: an untagged file is fine, a corrupted one isn't —
        // see [Mp4MetadataWriter] for why this never touches the file
        // unless it's confident the result is still valid.
        await _tagDownloadedFile(outputFile.path, result, trackTitle);
      }
      return outputFile.path;
    } catch (e) {
      _log('Download failed for "${result.title}": $e');
      rethrow;
    } finally {
      http.close(force: true);
    }
  }

  /// Embeds title/artist/comment/year/cover-art metadata into an already
  /// saved `.m4a` file. Never lets a tagging problem fail the download —
  /// the file at [path] is already a complete, valid track by the time
  /// this runs.
  Future<void> _tagDownloadedFile(
    String path,
    Mp3SearchResult result,
    TrackTitleParts trackTitle,
  ) async {
    try {
      final coverArt = await _fetchThumbnail(result.videoId);
      final tagged = await Mp4MetadataWriter.tag(
        path,
        title: trackTitle.title,
        artist: trackTitle.artist,
        comment: 'https://www.youtube.com/watch?v=${result.videoId}',
        year: result.uploadDate?.year,
        coverArtJpeg: coverArt,
      );
      _log(tagged
          ? 'Tagged metadata for "${result.title}"'
          : 'Skipped tagging "${result.title}" (unrecognised file layout)');
    } catch (e) {
      _log('Tagging failed for "${result.title}": $e');
    }
  }

  /// Fetches the video's thumbnail for embedding as cover art. Best-effort:
  /// any failure (offline, 404, timeout) just means no cover art.
  Future<Uint8List?> _fetchThumbnail(String videoId) async {
    final url = yt_explode.ThumbnailSet(videoId).highResUrl;
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await http.getUrl(Uri.parse(url));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final bytes = await response.fold<BytesBuilder>(
        BytesBuilder(),
        (builder, chunk) => builder..add(chunk),
      ).timeout(const Duration(seconds: 15));
      return bytes.toBytes();
    } catch (_) {
      return null;
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

/// A mutable boolean shared with an in-flight chunk fetch, so a timeout can
/// tell it to stop writing without waiting for it to notice on its own.
class _Flag {
  bool value = false;
}
