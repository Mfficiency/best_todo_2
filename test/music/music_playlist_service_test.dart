import 'dart:io';

import 'package:besttodo/models/music_playlist.dart';
import 'package:besttodo/models/playlist_rule.dart';
import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_library_service.dart';
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
    MusicLibraryService.instance.resetForTest();
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

  test('addAllTo adds every new id in one batch, skipping ones already present',
      () async {
    await MusicPlaylistService.instance.load();
    final playlist =
        await MusicPlaylistService.instance.createPlaylist('Road trip', ['t1']);

    await MusicPlaylistService.instance
        .addAllTo(playlist.id, ['t1', 't2', 't3']);

    expect(MusicPlaylistService.instance.byId(playlist.id)?.trackIds,
        ['t1', 't2', 't3']);
  });

  test('addAllTo is a no-op for an unknown playlist id', () async {
    await MusicPlaylistService.instance.load();
    await MusicPlaylistService.instance.addAllTo('nope', ['t1']);
    expect(MusicPlaylistService.instance.byId('nope'), isNull);
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

  group('resolvedTracks', () {
    Track track(String id,
            {String genre = '', int? year, DateTime? dateAdded, int playCount = 0}) =>
        Track.local(
          filePath: '/$id.mp3',
          title: id,
          genre: genre,
          year: year,
          dateAdded: dateAdded,
          playCount: playCount,
        );

    test('a list playlist resolves trackIds against the library, dropping missing ids',
        () async {
      await MusicPlaylistService.instance.load();
      final a = track('a');
      MusicLibraryService.instance.tracks.value = [a];
      final playlist =
          await MusicPlaylistService.instance.createPlaylist('Mix', [a.id, 'local:/gone.mp3']);

      final resolved = MusicPlaylistService.instance.resolvedTracks(playlist);

      expect(resolved, [a]);
    });

    test('lastAdded sorts newest-dateAdded first', () async {
      final older = track('a', dateAdded: DateTime(2020));
      final newer = track('b', dateAdded: DateTime(2024));
      MusicLibraryService.instance.tracks.value = [older, newer];
      final playlist = MusicPlaylist(
          id: MusicPlaylistService.lastAddedId, name: 'Last Added', kind: PlaylistKind.lastAdded);

      final resolved = MusicPlaylistService.instance.resolvedTracks(playlist);

      expect(resolved, [newer, older]);
    });

    test('mostPlayed sorts by playCount and drops never-played tracks', () async {
      final popular = track('a', playCount: 10);
      final unplayed = track('b', playCount: 0);
      final lessPopular = track('c', playCount: 2);
      MusicLibraryService.instance.tracks.value = [popular, unplayed, lessPopular];
      final playlist = MusicPlaylist(
          id: MusicPlaylistService.mostPlayedId, name: 'Most Played', kind: PlaylistKind.mostPlayed);

      final resolved = MusicPlaylistService.instance.resolvedTracks(playlist);

      expect(resolved, [popular, lessPopular]);
    });

    test('mostPlayed with a genreFilter only considers that genre', () async {
      final rock = track('a', genre: 'Rock', playCount: 5);
      final pop = track('b', genre: 'Pop', playCount: 5);
      MusicLibraryService.instance.tracks.value = [rock, pop];
      final playlist = MusicPlaylist(
        id: 'smart_most_played_Rock',
        name: 'Most Played: Rock',
        kind: PlaylistKind.mostPlayed,
        genreFilter: 'Rock',
      );

      final resolved = MusicPlaylistService.instance.resolvedTracks(playlist);

      expect(resolved, [rock]);
    });

    test('a rule playlist evaluates its ruleSet against the library', () async {
      final rock = track('a', genre: 'Rock');
      final pop = track('b', genre: 'Pop');
      MusicLibraryService.instance.tracks.value = [rock, pop];
      final playlist = MusicPlaylist(
        id: 'rule1',
        name: 'Rock only',
        kind: PlaylistKind.rule,
        ruleSet: const PlaylistRuleSet(conditions: [
          RuleCondition(field: RuleField.genre, operator: RuleOperator.equals, values: ['Rock']),
        ]),
      );

      final resolved = MusicPlaylistService.instance.resolvedTracks(playlist);

      expect(resolved, [rock]);
    });
  });

  group('smartPlaylists', () {
    test('is empty when the library is empty', () async {
      MusicLibraryService.instance.tracks.value = [];
      expect(MusicPlaylistService.instance.smartPlaylists, isEmpty);
    });

    test('includes Last Added, an overall Most Played, and one per genre', () async {
      MusicLibraryService.instance.tracks.value = [
        Track.local(filePath: '/a.mp3', title: 'a', genre: 'Rock'),
        Track.local(filePath: '/b.mp3', title: 'b', genre: 'Pop'),
        Track.local(filePath: '/c.mp3', title: 'c'), // no genre
      ];

      final names = MusicPlaylistService.instance.smartPlaylists.map((p) => p.name).toList();

      expect(names, ['Last Added', 'Most Played', 'Most Played: Pop', 'Most Played: Rock']);
    });
  });

  group('rule playlists', () {
    test('createRulePlaylist adds a deletable, non-system rule playlist', () async {
      await MusicPlaylistService.instance.load();
      const ruleSet = PlaylistRuleSet(conditions: [
        RuleCondition(field: RuleField.genre, operator: RuleOperator.equals, values: ['Rock']),
      ]);

      final playlist =
          await MusicPlaylistService.instance.createRulePlaylist('Rock only', ruleSet);

      expect(playlist.kind, PlaylistKind.rule);
      expect(playlist.isSystem, isFalse);
      expect(MusicPlaylistService.instance.byId(playlist.id)?.ruleSet?.conditions, hasLength(1));
    });

    test('updateRulePlaylist replaces name/ruleSet in place', () async {
      await MusicPlaylistService.instance.load();
      const originalRules = PlaylistRuleSet(conditions: [
        RuleCondition(field: RuleField.genre, operator: RuleOperator.equals, values: ['Rock']),
      ]);
      final playlist =
          await MusicPlaylistService.instance.createRulePlaylist('Rock only', originalRules);
      const newRules = PlaylistRuleSet(conditions: [
        RuleCondition(field: RuleField.genre, operator: RuleOperator.equals, values: ['Jazz']),
      ]);

      await MusicPlaylistService.instance
          .updateRulePlaylist(playlist.id, name: 'Jazz only', ruleSet: newRules);

      final updated = MusicPlaylistService.instance.byId(playlist.id)!;
      expect(updated.name, 'Jazz only');
      expect(updated.ruleSet!.conditions.first.values, ['Jazz']);
    });

    test('a rule playlist can be deleted like any other', () async {
      await MusicPlaylistService.instance.load();
      final playlist = await MusicPlaylistService.instance
          .createRulePlaylist('Temp', const PlaylistRuleSet());

      await MusicPlaylistService.instance.deletePlaylist(playlist.id);

      expect(MusicPlaylistService.instance.byId(playlist.id), isNull);
    });
  });
}
