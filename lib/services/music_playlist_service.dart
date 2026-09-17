import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/music_playlist.dart';
import '../models/playlist_rule.dart';
import '../models/track.dart';
import 'music_library_service.dart';

/// Owns every [MusicPlaylist] — the two system playlists that back the
/// Now Playing swipe gesture (Favorites = swipe up, "Don't really like" =
/// swipe down) plus any imported or hand-made playlist — and the weighted
/// shuffle used to build a play queue from them: favorited tracks come up
/// more, disliked tracks far less (never fully excluded, so a mood can
/// still change), without ever repeating a track twice in one pass.
class MusicPlaylistService {
  MusicPlaylistService._();

  static final MusicPlaylistService instance = MusicPlaylistService._();

  static const _fileName = 'music_playlists.json';

  static const double favoriteWeight = 3.0;
  static const double dislikedWeight = 0.05;
  static const double normalWeight = 1.0;

  final ValueNotifier<List<MusicPlaylist>> playlists =
      ValueNotifier<List<MusicPlaylist>>([]);
  bool _loaded = false;
  final _random = Random();

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    List<MusicPlaylist> loaded = [];
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final List<dynamic> data = jsonDecode(await file.readAsString());
        loaded = data
            .whereType<Map>()
            .map((e) => MusicPlaylist.fromJson(Map<String, dynamic>.from(e)))
            .where((p) => p.id.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    if (loaded.where((p) => p.id == MusicPlaylist.favoritesId).isEmpty) {
      loaded.insert(0, MusicPlaylist.favorites());
    }
    if (loaded.where((p) => p.id == MusicPlaylist.dislikedId).isEmpty) {
      loaded.insert(1, MusicPlaylist.disliked());
    }
    playlists.value = loaded;
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      final jsonString =
          jsonEncode(playlists.value.map((p) => p.toJson()).toList());
      await file.writeAsString(jsonString, flush: true);
    } catch (_) {}
  }

  MusicPlaylist? byId(String id) {
    for (final p in playlists.value) {
      if (p.id == id) return p;
    }
    return null;
  }

  MusicPlaylist get favorites => byId(MusicPlaylist.favoritesId)!;
  MusicPlaylist get disliked => byId(MusicPlaylist.dislikedId)!;

  bool isFavorite(String trackId) => favorites.trackIds.contains(trackId);
  bool isDisliked(String trackId) => disliked.trackIds.contains(trackId);

  Future<void> toggleFavorite(String trackId) async {
    if (isFavorite(trackId)) {
      await removeFrom(MusicPlaylist.favoritesId, trackId);
    } else {
      await addTo(MusicPlaylist.favoritesId, trackId);
      // A track can't be both loved and disliked at once.
      await removeFrom(MusicPlaylist.dislikedId, trackId);
    }
  }

  /// Marks [trackId] as disliked (swipe-down on Now Playing). Idempotent —
  /// safe to call even if it's already in the list.
  Future<void> markDisliked(String trackId) async {
    await addTo(MusicPlaylist.dislikedId, trackId);
    await removeFrom(MusicPlaylist.favoritesId, trackId);
  }

  Future<void> addTo(String playlistId, String trackId) async {
    final playlist = byId(playlistId);
    if (playlist == null || playlist.trackIds.contains(trackId)) return;
    playlist.trackIds.add(trackId);
    playlists.value = [...playlists.value];
    await _save();
  }

  Future<void> removeFrom(String playlistId, String trackId) async {
    final playlist = byId(playlistId);
    if (playlist == null || !playlist.trackIds.remove(trackId)) return;
    playlists.value = [...playlists.value];
    await _save();
  }

  /// Creates a new (non-system) playlist, e.g. from an M3U import. Returns
  /// the created playlist.
  Future<MusicPlaylist> createPlaylist(String name, List<String> trackIds,
      {String? id}) async {
    final playlist = MusicPlaylist(
      id: id ?? 'playlist_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      trackIds: [...trackIds],
    );
    playlists.value = [...playlists.value, playlist];
    await _save();
    return playlist;
  }

  Future<void> deletePlaylist(String id) async {
    final playlist = byId(id);
    if (playlist == null || playlist.isSystem) return;
    playlists.value = playlists.value.where((p) => p.id != id).toList();
    await _save();
  }

  /// Creates a new rule-based playlist (an AND/OR/NOT [ruleSet] over track
  /// metadata, evaluated live — never a stored track list). Returns the
  /// created playlist.
  Future<MusicPlaylist> createRulePlaylist(String name, PlaylistRuleSet ruleSet,
      {String? id}) async {
    final playlist = MusicPlaylist(
      id: id ?? 'rule_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      kind: PlaylistKind.rule,
      ruleSet: ruleSet,
    );
    playlists.value = [...playlists.value, playlist];
    await _save();
    return playlist;
  }

  /// Updates an existing rule playlist's name and/or rules in place. No-op
  /// if [id] isn't a rule playlist.
  Future<void> updateRulePlaylist(String id,
      {String? name, PlaylistRuleSet? ruleSet}) async {
    final index = playlists.value.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final existing = playlists.value[index];
    if (existing.kind != PlaylistKind.rule) return;
    final updated = MusicPlaylist(
      id: existing.id,
      name: name ?? existing.name,
      kind: PlaylistKind.rule,
      ruleSet: ruleSet ?? existing.ruleSet,
    );
    final list = List<MusicPlaylist>.of(playlists.value);
    list[index] = updated;
    playlists.value = list;
    await _save();
  }

  static const String lastAddedId = 'smart_last_added';
  static const String mostPlayedId = 'smart_most_played';

  /// How many tracks a computed ("smart") playlist shows at most.
  static const int smartPlaylistLimit = 50;

  /// Built-in computed playlists — "Last Added" and "Most Played" (overall,
  /// plus one per genre present in the library). Never persisted or
  /// deletable: recomputed from [MusicLibraryService.instance.tracks] on
  /// every read, so a rescan or a finished play immediately shows up.
  List<MusicPlaylist> get smartPlaylists {
    final libraryTracks = MusicLibraryService.instance.tracks.value;
    if (libraryTracks.isEmpty) return const [];
    final lastAdded = MusicPlaylist(
      id: lastAddedId,
      name: 'Last Added',
      isSystem: true,
      kind: PlaylistKind.lastAdded,
    );
    final mostPlayed = MusicPlaylist(
      id: mostPlayedId,
      name: 'Most Played',
      isSystem: true,
      kind: PlaylistKind.mostPlayed,
    );
    final genres = libraryTracks
        .map((t) => t.genre.trim())
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final mostPlayedByGenre = [
      for (final genre in genres)
        MusicPlaylist(
          id: 'smart_most_played_$genre',
          name: 'Most Played: $genre',
          isSystem: true,
          kind: PlaylistKind.mostPlayed,
          genreFilter: genre,
        ),
    ];
    return [lastAdded, mostPlayed, ...mostPlayedByGenre];
  }

  /// The tracks a playlist currently resolves to: [MusicPlaylist.trackIds]
  /// looked up in the library for [PlaylistKind.list], or computed live for
  /// every other kind.
  List<Track> resolvedTracks(MusicPlaylist playlist) {
    final libraryTracks = MusicLibraryService.instance.tracks.value;
    switch (playlist.kind) {
      case PlaylistKind.list:
        return playlist.trackIds
            .map((id) => MusicLibraryService.instance.byId(id))
            .whereType<Track>()
            .toList();
      case PlaylistKind.lastAdded:
        final sorted = [...libraryTracks]..sort((a, b) {
            final aDate = a.dateAdded;
            final bDate = b.dateAdded;
            if (aDate == null && bDate == null) return 0;
            if (aDate == null) return 1;
            if (bDate == null) return -1;
            return bDate.compareTo(aDate);
          });
        return sorted.take(smartPlaylistLimit).toList();
      case PlaylistKind.mostPlayed:
        final genreFilter = playlist.genreFilter;
        final scoped = (genreFilter == null || genreFilter.isEmpty)
            ? libraryTracks
            : libraryTracks.where((t) => t.genre == genreFilter).toList();
        final played = scoped.where((t) => t.playCount > 0).toList()
          ..sort((a, b) => b.playCount.compareTo(a.playCount));
        return played.take(smartPlaylistLimit).toList();
      case PlaylistKind.rule:
        final ruleSet = playlist.ruleSet;
        if (ruleSet == null) return const [];
        return libraryTracks.where(ruleSet.matches).toList();
    }
  }

  double weightOf(String trackId) {
    if (isDisliked(trackId)) return dislikedWeight;
    if (isFavorite(trackId)) return favoriteWeight;
    return normalWeight;
  }

  /// Builds a shuffled play order over [source] using weighted random
  /// sampling without replacement (Efraimidis–Spirakis A-Res): each track
  /// gets a key of `random()^(1/weight)` and the result is sorted
  /// descending by key. Higher-weight tracks (favorites) tend to land
  /// earlier; lower-weight tracks (disliked) tend to land much later —
  /// every track can still appear, just far less often for disliked ones.
  List<Track> weightedShuffle(List<Track> source) {
    if (source.length <= 1) return [...source];
    final keyed = source.map((t) {
      final w = max(weightOf(t.id), 0.0001);
      final r = _random.nextDouble().clamp(0.0001, 1.0);
      final key = pow(r, 1 / w).toDouble();
      return MapEntry(key, t);
    }).toList();
    keyed.sort((a, b) => b.key.compareTo(a.key));
    return keyed.map((e) => e.value).toList();
  }

  /// Resets in-memory state (for tests).
  @visibleForTesting
  void resetForTest() {
    playlists.value = [];
    _loaded = false;
  }
}
