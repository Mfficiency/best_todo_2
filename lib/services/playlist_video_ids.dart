import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;

/// Pulls every video id out of a YouTube playlist page directly, walking
/// the same `ytInitialData` JSON `youtube_explode_dart`'s own
/// `PlaylistClient.getVideos` parses — used as a fallback when that comes
/// back empty.
///
/// `PlaylistClient.getVideos` silently *skips* a playlist entry whose
/// uploader channel id it can't parse off the page (it tries three JSON
/// paths; none hit when the byline is a newer @handle-style layout none of
/// them cover), so a real, non-empty, fully public playlist can come back
/// with a title and zero tracks — reported against a 3-track playlist that
/// otherwise resolved fine. This walks the identical structural path but
/// only ever needs a video id, so it isn't tripped by that gap.
///
/// Single page only (no `continuation` follow-up), so a playlist beyond
/// YouTube's first-page batch (a few hundred entries) is only partially
/// covered — acceptable for the personal-sized playlists this tool targets,
/// and still strictly better than the zero tracks this replaces.
Future<List<String>> fetchPlaylistVideoIdsFromPage(
  String playlistIdOrUrl,
) async {
  final id =
      yt_explode.PlaylistId.parsePlaylistId(playlistIdOrUrl) ?? playlistIdOrUrl;
  final http = yt_explode.YoutubeHttpClient();
  try {
    final html = await http.getString(
      'https://www.youtube.com/playlist?list=$id&hl=en&persist_hl=1',
    );
    return extractPlaylistVideoIdsFromHtml(html);
  } catch (_) {
    return const [];
  } finally {
    http.close();
  }
}

/// The pure parsing half of [fetchPlaylistVideoIdsFromPage], split out so it
/// can be tested against a fixed HTML string instead of a live page.
List<String> extractPlaylistVideoIdsFromHtml(String html) {
  final data = _extractInitialData(html);
  if (data == null) return const [];
  return _videoIdsFrom(data);
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

List<String> _videoIdsFrom(Map<String, dynamic> data) {
  final ids = <String>[];
  final seen = <String>{};
  for (final item in _playlistItems(data)) {
    final videoId = _rendererOf(item)?['videoId'];
    if (videoId is String && seen.add(videoId)) ids.add(videoId);
  }
  return ids;
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
/// initial (non-continuation) page load.
List<Map<String, dynamic>> _playlistItems(Map<String, dynamic> data) {
  final tabs =
      _listAt(data, const ['contents', 'twoColumnBrowseResultsRenderer', 'tabs']);
  if (tabs == null) return const [];
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
