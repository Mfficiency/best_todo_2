import 'dart:async';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/music_playlist.dart';
import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/mp3_download_manager.dart';
import 'package:besttodo/services/mp3_downloader_service.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_player_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:besttodo/services/music_youtube_fallback.dart';
import 'package:besttodo/ui/music_player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = Mp3DownloaderService.instance;
  final played = <Track>[];

  const result = Mp3SearchResult(
    videoId: 'abc123',
    title: 'Daft Punk - One More Time (Official Video)',
    channel: 'Daft Punk',
    duration: Duration(minutes: 5, seconds: 20),
  );

  setUp(() {
    played.clear();
    Config.musicFolder = '';
    Config.mp3DownloadFolder = '';
    Config.musicConfirmSpeakerPlay = false;
    Mp3DownloadManager.instance.resetForTest();
    MusicLibraryService.instance.resetForTest();
    MusicPlaylistService.instance.resetForTest();
    MusicPlaylistService.instance.playlists.value = [
      MusicPlaylist.favorites(),
      MusicPlaylist.disliked(),
    ];
    // Downloads never finish: the test only cares that one was queued, and
    // a finishing job would write the history file from inside fake async.
    service.downloadOverride =
        (_, __, ___) => Completer<String>().future;
    MusicYoutubeFallback.downloadFolderOverride = () async => '/music';
    MusicYoutubeFallback.playOverride = (track) async => played.add(track);
  });

  tearDown(() {
    service.downloadOverride = null;
    service.searchOverride = null;
    MusicYoutubeFallback.downloadFolderOverride = null;
    MusicYoutubeFallback.playOverride = null;
    Mp3DownloadManager.instance.resetForTest();
  });

  test('trackFor builds a YouTube track titled like the downloaded file', () {
    final track = MusicYoutubeFallback.trackFor(result);
    expect(track.id, 'youtube:abc123');
    expect(track.source, TrackSource.youtube);
    expect(track.remoteId, 'abc123');
    expect(track.artist, 'Daft Punk');
    expect(track.title, 'One More Time');
    expect(track.durationMs, 320000);
    // A song, not a Subscriptions video: plays by music rules (1x speed,
    // music volume).
    expect(track.youtubeSong, isTrue);
    expect(track.isFeedVideo, isFalse);
  });

  test('a feed video stays a feed video', () {
    final video = Track.youtube(videoId: 'v', title: 'Podcast');
    expect(video.isFeedVideo, isTrue);
    expect(Track.fromJson(video.toJson()).isFeedVideo, isTrue);
  });

  test('a YouTube track survives a JSON round-trip', () {
    final track = MusicYoutubeFallback.trackFor(result);
    final back = Track.fromJson(track.toJson());
    expect(back.source, TrackSource.youtube);
    expect(back.remoteId, 'abc123');
    expect(back.id, track.id);
    expect(back.youtubeSong, isTrue);
    expect(back.isFeedVideo, isFalse);
  });

  test('playAndDownload plays the stream and queues a silent download',
      () async {
    await MusicYoutubeFallback.playAndDownload(result);

    expect(played.single.id, 'youtube:abc123');
    final jobs = Mp3DownloadManager.instance.jobs.value;
    expect(jobs, hasLength(1));
    expect(jobs.single.videoId, 'abc123');
    expect(jobs.single.destinationDir, '/music');
  });

  test('playing the same result again does not queue a second download',
      () async {
    await MusicYoutubeFallback.playAndDownload(result);
    await MusicYoutubeFallback.playAndDownload(result);

    expect(played, hasLength(2));
    expect(Mp3DownloadManager.instance.jobs.value, hasLength(1));
  });

  test('with no download folder it still plays, streaming only', () async {
    MusicYoutubeFallback.downloadFolderOverride = () async => null;
    await MusicYoutubeFallback.playAndDownload(result);

    expect(played, hasLength(1));
    expect(Mp3DownloadManager.instance.jobs.value, isEmpty);
  });

  test('downloadFolder prefers the MP3 Downloader folder', () async {
    MusicYoutubeFallback.downloadFolderOverride = null;
    Config.mp3DownloadFolder = '/downloads/music';
    expect(await MusicYoutubeFallback.downloadFolder(), '/downloads/music');
  });

  testWidgets(
      'library search with no match searches YouTube by itself, marks the '
      'results as not local, and plays a picked one',
      (tester) async {
    if (!MusicPlayerService.isReady) {
      await tester.runAsync(MusicPlayerService.init);
    }
    final queries = <String>[];
    service.searchOverride = (query, limit) async {
      queries.add(query);
      return [result];
    };
    Config.musicFolder = '/does/not/matter/for/this/test';
    MusicLibraryService.instance.tracks.value = [
      Track.local(
          filePath: '/does/not/matter/a.mp3',
          title: 'Yesterday',
          artist: 'The Beatles'),
    ];

    await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Search music'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'one more time');
    await tester.pump();

    // Searching right away, clearly flagged as not from the library.
    expect(find.text('Not in your library'), findsOneWidget);
    expect(queries, isEmpty, reason: 'waits for typing to pause');
    await tester.pump(YoutubeSearchFallback.debounce);
    await tester.pumpAndSettle();

    expect(queries, ['one more time']);
    expect(find.text(result.title), findsOneWidget);
    expect(find.textContaining('YouTube · Daft Punk'), findsOneWidget);
    expect(find.textContaining('not songs on your phone'), findsOneWidget);

    await tester.tap(find.text(result.title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(played.single.id, 'youtube:abc123');
    expect(Mp3DownloadManager.instance.jobs.value.single.videoId, 'abc123');
  });

  testWidgets('typing on cancels the pending search for the old query',
      (tester) async {
    final queries = <String>[];
    service.searchOverride = (query, limit) async {
      queries.add(query);
      return const [];
    };
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: YoutubeSearchFallback(key: ValueKey('a'), query: 'a'))));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: YoutubeSearchFallback(key: ValueKey('ab'), query: 'ab'))));
    await tester.pump(YoutubeSearchFallback.debounce);
    await tester.pumpAndSettle();
    expect(queries, ['ab']);
    expect(find.text('Nothing on YouTube for "ab" either'), findsOneWidget);
  });
}
