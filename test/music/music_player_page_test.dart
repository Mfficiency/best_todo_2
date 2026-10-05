import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/main_music.dart';
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
    Config.musicTrackSortField = 'deviceDate';
    Config.musicTrackSortAscending = false;
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
    expect(find.text('Tracks'), findsNothing);
  });

  testWidgets(
      'shows Favourites/Playlists/Tracks/Artists/Tags/Folders tabs once a folder is set',
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

    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Tracks'), findsOneWidget);
    expect(find.text('Artists'), findsOneWidget);
    expect(find.text('Tags'), findsOneWidget);
    expect(find.text('Folders'), findsOneWidget);
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
  testWidgets(
      'Best Music keeps every page clear of the system navigation bar '
      '(edge-to-edge inset), like BestToDo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(bottom: 144);
    tester.view.viewPadding = const FakeViewPadding(bottom: 144);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BestMusicApp());
    await tester.pumpAndSettle();

    // 2400/3 = 800 logical px tall; the 48 px navigation bar is excluded.
    expect(tester.getBottomLeft(find.byType(Scaffold).first).dy, 800 - 48);
  });

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

      // Sections start collapsed behind their section buttons.
      expect(find.widgetWithText(ChoiceChip, 'Library'), findsOneWidget);
      await tester.tap(find.byTooltip('Expand Library'));
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
        "Tracks tab's more-options menu Add to playlist toggles a track's membership",
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
      // Favourites is the default initial tab, and this track isn't
      // favorited — switch to Tracks to find its row.
      await tester.tap(find.text('Tracks'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to playlist'));
      await tester.pumpAndSettle();

      expect(find.text('Road trip'), findsOneWidget);
      await tester.tap(find.text('Road trip'));
      await drainIo(tester);

      expect(MusicPlaylistService.instance.byId('p1')!.trackIds, [song.id]);
    });

    testWidgets(
        'playlist detail page removes a track via the more-options menu',
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
      // Below the New/Rule/Songs by BPM rows and the smart playlists.
      await tester.dragUntilVisible(find.text('Road trip'),
          find.byType(ListView).last, const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Road trip'));
      await tester.pumpAndSettle();

      expect(find.text('Song'), findsOneWidget);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from playlist'));
      await drainIo(tester);
      await tester.pumpAndSettle();

      expect(MusicPlaylistService.instance.byId('p1')!.trackIds, isEmpty);
      expect(find.text('No tracks in this playlist yet.'), findsOneWidget);
    });

    testWidgets(
        'favorites/disliked and smart playlists never offer Remove from playlist',
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
      // Favorites is a system playlist — no "+" add-songs button either.
      expect(find.byTooltip('Add songs'), findsNothing);
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      expect(find.text('Remove from playlist'), findsNothing);
    });

    testWidgets(
        "playlist detail page's + button adds selected songs in one go",
        (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      final song1 =
          Track.local(filePath: '/does/not/matter/song1.mp3', title: 'Song 1');
      final song2 =
          Track.local(filePath: '/does/not/matter/song2.mp3', title: 'Song 2');
      MusicLibraryService.instance.tracks.value = [song1, song2];
      MusicPlaylistService.instance.playlists.value = [
        MusicPlaylist.favorites(),
        MusicPlaylist.disliked(),
        MusicPlaylist(id: 'p1', name: 'Road trip'),
      ];

      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Playlists'));
      await tester.pumpAndSettle();
      // Below the New/Rule/Songs by BPM rows and the smart playlists.
      await tester.dragUntilVisible(find.text('Road trip'),
          find.byType(ListView).last, const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Road trip'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Add songs'), findsOneWidget);
      await tester.tap(find.byTooltip('Add songs'));
      await tester.pumpAndSettle();

      expect(find.text('Song 1'), findsOneWidget);
      expect(find.text('Song 2'), findsOneWidget);
      await tester.tap(find.text('Song 1'));
      await tester.tap(find.text('Song 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add selected'));
      await drainIo(tester);
      await tester.pumpAndSettle();

      expect(MusicPlaylistService.instance.byId('p1')!.trackIds,
          containsAll([song1.id, song2.id]));
    });
  });

  group('Favourites/Artists/Tags/Folders tabs', () {
    testWidgets('Favourites tab shows only favorited tracks', (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      final loved =
          Track.local(filePath: '/does/not/matter/loved.mp3', title: 'Loved');
      final other =
          Track.local(filePath: '/does/not/matter/other.mp3', title: 'Other');
      MusicLibraryService.instance.tracks.value = [loved, other];
      MusicPlaylistService.instance.playlists.value = [
        MusicPlaylist.favorites()..trackIds.add(loved.id),
        MusicPlaylist.disliked(),
      ];

      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favourites'));
      await tester.pumpAndSettle();

      expect(find.text('Loved'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
    });

    testWidgets('Artists tab groups tracks by artist and drills in',
        (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      MusicLibraryService.instance.tracks.value = [
        Track.local(
            filePath: '/does/not/matter/a.mp3', title: 'Song A', artist: 'Alice'),
        Track.local(
            filePath: '/does/not/matter/b.mp3', title: 'Song B', artist: 'Alice'),
        Track.local(filePath: '/does/not/matter/c.mp3', title: 'Song C'),
      ];

      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('2 tracks'), findsOneWidget);
      expect(find.text('Unknown artist'), findsOneWidget);

      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(find.text('Song A'), findsOneWidget);
      expect(find.text('Song B'), findsOneWidget);
      expect(find.text('Song C'), findsNothing);
    });

    testWidgets(
        'Artists tab groups a "feat." credit under its main artist and shows who\'s featured',
        (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      MusicLibraryService.instance.tracks.value = [
        Track.local(
            filePath: '/does/not/matter/a.mp3',
            title: 'Song A',
            artist: '49th & Main'),
        Track.local(
            filePath: '/does/not/matter/b.mp3',
            title: 'Song B',
            artist: '49th & Main feat. SKYLAR'),
      ];

      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();

      expect(find.text('49th & Main'), findsOneWidget);
      expect(find.text('2 tracks'), findsOneWidget);
      expect(find.text('feat. SKYLAR'), findsOneWidget);

      await tester.tap(find.text('49th & Main'));
      await tester.pumpAndSettle();

      expect(find.text('Song A'), findsOneWidget);
      expect(find.text('Song B'), findsOneWidget);
    });

    testWidgets('Tags tab groups tracks by tag, a multi-tagged track appearing under each',
        (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      MusicLibraryService.instance.tracks.value = [
        Track.local(
            filePath: '/does/not/matter/a.mp3',
            title: 'Song A',
            tags: ['Wedding songs', 'Belgian Top Charts']),
        Track.local(filePath: '/does/not/matter/b.mp3', title: 'Song B'),
      ];

      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();

      expect(find.text('Wedding songs'), findsOneWidget);
      expect(find.text('Belgian Top Charts'), findsOneWidget);
      expect(find.text('Untagged'), findsOneWidget);

      await tester.tap(find.text('Wedding songs'));
      await tester.pumpAndSettle();

      expect(find.text('Song A'), findsOneWidget);
      expect(find.text('Song B'), findsNothing);
    });

    testWidgets('Folders tab groups tracks by their folder and drills in',
        (tester) async {
      Config.musicFolder = '/music';
      MusicLibraryService.instance.tracks.value = [
        Track.local(filePath: '/music/Road Trip/song1.mp3', title: 'Song 1'),
        Track.local(filePath: '/music/Road Trip/song2.mp3', title: 'Song 2'),
        Track.local(filePath: '/music/root.mp3', title: 'Root song'),
      ];

      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Folders'));
      await tester.pumpAndSettle();

      expect(find.text('Road Trip'), findsOneWidget);
      expect(find.text('(Music folder)'), findsOneWidget);

      await tester.tap(find.text('Road Trip'));
      await tester.pumpAndSettle();

      expect(find.text('Song 1'), findsOneWidget);
      expect(find.text('Song 2'), findsOneWidget);
      expect(find.text('Root song'), findsNothing);
    });
  });

  group('track sorting', () {
    final tracks = [
      Track.local(
          filePath: '/m/b.mp3',
          title: 'Bravo',
          artist: 'Zed',
          durationMs: 200000,
          dateAdded: DateTime(2026, 2, 1),
          deviceDate: DateTime(2024, 1, 1)),
      Track.local(
          filePath: '/m/a.mp3',
          title: 'alpha',
          artist: 'Mia',
          durationMs: 300000,
          dateAdded: DateTime(2026, 3, 1),
          deviceDate: DateTime(2025, 1, 1)),
      Track.local(
          filePath: '/m/c.mp3',
          title: 'Charlie',
          artist: 'Abe',
          durationMs: 100000,
          dateAdded: DateTime(2026, 1, 1),
          deviceDate: DateTime(2023, 1, 1)),
      Track.local(filePath: '/m/d.mp3', title: 'Delta', artist: 'Kim'),
    ];
    List<String> titles(List<Track> list) => [for (final t in list) t.title];

    test('every field sorts both ascending and descending', () {
      expect(titles(sortTracks(tracks, TrackSortField.title, ascending: true)),
          ['alpha', 'Bravo', 'Charlie', 'Delta']);
      expect(titles(sortTracks(tracks, TrackSortField.title, ascending: false)),
          ['Delta', 'Charlie', 'Bravo', 'alpha']);
      expect(titles(sortTracks(tracks, TrackSortField.artist, ascending: true)),
          ['Charlie', 'Delta', 'alpha', 'Bravo']);
      expect(titles(sortTracks(tracks, TrackSortField.artist, ascending: false)),
          ['Bravo', 'alpha', 'Delta', 'Charlie']);
      expect(
          titles(sortTracks(tracks, TrackSortField.duration, ascending: true)),
          ['Delta', 'Charlie', 'Bravo', 'alpha']);
      expect(
          titles(sortTracks(tracks, TrackSortField.duration, ascending: false)),
          ['alpha', 'Bravo', 'Charlie', 'Delta']);
      // A track with no date added stays last either way.
      expect(
          titles(sortTracks(tracks, TrackSortField.dateAdded, ascending: true)),
          ['Charlie', 'Bravo', 'alpha', 'Delta']);
      expect(
          titles(
              sortTracks(tracks, TrackSortField.dateAdded, ascending: false)),
          ['alpha', 'Bravo', 'Charlie', 'Delta']);
    });

    test('"Added to device" sorts by the file date, not the app scan date',
        () {
      final onDevice = [
        Track.local(
            filePath: '/m/old.mp3',
            title: 'Old file, scanned late',
            dateAdded: DateTime(2026, 9, 1),
            deviceDate: DateTime(2020, 1, 1)),
        Track.local(
            filePath: '/m/new.mp3',
            title: 'New file, scanned early',
            dateAdded: DateTime(2026, 1, 1),
            deviceDate: DateTime(2025, 1, 1)),
      ];
      expect(
          titles(sortTracks(onDevice, TrackSortField.deviceDate,
              ascending: false)),
          ['New file, scanned early', 'Old file, scanned late']);
      expect(
          titles(sortTracks(onDevice, TrackSortField.dateAdded,
              ascending: false)),
          ['Old file, scanned late', 'New file, scanned early']);
      expect(trackSectionLabel(onDevice[0], TrackSortField.deviceDate),
          'Jan 2020');
      expect(trackSectionLabel(onDevice[0], TrackSortField.dateAdded),
          'Sep 2026');
    });

    test('section labels follow the sort field', () {
      expect(trackSectionLabel(tracks[1], TrackSortField.title), 'A');
      expect(trackSectionLabel(tracks[0], TrackSortField.artist), 'Z');
      expect(trackSectionLabel(tracks[0], TrackSortField.dateAdded), 'Feb 2026');
      expect(trackSectionLabel(tracks[1], TrackSortField.duration), '5 min');
      expect(
          trackSectionLabel(
              Track.local(filePath: '/m/1.mp3', title: '1999'),
              TrackSortField.title),
          '#');
    });

    testWidgets('direction button and re-picking a field flip the order',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TrackListView(tracks: tracks))));
      await tester.pumpAndSettle();

      double y(String text) => tester.getTopLeft(find.text(text)).dy;
      // Default: added to device, newest first.
      expect(find.text('Added to device'), findsOneWidget);
      expect(find.text('Newest first'), findsOneWidget);
      expect(y('alpha'), lessThan(y('Charlie')));

      await tester.tap(find.byKey(const ValueKey('sortDirectionButton')));
      await tester.pumpAndSettle();
      expect(find.text('Oldest first'), findsOneWidget);
      expect(y('Charlie'), lessThan(y('alpha')));
      expect(Config.musicTrackSortAscending, isTrue);

      // Picking Title starts A–Z; picking it again flips to Z–A.
      await tester.tap(find.byTooltip('Sort tracks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title').last);
      await tester.pumpAndSettle();
      expect(find.text('A–Z'), findsOneWidget);
      expect(y('alpha'), lessThan(y('Delta')));
      expect(Config.musicTrackSortField, 'title');

      await tester.tap(find.byTooltip('Sort tracks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title').last);
      await tester.pumpAndSettle();
      expect(find.text('Z–A'), findsOneWidget);
      expect(y('Delta'), lessThan(y('alpha')));
    });

    testWidgets('a long list gets a fast-scroll handle that jumps to the end',
        (tester) async {
      final many = [
        for (var i = 0; i < 200; i++)
          Track.local(
              filePath: '/m/$i.mp3',
              title: 'Song ${i.toString().padLeft(3, '0')}'),
      ];
      Config.musicTrackSortField = 'title';
      Config.musicTrackSortAscending = true;
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TrackListView(tracks: many))));
      await tester.pumpAndSettle();

      expect(find.text('Song 000'), findsOneWidget);
      final handle = find.byKey(const ValueKey('fastScrollHandle'));
      expect(handle, findsOneWidget);

      final box = tester.getRect(handle);
      final gesture = await tester.startGesture(box.topCenter + const Offset(0, 30));
      await tester.pump();
      await gesture.moveTo(box.bottomCenter - const Offset(0, 2));
      await tester.pump();
      // Dragging shows the bubble for the row now on top.
      expect(find.textContaining('S'), findsWidgets);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Song 000'), findsNothing);
      expect(find.text('Song 199'), findsOneWidget);
    });

    testWidgets('a short list has no fast-scroll handle', (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: TrackListView(tracks: tracks))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fastScrollHandle')), findsNothing);
    });
  });

  group('search', () {
    testWidgets('search icon filters tracks by title/artist and plays a result',
        (tester) async {
      Config.musicFolder = '/does/not/matter/for/this/test';
      MusicLibraryService.instance.tracks.value = [
        Track.local(
            filePath: '/does/not/matter/a.mp3', title: 'Bohemian Rhapsody', artist: 'Queen'),
        Track.local(filePath: '/does/not/matter/b.mp3', title: 'Yesterday', artist: 'The Beatles'),
      ];

      await tester.pumpWidget(const MaterialApp(home: MusicPlayerPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search music'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'queen');
      await tester.pumpAndSettle();

      expect(find.text('Bohemian Rhapsody'), findsOneWidget);
      expect(find.text('Yesterday'), findsNothing);
    });
  });
}
