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
}
