import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'mp3_downloader_service.dart'
    show looksLikeYoutubeUrl, looksLikeYoutubePlaylistUrl;

/// Where a detected [MusicShareLink] came from. Only changes how the link
/// is resolved into a search query — YouTube resolves straight through the
/// existing MP3 Downloader URL handling, Spotify/Shazam need their page's
/// title looked up first.
enum MusicLinkSource { spotify, shazam, youtube }

/// A song/video link recognized inside a shared payload's text (see
/// `ShareIntentService`/`main.dart`), plus whatever other text came with it
/// — Shazam's share bundles "I used Shazam to discover Song - Artist" next
/// to the link, which is a better search query than anything a page fetch
/// would return, and is used as such by [MusicLinkResolverService].
class MusicShareLink {
  const MusicShareLink({
    required this.url,
    required this.source,
    this.textHint = '',
  });

  final String url;
  final MusicLinkSource source;
  final String textHint;
}

final RegExp _urlPattern = RegExp(r'https?://\S+');

final RegExp _spotifyTrackPattern = RegExp(
  r'open\.spotify\.com/(?:intl-[a-z]{2}/)?track/[A-Za-z0-9]+',
  caseSensitive: false,
);

final RegExp _shazamTrackPattern = RegExp(
  r'shazam\.com/(?:[a-z]{2}-[a-z]{2}/)?(?:track|song)/\S+',
  caseSensitive: false,
);

MusicLinkSource? _sourceFor(String url) {
  if (_spotifyTrackPattern.hasMatch(url)) return MusicLinkSource.spotify;
  if (_shazamTrackPattern.hasMatch(url)) return MusicLinkSource.shazam;
  if (looksLikeYoutubeUrl(url) || looksLikeYoutubePlaylistUrl(url)) {
    return MusicLinkSource.youtube;
  }
  return null;
}

/// Scans [text] (a shared payload's text or subject) for a Spotify, Shazam
/// or YouTube link, returning it plus whatever other text came with it. Null
/// when nothing recognized is found, so the caller falls back to the
/// ordinary quick-add task flow — this is what routes a share straight into
/// the MP3 Downloader instead of the task editor (see `main.dart`).
MusicShareLink? detectMusicShareLink(String text) {
  for (final match in _urlPattern.allMatches(text)) {
    final url = match.group(0)!;
    final source = _sourceFor(url);
    if (source == null) continue;
    final hint = (text.substring(0, match.start) + text.substring(match.end))
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return MusicShareLink(url: url, source: source, textHint: hint);
  }
  return null;
}

/// Thrown by [MusicLinkResolverService.resolveSearchQuery] when a
/// Spotify/Shazam link's title couldn't be read and no usable text came
/// with the share either.
class MusicLinkResolveException implements Exception {
  MusicLinkResolveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Boilerplate phrases apps prepend to a shared link's caption — stripped so
/// what's left is just the song title/artist.
final RegExp _shareCaptionPrefix = RegExp(
  r'^(i used shazam to discover|check out|listen to)\s+',
  caseSensitive: false,
);

String _cleanedHint(String text) {
  var hint = text.trim();
  hint = hint.replaceFirst(_shareCaptionPrefix, '');
  hint = hint.replaceAll(RegExp(r'[.!]+$'), '');
  return hint.trim();
}

/// Turns a detected [MusicShareLink] into a query the MP3 Downloader's
/// existing search/resolve can use — a YouTube link is returned unchanged
/// (the downloader already resolves it directly), a Spotify link's title is
/// read from its public oEmbed endpoint (no API key needed), and a Shazam
/// link's title is read off its page's `<title>`/`og:title`. Either falls
/// back to the share's own caption text first, since that's already exactly
/// what a user would type into the search box, and is free.
class MusicLinkResolverService {
  static MusicLinkResolverService instance = MusicLinkResolverService();

  MusicLinkResolverService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> resolveSearchQuery(MusicShareLink link) async {
    if (link.source == MusicLinkSource.youtube) return link.url;
    final hint = _cleanedHint(link.textHint);
    if (hint.isNotEmpty) return hint;
    return link.source == MusicLinkSource.spotify
        ? _resolveSpotify(link.url)
        : _resolveShazam(link.url);
  }

  Future<String> _resolveSpotify(String url) async {
    try {
      final endpoint = Uri.parse(
          'https://open.spotify.com/oembed?url=${Uri.encodeComponent(url)}');
      final response =
          await _client.get(endpoint).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final title = (data['title'] as String?)?.trim() ?? '';
        final artist = (data['author_name'] as String?)?.trim() ?? '';
        final query = [title, artist].where((s) => s.isNotEmpty).join(' ');
        if (query.isNotEmpty) return query;
      }
    } catch (_) {}
    throw MusicLinkResolveException(
        "Couldn't read this Spotify link's title. Paste the song name instead.");
  }

  Future<String> _resolveShazam(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        var title = document
                .querySelector('meta[property="og:title"]')
                ?.attributes['content']
                ?.trim() ??
            '';
        if (title.isEmpty) title = document.querySelector('title')?.text.trim() ?? '';
        title = title
            .replaceAll(RegExp(r'\s*[|–-]\s*Shazam\s*$', caseSensitive: false), '')
            .trim();
        if (title.isNotEmpty) return title;
      }
    } catch (_) {}
    throw MusicLinkResolveException(
        "Couldn't read this Shazam link's title. Paste the song name instead.");
  }
}
