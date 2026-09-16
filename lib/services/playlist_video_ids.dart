import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;

import 'log_service.dart';

/// Pulls every video id out of a YouTube playlist directly, bypassing
/// `youtube_explode_dart`'s own `PlaylistClient.getVideos` — used as a
/// fallback when that comes back empty for a playlist that otherwise
/// resolves fine (a title, non-error), reported against a real 3-track
/// public playlist. Two independent gaps in that method can each produce
/// exactly that symptom, so this works around both:
///
/// 1. `PlaylistClient.getVideos` silently *skips* a playlist entry whose
///    uploader channel id it can't parse off the page (three JSON paths
///    tried; a newer @handle-style byline layout can miss all three).
/// 2. Some playlists don't embed their video list in the initial page's
///    `ytInitialData` at all — `youtube_explode_dart`'s own doc comment
///    notes this for "Mixes and YT Music playlists" specifically, though
///    it isn't necessarily limited to those — and need a separate `browse`
///    API call instead. `PlaylistClient.get`/`getVideos` already attempt
///    this internally, but the outcome isn't observable from outside, so
///    it's repeated here.
///
/// Every step is logged (source `MP3`, see [LogService]) since both gaps
/// are easy to reproduce from a bug report but hard to diagnose blind —
/// this is exactly what's expected to be checked after a report that the
/// first fallback (page parsing alone) still didn't find any tracks.
///
/// Single page only (no `continuation` follow-up), so a playlist beyond
/// YouTube's first-page batch (a few hundred entries) is only partially
/// covered — acceptable for the personal-sized playlists this tool targets.
Future<List<String>> fetchPlaylistVideoIdsFromPage(
  String playlistIdOrUrl,
) async {
  final id =
      yt_explode.PlaylistId.parsePlaylistId(playlistIdOrUrl) ?? playlistIdOrUrl;
  LogService.add('MP3', 'Playlist fallback: parsed id "$id" from "$playlistIdOrUrl"');
  final http = yt_explode.YoutubeHttpClient();
  try {
    List<String> ids;
    try {
      final html = await http.getString(
        'https://www.youtube.com/playlist?list=$id&hl=en&persist_hl=1',
      );
      LogService.add('MP3', 'Playlist fallback: fetched page, ${html.length} bytes');
      ids = extractPlaylistVideoIdsFromHtml(html);
      LogService.add(
          'MP3', 'Playlist fallback: found ${ids.length} id(s) in the initial page');
    } catch (e) {
      LogService.add('MP3', 'Playlist fallback: fetching the page failed: $e');
      ids = const [];
    }
    if (ids.isNotEmpty) return ids;

    // Some playlists (YouTube Music imports, "Mixes", and apparently at
    // least some plain user playlists) don't embed their video list in the
    // initial page at all — the same gap youtube_explode_dart's own
    // PlaylistPage.get() already works around internally for its title
    // fetch, just not in a way this can reuse. Repeat it: `VL<playlistId>`
    // is the standard "browse id" for a playlist's video list on YouTube's
    // internal API (the same convention yt-dlp and other scrapers use).
    LogService.add('MP3', 'Playlist fallback: trying the browse API (browseId VL$id)');
    try {
      final data = await http.sendPost('browse', {'browseId': 'VL$id'});
      ids = extractPlaylistVideoIdsFromData(data);
      LogService.add('MP3', 'Playlist fallback: browse API found ${ids.length} id(s)');
    } catch (e) {
      LogService.add('MP3', 'Playlist fallback: browse API failed: $e');
      ids = const [];
    }
    return ids;
  } finally {
    http.close();
  }
}

/// The pure parsing half of [fetchPlaylistVideoIdsFromPage] for an HTML
/// page, split out so it can be tested against a fixed HTML string instead
/// of a live page.
List<String> extractPlaylistVideoIdsFromHtml(String html) {
  final data = _extractInitialData(html);
  if (data == null) {
    LogService.add('MP3', 'Playlist fallback: no ytInitialData found in the page');
    return const [];
  }
  return extractPlaylistVideoIdsFromData(data);
}

/// The pure parsing half of [fetchPlaylistVideoIdsFromPage] for an already
/// -decoded JSON blob — shared by the HTML-embedded `ytInitialData` path
/// and the raw `browse` API response, since both use the same underlying
/// `contents.twoColumnBrowseResultsRenderer…` shape.
List<String> extractPlaylistVideoIdsFromData(Map<String, dynamic> data) {
  final items = _playlistItems(data);
  LogService.add('MP3', 'Playlist fallback: walked ${items.length} playlist item(s)');
  final ids = <String>[];
  final seen = <String>{};
  for (final item in items) {
    final videoId = _rendererOf(item)?['videoId'];
    if (videoId is String && seen.add(videoId)) ids.add(videoId);
  }
  return ids;
}

const List<String> _initialDataMarkers = [
  'var ytInitialData = ',
  'window["ytInitialData"] =',
];

/// Finds `ytInitialData` the same way `youtube_explode_dart` does: scan
/// every `<script>` tag's text for one of the known assignment prefixes,
/// then decode the JSON object that follows.
Map<String, dynamic>? _extractInitialData(String html) {
  final document = html_parser.parse(html);
  for (final script in document.querySelectorAll('script')) {
    final text = script.text;
    for (final marker in _initialDataMarkers) {
      final markerIndex = text.indexOf(marker);
      if (markerIndex == -1) continue;
      final decoded = _decodeJsonObject(text, markerIndex + marker.length);
      if (decoded != null) return decoded;
    }
  }
  return null;
}

/// Decodes the JSON object starting at the first `{` at or after [from] in
/// [text]. Starts from the last `}` in the remainder and backs off on a
/// parse failure, in case that naive guess grabbed something past the
/// object's real end (defensive; not observed in practice, but cheap to
/// guard since a wrong guess here silently returns no tracks).
Map<String, dynamic>? _decodeJsonObject(String text, int from) {
  final rest = text.substring(from);
  final start = rest.indexOf('{');
  if (start == -1) return null;
  var end = rest.lastIndexOf('}');
  while (end > start) {
    try {
      final decoded = jsonDecode(rest.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      end = rest.lastIndexOf('}', end - 1);
    }
  }
  return null;
}

Map<String, dynamic>? _rendererOf(Map<String, dynamic> item) {
  final direct = item['playlistVideoRenderer'];
  if (direct is Map<String, dynamic>) return direct;
  final nested =
      _asMap(_asMap(item['richItemRenderer'])?['content'])?['playlistVideoRenderer'];
  return nested is Map<String, dynamic> ? nested : null;
}

Map<String, dynamic>? _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// Walks `contents.twoColumnBrowseResultsRenderer.tabs[].tabRenderer.
/// content.sectionListRenderer.contents[].itemSectionRenderer.contents[].
/// playlistVideoListRenderer.contents` — the exact path
/// `youtube_explode_dart`'s `PlaylistPage._videoItems` getter uses for an
/// initial (non-continuation) page load, and also the shape of an initial
/// (non-continuation) `browse` API JSON response for a playlist.
List<Map<String, dynamic>> _playlistItems(Map<String, dynamic> data) {
  final tabs =
      _listAt(data, const ['contents', 'twoColumnBrowseResultsRenderer', 'tabs']);
  if (tabs == null) {
    LogService.add('MP3', 'Playlist fallback: no tabs found at the expected path');
    return const [];
  }
  for (final tab in tabs) {
    final tabMap = _asMap(tab);
    if (tabMap == null) continue;
    final sections = _listAt(
      tabMap,
      const ['tabRenderer', 'content', 'sectionListRenderer', 'contents'],
    );
    if (sections == null) continue;
    for (final section in sections) {
      final sectionMap = _asMap(section);
      if (sectionMap == null) continue;
      final itemContents =
          _listAt(sectionMap, const ['itemSectionRenderer', 'contents']);
      if (itemContents == null) continue;
      for (final item in itemContents) {
        final itemMap = _asMap(item);
        if (itemMap == null) continue;
        final contents =
            _listAt(itemMap, const ['playlistVideoListRenderer', 'contents']);
        if (contents != null) {
          return contents.whereType<Map<String, dynamic>>().toList();
        }
      }
    }
  }
  LogService.add(
      'MP3', 'Playlist fallback: tabs found but no playlistVideoListRenderer inside');
  return const [];
}

List<dynamic>? _listAt(Map<String, dynamic> data, List<String> path) {
  dynamic current = data;
  for (final key in path) {
    if (current is! Map) return null;
    current = current[key];
  }
  return current is List ? current : null;
}
