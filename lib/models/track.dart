/// Where a [Track]'s audio bytes come from.
enum TrackSource { local, subsonic }

/// A single playable song, either a file under the user's configured music
/// folder ([TrackSource.local]) or a song on a connected Subsonic/
/// OpenSubsonic server ([TrackSource.subsonic]).
///
/// [id] is stable and unique across both sources: `local:<absolute path>`
/// for local files, `subsonic:<server song id>` for remote ones — used as
/// the key everywhere a track needs to be referenced (favorites, disliked,
/// playlists, the now-playing queue) without holding the whole object.
class Track {
  final String id;
  final TrackSource source;

  /// Absolute file path. Only set for [TrackSource.local].
  final String? filePath;

  /// Subsonic song id on the configured server. Only set for
  /// [TrackSource.subsonic].
  final String? remoteId;

  final String title;
  final String artist;
  final String album;

  /// Track length in milliseconds, when known (from ID3 tags or the server).
  final int? durationMs;

  /// Genre, when known (from an mp3's `TCON` ID3 tag). Empty when unknown —
  /// used to build "most played per genre" smart playlists and genre rule
  /// conditions.
  final String genre;

  /// Release year, when known (from an mp3's `TDRC`/`TYER`/`TDOR` ID3 tag).
  final int? year;

  /// When this track was first seen by a library scan. Preserved across
  /// later rescans (a file that's still there doesn't get a new "added"
  /// date just because the library was refreshed) — backs the "Last Added"
  /// smart playlist.
  final DateTime? dateAdded;

  /// How many times this track has been played to completion. Backs the
  /// "Most Played" smart playlists; bumped by [MusicAudioHandler], not by a
  /// manual skip.
  final int playCount;

  const Track({
    required this.id,
    required this.source,
    this.filePath,
    this.remoteId,
    required this.title,
    this.artist = '',
    this.album = '',
    this.durationMs,
    this.genre = '',
    this.year,
    this.dateAdded,
    this.playCount = 0,
  });

  factory Track.local({
    required String filePath,
    required String title,
    String artist = '',
    String album = '',
    int? durationMs,
    String genre = '',
    int? year,
    DateTime? dateAdded,
    int playCount = 0,
  }) {
    return Track(
      id: 'local:$filePath',
      source: TrackSource.local,
      filePath: filePath,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
      genre: genre,
      year: year,
      dateAdded: dateAdded,
      playCount: playCount,
    );
  }

  factory Track.subsonic({
    required String remoteId,
    required String title,
    String artist = '',
    String album = '',
    int? durationMs,
  }) {
    return Track(
      id: 'subsonic:$remoteId',
      source: TrackSource.subsonic,
      remoteId: remoteId,
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
    );
  }

  /// The file's base name without extension, used as a fallback title and
  /// for fuzzy-matching M3U playlist entries.
  String get fileBaseName {
    final path = filePath ?? '';
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    final name = slash >= 0 ? path.substring(slash + 1) : path;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// Returns a copy with the given fields replaced. Used to update
  /// per-scan metadata while preserving [dateAdded]/[playCount] across a
  /// rescan, and to bump [playCount] on playback.
  Track copyWith({
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    String? genre,
    int? year,
    DateTime? dateAdded,
    int? playCount,
  }) {
    return Track(
      id: id,
      source: source,
      filePath: filePath,
      remoteId: remoteId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationMs: durationMs ?? this.durationMs,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      dateAdded: dateAdded ?? this.dateAdded,
      playCount: playCount ?? this.playCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source.name,
        if (filePath != null) 'filePath': filePath,
        if (remoteId != null) 'remoteId': remoteId,
        'title': title,
        'artist': artist,
        'album': album,
        if (durationMs != null) 'durationMs': durationMs,
        if (genre.isNotEmpty) 'genre': genre,
        if (year != null) 'year': year,
        if (dateAdded != null) 'dateAdded': dateAdded!.millisecondsSinceEpoch,
        if (playCount != 0) 'playCount': playCount,
      };

  factory Track.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source'] as String?;
    final source = TrackSource.values.firstWhere(
      (s) => s.name == sourceName,
      orElse: () => TrackSource.local,
    );
    final dateAddedMs = json['dateAdded'];
    return Track(
      id: json['id'] as String? ?? '',
      source: source,
      filePath: json['filePath'] as String?,
      remoteId: json['remoteId'] as String?,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.round(),
      genre: json['genre'] as String? ?? '',
      year: (json['year'] as num?)?.round(),
      dateAdded: dateAddedMs is num
          ? DateTime.fromMillisecondsSinceEpoch(dateAddedMs.round())
          : null,
      playCount: (json['playCount'] as num?)?.round() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
