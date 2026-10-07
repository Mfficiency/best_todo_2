import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_audio_handler.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The handler builds a real just_audio player, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MusicLibraryService.instance.resetForTest();
    MusicPlaylistService.instance.resetForTest();
  });

  Track track(String id) =>
      Track.local(filePath: '/fake/$id.mp3', title: id);

  /// A queue of a, b, c with a current — set via [MusicAudioHandler.restore]
  /// so no audio is loaded (there's no just_audio platform in tests; loading
  /// would fail and hang the test).
  MusicAudioHandler handlerWithQueue() =>
      MusicAudioHandler()..restore([track('a'), track('b'), track('c')]);

  List<String> ids(MusicAudioHandler h) =>
      h.currentQueueTracks.map((t) => t.id).toList();

  test('reorderQueue moves a track to its new position', () {
    final handler = handlerWithQueue();

    // ReorderableListView convention (what QueuePage passes): dropping the
    // first row below the last one reports newIndex == length.
    handler.reorderQueue(0, 3);
    expect(ids(handler),
        ['local:/fake/b.mp3', 'local:/fake/c.mp3', 'local:/fake/a.mp3']);
    // The playing track keeps playing, now at its new position.
    expect(handler.currentTrack!.id, 'local:/fake/a.mp3');

    // Dropping the last row above the first: newIndex 0.
    handler.reorderQueue(2, 0);
    expect(ids(handler),
        ['local:/fake/a.mp3', 'local:/fake/b.mp3', 'local:/fake/c.mp3']);
    expect(handler.currentTrack!.id, 'local:/fake/a.mp3');
  });

  test('toggleShuffle flips shuffleEnabled and restores order on toggle off',
      () async {
    final handler = handlerWithQueue();
    final order = ids(handler);

    expect(handler.shuffleEnabled.value, isFalse);

    await handler.toggleShuffle();
    expect(handler.shuffleEnabled.value, isTrue);
    expect(ids(handler).toSet(), order.toSet());
    // Only the upcoming tail is shuffled; the playing track stays first.
    expect(ids(handler).first, order.first);

    await handler.toggleShuffle();
    expect(handler.shuffleEnabled.value, isFalse);
    expect(ids(handler), order);
  });
}
