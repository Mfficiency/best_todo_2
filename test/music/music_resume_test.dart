import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:besttodo/models/track.dart';
import 'package:besttodo/models/youtube_feed.dart';
import 'package:besttodo/services/music_audio_handler.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_player_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:besttodo/services/music_resume_service.dart';
import 'package:besttodo/services/youtube_feed_service.dart';
import 'package:besttodo/ui/music_mini_player_bar.dart';
import 'package:besttodo/ui/now_playing_page.dart';
import 'package:besttodo/ui/youtube_feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Records play/pause instead of touching a real audio player.
class _FakeAudioHandler extends BaseAudioHandler {
  int plays = 0;
  int pauses = 0;

  @override
  Future<void> play() async {
    plays++;
    playbackState.add(playbackState.value.copyWith(playing: true));
  }

  @override
  Future<void> pause() async {
    pauses++;
    playbackState.add(playbackState.value.copyWith(playing: false));
  }
}

class _RecordingObserver extends NavigatorObserver {
  _RecordingObserver(this.pushed);
  final List<String?> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route.settings.name);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add('pop ${route.settings.name}');
}

void main() {
  late Directory tempDir;

  Track track(String id, {String artist = ''}) =>
      Track.local(filePath: '/fake/$id.mp3', title: id, artist: artist);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    MusicLibraryService.instance.resetForTest();
    MusicPlaylistService.instance.resetForTest();
    MusicPlayerService.setHandlerForTest(null);
  });

  tearDown(() async {
    MusicPlayerService.setHandlerForTest(null);
    await tempDir.delete(recursive: true);
  });

  group('MusicResumeService', () {
    test('saves and loads the queue, index, position and current track',
        () async {
      await MusicResumeService.save(MusicResumeState(
        queueIds: ['local:/fake/a.mp3', 'local:/fake/b.mp3'],
        index: 1,
        position: const Duration(seconds: 42),
        current: track('b', artist: 'Bee'),
      ));

      final state = await MusicResumeService.load();

      expect(state, isNotNull);
      expect(state!.queueIds, ['local:/fake/a.mp3', 'local:/fake/b.mp3']);
      expect(state.index, 1);
      expect(state.position, const Duration(seconds: 42));
      expect(state.current!.title, 'b');
      expect(state.current!.artist, 'Bee');
    });

    test('nothing saved yet loads as null', () async {
      expect(await MusicResumeService.load(), isNull);
      expect(await MusicResumeService.loadOther(), isNull);
    });

    test('also keeps the other kind\'s session, videos as full copies',
        () async {
      final v1 = Track.youtube(videoId: 'v1', title: 'Talk', artist: 'Ch');
      final v2 = Track.youtube(videoId: 'v2', title: 'Next', artist: 'Ch');
      await MusicResumeService.save(
        MusicResumeState(
          queueIds: ['local:/fake/a.mp3'],
          index: 0,
          position: const Duration(seconds: 3),
          current: track('a'),
        ),
        other: MusicResumeState(
          queueIds: [v1.id, v2.id],
          index: 0,
          position: const Duration(minutes: 12),
          current: v1,
          tracks: [v1, v2],
        ),
      );

      expect((await MusicResumeService.load())!.current!.title, 'a');
      final other = await MusicResumeService.loadOther();
      expect(other!.position, const Duration(minutes: 12));
      expect(other.tracks!.map((t) => t.title), ['Talk', 'Next']);
      expect(other.tracks!.first.isFeedVideo, isTrue);
    });
  });

  group('restoreLastSession', () {
    test(
        'shows the last-played track paused at its position, dropping '
        'queue entries no longer in the library', () async {
      MusicLibraryService.instance.tracks.value = [track('a'), track('c')];
      await MusicResumeService.save(MusicResumeState(
        queueIds: [
          'local:/fake/a.mp3',
          'local:/fake/gone.mp3',
          'local:/fake/c.mp3',
        ],
        index: 2,
        position: const Duration(minutes: 1, seconds: 5),
        current: track('c'),
      ));
      final handler = MusicAudioHandler();
      MusicPlayerService.setHandlerForTest(handler);

      await MusicPlayerService.restoreLastSession();

      expect(handler.currentQueueTracks.map((t) => t.title), ['a', 'c']);
      expect(handler.currentTrack!.title, 'c');
      expect(handler.mediaItem.value!.title, 'c');
      expect(handler.playbackState.value.playing, isFalse);
      expect(handler.playbackState.value.updatePosition,
          const Duration(minutes: 1, seconds: 5));
    });

    test('keeps the last track from its saved copy if the library lost it',
        () async {
      await MusicResumeService.save(MusicResumeState(
        queueIds: ['local:/fake/solo.mp3'],
        index: 0,
        position: Duration.zero,
        current: track('solo', artist: 'Someone'),
      ));
      final handler = MusicAudioHandler();
      MusicPlayerService.setHandlerForTest(handler);

      await MusicPlayerService.restoreLastSession();

      expect(handler.mediaItem.value!.title, 'solo');
      expect(handler.mediaItem.value!.artist, 'Someone');
    });
  });

  group('switching between the last song and the last video', () {
    test('restoreLastSession brings back the other session too', () async {
      MusicLibraryService.instance.tracks.value = [track('a')];
      final v1 = Track.youtube(videoId: 'v1', title: 'Talk', artist: 'Ch');
      await MusicResumeService.save(
        MusicResumeState(
          queueIds: ['local:/fake/a.mp3'],
          index: 0,
          position: const Duration(seconds: 30),
          current: track('a'),
        ),
        other: MusicResumeState(
          queueIds: [v1.id],
          index: 0,
          position: const Duration(minutes: 12),
          current: v1,
          tracks: [v1],
        ),
      );
      final handler = MusicAudioHandler();
      MusicPlayerService.setHandlerForTest(handler);

      await MusicPlayerService.restoreLastSession();

      expect(handler.currentTrack!.title, 'a');
      final other = handler.otherSession.value!;
      expect(other.isVideo, isTrue);
      expect(other.current.title, 'Talk');
      expect(other.position, const Duration(minutes: 12));
    });

    test('a restored video session keeps its whole queue', () async {
      final v1 = Track.youtube(videoId: 'v1', title: 'One');
      final v2 = Track.youtube(videoId: 'v2', title: 'Two');
      await MusicResumeService.save(MusicResumeState(
        queueIds: [v1.id, v2.id],
        index: 1,
        position: const Duration(minutes: 2),
        current: v2,
        tracks: [v1, v2],
      ));
      final handler = MusicAudioHandler();
      MusicPlayerService.setHandlerForTest(handler);

      await MusicPlayerService.restoreLastSession();

      expect(handler.currentQueueTracks.map((t) => t.title), ['One', 'Two']);
      expect(handler.currentTrack!.title, 'Two');
      expect(handler.otherSession.value, isNull);
    });

    testWidgets('the mini player offers one tap back to the other session',
        (tester) async {
      final handler = MusicAudioHandler();
      handler.restore([track('a')]);

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: MusicMiniPlayerBar(handler: handler))));
      expect(find.byKey(const ValueKey('switchSessionButton')), findsNothing);

      handler.restoreOtherSession(PlaybackSession(
        queue: [Track.youtube(videoId: 'v1', title: 'Talk')],
        index: 0,
        position: const Duration(minutes: 12),
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('switchSessionButton')), findsOneWidget);
      expect(find.bySemanticsLabel('Back to video: Talk'), findsOneWidget);
    });
  });

  group('bottom-left switch button', () {
    testWidgets('shows "Back to videos" with a remembered video session',
        (tester) async {
      YoutubeFeedService.instance.resetForTest();
      final handler = MusicAudioHandler();
      handler.restore([track('a')]);

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SessionSwitchPill(handler: handler))));
      expect(find.byKey(const ValueKey('sessionSwitchPill')), findsNothing,
          reason: 'nothing to switch to yet');

      handler.restoreOtherSession(PlaybackSession(
        queue: [Track.youtube(videoId: 'v1', title: 'Talk')],
        index: 0,
        position: const Duration(minutes: 12),
      ));
      await tester.pump();
      expect(find.text('Back to videos'), findsOneWidget);
    });

    test('with no remembered video, falls back to the last played one',
        () async {
      final feed = YoutubeFeedService.instance..resetForTest();
      feed.videos.value = [
        const FeedVideo(
            videoId: 'v9', title: 'Podcast', channelId: 'c', channelName: 'C'),
      ];
      await feed.recordProgress('v9', const Duration(minutes: 3));
      final handler = MusicAudioHandler();
      handler.restore([track('a')]);

      final target = handler.switchTarget()!;
      expect(target.isVideo, isTrue);
      expect(target.current.title, 'Podcast');
      feed.resetForTest();
    });
  });

  group('switching brings its screen along', () {
    Route<void> named(String name, String text) => MaterialPageRoute(
        settings: RouteSettings(name: name),
        builder: (_) => Scaffold(body: Text(text)));

    testWidgets('"Back to videos" pops back to an open feed', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
          navigatorKey: key, home: const Scaffold(body: Text('Library'))));
      key.currentState!.push(named(YoutubeFeedPage.routeName, 'Feed'));
      key.currentState!.push(named('/other', 'Video info'));
      await tester.pumpAndSettle();

      showSessionScreen(key.currentState!, video: true);
      await tester.pumpAndSettle();
      expect(find.text('Feed'), findsOneWidget);
      expect(find.text('Video info'), findsNothing);
    });

    testWidgets('"Back to music" pops back to an open Now Playing',
        (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
          navigatorKey: key, home: const Scaffold(body: Text('Library'))));
      key.currentState!.push(named(NowPlayingPage.routeName, 'Playing'));
      key.currentState!.push(named('/other', 'Queue'));
      await tester.pumpAndSettle();

      showSessionScreen(key.currentState!, video: false);
      await tester.pumpAndSettle();
      expect(find.text('Playing'), findsOneWidget);
      expect(find.text('Queue'), findsNothing);
    });

    testWidgets('opens the feed fresh from Now Playing', (tester) async {
      final key = GlobalKey<NavigatorState>();
      final pushed = <String?>[];
      await tester.pumpWidget(MaterialApp(
        navigatorKey: key,
        navigatorObservers: [_RecordingObserver(pushed)],
        home: const Scaffold(body: Text('Library')),
      ));
      key.currentState!.push(named(NowPlayingPage.routeName, 'Playing'));
      await tester.pumpAndSettle();
      pushed.clear();

      showSessionScreen(key.currentState!, video: true);
      await tester.pump();
      // Now Playing is left, not kept underneath the feed.
      expect(pushed,
          ['pop ${NowPlayingPage.routeName}', YoutubeFeedPage.routeName]);
    });

    test('does nothing when there is nothing to switch to', () async {
      YoutubeFeedService.instance.resetForTest();
      final handler = MusicAudioHandler();
      handler.restore([track('a')]);
      await switchSessionAndShow(handler, null);
      expect(handler.currentTrack!.title, 'a');
    });
  });

  group('MusicMiniPlayerBar', () {
    testWidgets('shows the last-played song with a play button that plays it',
        (tester) async {
      final audio = _FakeAudioHandler();
      audio.mediaItem.add(const MediaItem(
          id: 'local:/fake/x.mp3', title: 'Last Song', artist: 'Band'));

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: MusicMiniPlayerBar(handler: audio))));
      await tester.pump();

      expect(find.text('Last Song'), findsOneWidget);
      expect(find.text('Band'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('musicMiniPlayerPlayPause')));
      await tester.pump();
      expect(audio.plays, 1);
      expect(find.byIcon(Icons.pause), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('musicMiniPlayerPlayPause')));
      await tester.pump();
      expect(audio.pauses, 1);
    });

    testWidgets('is hidden when there is no current or last-played song',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MusicMiniPlayerBar(handler: _FakeAudioHandler()))));
      await tester.pump();
      expect(find.byKey(const ValueKey('musicMiniPlayer')), findsNothing);
    });

    testWidgets('hides while Now Playing is open', (tester) async {
      final audio = _FakeAudioHandler();
      audio.mediaItem.add(const MediaItem(id: 'x', title: 'Song'));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: MusicMiniPlayerBar(handler: audio))));
      await tester.pump();
      expect(find.text('Song'), findsOneWidget);

      NowPlayingPage.openCount.value = 1;
      await tester.pump();
      expect(find.text('Song'), findsNothing);
      NowPlayingPage.openCount.value = 0;
    });
  });
}
