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
  // it is the app's root/home page, so it gets a real Drawer (like
  // BestToDo's own home page) instead of buildSubpageAppBar's
  // "Menu"/"Back to Home" leading buttons, which have no drawer to open here.
  group('standalone (Best Music app home page)', () {
    testWidgets('has a drawer button instead of Menu/Back to Home, '
        'even before a folder is set', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: MusicPlayerPage(standalone: true)));
      await tester.pumpAndSettle();

      expect(find.text('Best Music'), findsOneWidget);
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      expect(find.byTooltip('Menu'), findsNothing);
      expect(find.byTooltip('Back to Home'), findsNothing);
    });

    testWidgets('drawer lists Downloader, Settings, Changelog, Startup '
        'Times, App Logs and About', (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      MusicLibraryService.instance.tracks.value = [
        Track.local(filePath: '/does/not/matter/song.mp3', title: 'Song'),
      ];

      await tester.pumpWidget(
          const MaterialApp(home: MusicPlayerPage(standalone: true)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Best Music v'), findsOneWidget);
      expect(find.text('MP3 Downloader'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Changelog'), findsOneWidget);
      expect(find.text('Startup Times'), findsOneWidget);
      expect(find.text('App Logs'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
    });

    testWidgets('tapping Settings in the drawer opens MusicSettingsPage',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: MusicPlayerPage(standalone: true)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Music folder'), findsOneWidget);
    });

    testWidgets('non-standalone (BestToDo Tools) keeps the Menu/Back to '
        'Home buttons and the "Music Player" title', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();

      expect(find.text('Music Player'), findsOneWidget);
      expect(find.byTooltip('Menu'), findsOneWidget);
      expect(find.byTooltip('Back to Home'), findsOneWidget);
      expect(find.byTooltip('Open navigation menu'), findsNothing);
    });
  });
}
