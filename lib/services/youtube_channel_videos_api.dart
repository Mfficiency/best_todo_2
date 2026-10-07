import 'dart:convert';

import 'package:http/http.dart' as http;

import 'youtube_search_api.dart';

/// What a channel's Videos tab says about one video.
class ChannelTabVideo {
  const ChannelTabVideo({
    required this.videoId,
    this.duration,
    this.views,
    this.published,
    this.title,
  });

  final String videoId;

  /// The card's title — lets the feed list a channel from this tab alone
  /// when its RSS feed is down. Null when the card has none readable.
  final String? title;

  /// Null for a live/upcoming stream (no clock badge) or when unreadable.
  final Duration? duration;
  final int? views;

  /// Approximate ("3 days ago").
  final DateTime? published;
}

/// A channel's Videos tab through YouTube's internal JSON API
/// (`youtubei/v1/browse`, what youtube.com itself calls).
///
/// Replaces `youtube_explode_dart`'s `getUploadsFromPage` as the first
/// choice: that one reads YouTube's newer `lockupViewModel` cards from
/// paths that no longer exist, so every video came back with no duration
/// and 0 views (SPEC.md §10.6m). The parser here doesn't rely on fixed
/// paths inside a card: it collects the card's texts and recognises the
/// clock ("12:34"), the views ("1.2K views") and the age ("3 days ago").
class YoutubeChannelVideosApi {
  YoutubeChannelVideosApi._();

  static const String _clientVersion = '2.20250925.01.00';

  /// `params` for the channel's "Videos" tab.
  static const String _videosTab = 'EgZ2aWRlb3PyBgQKAjoA';

  static Future<List<ChannelTabVideo>> fetch(
    String channelId, {
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final response = await c
          .post(
            Uri.parse(
                'https://www.youtube.com/youtubei/v1/browse?prettyPrint=false'),
            headers: const {
              'content-type': 'application/json',
              'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                  'AppleWebKit/537.36 (KHTML, like Gecko) '
                  'Chrome/128.0.0.0 Safari/537.36',
              'x-youtube-client-name': '1',
              'x-youtube-client-version': _clientVersion,
              'origin': 'https://www.youtube.com',
              'cookie': 'SOCS=CAI',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB',
                  'clientVersion': _clientVersion,
                  'hl': 'en',
                  'gl': 'US',
                },
              },
              'browseId': channelId,
              'params': _videosTab,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Videos tab answered HTTP ${response.statusCode}');
      }
      return parseVideosTab(jsonDecode(utf8.decode(response.bodyBytes)));
    } finally {
      if (client == null) c.close();
    }
  }

  /// Every video card in a browse response, in page order (deduped).
  /// Understands both the classic `videoRenderer`/`gridVideoRenderer` and
  /// the newer `lockupViewModel`. [now] anchors "3 days ago" (tests pin it).
  static List<ChannelTabVideo> parseVideosTab(Object? json, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final results = <ChannelTabVideo>[];
    final seen = <String>{};

    void walk(Object? node) {
      if (node is Map) {
        ChannelTabVideo? video;
        for (final key in const ['videoRenderer', 'gridVideoRenderer']) {
          final r = node[key];
          if (r is Map && r['videoId'] is String) {
            video = _parseCard(r['videoId'] as String, r, at,
                title: _runsText(r['title']));
          }
        }
        final lockup = node['lockupViewModel'];
        if (lockup is Map) {
          final type = lockup['contentType'];
          final id = lockup['contentId'];
          if (id is String &&
              id.isNotEmpty &&
              (type == null || type == 'LOCKUP_CONTENT_TYPE_VIDEO')) {
            final meta = lockup['metadata'];
            final lockupMeta =
                meta is Map ? meta['lockupMetadataViewModel'] : null;
            final titleNode =
                lockupMeta is Map ? lockupMeta['title'] : null;
            video = _parseCard(id, lockup, at,
                title: titleNode is Map && titleNode['content'] is String
                    ? titleNode['content'] as String
                    : _runsText(titleNode));
          }
        }
        if (video != null) {
          if (seen.add(video.videoId)) results.add(video);
          return; // a card doesn't contain other cards
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

  static final RegExp _clock = RegExp(r'^\d{1,2}(:\d{2}){1,2}$');

  /// A `{simpleText}` / `{runs: [{text}]}` node as one string.
  static String? _runsText(Object? node) {
    if (node is! Map) return null;
    final simple = node['simpleText'];
    if (simple is String && simple.trim().isNotEmpty) return simple.trim();
    final runs = node['runs'];
    if (runs is List) {
      final text = runs
          .map((r) => r is Map && r['text'] is String ? r['text'] : '')
          .join()
          .trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static ChannelTabVideo _parseCard(String id, Map card, DateTime now,
      {String? title}) {
    Duration? duration;
    int? views;
    DateTime? published;
    final titleText = title?.trim();
    for (final text in _texts(card)) {
      final t = text.trim();
      if (t == titleText) continue; // "… 10 years ago" in a title isn't a date
      if (duration == null && _clock.hasMatch(t)) {
        duration = YoutubeSearchApi.parseClockDuration(t);
      } else if (views == null && parseViewCount(t) != null) {
        views = parseViewCount(t);
      } else if (published == null && t.toLowerCase().endsWith('ago')) {
        published = YoutubeSearchApi.parseRelativeDate(t, now);
      }
    }
    return ChannelTabVideo(
        videoId: id,
        duration: duration,
        views: views,
        published: published,
        title: titleText == null || titleText.isEmpty ? null : titleText);
  }

  /// Every display string in [node]: `simpleText`, `runs` joined, `text`
  /// and `content` strings (lockup view models), badge texts.
  static Iterable<String> _texts(Object? node) sync* {
    if (node is Map) {
      final runs = node['runs'];
      if (runs is List) {
        yield runs
            .map((r) => r is Map && r['text'] is String ? r['text'] : '')
            .join();
      }
      for (final entry in node.entries) {
        final value = entry.value;
        if (value is String &&
            (entry.key == 'simpleText' ||
                entry.key == 'text' ||
                entry.key == 'content')) {
          yield value;
        } else if (value is Map || value is List) {
          yield* _texts(value);
        }
      }
    } else if (node is List) {
      for (final item in node) {
        yield* _texts(item);
      }
    }
  }

  static final RegExp _viewsText = RegExp(
      r'^([\d.,]+)\s*([KMB])?\s+views?$|^no views$',
      caseSensitive: false);

  /// "1,234 views" → 1234, "1.2K views" → 1200, "3M views", "No views" → 0;
  /// null for anything else ("1.2K watching" is a live stream).
  static int? parseViewCount(String text) {
    final m = _viewsText.firstMatch(text.trim());
    if (m == null) return null;
    if (m.group(1) == null) return 0;
    final suffix = m.group(2)?.toUpperCase();
    if (suffix == null) {
      return int.tryParse(m.group(1)!.replaceAll(RegExp(r'[.,]'), ''));
    }
    final n = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    if (n == null) return null;
    final mult = switch (suffix) {
      'K' => 1e3,
      'M' => 1e6,
      _ => 1e9,
    };
    return (n * mult).round();
  }
}
