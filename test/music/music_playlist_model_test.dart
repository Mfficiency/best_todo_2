import 'package:besttodo/models/music_playlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MusicPlaylist', () {
    test('favorites()/disliked() build the fixed system playlists', () {
      final favorites = MusicPlaylist.favorites();
      final disliked = MusicPlaylist.disliked();

      expect(favorites.id, MusicPlaylist.favoritesId);
      expect(favorites.isSystem, isTrue);
      expect(favorites.trackIds, isEmpty);

      expect(disliked.id, MusicPlaylist.dislikedId);
      expect(disliked.isSystem, isTrue);
    });

    test('toJson/fromJson round-trips', () {
      final playlist = MusicPlaylist(
        id: 'p1',
        name: 'Road trip',
        trackIds: ['local:/a.mp3', 'local:/b.mp3'],
      );

      final restored = MusicPlaylist.fromJson(playlist.toJson());

      expect(restored.id, 'p1');
      expect(restored.name, 'Road trip');
      expect(restored.trackIds, ['local:/a.mp3', 'local:/b.mp3']);
      expect(restored.isSystem, isFalse);
    });

    test('fromJson tolerates a missing/non-list trackIds', () {
      final restored = MusicPlaylist.fromJson({'id': 'p2', 'name': 'Empty'});
      expect(restored.trackIds, isEmpty);
    });
  });
}
