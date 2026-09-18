import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/music_playlist.dart';
import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:besttodo/ui/music_player_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
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

  tearDown(() async {
    Config.musicFolder = '';
    Config.musicExcludedSubfolders = [];
    Config.mp3DownloadFolder = '';
    await tempDir.delete(recursive: true);
  });

  /// Drains a tapped handler's real file-write before its effect (a save,
  /// a sheet closing) is checked — a single runAsync delay only advances
  /// ~one I/O hop, so this loops a fixed number of rounds instead of
  /// `pumpAndSettle()`, which never resolves a real dart:io Future inside
  /// testWidgets' fake-async zone. See CLAUDE.md's "Real file I/O hangs
  /// inside testWidgets" note.
  Future<void> drainIo(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

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

  testWidgets('Metadata scan action opens the scan page', (tester) async {
    Config.musicFolder = '/does/not/matter/for/this/test';
    MusicLibraryService.instance.tracks.value = [
      Track.local(filePath: '/does/not/matter/song.mp3', title: 'Song'),
    ];

    await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Metadata scan'));
    // Not pumpAndSettle(): the scan page shows an indeterminate
    // LinearProgressIndicator while its own (real-I/O) scan runs, which
    // never settles — just confirm the navigation happened.
    await tester.pump();

    expect(find.text('Metadata Scan'), findsOneWidget);
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

  // Building a normal, hand-picked playlist the way Samsung Music does:
  // create an empty playlist, then add songs to it from the library one at
  // a time (and remove them again from the playlist itself).
  group('hand-built playlists', () {
    testWidgets('New playlist creates an empty, non-system playlist',
        (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      MusicLibraryService.instance.tracks.value = [
        Track.local(filePath: '/does/not/matter/song.mp3', title: 'Song'),
      ];

      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New playlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Road trip');
      await tester.tap(find.text('Create'));
      await drainIo(tester);

      final created = MusicPlaylistService.instance.playlists.value
          .where((p) => p.name == 'Road trip')
          .toList();
      expect(created, hasLength(1));
      expect(created.single.kind, PlaylistKind.list);
      expect(created.single.isSystem, isFalse);
      expect(created.single.trackIds, isEmpty);
    });

    testWidgets(
        "Library tab's Add to playlist sheet toggles a track's membership",
        (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      final song =
          Track.local(filePath: '/does/not/matter/song.mp3', title: 'Song');
      MusicLibraryService.instance.tracks.value = [song];
      MusicPlaylistService.instance.playlists.value = [
        MusicPlaylist.favorites(),
        MusicPlaylist.disliked(),
        MusicPlaylist(id: 'p1', name: 'Road trip'),
      ];

      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to playlist'));
      await tester.pumpAndSettle();

      expect(find.text('Road trip'), findsOneWidget);
      await tester.tap(find.text('Road trip'));
      await drainIo(tester);

      expect(MusicPlaylistService.instance.byId('p1')!.trackIds, [song.id]);
    });

    testWidgets(
        'playlist detail page removes a track when its remove button is tapped',
        (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      final song =
          Track.local(filePath: '/does/not/matter/song.mp3', title: 'Song');
      MusicLibraryService.instance.tracks.value = [song];
      MusicPlaylistService.instance.playlists.value = [
        MusicPlaylist.favorites(),
        MusicPlaylist.disliked(),
        MusicPlaylist(id: 'p1', name: 'Road trip', trackIds: [song.id]),
      ];

      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Road trip'));
      await tester.pumpAndSettle();

      expect(find.text('Song'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove from playlist'));
      await drainIo(tester);
      await tester.pumpAndSettle();

      expect(MusicPlaylistService.instance.byId('p1')!.trackIds, isEmpty);
      expect(find.text('No tracks in this playlist yet.'), findsOneWidget);
    });

    testWidgets(
        'favorites/disliked and smart playlists never show a remove button',
        (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      final song =
          Track.local(filePath: '/does/not/matter/song.mp3', title: 'Song');
      MusicLibraryService.instance.tracks.value = [song];
      MusicPlaylistService.instance.playlists.value = [
        MusicPlaylist.favorites()..trackIds.add(song.id),
        MusicPlaylist.disliked(),
      ];

      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();

      expect(find.text('Song'), findsOneWidget);
      expect(find.byTooltip('Remove from playlist'), findsNothing);
    });
  });
}
