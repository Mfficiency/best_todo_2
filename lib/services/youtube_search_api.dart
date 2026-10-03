import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mp3_downloader_service.dart';

/// Video search through YouTube's internal JSON API (`youtubei/v1/search`,
/// the same endpoint youtube.com's own search box calls).
///
/// `youtube_explode_dart`'s `search.search` scrapes the HTML results page
/// instead, sending only the legacy `CONSENT=YES+cb` cookie — in the EU
/// that page can come back as Google's cookie-consent interstitial, with no
/// results data in it, so every search fails with what looks like a
/// connection error. The JSON API has no consent page, so it is tried first
/// ([Mp3DownloaderService.search] falls back to the scraper if it fails).
class YoutubeSearchApi {
  YoutubeSearchApi._();

  static const String _clientVersion = '2.20250925.01.00';

  /// `params` for "Type: Video" (protobuf `{2: {2: 1}}`), so channels,
  /// playlists and shelves don't crowd out actual songs.
  static const String _videosOnly = 'EgIQAQ==';

  static Future<List<Mp3SearchResult>> search(
    String query, {
    int limit = 5,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final response = await c
          .post(
            Uri.parse(
                'https://www.youtube.com/youtubei/v1/search?prettyPrint=false'),
            headers: const {
              'content-type': 'application/json',
              'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                  'AppleWebKit/537.36 (KHTML, like Gecko) '
                  'Chrome/128.0.0.0 Safari/537.36',
              'x-youtube-client-name': '1',
              'x-youtube-client-version': _clientVersion,
              'origin': 'https://www.youtube.com',
              // Current-style "reject all" consent cookie, in case a
              // consent check ever applies here too.
              'cookie': 'SOCS=CAI',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB',
                  'clientVersion': _clientVersion,
                  'hl': 'en',
                },
              },
              'query': query,
              'params': _videosOnly,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Mp3DownloadException(
            'YouTube search failed (HTTP ${response.statusCode})');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return parseSearchResponse(decoded, limit: limit);
    } finally {
      if (client == null) c.close();
    }
  }

  /// Every `videoRenderer` in a search response, in page order, mapped to
  /// [Mp3SearchResult]s. Walks the whole tree rather than one fixed JSON
  /// path, since YouTube moves its section/shelf wrappers around often.
  /// [now] anchors relative "3 years ago" dates (tests pin it).
  static List<Mp3SearchResult> parseSearchResponse(
    Object? json, {
    int limit = 5,
    DateTime? now,
  }) {
    final results = <Mp3SearchResult>[];
    final seen = <String>{};
    final at = now ?? DateTime.now();

    void walk(Object? node) {
      if (results.length >= limit) return;
      if (node is Map) {
        final renderer = node['videoRenderer'];
        if (renderer is Map) {
          final result = _parseVideo(renderer, at);
          if (result != null && seen.add(result.videoId)) results.add(result);
        }
        for (final value in node.values) {
          if (value is Map || value is List) walk(value);
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(json);
    return results;
  }

  static Mp3SearchResult? _parseVideo(Map renderer, DateTime now) {
    final id = renderer['videoId'];
    if (id is! String || id.isEmpty) return null;
    final title = _text(renderer['title']);
    if (title.isEmpty) return null;
    var channel = _text(renderer['ownerText']);
    if (channel.isEmpty) channel = _text(renderer['longBylineText']);
    return Mp3SearchResult(
      videoId: id,
      title: title,
      channel: channel,
      duration: parseClockDuration(_text(renderer['lengthText'])),
      viewCount: _parseViews(_text(renderer['viewCountText'])),
      uploadDate: parseRelativeDate(_text(renderer['publishedTimeText']), now),
    );
  }

  /// `{simpleText: ...}` or `{runs: [{text: ...}, ...]}` → plain text.
  static String _text(Object? node) {
    if (node is! Map) return '';
    final simple = node['simpleText'];
    if (simple is String) return simple;
    final runs = node['runs'];
    if (runs is List) {
      return runs
          .map((r) => r is Map && r['text'] is String ? r['text'] as String : '')
          .join();
    }
    return '';
  }

  /// "4:05" / "1:02:03" → [Duration]; null for anything else (a live
  /// stream has no length).
  static Duration? parseClockDuration(String text) {
    final parts = text.trim().split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    var seconds = 0;
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null) return null;
      seconds = seconds * 60 + n;
    }
    return Duration(seconds: seconds);
  }

  static int? _parseViews(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  static final RegExp _relative =
      RegExp(r'(\d+)\s+(second|minute|hour|day|week|month|year)s?\s+ago');

  /// "3 years ago" → roughly that long before [now]; only the year is ever
  /// used (the downloaded file's year tag), so approximate is fine.
  static DateTime? parseRelativeDate(String text, DateTime now) {
    final match = _relative.firstMatch(text.toLowerCase());
    if (match == null) return null;
    final n = int.parse(match.group(1)!);
    switch (match.group(2)) {
      case 'year':
        return DateTime(now.year - n, now.month, now.day);
      case 'month':
        return DateTime(now.year, now.month - n, now.day);
      case 'week':
        return now.subtract(Duration(days: 7 * n));
      case 'day':
        return now.subtract(Duration(days: n));
      case 'hour':
        return now.subtract(Duration(hours: n));
      case 'minute':
        return now.subtract(Duration(minutes: n));
      default:
        return now.subtract(Duration(seconds: n));
    }
  }
}
