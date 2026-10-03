import 'package:besttodo/models/youtube_feed.dart';
import 'package:besttodo/services/youtube_feed_service.dart';
import 'package:besttodo/ui/youtube_channels_page.dart';
import 'package:besttodo/ui/youtube_feed_page.dart';
import 'package:besttodo/ui/youtube_feed_settings_page.dart';
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

FeedVideo _video(String id, {bool isShort = false, String description = ''}) =>
    FeedVideo(
      videoId: id,
      title: 'Title $id',
      channelId: _channel.id,
      channelName: _channel.name,
      published: DateTime.now().subtract(const Duration(days: 2)),
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
    expect(find.text('3:05'), findsNWidgets(2));
    expect(find.textContaining('2d ago'), findsNWidgets(2));

    expect(service.refreshing.value, isFalse);
    await tester.tap(find.text('Title vid1'));
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

  testWidgets('feed settings toggle Shorts and SponsorBlock categories',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: YoutubeFeedSettingsPage()));
    await tester.tap(find.text('Hide Shorts'));
    await tester.pump();
    expect(service.settings.value.hideShorts, isFalse);

    await tester.scrollUntilVisible(find.text('Filler tangent/jokes'), 100);
    await tester.tap(find.text('Filler tangent/jokes'));
    await tester.pump();
    expect(service.settings.value.sponsorBlockCategories,
        contains(SponsorBlockCategory.filler));

    await tester.scrollUntilVisible(find.text('SponsorBlock'), -100);
    await tester.tap(find.text('SponsorBlock'));
    await tester.pump();
    expect(service.settings.value.sponsorBlockEnabled, isFalse);
    expect(find.text('Filler tangent/jokes'), findsNothing);
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
    expect(formatVideoDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03');
  });
}
