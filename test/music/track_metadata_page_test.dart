import 'dart:io';

import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/ui/track_metadata_page.dart';
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
    MusicLibraryService.instance.resetForTest();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// Drains a real file-write the tapped handler awaits before popping —
  /// a single runAsync delay only advances ~one I/O hop, so this loops a
  /// fixed number of rounds instead of `pumpAndSettle()`. Same pattern used
  /// throughout test/music for a save-on-tap handler (CLAUDE.md's "Real
  /// file I/O hangs inside testWidgets" note).
  Future<void> drainIo(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<void> pushPage(WidgetTester tester, String trackId) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TrackMetadataPage(trackId: trackId),
          )),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the track\'s current metadata and read-only info',
      (tester) async {
    final track = Track.local(
      filePath: '/music/song.mp3',
      title: 'My Song',
      artist: 'My Artist',
      album: 'My Album',
      genre: 'Rock',
      year: 2020,
      durationMs: 125000,
      playCount: 3,
    );
    MusicLibraryService.instance.tracks.value = [track];

    await pushPage(tester, track.id);

    expect(find.text('My Song'), findsOneWidget);
    expect(find.text('My Artist'), findsOneWidget);
    expect(find.text('My Album'), findsOneWidget);
    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('2020'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // play count
    expect(find.text('2:05'), findsOneWidget); // duration
  });

  testWidgets('shows "Track not found" for an unknown id', (tester) async {
    await pushPage(tester, 'local:/nope.mp3');

    expect(find.text('Track not found.'), findsOneWidget);
  });

  testWidgets('editing and saving fills in missing metadata and marks it edited',
      (tester) async {
    final track = Track.local(filePath: '/music/song.mp3', title: 'Untagged');
    MusicLibraryService.instance.tracks.value = [track];

    await pushPage(tester, track.id);
    await tester.enterText(find.widgetWithText(TextField, 'Genre'), 'Jazz');
    await tester.enterText(find.widgetWithText(TextField, 'Year'), '1999');
    await tester.tap(find.byTooltip('Save'));
    await drainIo(tester);

    final updated = MusicLibraryService.instance.byId(track.id)!;
    expect(updated.genre, 'Jazz');
    expect(updated.year, 1999);
    expect(updated.metadataEdited, isTrue);
    // The page popped back to the dummy route.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a non-numeric year shows an error and does not save',
      (tester) async {
    final track = Track.local(filePath: '/music/song.mp3', title: 'Untagged');
    MusicLibraryService.instance.tracks.value = [track];

    await pushPage(tester, track.id);
    await tester.enterText(find.widgetWithText(TextField, 'Year'), 'not a year');
    await tester.tap(find.byTooltip('Save'));
    await tester.pump();

    expect(find.text('Year must be a number, e.g. 2021'), findsOneWidget);
    expect(MusicLibraryService.instance.byId(track.id)!.metadataEdited, isFalse);
  });
}
