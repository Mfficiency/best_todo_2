import 'dart:io';

import 'package:besttodo/models/music_playlist.dart';
import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_playlist_service.dart';
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
    MusicPlaylistService.instance.resetForTest();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('load() seeds the two system playlists exactly once', () async {
    await MusicPlaylistService.instance.load();

    final ids = MusicPlaylistService.instance.playlists.value.map((p) => p.id);
    expect(ids, containsAll([MusicPlaylist.favoritesId, MusicPlaylist.dislikedId]));
    expect(MusicPlaylistService.instance.playlists.value, hasLength(2));
  });

  test('toggleFavorite adds/removes and clears any dislike on the same track',
      () async {
    await MusicPlaylistService.instance.load();
    await MusicPlaylistService.instance.markDisliked('t1');
    expect(MusicPlaylistService.instance.isDisliked('t1'), isTrue);

    await MusicPlaylistService.instance.toggleFavorite('t1');
    expect(MusicPlaylistService.instance.isFavorite('t1'), isTrue);
    expect(MusicPlaylistService.instance.isDisliked('t1'), isFalse);

    await MusicPlaylistService.instance.toggleFavorite('t1');
    expect(MusicPlaylistService.instance.isFavorite('t1'), isFalse);
  });

  test('markDisliked clears any favorite on the same track and is idempotent',
      () async {
    await MusicPlaylistService.instance.load();
    await MusicPlaylistService.instance.toggleFavorite('t2');

    await MusicPlaylistService.instance.markDisliked('t2');
    await MusicPlaylistService.instance.markDisliked('t2');

    expect(MusicPlaylistService.instance.isFavorite('t2'), isFalse);
    expect(MusicPlaylistService.instance.isDisliked('t2'), isTrue);
    expect(MusicPlaylistService.instance.disliked.trackIds, ['t2']);
  });

  test('createPlaylist adds a non-system playlist; deletePlaylist removes it',
      () async {
    await MusicPlaylistService.instance.load();

    final playlist = await MusicPlaylistService.instance
        .createPlaylist('Road trip', ['t1', 't2']);
    expect(playlist.isSystem, isFalse);
    expect(MusicPlaylistService.instance.byId(playlist.id)?.trackIds,
        ['t1', 't2']);

    await MusicPlaylistService.instance.deletePlaylist(playlist.id);
    expect(MusicPlaylistService.instance.byId(playlist.id), isNull);
  });

  test('deletePlaylist refuses to remove a system playlist', () async {
    await MusicPlaylistService.instance.load();
    await MusicPlaylistService.instance.deletePlaylist(MusicPlaylist.favoritesId);
    expect(MusicPlaylistService.instance.byId(MusicPlaylist.favoritesId),
        isNotNull);
  });

  test('state survives a resetForTest + load() round-trip', () async {
    await MusicPlaylistService.instance.load();
    await MusicPlaylistService.instance.toggleFavorite('persisted-track');

    MusicPlaylistService.instance.resetForTest();
    await MusicPlaylistService.instance.load();

    expect(MusicPlaylistService.instance.isFavorite('persisted-track'), isTrue);
  });

  group('weightedShuffle', () {
    test('weightOf reflects favorite/disliked/normal state', () async {
      await MusicPlaylistService.instance.load();
      await MusicPlaylistService.instance.toggleFavorite('fav');
      await MusicPlaylistService.instance.markDisliked('dis');

      expect(MusicPlaylistService.instance.weightOf('fav'),
          MusicPlaylistService.favoriteWeight);
      expect(MusicPlaylistService.instance.weightOf('dis'),
          MusicPlaylistService.dislikedWeight);
      expect(MusicPlaylistService.instance.weightOf('normal'),
          MusicPlaylistService.normalWeight);
    });

    test('returns every input track exactly once', () async {
      await MusicPlaylistService.instance.load();
      final tracks = [
        for (var i = 0; i < 10; i++) Track.local(filePath: '/t$i.mp3', title: 't$i'),
      ];

      final shuffled = MusicPlaylistService.instance.weightedShuffle(tracks);

      expect(shuffled.toSet(), tracks.toSet());
      expect(shuffled, hasLength(tracks.length));
    });

    test(
        'a disliked track lands later, on average, than a favorited one '
        'across many shuffles', () async {
      await MusicPlaylistService.instance.load();
      final favorite = Track.local(filePath: '/fav.mp3', title: 'fav');
      final disliked = Track.local(filePath: '/dis.mp3', title: 'dis');
      final normal = Track.local(filePath: '/normal.mp3', title: 'normal');
      await MusicPlaylistService.instance.toggleFavorite(favorite.id);
      await MusicPlaylistService.instance.markDisliked(disliked.id);
      final tracks = [favorite, disliked, normal];

      const trials = 300;
      var favoriteIndexSum = 0;
      var dislikedIndexSum = 0;
      for (var i = 0; i < trials; i++) {
        final shuffled = MusicPlaylistService.instance.weightedShuffle(tracks);
        favoriteIndexSum += shuffled.indexOf(favorite);
        dislikedIndexSum += shuffled.indexOf(disliked);
      }

      // Favorite weight (3.0) vs. disliked weight (0.05) is a 60x ratio, so
      // over 300 trials the disliked track's average position should be
      // clearly later than the favorite's — a large margin keeps this from
      // ever being flaky.
      expect(dislikedIndexSum / trials, greaterThan(favoriteIndexSum / trials));
    });
  });
}
