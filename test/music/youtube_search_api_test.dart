import 'dart:convert';

import 'package:besttodo/services/youtube_search_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _video(String id, String title,
        {String channel = 'Some Channel',
        String? length = '3:45',
        String views = '1,234,567 views',
        String published = '2 years ago'}) =>
    {
      'videoRenderer': {
        'videoId': id,
        'title': {
          'runs': [
            {'text': title}
          ]
        },
        'ownerText': {
          'runs': [
            {'text': channel}
          ]
        },
        if (length != null) 'lengthText': {'simpleText': length},
        'viewCountText': {'simpleText': views},
        'publishedTimeText': {'simpleText': published},
      }
    };

/// Trimmed-down shape of a real `youtubei/v1/search` response.
Map<String, dynamic> _response(List<Map<String, dynamic>> items) => {
      'contents': {
        'twoColumnSearchResultsRenderer': {
          'primaryContents': {
            'sectionListRenderer': {
              'contents': [
                {
                  'itemSectionRenderer': {
                    'contents': [
                      {'adSlotRenderer': {}},
                      ...items,
                    ]
                  }
                }
              ]
            }
          }
        }
      }
    };

void main() {
  final now = DateTime(2026, 10, 3);

  test('parses videoRenderers in page order with all fields', () {
    final results = YoutubeSearchApi.parseSearchResponse(
      _response([
        _video('aaaaaaaaaaa', 'Chocolate - The 1975',
            channel: 'The 1975', length: '3:45'),
        _video('bbbbbbbbbbb', 'Long mix', length: '1:02:03'),
      ]),
      limit: 10,
      now: now,
    );
    expect(results.map((r) => r.videoId), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
    expect(results.first.title, 'Chocolate - The 1975');
    expect(results.first.channel, 'The 1975');
    expect(results.first.duration, const Duration(minutes: 3, seconds: 45));
    expect(results.first.viewCount, 1234567);
    expect(results.first.uploadDate?.year, 2024);
    expect(results[1].duration,
        const Duration(hours: 1, minutes: 2, seconds: 3));
  });

  test('honours limit, skips duplicates and live streams have no duration',
      () {
    final results = YoutubeSearchApi.parseSearchResponse(
      _response([
        _video('aaaaaaaaaaa', 'One', length: null),
        _video('aaaaaaaaaaa', 'One again'),
        _video('bbbbbbbbbbb', 'Two'),
        _video('ccccccccccc', 'Three'),
      ]),
      limit: 2,
      now: now,
    );
    expect(results.map((r) => r.videoId), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
    expect(results.first.duration, isNull);
  });

  test('a response with no videos parses to an empty list', () {
    expect(YoutubeSearchApi.parseSearchResponse({'contents': {}}), isEmpty);
    expect(YoutubeSearchApi.parseSearchResponse(null), isEmpty);
  });

  test('search posts the query to the JSON API and parses the reply',
      () async {
    late Map<String, dynamic> sent;
    final client = MockClient((request) async {
      expect(request.url.path, '/youtubei/v1/search');
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode(_response([_video('aaaaaaaaaaa', 'Chocolate')])), 200);
    });
    final results =
        await YoutubeSearchApi.search('chocolate', limit: 5, client: client);
    expect(sent['query'], 'chocolate');
    expect(results.single.videoId, 'aaaaaaaaaaa');
  });

  test('a non-200 reply throws', () async {
    final client = MockClient((_) async => http.Response('nope', 403));
    expect(YoutubeSearchApi.search('x', client: client), throwsException);
  });
}
