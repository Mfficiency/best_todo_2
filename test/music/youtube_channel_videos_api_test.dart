import 'package:besttodo/services/youtube_channel_videos_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Videos-tab card in YouTube's newer `lockupViewModel` shape — the one
/// youtube_explode reads no duration or views from.
Map<String, dynamic> _lockup(String id,
        {String? clock = '12:34',
        String views = '1.2K views',
        String age = '3 days ago'}) =>
    {
      'richItemRenderer': {
        'content': {
          'lockupViewModel': {
            'contentId': id,
            'contentType': 'LOCKUP_CONTENT_TYPE_VIDEO',
            'contentImage': {
              'thumbnailViewModel': {
                'image': {
                  'sources': [
                    {'url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg'}
                  ]
                },
                'overlays': [
                  if (clock != null)
                    {
                      'thumbnailOverlayBadgeViewModel': {
                        'thumbnailBadges': [
                          {
                            'thumbnailBadgeViewModel': {'text': clock}
                          }
                        ]
                      }
                    }
                ],
              }
            },
            'metadata': {
              'lockupMetadataViewModel': {
                'title': {'content': 'Video $id'},
                'metadata': {
                  'contentMetadataViewModel': {
                    'metadataRows': [
                      {
                        'metadataParts': [
                          {
                            'text': {'content': views}
                          },
                          {
                            'text': {'content': age}
                          },
                        ]
                      }
                    ]
                  }
                },
              }
            },
          }
        }
      }
    };

void main() {
  final now = DateTime(2026, 10, 4, 12);

  test('reads duration, views and age from lockupViewModel cards', () {
    final json = {
      'contents': {
        'twoColumnBrowseResultsRenderer': {
          'tabs': [
            {
              'tabRenderer': {
                'content': {
                  'richGridRenderer': {
                    'contents': [
                      _lockup('AAAAAAAAAAA'),
                      _lockup('BBBBBBBBBBB',
                          clock: '1:02:03',
                          views: '1,234,567 views',
                          age: '2 weeks ago'),
                      _lockup('AAAAAAAAAAA'), // duplicate
                      _lockup('LLLLLLLLLLL',
                          clock: null, views: '532 watching', age: ''),
                    ]
                  }
                }
              }
            }
          ]
        }
      }
    };
    final videos = YoutubeChannelVideosApi.parseVideosTab(json, now: now);
    expect(videos.map((v) => v.videoId),
        ['AAAAAAAAAAA', 'BBBBBBBBBBB', 'LLLLLLLLLLL']);
    expect(videos[0].duration, const Duration(minutes: 12, seconds: 34));
    expect(videos[0].views, 1200);
    expect(videos[0].published, now.subtract(const Duration(days: 3)));
    expect(videos[1].duration,
        const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(videos[1].views, 1234567);
    expect(videos[2].duration, isNull, reason: 'live: no clock badge');
    expect(videos[2].views, isNull, reason: '"watching" is not views');
  });

  test('still reads classic videoRenderer cards', () {
    final json = {
      'items': [
        {
          'gridVideoRenderer': {
            'videoId': 'CCCCCCCCCCC',
            'title': {
              'runs': [
                {'text': 'Old style'}
              ]
            },
            'thumbnailOverlays': [
              {
                'thumbnailOverlayTimeStatusRenderer': {
                  'text': {'simpleText': '4:05'}
                }
              }
            ],
            'viewCountText': {'simpleText': '98 views'},
            'publishedTimeText': {'simpleText': '5 hours ago'},
          }
        }
      ]
    };
    final v = YoutubeChannelVideosApi.parseVideosTab(json, now: now).single;
    expect(v.duration, const Duration(minutes: 4, seconds: 5));
    expect(v.views, 98);
    expect(v.published, now.subtract(const Duration(hours: 5)));
  });

  test('reads titles from both card shapes', () {
    final classic = YoutubeChannelVideosApi.parseVideosTab({
      'items': [
        {
          'videoRenderer': {
            'videoId': 'CCCCCCCCCCC',
            'title': {
              'runs': [
                {'text': 'Part one, '},
                {'text': 'part two'}
              ]
            },
            'publishedTimeText': {'simpleText': '1 day ago'},
          }
        }
      ]
    }, now: now).single;
    expect(classic.title, 'Part one, part two');

    final lockup = YoutubeChannelVideosApi.parseVideosTab(
        {'items': [_lockup('AAAAAAAAAAA')]},
        now: now).single;
    expect(lockup.title, 'Video AAAAAAAAAAA');
  });

  test('a title ending in "ago" is not taken for the upload age', () {
    final v = YoutubeChannelVideosApi.parseVideosTab({
      'items': [
        {
          'videoRenderer': {
            'videoId': 'DDDDDDDDDDD',
            'title': {'simpleText': 'What we did 10 years ago'},
            'publishedTimeText': {'simpleText': '2 days ago'},
          }
        }
      ]
    }, now: now).single;
    expect(v.title, 'What we did 10 years ago');
    expect(v.published, now.subtract(const Duration(days: 2)));
  });

  test('parseViewCount', () {
    expect(YoutubeChannelVideosApi.parseViewCount('1,234 views'), 1234);
    expect(YoutubeChannelVideosApi.parseViewCount('1 view'), 1);
    expect(YoutubeChannelVideosApi.parseViewCount('1.2K views'), 1200);
    expect(YoutubeChannelVideosApi.parseViewCount('15K views'), 15000);
    expect(YoutubeChannelVideosApi.parseViewCount('3.4M views'), 3400000);
    expect(YoutubeChannelVideosApi.parseViewCount('2B views'), 2000000000);
    expect(YoutubeChannelVideosApi.parseViewCount('No views'), 0);
    expect(YoutubeChannelVideosApi.parseViewCount('1.2K watching'), isNull);
    expect(YoutubeChannelVideosApi.parseViewCount('3 days ago'), isNull);
  });
}
