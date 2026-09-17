import 'dart:convert';

import 'package:besttodo/services/music_share_link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('detectMusicShareLink', () {
    test('recognizes a Spotify track link', () {
      final link = detectMusicShareLink(
        'https://open.spotify.com/track/1a2b3c4d5e6f?si=abc123',
      );
      expect(link, isNotNull);
      expect(link!.source, MusicLinkSource.spotify);
      expect(link.textHint, '');
    });

    test('recognizes a Shazam link and keeps its caption as a hint', () {
      final link = detectMusicShareLink(
        'I used Shazam to discover Yellow by Coldplay.\n'
        'https://www.shazam.com/track/52323911/yellow',
      );
      expect(link, isNotNull);
      expect(link!.source, MusicLinkSource.shazam);
      expect(link.textHint, contains('Yellow by Coldplay'));
    });

    test('recognizes a plain YouTube video link', () {
      final link = detectMusicShareLink('https://youtu.be/dQw4w9WgXcQ');
      expect(link, isNotNull);
      expect(link!.source, MusicLinkSource.youtube);
    });

    test('recognizes a YouTube playlist link', () {
      final link = detectMusicShareLink(
        'https://www.youtube.com/playlist?list=PLabc123',
      );
      expect(link, isNotNull);
      expect(link!.source, MusicLinkSource.youtube);
    });

    test('returns null for a link with no recognized music source', () {
      expect(detectMusicShareLink('https://example.com/article'), isNull);
    });

    test('returns null for plain text with no link at all', () {
      expect(detectMusicShareLink('buy milk'), isNull);
    });
  });

  group('MusicLinkResolverService.resolveSearchQuery', () {
    test('a YouTube link is returned unchanged', () async {
      final resolver = MusicLinkResolverService();
      final query = await resolver.resolveSearchQuery(
        const MusicShareLink(
          url: 'https://youtu.be/dQw4w9WgXcQ',
          source: MusicLinkSource.youtube,
        ),
      );
      expect(query, 'https://youtu.be/dQw4w9WgXcQ');
    });

    test('prefers the share caption over a network fetch when present',
        () async {
      var fetched = false;
      final resolver = MusicLinkResolverService(
        client: MockClient((request) async {
          fetched = true;
          return http.Response('{}', 200);
        }),
      );
      final query = await resolver.resolveSearchQuery(
        const MusicShareLink(
          url: 'https://www.shazam.com/track/1/yellow',
          source: MusicLinkSource.shazam,
          textHint: 'I used Shazam to discover Yellow by Coldplay.',
        ),
      );
      expect(query, 'Yellow by Coldplay');
      expect(fetched, false);
    });

    test('a Spotify link with no caption is resolved via its oEmbed title',
        () async {
      Uri? requested;
      final resolver = MusicLinkResolverService(
        client: MockClient((request) async {
          requested = request.url;
          return http.Response(
            jsonEncode({'title': 'Yellow', 'author_name': 'Coldplay'}),
            200,
          );
        }),
      );
      final query = await resolver.resolveSearchQuery(
        const MusicShareLink(
          url: 'https://open.spotify.com/track/abc123',
          source: MusicLinkSource.spotify,
        ),
      );
      expect(query, 'Yellow Coldplay');
      expect(requested.toString(), contains('open.spotify.com/oembed'));
      expect(
        requested.toString(),
        contains(Uri.encodeComponent('https://open.spotify.com/track/abc123')),
      );
    });

    test('a Shazam link with no caption is resolved from the page title',
        () async {
      final resolver = MusicLinkResolverService(
        client: MockClient((request) async {
          return http.Response(
            '<html><head><title>Yellow - Coldplay | Shazam</title>'
            '</head></html>',
            200,
          );
        }),
      );
      final query = await resolver.resolveSearchQuery(
        const MusicShareLink(
          url: 'https://www.shazam.com/track/1/yellow',
          source: MusicLinkSource.shazam,
        ),
      );
      expect(query, 'Yellow - Coldplay');
    });

    test(
        'throws when the fetch fails and there is no caption to fall back on',
        () async {
      final resolver = MusicLinkResolverService(
        client: MockClient((request) async => http.Response('', 500)),
      );
      expect(
        () => resolver.resolveSearchQuery(
          const MusicShareLink(
            url: 'https://open.spotify.com/track/abc123',
            source: MusicLinkSource.spotify,
          ),
        ),
        throwsA(isA<MusicLinkResolveException>()),
      );
    });
  });
}
