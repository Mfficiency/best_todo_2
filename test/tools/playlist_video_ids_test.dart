import 'dart:convert';

import 'package:besttodo/services/playlist_video_ids.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a synthetic playlist page whose `ytInitialData` matches the real
/// structure `youtube_explode_dart`'s `PlaylistPage` parses, with entries
/// covering the case that motivated this file: `youtube_explode_dart`'s own
/// `PlaylistClient.getVideos` silently skips a playlist entry whose
/// uploader channel id it can't parse off the page — reported against a
/// real 3-track public playlist that otherwise resolved fine (title came
/// back, tracks didn't). `extractPlaylistVideoIdsFromHtml` only ever needs
/// a video id, so it must find every entry regardless of that.
Map<String, dynamic> _buildSyntheticPlaylistData() {
  Map<String, dynamic> videoRenderer(String id, {bool withByline = true}) => {
        'videoId': id,
        'title': {
          'runs': [
            {'text': 'Track $id'}
          ],
        },
        if (withByline)
          'shortBylineText': {
            'runs': [
              {
                'text': 'Some Channel',
                'navigationEndpoint': {
                  'browseEndpoint': {'browseId': 'UCabc123'},
                },
              },
            ],
          },
      };

  return {
    'contents': {
      'twoColumnBrowseResultsRenderer': {
        'tabs': [
          {
            'tabRenderer': {
              'content': {
                'sectionListRenderer': {
                  'contents': [
                    {
                      'itemSectionRenderer': {
                        'contents': [
                          {
                            'playlistVideoListRenderer': {
                              'contents': [
                                {
                                  'playlistVideoRenderer':
                                      videoRenderer('aaaaaaaaaaa'),
                                },
                                // The bug case: no ownerText/shortBylineText
                                // at all, so channelId can't be parsed.
                                {
                                  'playlistVideoRenderer': videoRenderer(
                                    'bbbbbbbbbbb',
                                    withByline: false,
                                  ),
                                },
                                // An alternate layout YouTube also uses.
                                {
                                  'richItemRenderer': {
                                    'content': {
                                      'playlistVideoRenderer': videoRenderer(
                                        'ccccccccccc',
                                        withByline: false,
                                      ),
                                    },
                                  },
                                },
                                // A duplicate of the first id — deduped.
                                {
                                  'playlistVideoRenderer':
                                      videoRenderer('aaaaaaaaaaa'),
                                },
                                // A continuation marker, not a video.
                                {
                                  'continuationItemRenderer': {
                                    'continuationEndpoint': {
                                      'continuationCommand': {'token': 'xyz'},
                                    },
                                  },
                                },
                              ],
                            },
                          },
                        ],
                      },
                    },
                  ],
                },
              },
            },
          },
        ],
      },
    },
  };
}

String _buildSyntheticPlaylistHtml({String marker = 'var ytInitialData = '}) {
  final json = jsonEncode(_buildSyntheticPlaylistData());
  return '<html><head></head><body>'
      '<script>var unrelated = {"foo": "bar"};</script>'
      '<script>$marker $json;</script>'
      '</body></html>';
}

void main() {
  group('extractPlaylistVideoIdsFromHtml', () {
    test('finds every video id, including one with no parseable byline',
        () {
      final ids = extractPlaylistVideoIdsFromHtml(_buildSyntheticPlaylistHtml());
      expect(ids, ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);
    });

    test('dedupes a repeated id and skips a continuation marker', () {
      final ids = extractPlaylistVideoIdsFromHtml(_buildSyntheticPlaylistHtml());
      expect(ids.toSet(), hasLength(3));
    });

    test('also finds ids wrapped in richItemRenderer', () {
      final ids = extractPlaylistVideoIdsFromHtml(_buildSyntheticPlaylistHtml());
      expect(ids, contains('ccccccccccc'));
    });

    test('parses the window["ytInitialData"] = marker variant too', () {
      final html = _buildSyntheticPlaylistHtml(
        marker: 'window["ytInitialData"] =',
      );
      expect(extractPlaylistVideoIdsFromHtml(html), hasLength(3));
    });

    test('a page with no ytInitialData returns no ids rather than throwing',
        () {
      expect(
        extractPlaylistVideoIdsFromHtml('<html><body>nothing here</body></html>'),
        isEmpty,
      );
    });

    test('malformed JSON after the marker returns no ids rather than throwing',
        () {
      const html = '<html><body><script>var ytInitialData = '
          '{"contents": {not valid json here</script></body></html>';
      expect(extractPlaylistVideoIdsFromHtml(html), isEmpty);
    });
  });

  group('extractPlaylistVideoIdsFromData', () {
    test(
        'walks a raw JSON blob the same way — the shape a browse API '
        'response for a playlist uses, no HTML wrapper involved', () {
      final ids = extractPlaylistVideoIdsFromData(_buildSyntheticPlaylistData());
      expect(ids, ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'ccccccccccc']);
    });

    test('a blob with no matching structure returns no ids', () {
      expect(extractPlaylistVideoIdsFromData({'unrelated': 'stuff'}), isEmpty);
    });
  });
}
