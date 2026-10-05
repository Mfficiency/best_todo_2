import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_audio_handler.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_player_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:besttodo/ui/music_mini_player_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Back/forward 10 seconds for Subscriptions videos (SPEC.md §10.6m): in
/// the notification (and lock screen / Android media controls), Now
/// Playing and the mini player; songs keep their usual buttons.
void main() {
  late Directory tempDir;
  final video = Track.youtube(videoId: 'v1', title: 'Talk', artist: 'Ch');
  final song = Track.local(filePath: '/fake/a.mp3', title: 'a');

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

  List<MediaAction> actions(MusicAudioHandler h) =>
      [for (final c in h.playbackState.value.controls) c.action];

  test('a video gets back/forward 10 s in the notification, a song does not',
      () {
    final handler = MusicAudioHandler();
    handler.restore([video]);
    expect(actions(handler), [
      MediaAction.skipToPrevious,
      MediaAction.rewind,
      MediaAction.play,
      MediaAction.fastForward,
      MediaAction.skipToNext,
    ]);
    // Collapsed notification: back 10, play, forward 10.
    expect(handler.playbackState.value.androidCompactActionIndices, [1, 2, 3]);
    expect(handler.playbackState.value.controls[1].androidIcon,
        'drawable/ic_replay_10');
    expect(handler.playbackState.value.controls[3].label,
        'Forward 10 seconds');

    handler.restore([song]);
    expect(actions(handler), [
      MediaAction.skipToPrevious,
      MediaAction.play,
      MediaAction.skipToNext,
    ]);
    expect(handler.playbackState.value.androidCompactActionIndices, [0, 1, 2]);
  });

  test('rewind/fastForward move by 10 seconds, never before the start',
      () async {
    final handler = MusicAudioHandler();
    handler.restore([video], position: const Duration(seconds: 42));

    await handler.rewind();
    expect(handler.playbackState.value.updatePosition,
        const Duration(seconds: 32));
    await handler.fastForward();
    await handler.fastForward();
    expect(handler.playbackState.value.updatePosition,
        const Duration(seconds: 52));

    handler.restore([video], position: const Duration(seconds: 4));
    await handler.rewind();
    expect(handler.playbackState.value.updatePosition, Duration.zero);
  });

  testWidgets('the mini player shows the 10-second buttons for a video only',
      (tester) async {
    final handler = MusicAudioHandler();
    handler.restore([video], position: const Duration(seconds: 30));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MusicMiniPlayerBar(handler: handler))));

    expect(find.byTooltip('Back 10 seconds'), findsOneWidget);
    expect(find.byTooltip('Forward 10 seconds'), findsOneWidget);
    await tester.tap(find.byTooltip('Back 10 seconds'));
    await tester.pump();
    expect(handler.playbackState.value.updatePosition,
        const Duration(seconds: 20));

    handler.restore([song]);
    await tester.pump();
    expect(find.byTooltip('Back 10 seconds'), findsNothing);
    expect(find.byTooltip('Forward 10 seconds'), findsNothing);
  });
}
