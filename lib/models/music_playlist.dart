/// A named ordered list of [Track] ids.
///
/// Two playlists are "system" playlists that always exist and can't be
/// deleted or renamed: [MusicPlaylist.favoritesId] (swipe up on Now
/// Playing) and [MusicPlaylist.dislikedId] (swipe down — skips the song and
/// makes it far less likely to come up again in shuffle). Every other
/// playlist is either imported from an M3U/M3U8 file or created by hand.
class MusicPlaylist {
  static const String favoritesId = 'favorites';
  static const String dislikedId = 'disliked';

  final String id;
  String name;
  List<String> trackIds;
  final bool isSystem;

  MusicPlaylist({
    required this.id,
    required this.name,
    List<String>? trackIds,
    this.isSystem = false,
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
      };

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    final rawIds = json['trackIds'];
    return MusicPlaylist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      trackIds: rawIds is List ? rawIds.whereType<String>().toList() : [],
      isSystem: json['isSystem'] as bool? ?? false,
    );
  }
}
