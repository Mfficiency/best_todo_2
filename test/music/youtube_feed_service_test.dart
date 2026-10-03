import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/track.dart';
import 'package:besttodo/models/youtube_feed.dart';
import 'package:besttodo/services/sponsorblock_service.dart';
import 'package:besttodo/services/youtube_feed_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

const _channelId = 'UCabcdefghijklmnopqrstuv';

const _rss = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
 <link rel="self" href="http://www.youtube.com/feeds/videos.xml?channel_id=$_channelId"/>
 <id>yt:channel:abcdefghijklmnopqrstuv</id>
 <yt:channelId>abcdefghijklmnopqrstuv</yt:channelId>
 <title>Great Channel</title>
 <entry>
  <id>yt:video:AAAAAAAAAAA</id>
  <yt:videoId>AAAAAAAAAAA</yt:videoId>
  <title>A normal video</title>
  <link rel="alternate" href="https://www.youtube.com/watch?v=AAAAAAAAAAA"/>
  <published>2026-09-30T10:00:00+00:00</published>
  <media:group>
   <media:title>A normal video</media:title>
   <media:thumbnail url="https://i1.ytimg.com/vi/AAAAAAAAAAA/hqdefault.jpg" width="480" height="360"/>
   <media:description>Line one
https://example.com/link</media:description>
   <media:community>
    <media:starRating count="10" average="5.00" min="1" max="5"/>
    <media:statistics views="12345"/>
   </media:community>
  </media:group>
 </entry>
 <entry>
  <id>yt:video:BBBBBBBBBBB</id>
  <yt:videoId>BBBBBBBBBBB</yt:videoId>
  <title>A short</title>
  <link rel="alternate" href="https://www.youtube.com/shorts/BBBBBBBBBBB"/>
  <published>2026-09-29T10:00:00+00:00</published>
  <media:group><media:description></media:description></media:group>
 </entry>
 <entry>
  <id>yt:video:CCCCCCCCCCC</id>
  <yt:videoId>CCCCCCCCCCC</yt:videoId>
  <title>A livestream</title>
  <link rel="alternate" href="https://www.youtube.com/watch?v=CCCCCCCCCCC"/>
  <published>2026-09-28T10:00:00+00:00</published>
 </entry>
</feed>''';

FeedVideo _video(String id, String channelId, DateTime published,
        {bool isShort = false}) =>
    FeedVideo(
      videoId: id,
      title: 'Video $id',
      channelId: channelId,
      channelName: 'Channel $channelId',
      published: published,
      isShort: isShort,
    );

void main() {
  final service = YoutubeFeedService.instance;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    service.resetForTest();
  });

  tearDown(() async {
    service.resetForTest();
    SponsorBlockService.instance.clientOverride = null;
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('parseYoutubeRss', () {
    test('reads ids, titles, dates, descriptions, views and Shorts links', () {
      final videos =
          parseYoutubeRss(_rss, channelId: _channelId, channelName: 'Fallback');
      expect(videos.map((v) => v.videoId),
          ['AAAAAAAAAAA', 'BBBBBBBBBBB', 'CCCCCCCCCCC']);
      final first = videos.first;
      expect(first.title, 'A normal video');
      expect(first.channelName, 'Great Channel');
      expect(first.channelId, _channelId);
      expect(first.published, DateTime.utc(2026, 9, 30, 10));
      expect(first.description, 'Line one\nhttps://example.com/link');
      expect(first.viewCount, 12345);
      expect(first.isShort, isFalse);
      expect(videos[1].isShort, isTrue);
      expect(videos[2].description, '');
    });
  });

  group('mergeVideosTab', () {
    final rss =
        parseYoutubeRss(_rss, channelId: _channelId, channelName: 'Fallback');

    test('adds durations and flags non-Shorts missing from the tab as live',
        () {
      final merged = mergeVideosTab(rss, {
        'AAAAAAAAAAA': (duration: const Duration(minutes: 4), views: 99),
      });
      expect(merged[0].duration, const Duration(minutes: 4));
      expect(merged[0].viewCount, 99);
      expect(merged[0].isLivestream, isFalse);
      expect(merged[1].isLivestream, isFalse, reason: 'Shorts are not live');
      expect(merged[2].isLivestream, isTrue);
    });

    test('an unreadable Videos tab flags nothing', () {
      expect(mergeVideosTab(rss, null).any((v) => v.isLivestream), isFalse);
    });
  });

  test('filterFeed hides Shorts and livestreams per the settings', () {
    final all = mergeVideosTab(
      parseYoutubeRss(_rss, channelId: _channelId, channelName: 'x'),
      {'AAAAAAAAAAA': (duration: null, views: 1)},
    );
    expect(filterFeed(all, const YoutubeFeedSettings()).map((v) => v.videoId),
        ['AAAAAAAAAAA']);
    expect(
        filterFeed(
                all,
                const YoutubeFeedSettings(
                    hideShorts: false, hideLivestreams: false))
            .length,
        3);
    expect(
        filterFeed(all, const YoutubeFeedSettings(hideShorts: false))
            .map((v) => v.videoId),
        ['AAAAAAAAAAA', 'BBBBBBBBBBB']);
  });

  group('parseChannelSearchResults', () {
    Map<String, dynamic> renderer(String id, String title,
            {bool runsCount = true}) =>
        {
          'channelRenderer': {
            'channelId': id,
            'title': {'simpleText': title},
            'thumbnail': {
              'thumbnails': [
                {'url': '//yt3.ggpht.com/small', 'width': 88, 'height': 88},
                {'url': '//yt3.ggpht.com/big', 'width': 176, 'height': 176},
              ],
            },
            // The shape that crashed youtube_explode_dart 3.1.0's parser.
            if (runsCount)
              'videoCountText': {
                'runs': [
                  {'text': '1.2M'},
                  {'text': ' subscribers'},
                ],
              },
          },
        };

    test('reads every channel renderer, with https avatars, deduplicated',
        () {
      final response = {
        'contents': {
          'twoColumnSearchResultsRenderer': {
            'primaryContents': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'itemSectionRenderer': {
                      'contents': [
                        renderer('UCaaaaaaaaaaaaaaaaaaaaaa', 'Boy Boy'),
                        renderer('UCbbbbbbbbbbbbbbbbbbbbbb', 'Boyboy Music',
                            runsCount: false),
                        renderer('UCaaaaaaaaaaaaaaaaaaaaaa', 'Boy Boy'),
                        {'shelfRenderer': {'title': 'not a channel'}},
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
      };
      final channels = parseChannelSearchResults(response);
      expect(channels.map((c) => c.name), ['Boy Boy', 'Boyboy Music']);
      expect(channels.first.id, 'UCaaaaaaaaaaaaaaaaaaaaaa');
      expect(channels.first.avatarUrl, 'https://yt3.ggpht.com/big');
    });

    test('titles given as runs work; renderers without an id are skipped',
        () {
      final channels = parseChannelSearchResults([
        {
          'channelRenderer': {
            'channelId': 'UCcccccccccccccccccccccc',
            'title': {
              'runs': [
                {'text': 'Split '},
                {'text': 'Title'},
              ],
            },
          },
        },
        {
          'channelRenderer': {
            'title': {'simpleText': 'No id'},
          },
        },
      ]);
      expect(channels.single.name, 'Split Title');
      expect(channels.single.avatarUrl, isNull);
      expect(parseChannelSearchResults(null), isEmpty);
    });
  });

  test('searchChannels resolves an @handle directly instead of searching',
      () async {
    final asked = <String>[];
    service.resolveChannelOverride = (url) async {
      asked.add(url);
      return const YoutubeChannel(
          id: 'UChandlehandlehandlehand', name: 'Handle Channel');
    };
    final results = await service.searchChannels('@somehandle');
    expect(results.single.name, 'Handle Channel');
    expect(asked, ['https://www.youtube.com/@somehandle']);
  });

  group('Tubular/NewPipe import', () {
    final export = jsonEncode({
      'app_version': '0.27.0',
      'subscriptions': [
        {
          'service_id': 0,
          'url': 'https://www.youtube.com/channel/$_channelId',
          'name': 'Great Channel',
        },
        {
          'service_id': 0,
          'url': 'https://www.youtube.com/@somehandle',
          'name': 'Handle Channel',
        },
        {
          'service_id': 1,
          'url': 'https://soundcloud.com/someone',
          'name': 'SoundCloud artist',
        },
        {
          'service_id': 0,
          'url': 'https://www.youtube.com/c/legacyname',
          'name': 'Unresolvable',
        },
      ],
    });

    test('parseNewPipeSubscriptions keeps only YouTube entries', () {
      final entries = parseNewPipeSubscriptions(export);
      expect(entries.length, 3);
      expect(entries.first.name, 'Great Channel');
      expect(() => parseNewPipeSubscriptions('{"nope": 1}'),
          throwsFormatException);
    });

    test('channelIdFromUrl', () {
      expect(channelIdFromUrl('https://www.youtube.com/channel/$_channelId'),
          _channelId);
      expect(channelIdFromUrl('https://www.youtube.com/@handle'), isNull);
    });

    test('importNewPipe adds, resolves handles, dedups and counts skips',
        () async {
      service.fetchOverride = (_) async => const ChannelFetchResult([]);
      service.resolveChannelOverride = (url) async => url.contains('@')
          ? const YoutubeChannel(
              id: 'UChandlehandlehandlehand', name: 'Handle Channel')
          : null;
      final first = await service.importNewPipe(export);
      expect(first.added, 2);
      expect(first.skipped, 1);
      expect(service.subscriptions.value.map((c) => c.name),
          ['Great Channel', 'Handle Channel']);

      final again = await service.importNewPipe(export);
      expect(again.added, 0);
      expect(again.alreadySubscribed, 2);
    });
  });

  test('refresh merges channels newest first and keeps a failed one cached',
      () async {
    const a = YoutubeChannel(id: 'UCaaaaaaaaaaaaaaaaaaaaaa', name: 'A');
    const b = YoutubeChannel(id: 'UCbbbbbbbbbbbbbbbbbbbbbb', name: 'B');
    service.subscriptions.value = [a, b];
    var failB = false;
    service.fetchOverride = (channel) async {
      if (channel.id == a.id) {
        return ChannelFetchResult([
          _video('a1', a.id, DateTime(2026, 9, 1)),
          _video('a2', a.id, DateTime(2026, 9, 3)),
        ]);
      }
      if (failB) throw Exception('offline');
      return ChannelFetchResult([_video('b1', b.id, DateTime(2026, 9, 2))]);
    };
    await service.refresh();
    expect(service.videos.value.map((v) => v.videoId), ['a2', 'b1', 'a1']);
    expect(service.failedChannels.value, isEmpty);

    failB = true;
    await service.refresh();
    expect(service.videos.value.map((v) => v.videoId), ['a2', 'b1', 'a1']);
    expect(service.failedChannels.value, ['B']);

    await service.unsubscribe(b.id);
    expect(service.videos.value.map((v) => v.videoId), ['a2', 'a1']);
  });

  test('refresh reports progress by channels fetched', () async {
    const a = YoutubeChannel(id: 'UCaaaaaaaaaaaaaaaaaaaaaa', name: 'A');
    const b = YoutubeChannel(id: 'UCbbbbbbbbbbbbbbbbbbbbbb', name: 'B');
    service.subscriptions.value = [a, b];
    service.fetchOverride = (_) async => const ChannelFetchResult([]);
    final seen = <double>[];
    void listener() => seen.add(service.refreshProgress.value);
    service.refreshProgress.addListener(listener);
    await service.refresh();
    service.refreshProgress.removeListener(listener);
    expect(seen.last, 1.0);
    expect(seen, contains(0.5));
  });

  group('listening progress', () {
    test('counts as played within the last 30 s and resumes otherwise',
        () async {
      await service.recordProgress('v1', const Duration(minutes: 5),
          duration: const Duration(minutes: 20));
      expect(service.isPlayed('v1'), isFalse);
      expect(service.resumePosition('v1'),
          const Duration(minutes: 4, seconds: 57));
      expect(service.progressFor('v1')!.fraction, closeTo(0.25, 0.001));

      await service.recordProgress('v1', const Duration(minutes: 19, seconds: 40));
      expect(service.isPlayed('v1'), isTrue);
      expect(service.resumePosition('v1'), isNull);

      await service.setPlayed('v1', false);
      expect(service.progressFor('v1'), isNull);
    });

    test('the first few seconds are not worth resuming', () async {
      await service.recordProgress('v2', const Duration(seconds: 5),
          duration: const Duration(minutes: 3));
      expect(service.resumePosition('v2'), isNull);
    });

    test('queueFrom starts at the tapped video and skips played ones',
        () async {
      final list = [
        for (final id in ['v1', 'v2', 'v3', 'v4'])
          _video(id, _channelId, DateTime(2026)),
      ];
      await service.setPlayed('v1', true);
      await service.setPlayed('v3', true);
      final queue = service.queueFrom(list, 0);
      expect(queue.map((t) => t.id), ['youtube:v1', 'youtube:v2', 'youtube:v4']);
      expect(queue.first.source, TrackSource.youtube);
      expect(queue.first.artUrl, 'https://i.ytimg.com/vi/v1/hqdefault.jpg');
    });
  });

  test('state survives a reload from youtube_feed.json', () async {
    service.fetchOverride = (_) async => ChannelFetchResult(
        [_video('x1', _channelId, DateTime(2026, 9, 1))]);
    await service.subscribe(
        const YoutubeChannel(id: _channelId, name: 'Great Channel'));
    await service.refresh();
    await service.updateSettings(const YoutubeFeedSettings(
      hideShorts: false,
      sponsorBlockCategories: {SponsorBlockCategory.intro},
    ));
    await service.recordProgress('x1', const Duration(minutes: 1),
        duration: const Duration(minutes: 10));

    service.resetForTest();
    await service.load();
    expect(service.subscriptions.value.single.name, 'Great Channel');
    expect(service.videos.value.single.videoId, 'x1');
    expect(service.settings.value.hideShorts, isFalse);
    expect(service.settings.value.sponsorBlockCategories,
        {SponsorBlockCategory.intro});
    expect(service.progressFor('x1')!.position, const Duration(minutes: 1));
  });

  test('default playback speed round-trips and is clamped to 0.5–3x', () {
    final json = const YoutubeFeedSettings(playbackSpeed: 1.75).toJson();
    expect(YoutubeFeedSettings.fromJson(json).playbackSpeed, 1.75);
    expect(YoutubeFeedSettings.fromJson({}).playbackSpeed, 1.0);
    expect(YoutubeFeedSettings.fromJson({'playbackSpeed': 9}).playbackSpeed,
        3.0);
    expect(
        YoutubeFeedSettings.fromJson({'playbackSpeed': 0.1}).playbackSpeed,
        0.5);
  });

  test('Track.youtube round-trips through JSON with its art URL', () {
    final track = YoutubeFeedService.trackFor(
        _video('AAAAAAAAAAA', _channelId, DateTime(2026))
            .copyWith(duration: const Duration(minutes: 3)));
    final copy = Track.fromJson(track.toJson());
    expect(copy.id, 'youtube:AAAAAAAAAAA');
    expect(copy.source, TrackSource.youtube);
    expect(copy.remoteId, 'AAAAAAAAAAA');
    expect(copy.artUrl, track.artUrl);
    expect(copy.durationMs, 180000);
  });

  group('SponsorBlock', () {
    test('parses skip segments, ignoring other action types', () {
      final segments = parseSponsorBlockSegments(jsonEncode([
        {'segment': [60.5, 90.0], 'category': 'sponsor', 'actionType': 'skip'},
        {'segment': [10, 20], 'category': 'intro', 'actionType': 'skip'},
        {'segment': [30, 40], 'category': 'filler', 'actionType': 'mute'},
      ]));
      expect(segments.map((s) => s.category), ['intro', 'sponsor']);
      expect(segments.last.start, const Duration(milliseconds: 60500));
      expect(segments.last.end, const Duration(seconds: 90));
    });

    test('asks for the chosen categories; 404 means nothing to skip',
        () async {
      Uri? asked;
      SponsorBlockService.instance.clientOverride =
          MockClient((request) async {
        asked = request.url;
        return http.Response('Not Found', 404);
      });
      final segments = await SponsorBlockService.instance
          .segmentsFor('vid', {SponsorBlockCategory.sponsor});
      expect(segments, isEmpty);
      expect(asked!.queryParameters['videoID'], 'vid');
      expect(asked!.queryParameters['categories'], '["sponsor"]');
    });
  });
}
