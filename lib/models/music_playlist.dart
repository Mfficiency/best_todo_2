import 'playlist_rule.dart';

/// What kind of playlist a [MusicPlaylist] is, and so where its track list
/// comes from.
enum PlaylistKind {
  /// A fixed, stored [MusicPlaylist.trackIds] list — the two system
  /// playlists (Favorites/"Don't really like"), an M3U import, or a plain
  /// hand-built playlist.
  list,

  /// Computed on the fly: the most recently added tracks in the library.
  /// Never persisted (see [MusicPlaylistService.smartPlaylists]).
  lastAdded,

  /// Computed on the fly: tracks with the highest [Track.playCount],
  /// optionally scoped to [MusicPlaylist.genreFilter]. Never persisted.
  mostPlayed,

  /// Computed on the fly from [MusicPlaylist.ruleSet] — a manually built
  /// AND/OR/NOT rule set over track metadata.
  rule,
}

/// A named playlist — either a fixed ordered list of [Track] ids
/// ([PlaylistKind.list]) or one computed live from the library
/// ([PlaylistKind.lastAdded]/[PlaylistKind.mostPlayed]/[PlaylistKind.rule]).
///
/// Two [PlaylistKind.list] playlists are "system" playlists that always
/// exist and can't be deleted or renamed: [MusicPlaylist.favoritesId]
/// (swipe up on Now Playing) and [MusicPlaylist.dislikedId] (swipe down —
/// skips the song and makes it far less likely to come up again in
/// shuffle). The built-in smart playlists ([MusicPlaylistService.smartPlaylists])
/// are also system playlists but are never persisted here; every other
/// playlist — imported from an M3U/M3U8 file, hand-built, or a rule
/// playlist — is a normal, deletable entry.
class MusicPlaylist {
  static const String favoritesId = 'favorites';
  static const String dislikedId = 'disliked';

  final String id;
  String name;
  List<String> trackIds;
  final bool isSystem;
  final PlaylistKind kind;

  /// For [PlaylistKind.mostPlayed]: restricts to tracks whose [Track.genre]
  /// matches exactly. Null/empty means "most played across the whole
  /// library".
  final String? genreFilter;

  /// For [PlaylistKind.rule]: the AND/OR/NOT conditions to match against
  /// the library. Null for every other [kind].
  final PlaylistRuleSet? ruleSet;

  MusicPlaylist({
    required this.id,
    required this.name,
    List<String>? trackIds,
    this.isSystem = false,
    this.kind = PlaylistKind.list,
    this.genreFilter,
    this.ruleSet,
  }) : trackIds = trackIds ?? [];

  factory MusicPlaylist.favorites() => MusicPlaylist(
        id: favoritesId,
        name: 'Favorites',
        isSystem: true,
      );

  factory MusicPlaylist.disliked() => MusicPlaylist(
        id: dislikedId,
        name: "Don't really like",
        isSystem: true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'isSystem': isSystem,
        'kind': kind.name,
        if (genreFilter != null) 'genreFilter': genreFilter,
        if (ruleSet != null) 'ruleSet': ruleSet!.toJson(),
      };

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    final rawIds = json['trackIds'];
    final rawRuleSet = json['ruleSet'];
    return MusicPlaylist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      trackIds: rawIds is List ? rawIds.whereType<String>().toList() : [],
      isSystem: json['isSystem'] as bool? ?? false,
      kind: PlaylistKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => PlaylistKind.list,
      ),
      genreFilter: json['genreFilter'] as String?,
      ruleSet: rawRuleSet is Map
          ? PlaylistRuleSet.fromJson(Map<String, dynamic>.from(rawRuleSet))
          : null,
    );
  }
}
