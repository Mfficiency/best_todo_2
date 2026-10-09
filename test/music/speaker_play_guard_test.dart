import 'dart:async';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/track.dart';
import 'package:besttodo/models/youtube_feed.dart';
import 'package:besttodo/services/music_audio_handler.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/speaker_play_guard.dart';
import 'package:besttodo/services/youtube_feed_service.dart';
import 'package:besttodo/ui/bpm_range_page.dart';
import 'package:besttodo/ui/music_mini_player_bar.dart';
import 'package:besttodo/ui/youtube_feed_page.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late bool external;
  late bool playing;

  setUp(() {
    external = false;
    playing = false;
    Config.musicConfirmSpeakerPlay = true;
    SpeakerPlayGuard.externalOutputOverride = () async => external;
    SpeakerPlayGuard.isPlayingOverride = () => playing;
  });

  tearDown(() {
    SpeakerPlayGuard.externalOutputOverride = null;
    SpeakerPlayGuard.isPlayingOverride = null;
    Config.musicConfirmSpeakerPlay = true;
  });

  /// Pumps a button that runs [SpeakerPlayGuard.confirmPlay] and records the
  /// answer in the returned list.
  Future<List<bool>> pumpGuard(WidgetTester tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              answers.add(await SpeakerPlayGuard.confirmPlay(context)),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return answers;
  }

  testWidgets('phone speaker only, nothing playing: asks first',
      (tester) async {
    final answers = await pumpGuard(tester);
    expect(find.text('Play out loud?'), findsOneWidget);
    expect(answers, isEmpty);

    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(answers, [true]);
  });

  testWidgets('Cancel keeps it quiet', (tester) async {
    final answers = await pumpGuard(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answers, [false]);
  });

  testWidgets('a Bluetooth speaker/headphones connected: plays straight away',
      (tester) async {
    external = true;
    final answers = await pumpGuard(tester);
    expect(find.text('Play out loud?'), findsNothing);
    expect(answers, [true]);
  });

  testWidgets('music already playing: never asks', (tester) async {
    playing = true;
    final answers = await pumpGuard(tester);
    expect(find.text('Play out loud?'), findsNothing);
    expect(answers, [true]);
  });

  testWidgets('turned off in settings: never asks', (tester) async {
    Config.musicConfirmSpeakerPlay = false;
    final answers = await pumpGuard(tester);
    expect(find.text('Play out loud?'), findsNothing);
    expect(answers, [true]);
  });

  group('every way to start playing asks (0.3.19)', () {
    testWidgets('tapping a Subscriptions video', (tester) async {
      PathProviderPlatform.instance = _NoPathProvider();
      final feed = YoutubeFeedService.instance..resetForTest();
      addTearDown(feed.resetForTest);
      const channel =
          YoutubeChannel(id: 'UCaaaaaaaaaaaaaaaaaaaaaa', name: 'Chan');
      feed.subscriptions.value = [channel];
      feed.fetchOverride = (_) async => ChannelFetchResult([
            FeedVideo(
                videoId: 'v1',
                title: 'A video',
                channelId: channel.id,
                channelName: channel.name,
                published: DateTime.now()),
          ]);
      final played = <List<Track>>[];
      await tester.pumpWidget(MaterialApp(
          home: YoutubeFeedPage(playQueue: (q) async => played.add(q))));
      await tester.pump();
      await tester.pump();
      final original = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exception is NetworkImageLoadException) return;
        original?.call(d);
      };
      addTearDown(() => FlutterError.onError = original);

      await tester.tap(find.text('A video'));
      await tester.pumpAndSettle();
      expect(find.text('Play out loud?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(played, isEmpty);

      await tester.tap(find.text('A video'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      expect(played, hasLength(1));
    });

    testWidgets('"Play as queue" on Songs by BPM', (tester) async {
      MusicLibraryService.instance.resetForTest();
      addTearDown(MusicLibraryService.instance.resetForTest);
      MusicLibraryService.instance.tracks.value = [
        Track.local(filePath: '/m/a.mp3', title: 'Fast', bpm: 128),
      ];
      final played = <List<Track>>[];
      await tester.pumpWidget(MaterialApp(
          home: BpmRangePage(
              playQueue: (q, {startIndex = 0}) async => played.add(q))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play as queue'));
      await tester.pumpAndSettle();
      expect(find.text('Play out loud?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(played, isEmpty);
    });

    testWidgets('"Back to music" from a video that is still loading',
        (tester) async {
      // A video still loading counts as "not listening yet" — the real
      // check is MusicAudioHandler.isAudible, false until sound came out.
      final handler = MusicAudioHandler();
      expect(handler.isAudible, isFalse);
      handler.restore([Track.youtube(videoId: 'v1', title: 'Loading video')]);
      handler.restoreOtherSession(PlaybackSession(
        queue: [Track.local(filePath: '/m/a.mp3', title: 'Song')],
        index: 0,
        position: Duration.zero,
      ));
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
          navigatorKey: key, home: const Scaffold(body: Text('home'))));
      unawaited(switchSessionAndShow(handler, key.currentState));
      await tester.pumpAndSettle();
      expect(find.text('Play out loud?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(handler.currentTrack!.title, 'Loading video',
          reason: 'cancelled: nothing switched');
    });
  });
}

class _NoPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => null;
}
