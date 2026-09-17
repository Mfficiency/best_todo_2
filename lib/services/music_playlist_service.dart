import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/music_playlist.dart';
import '../models/track.dart';

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
