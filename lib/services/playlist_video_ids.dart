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
/// and the raw `browse` API response.
List<String> extractPlaylistVideoIdsFromData(Map<String, dynamic> data) {
  final renderers = _findPlaylistVideoRenderers(data);
  LogService.add(
      'MP3', 'Playlist fallback: found ${renderers.length} playlistVideoRenderer(s)');
  final ids = <String>[];
  final seen = <String>{};
  for (final renderer in renderers) {
    final videoId = renderer['videoId'];
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

Map<String, dynamic>? _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// Finds every `playlistVideoRenderer` anywhere in [data], in document
/// order (a `jsonDecode`d object preserves source key/array order, so a
/// depth-first walk visits them in playlist order).
///
/// Deliberately schema-agnostic rather than a hardcoded path: an earlier
/// version walked `contents.twoColumnBrowseResultsRenderer.tabs[]…
/// playlistVideoListRenderer.contents` — the exact path
/// `youtube_explode_dart`'s own `PlaylistPage._videoItems` getter uses —
/// and it found *nothing* even though `playlists.get()` confirmed the
/// playlist genuinely has videos (`videoCount=3`) and the page fetched
/// fine. Since the official library's own hardcoded path failed
/// identically (that's exactly why `getVideos()` came back empty in the
/// first place), the real cause isn't a filter or a missing byline — it's
/// that YouTube's current response nests the video list somewhere this
/// hardcoded path no longer matches. `playlistVideoRenderer` (direct, or
/// wrapped in `richItemRenderer.content`) is otherwise a stable, specific
/// type name — it only ever represents a video in a playlist's own
/// listing — so searching the whole tree for it is robust to exactly the
/// kind of path drift that broke both other approaches, and doesn't need
/// to know or guess the surrounding container structure at all.
List<Map<String, dynamic>> _findPlaylistVideoRenderers(Map<String, dynamic> data) {
  final found = <Map<String, dynamic>>[];

  void visit(Object? node) {
    if (node is Map<String, dynamic>) {
      final direct = node['playlistVideoRenderer'];
      if (direct is Map<String, dynamic>) {
        found.add(direct);
        return;
      }
      final wrapped =
          _asMap(_asMap(node['richItemRenderer'])?['content'])?['playlistVideoRenderer'];
      if (wrapped is Map<String, dynamic>) {
        found.add(wrapped);
        return;
      }
      for (final value in node.values) {
        visit(value);
      }
    } else if (node is List) {
      for (final value in node) {
        visit(value);
      }
    }
  }

  visit(data);
  if (found.isEmpty) {
    // If this is empty too, the next fix needs to target a different
    // renderer/view-model type name rather than guess again — this census
    // says exactly which ones are actually present in this response.
    final typeNames = _collectRendererTypeNames(data).toList()..sort();
    LogService.add(
      'MP3',
      'Playlist fallback: no playlistVideoRenderer found; '
      'renderer/view-model keys present: $typeNames',
    );
  }
  return found;
}

/// Every distinct key ending in `Renderer` or `ViewModel` found anywhere in
/// [node] — a census of the response's actual content types, used only for
/// the diagnostic above.
Set<String> _collectRendererTypeNames(Object? node, [Set<String>? into]) {
  final result = into ?? <String>{};
  if (node is Map<String, dynamic>) {
    for (final key in node.keys) {
      if (key.endsWith('Renderer') || key.endsWith('ViewModel')) {
        result.add(key);
      }
    }
    for (final value in node.values) {
      _collectRendererTypeNames(value, result);
    }
  } else if (node is List) {
    for (final value in node) {
      _collectRendererTypeNames(value, result);
    }
  }
  return result;
}
