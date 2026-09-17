import 'package:besttodo/config.dart';
import 'package:besttodo/models/music_playlist.dart';
import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:besttodo/ui/music_player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    Config.musicFolder = '';
    Config.musicExcludedSubfolders = [];
    Config.mp3DownloadFolder = '';
    MusicLibraryService.instance.resetForTest();
    MusicPlaylistService.instance.resetForTest();
    MusicPlaylistService.instance.playlists.value = [
      MusicPlaylist.favorites(),
      MusicPlaylist.disliked(),
    ];
  });

  tearDown(() {
    Config.musicFolder = '';
    Config.musicExcludedSubfolders = [];
    Config.mp3DownloadFolder = '';
  });

  testWidgets('shows a folder picker prompt when no music folder is set',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
    await tester.pumpAndSettle();

    expect(find.text('Choose music folder'), findsOneWidget);
    expect(find.text('Library'), findsNothing);
  });

  testWidgets('shows Library/Playlists tabs once a folder is set',
      (tester) async {
    Config.musicFolder = '/does/not/matter/for/this/test';
    // Pre-populate the library so initState's "scan if empty" check finds
    // nothing to do — this test is about the tab chrome, not scanning, and
    // real directory I/O started inside initState can't complete within a
    // testWidgets fake-async zone.
    MusicLibraryService.instance.tracks.value = [
      Track.local(filePath: '/does/not/matter/song.mp3', title: 'Song'),
    ];

    await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Choose music folder'), findsNothing);
  });

  testWidgets('Playlists tab lists the two system playlists', (tester) async {
    Config.musicFolder = '/does/not/matter/for/this/test';
    MusicLibraryService.instance.tracks.value = [
      Track.local(filePath: '/does/not/matter/song.mp3', title: 'Song'),
    ];

    await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();

    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text("Don't really like"), findsOneWidget);
  });

  // `standalone: true` is what lib/main_music.dart's Best Music app passes —
  // no BestToDo drawer to reach, so its "Menu"/"Back to Home" leading
  // buttons (buildSubpageAppBar) shouldn't appear, and the Best Music-only
  // actions should.
  group('standalone (Best Music app home page)', () {
    testWidgets('shows Best Music actions instead of the drawer buttons '
        'when no folder is set yet', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: MusicPlayerPage(standalone: true)));
      await tester.pumpAndSettle();

      expect(find.text('Best Music'), findsOneWidget);
      expect(find.byTooltip('Download MP3'), findsOneWidget);
      expect(find.byTooltip('Check for updates'), findsOneWidget);
      expect(find.byTooltip('Menu'), findsNothing);
      expect(find.byTooltip('Back to Home'), findsNothing);
    });

    testWidgets('shows Best Music actions once the library is showing',
        (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      MusicLibraryService.instance.tracks.value = [
        Track.local(filePath: '/does/not/matter/song.mp3', title: 'Song'),
      ];

      await tester.pumpWidget(
          const MaterialApp(home: MusicPlayerPage(standalone: true)));
      await tester.pumpAndSettle();

      expect(find.text('Best Music'), findsOneWidget);
      expect(find.byTooltip('Download MP3'), findsOneWidget);
      expect(find.byTooltip('Check for updates'), findsOneWidget);
      expect(find.byTooltip('Menu'), findsNothing);
      expect(find.byTooltip('Back to Home'), findsNothing);
    });

    testWidgets('non-standalone (BestToDo Tools) keeps the drawer buttons '
        'and the "Music Player" title', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();

      expect(find.text('Music Player'), findsOneWidget);
      expect(find.byTooltip('Menu'), findsOneWidget);
      expect(find.byTooltip('Back to Home'), findsOneWidget);
      expect(find.byTooltip('Download MP3'), findsNothing);
      expect(find.byTooltip('Check for updates'), findsNothing);
    });
  });
}
