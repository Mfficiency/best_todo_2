import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_audio_handler.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MusicLibraryService.instance.resetForTest();
    MusicPlaylistService.instance.resetForTest();
  });

  Track track(String id) =>
      Track.local(filePath: '/fake/$id.mp3', title: id);

  test('reorderQueue moves a track to its new position', () async {
    final handler = MusicAudioHandler();
    await handler.setQueueAndPlay([track('a'), track('b'), track('c')]);

    handler.reorderQueue(0, 2);

    expect(
      handler.currentQueueTracks.map((t) => t.id).toList(),
      ['local:/fake/b.mp3', 'local:/fake/c.mp3', 'local:/fake/a.mp3'],
    );
  });

  test('toggleShuffle flips shuffleEnabled and restores order on toggle off',
      () async {
    final handler = MusicAudioHandler();
    await handler.setQueueAndPlay([track('a'), track('b'), track('c')]);
    // Move the currently-playing track to the front so there's an upcoming
    // tail left for shuffle to actually reorder.
    handler.reorderQueue(handler.currentQueueTracks.length - 1, 0);
    final order = handler.currentQueueTracks.map((t) => t.id).toList();

    expect(handler.shuffleEnabled.value, isFalse);

    await handler.toggleShuffle();
    expect(handler.shuffleEnabled.value, isTrue);
    expect(
      handler.currentQueueTracks.map((t) => t.id).toSet(),
      order.toSet(),
    );

    await handler.toggleShuffle();
    expect(handler.shuffleEnabled.value, isFalse);
    expect(handler.currentQueueTracks.map((t) => t.id).toList(), order);
  });
}
