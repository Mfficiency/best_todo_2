import 'package:besttodo/config.dart';
import 'package:besttodo/models/music_playlist.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_player_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:besttodo/ui/now_playing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    Config.musicFolder = '';
    Config.musicExcludedSubfolders = [];
    Config.mp3DownloadFolder = '';
    MusicLibraryService.instance.resetForTest();
    MusicPlaylistService.instance.resetForTest();
    MusicPlaylistService.instance.playlists.value = [
      MusicPlaylist.favorites(),
      MusicPlaylist.disliked(),
    ];
    if (!MusicPlayerService.isReady) {
      await MusicPlayerService.init();
    }
  });

  testWidgets('shows shuffle and queue buttons in the app bar',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NowPlayingPage()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Shuffle off'), findsOneWidget);
    expect(find.byTooltip('Queue'), findsOneWidget);
  });

  testWidgets('shows a Track info button, disabled while nothing is playing',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NowPlayingPage()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Track info'), findsOneWidget);
    final button = tester.widget<IconButton>(find.byTooltip('Track info'));
    expect(button.onPressed, isNull);
  });

  testWidgets('tapping shuffle toggles it on and off', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NowPlayingPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Shuffle off'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Shuffle on'), findsOneWidget);

    await tester.tap(find.byTooltip('Shuffle on'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Shuffle off'), findsOneWidget);
  });

  testWidgets('tapping the queue button opens the Queue page',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NowPlayingPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Queue'));
    await tester.pumpAndSettle();

    expect(find.text('Queue is empty'), findsOneWidget);
  });
}
