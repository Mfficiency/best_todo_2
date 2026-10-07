import 'dart:async';

import 'package:besttodo/models/track.dart';
import 'package:besttodo/models/youtube_feed.dart';
import 'package:besttodo/services/mp3_downloader_service.dart';
import 'package:besttodo/services/youtube_feed_service.dart';
import 'package:besttodo/ui/music_settings_page.dart';
import 'package:besttodo/ui/playback_speed_sheet.dart';
import 'package:besttodo/ui/youtube_channels_page.dart';
import 'package:besttodo/ui/youtube_feed_page.dart';
import 'package:besttodo/utils/linkified_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// No documents dir: YoutubeFeedService's file lookup fails fast and
/// persistence is skipped, so nothing does real I/O inside testWidgets.
class _NoPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => null;
}

const _channel = YoutubeChannel(id: 'UCaaaaaaaaaaaaaaaaaaaaaa', name: 'Chan');

FeedVideo _video(String id,
        {bool isShort = false, String description = '', int ageDays = 2}) =>
    FeedVideo(
      videoId: id,
      title: 'Title $id',
      channelId: _channel.id,
      channelName: _channel.name,
      published: DateTime.now().subtract(Duration(days: ageDays)),
      description: description,
      duration: const Duration(minutes: 3, seconds: 5),
      isShort: isShort,
    );

/// Thumbnails can't load in tests (the binding answers every HTTP request
/// with 400). The pages show a placeholder for that, but an error landing
/// while a row is hidden behind a pushed route has no listener and gets
/// reported, so those — and only those — are ignored here.
void _ignoreThumbnailErrors() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception is NetworkImageLoadException) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

/// The video page's own list (its SelectableText title is a Scrollable too).
final _pageScrollable = find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

void main() {
  final service = YoutubeFeedService.instance;

  setUp(() {
    PathProviderPlatform.instance = _NoPathProvider();
    service.resetForTest();
  });
  tearDown(service.resetForTest);

  testWidgets('no subscriptions shows the empty state', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: YoutubeFeedPage()));
    await tester.pump();
    expect(find.text('Add channels'), findsOneWidget);
  });

  testWidgets('opening the feed refreshes it, hides Shorts and marks played',
      (tester) async {
    _ignoreThumbnailErrors();
    service.subscriptions.value = [_channel];
    service.fetchOverride = (_) async => ChannelFetchResult([
          _video('vid1', description: 'Full description here'),
          _video('short1', isShort: true),
          _video('vid2'),
        ]);
    await service.setPlayed('vid2', true);

    await tester.pumpWidget(const MaterialApp(home: YoutubeFeedPage()));
    await tester.pump();
    await tester.pump();

    expect(find.text('Title vid1'), findsOneWidget);
    expect(find.text('Title vid2'), findsOneWidget);
    expect(find.text('Title short1'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    // On the thumbnail and in the duration/views line of each row.
    expect(find.text('3:05'), findsNWidgets(4));
    expect(find.textContaining('2d ago'), findsNWidgets(2));
    // Each row shows duration + views and when the video went up, each on
    // its own line.
    expect(find.byKey(const ValueKey('feedVideoStats')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('feedVideoUploadTime')), findsNWidgets(2));

    expect(service.refreshing.value, isFalse);
    // The info button opens the video's page (tapping the row plays it).
    await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text('Title vid1'), matching: find.byType(FeedVideoTile)),
        matching: find.byTooltip('Video info')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(find.byType(LinkifiedText), 200,
        scrollable: _pageScrollable);
    expect(tester.widget<LinkifiedText>(find.byType(LinkifiedText)).text,
        'Full description here');
    expect(find.text('Open in YouTube'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Mark played'), -200,
        scrollable: _pageScrollable);
    await tester.tap(find.text('Mark played'));
    await tester.pump();
    expect(service.isPlayed('vid1'), isTrue);
    expect(find.text('Mark unplayed'), findsOneWidget);
  });

  testWidgets('search finds feed videos by title, channel and date, '
      'including older ones', (tester) async {
    _ignoreThumbnailErrors();
    service.subscriptions.value = [_channel];
    service.fetchOverride = (_) async => ChannelFetchResult([
          FeedVideo(
              videoId: 'lofi',
              title: 'Lofi beats to study to',
              channelId: _channel.id,
              channelName: 'Chan',
              published: DateTime.now().subtract(const Duration(days: 1))),
          FeedVideo(
              videoId: 'jazz',
              title: 'Late night jazz',
              channelId: _channel.id,
              channelName: 'Chan',
              published: DateTime.now().subtract(const Duration(days: 40))),
        ]);
    final searched = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: YoutubeFeedPage(onlineSearch: (q) async {
      searched.add(q);
      return [
        const Mp3SearchResult(
            videoId: 'yt1',
            title: 'Found on YouTube',
            channel: 'Someone',
            duration: Duration(minutes: 4)),
      ];
    })));
    await tester.pump();
    await tester.pump();
    // 40 days old: outside the week the feed opens on.
    expect(find.text('Late night jazz'), findsNothing);

    await tester.tap(find.byTooltip('Search feed'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'jaz nihgt'); // typos
    await tester.pump();
    expect(find.text('Late night jazz'), findsOneWidget);
    expect(find.text('Lofi beats to study to'), findsNothing);

    await tester.enterText(find.byType(TextField), 'yesterday');
    await tester.pump();
    expect(find.text('Lofi beats to study to'), findsOneWidget);
    expect(find.text('Late night jazz'), findsNothing);

    // Limited to the title, a channel name no longer matches.
    await tester.enterText(find.byType(TextField), 'chan');
    await tester.pump();
    expect(find.text('Lofi beats to study to'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Title'));
    await tester.pump();
    expect(find.text('Lofi beats to study to'), findsNothing);
    // Nothing in the feed: YouTube is searched instead (debounced).
    expect(find.text('Nothing in your feed — searching YouTube…'),
        findsOneWidget);
    expect(searched, isEmpty);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(searched, ['chan']);
    expect(find.text('Found on YouTube'), findsOneWidget);
    expect(find.text('Nothing in your feed — results from YouTube'),
        findsOneWidget);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pump();
    expect(find.text('Lofi beats to study to'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the feed has no settings button', (tester) async {
    service.subscriptions.value = [_channel];
    service.fetchOverride = (_) async => const ChannelFetchResult([]);
    await tester.pumpWidget(const MaterialApp(home: YoutubeFeedPage()));
    await tester.pump();
    expect(find.byTooltip('Feed settings'), findsNothing);
    expect(find.byIcon(Icons.tune), findsNothing);
  });

  group('swipes and long-press', () {
    Future<List<Track>> pumpFeed(WidgetTester tester) async {
      _ignoreThumbnailErrors();
      service.subscriptions.value = [_channel];
      service.fetchOverride =
          (_) async => ChannelFetchResult([_video('vid1')]);
      final queued = <Track>[];
      await tester.pumpWidget(MaterialApp(
          home: YoutubeFeedPage(
              playQueue: (_) async {},
              addToQueue: (t) async {
                queued.add(t);
                return true;
              })));
      await tester.pump();
      await tester.pump();
      return queued;
    }

    testWidgets('swipe right adds to the queue, the row stays',
        (tester) async {
      final queued = await pumpFeed(tester);
      await tester.drag(find.text('Title vid1'), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(queued.map((t) => t.remoteId), ['vid1']);
      expect(find.text('Title vid1'), findsOneWidget);
      expect(find.text('Added to the queue — downloading it for offline play'),
          findsOneWidget);
    });

    testWidgets('swipe left marks watched, with Undo', (tester) async {
      await pumpFeed(tester);
      await tester.drag(find.text('Title vid1'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(service.isPlayed('vid1'), isTrue);
      expect(find.text('Marked watched'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(service.isPlayed('vid1'), isFalse);
    });

    testWidgets('long-press shows the options, Transcript among them',
        (tester) async {
      final queued = await pumpFeed(tester);
      await tester.longPress(find.text('Title vid1'));
      await tester.pumpAndSettle();
      expect(find.text('Transcript'), findsOneWidget);
      expect(find.text('Quick summary'), findsOneWidget);
      expect(find.text('Mark watched'), findsOneWidget);
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      expect(queued, hasLength(1));
    });

    testWidgets('gestures follow the settings', (tester) async {
      await service.updateSettings(service.settings.value.copyWith(
        swipeRight: FeedGestureAction.togglePlayed,
        swipeLeft: FeedGestureAction.nothing,
        longPress: FeedGestureAction.nothing,
      ));
      final queued = await pumpFeed(tester);
      await tester.drag(find.text('Title vid1'), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(service.isPlayed('vid1'), isTrue);
      expect(queued, isEmpty);
      await tester.longPress(find.text('Title vid1'));
      await tester.pumpAndSettle();
      expect(find.text('Transcript'), findsNothing);
    });
  });

  testWidgets('tapping a video plays just that video', (tester) async {
    _ignoreThumbnailErrors();
    service.subscriptions.value = [_channel];
    service.fetchOverride = (_) async =>
        ChannelFetchResult([_video('vid1'), _video('vid2', ageDays: 3)]);
    final played = <List<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: YoutubeFeedPage(
        playQueue: (queue) async => played.add([for (final t in queue) t.id]),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Title vid1'));
    await tester.pump();
    // No auto-playing the next video by default.
    expect(played, [
      ['youtube:vid1']
    ]);
  });

  testWidgets(
      'opens on the last 2 days, fills in the week, older only on demand',
      (tester) async {
    _ignoreThumbnailErrors();
    service.subscriptions.value = [_channel];
    // Already cached from last time: shows at once, but only 2 days of it.
    service.videos.value = [
      _video('new', ageDays: 1),
      _video('week', ageDays: 5),
      _video('old', ageDays: 12),
    ];
    final fetch = Completer<ChannelFetchResult>();
    service.fetchOverride = (_) => fetch.future;

    await tester.pumpWidget(const MaterialApp(home: YoutubeFeedPage()));
    await tester.pump();
    expect(find.text('Title new'), findsOneWidget);
    expect(find.text('Title week'), findsNothing);
    expect(find.text('Loading the rest of the week...'), findsOneWidget);

    fetch.complete(ChannelFetchResult([
      _video('new', ageDays: 1),
      _video('week', ageDays: 5),
      _video('old', ageDays: 12),
    ]));
    await tester.pump();
    await tester.pump();
    expect(find.text('Title week'), findsOneWidget);
    expect(find.text('Title old'), findsNothing);

    await tester.tap(find.text('Show older videos'));
    await tester.pump();
    expect(find.text('Title old'), findsOneWidget);
    expect(find.text('No older videos'), findsOneWidget);
  });

  testWidgets('a video without a description fetches it on open',
      (tester) async {
    _ignoreThumbnailErrors();
    service.descriptionOverride = (id) async => 'Fetched for $id';
    await tester.pumpWidget(MaterialApp(
      home: YoutubeVideoPage(video: _video('vid9'), onPlay: () {}),
    ));
    await tester.pump();
    await tester.pump();
    await tester.scrollUntilVisible(find.byType(LinkifiedText), 200,
        scrollable: _pageScrollable);
    expect(tester.widget<LinkifiedText>(find.byType(LinkifiedText)).text,
        'Fetched for vid9');
  });

  testWidgets('channel search subscribes', (tester) async {
    service.fetchOverride = (_) async => const ChannelFetchResult([]);
    service.searchOverride = (query) async => [
          YoutubeChannel(id: 'UCbbbbbbbbbbbbbbbbbbbbbb', name: '$query Music'),
        ];
    await tester.pumpWidget(const MaterialApp(home: YoutubeChannelsPage()));
    await tester.enterText(find.byType(TextField), 'Lofi');
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Lofi Music'), findsOneWidget);

    await tester.tap(find.text('Subscribe'));
    await tester.pump();
    expect(service.isSubscribed('UCbbbbbbbbbbbbbbbbbbbbbb'), isTrue);
    expect(find.text('Subscribed'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('Subscribed (1)'), findsOneWidget);
    await tester.tap(find.byTooltip('Unsubscribe'));
    await tester.pump();
    expect(service.subscriptions.value, isEmpty);
  });

  testWidgets('a channel\'s "Check for new videos" fetches just that channel',
      (tester) async {
    service.subscriptions.value = [_channel];
    service.forceRetryDelays = const [Duration.zero, Duration.zero];
    var calls = 0;
    service.fetchOverride = (_) async {
      if (++calls == 1) throw Exception('RSS hiccup');
      return ChannelFetchResult([_video('new1')]);
    };
    await tester.pumpWidget(const MaterialApp(home: YoutubeChannelsPage()));
    await tester.pump();
    await tester.tap(find.byTooltip('Check for new videos'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(calls, 2, reason: 'retried after the first failure');
    expect(find.text('Chan: 1 new video'), findsOneWidget);
    expect(service.videos.value.map((v) => v.videoId), ['new1']);
  });

  testWidgets('the feed\'s "Couldn\'t refresh" line has a Retry button',
      (tester) async {
    _ignoreThumbnailErrors();
    service.subscriptions.value = [_channel];
    service.forceRetryDelays = const [Duration.zero, Duration.zero];
    var failing = true;
    service.fetchOverride = (_) async {
      if (failing) throw Exception('down');
      return ChannelFetchResult([_video('back1')]);
    };
    await tester.pumpWidget(const MaterialApp(home: YoutubeFeedPage()));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining("Couldn't refresh 1 channel"), findsOneWidget);

    failing = false;
    await tester.tap(find.text('Retry'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(find.textContaining("Couldn't refresh"), findsNothing);
    expect(find.text('All 1 channel loaded'), findsOneWidget);
    expect(find.text('Title back1'), findsOneWidget);
  });

  testWidgets('feed settings toggle Shorts and SponsorBlock categories',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MusicSettingsPage(initialSection: MusicSettingsSection.feed)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide Shorts'));
    await tester.pump();
    expect(service.settings.value.hideShorts, isFalse);

    expect(find.text('Filler tangent/jokes'), findsNothing);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'SponsorBlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'SponsorBlock'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Filler tangent/jokes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filler tangent/jokes'));
    await tester.pump();
    expect(service.settings.value.sponsorBlockCategories,
        contains(SponsorBlockCategory.filler));

    await tester.ensureVisible(find.text('Skip sponsored segments'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip sponsored segments'));
    await tester.pump();
    expect(service.settings.value.sponsorBlockEnabled, isFalse);
    expect(find.text('Filler tangent/jokes'), findsNothing);
  });

  testWidgets('feed settings pick the swipe/long-press actions and offline days',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MusicSettingsPage(initialSection: MusicSettingsSection.feed)));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Swipe a video left'));
    await tester.pumpAndSettle();
    expect(find.text('Mark watched / unwatched'), findsOneWidget);
    await tester.tap(find.text('Swipe a video left'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(RadioListTile<FeedGestureAction>,
        'Quick summary'));
    await tester.pumpAndSettle();
    expect(service.settings.value.swipeLeft, FeedGestureAction.summary);

    await tester.ensureVisible(find.text('Keep queued videos offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('For 2 days'), findsOneWidget);
    await tester.tap(find.text('Keep queued videos offline'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 days'));
    await tester.pumpAndSettle();
    expect(service.settings.value.offlineDays, 7);
  });

  test('gesture settings round-trip through JSON, unknown keys fall back',
      () {
    const s = YoutubeFeedSettings(
        swipeRight: FeedGestureAction.transcript,
        swipeLeft: FeedGestureAction.nothing,
        longPress: FeedGestureAction.info,
        offlineDays: 5);
    final back = YoutubeFeedSettings.fromJson(s.toJson());
    expect(back.swipeRight, FeedGestureAction.transcript);
    expect(back.swipeLeft, FeedGestureAction.nothing);
    expect(back.longPress, FeedGestureAction.info);
    expect(back.offlineDays, 5);
    final old = YoutubeFeedSettings.fromJson(
        {'swipeRight': 'bogus', 'offlineDays': 99});
    expect(old.swipeRight, FeedGestureAction.addToQueue);
    expect(old.swipeLeft, FeedGestureAction.togglePlayed);
    expect(old.longPress, FeedGestureAction.options);
    expect(old.offlineDays, YoutubeFeedSettings.maxOfflineDays);
  });

  testWidgets('feed settings set the video speed', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MusicSettingsPage(initialSection: MusicSettingsSection.feed)));
    await tester.pumpAndSettle();
    expect(find.textContaining('1× — the last speed you picked'),
        findsOneWidget);
    await tester.tap(find.text('Video speed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5×'));
    await tester.pump();
    expect(service.settings.value.playbackSpeed, 1.5);
    await tester.tap(find.byTooltip('Faster'));
    await tester.pump();
    expect(service.settings.value.playbackSpeed, closeTo(1.55, 0.001));
  });

  test('formatSpeed', () {
    expect(formatSpeed(1), '1×');
    expect(formatSpeed(1.5), '1.5×');
    expect(formatSpeed(1.25), '1.25×');
    expect(formatSpeed(2.0), '2×');
  });

  test('formatFeedAge / formatVideoDuration', () {
    final now = DateTime(2026, 10, 3, 12);
    expect(formatFeedAge(now.subtract(const Duration(minutes: 5)), now: now),
        '5m ago');
    expect(formatFeedAge(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago');
    expect(formatFeedAge(now.subtract(const Duration(days: 15)), now: now),
        '2w ago');
    expect(formatFeedAge(now.subtract(const Duration(days: 400)), now: now),
        '1y ago');
    expect(formatVideoDuration(const Duration(seconds: 65)), '1:05');
  });

  test('formatFeedUploadTime', () {
    final now = DateTime(2026, 10, 3, 12); // a Saturday
    expect(formatFeedUploadTime(null, now: now), '');
    expect(formatFeedUploadTime(DateTime(2026, 10, 3, 9, 5), now: now),
        'Today 09:05');
    expect(formatFeedUploadTime(DateTime(2026, 10, 2, 23, 40), now: now),
        'Yesterday 23:40');
    expect(formatFeedUploadTime(DateTime(2026, 9, 29, 18, 30), now: now),
        'Tue 18:30');
    expect(formatFeedUploadTime(DateTime(2026, 8, 14, 7, 0), now: now),
        '14 Aug, 07:00');
    expect(formatFeedUploadTime(DateTime(2025, 12, 1, 7, 0), now: now),
        '1 Dec 2025');
    // A date read off "3 days ago" has no meaningful clock time.
    expect(
        formatFeedUploadTime(DateTime(2026, 9, 29, 18, 30),
            now: now, approx: true),
        'Tue');
    expect(
        formatFeedUploadTime(DateTime(2026, 8, 14, 7, 0),
            now: now, approx: true),
        '14 Aug');
    expect(formatVideoDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03');
  });
}
