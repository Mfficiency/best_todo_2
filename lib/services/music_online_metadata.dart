import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// What an online lookup found for one song. Every field is optional —
/// a source only fills what it knows.
class OnlineTrackMetadata {
  const OnlineTrackMetadata({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.year,
    this.bpm,
    this.sources = const [],
    this.incomplete = false,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? year;
  final int? bpm;

  /// Which services contributed (e.g. `['deezer', 'musicbrainz']`) — logged
  /// and kept in the enrichment cache for debugging.
  final List<String> sources;

  /// A service couldn't be asked this time (rate-limited / resting), so
  /// this may be missing what it would have added — worth asking again
  /// later. Not persisted with the result itself.
  final bool incomplete;

  bool get isEmpty =>
      title == null &&
      artist == null &&
      album == null &&
      genre == null &&
      year == null &&
      bpm == null;

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
        if (album != null) 'album': album,
        if (genre != null) 'genre': genre,
        if (year != null) 'year': year,
        if (bpm != null) 'bpm': bpm,
        if (sources.isNotEmpty) 'sources': sources,
      };

  factory OnlineTrackMetadata.fromJson(Map<String, dynamic> json) =>
      OnlineTrackMetadata(
        title: json['title'] as String?,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        genre: json['genre'] as String?,
        year: (json['year'] as num?)?.round(),
        bpm: (json['bpm'] as num?)?.round(),
        sources: (json['sources'] as List?)?.map((e) => '$e').toList() ??
            const [],
      );
}

/// The fields a lookup should try to fill.
enum MetadataField { artist, album, genre, year, bpm }

/// A song to look up: its (possibly filename-derived) title and artist,
/// plus the length when known — used to reject a same-named but different
/// recording (a live version, an extended mix).
class TrackQuery {
  const TrackQuery({required this.title, this.artist = '', this.durationMs});

  final String title;
  final String artist;
  final int? durationMs;
}

/// A lookup couldn't reach a service (offline, timeout, rate-limited) —
/// as opposed to "reached it, no match". The enricher retries these later
/// instead of remembering the song as unfindable.
class MetadataLookupUnavailable implements Exception {
  const MetadataLookupUnavailable(this.message, {this.retryAfter});
  final String message;

  /// When asking again makes sense (every service resting until then);
  /// null = no idea (offline).
  final DateTime? retryAfter;
  @override
  String toString() => 'MetadataLookupUnavailable: $message';
}

/// Best Music's online metadata search: looks a song up on Deezer (the
/// only free, keyless API that publishes BPM, plus album/genre/release
/// date), the iTunes Search API (clean single genre, album, year) and
/// MusicBrainz (original release year, community genre tags) — trying
/// several spellings of the query per service (cleaned-up title, main
/// artist only, title without anything in brackets, "Title - Artist"
/// filenames swapped round) until one matches. Every candidate is scored
/// on title/artist word overlap and, when both lengths are known,
/// duration; anything below [minMatchScore] is ignored rather than
/// filling a song with a stranger's tags.
///
/// Services are asked in order and skipped once every requested field is
/// filled, so a well-tagged song costs one or two requests.
class MusicOnlineMetadataLookup {
  MusicOnlineMetadataLookup({
    http.Client? client,
    this.userAgent = 'BestMusic/1.0 ( https://github.com/mfficiency/best_todo_2 )',
    Duration? musicBrainzSpacing,
    Map<String, Duration>? spacing,
    Duration? timeout,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        _spacing = {
          ...defaultSpacing,
          if (musicBrainzSpacing != null) _musicBrainzHost: musicBrainzSpacing,
          ...?spacing,
        },
        _timeout = timeout ?? const Duration(seconds: 15),
        _sleep = sleep ?? ((d) => Future<void>.delayed(d)),
        _clock = clock ?? DateTime.now;

  static const String _deezerHost = 'api.deezer.com';
  static const String _itunesHost = 'itunes.apple.com';
  static const String _musicBrainzHost = 'musicbrainz.org';

  /// Minimum gap between two requests to the same service — each one's
  /// published (or observed) rate limit: Deezer 50 per 5 s, iTunes about
  /// 20 per minute, MusicBrainz 1 per second. Going faster is what made
  /// 0.3.11 stall after a handful of songs: Deezer answered "quota
  /// exceeded" and the whole search paused.
  static const Map<String, Duration> defaultSpacing = {
    _deezerHost: Duration(milliseconds: 120),
    _itunesHost: Duration(milliseconds: 3100),
    _musicBrainzHost: Duration(milliseconds: 1100),
  };

  /// How long a service that keeps refusing (after retries) is left alone
  /// while the others carry on.
  static const Duration cooldown = Duration(minutes: 10);

  final http.Client _client;
  final String userAgent;
  final Map<String, Duration> _spacing;
  final Duration _timeout;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _clock;
  final Map<String, DateTime> _lastCall = {};
  final Map<String, DateTime> _coolingUntil = {};

  /// Per-lookup bookkeeping: did any service answer, did any fail.
  int _answered = 0;
  bool _hadTrouble = false;

  /// Lets every resting service be asked again right away (the "Restart
  /// online search" button).
  void resetCooldowns() => _coolingUntil.clear();

  static const double minMatchScore = 0.72;

  Future<OnlineTrackMetadata> lookup(
      TrackQuery query, Set<MetadataField> wanted) async {
    final variants = queryVariants(query);
    if (variants.isEmpty || wanted.isEmpty) return const OnlineTrackMetadata();

    String? title, artist, album, genre;
    int? bpm;
    int? deezerYear, itunesYear, mbYear;
    final sources = <String>[];
    var bestScore = 0.0;
    var incomplete = false;
    var skipped = 0;
    _answered = 0;
    _hadTrouble = false;

    /// Runs one service's part; a service that can't be reached is
    /// skipped (the song is marked [OnlineTrackMetadata.incomplete])
    /// instead of stopping the whole search.
    Future<void> service(String host, Future<void> Function() body) async {
      final until = _coolingUntil[host];
      if (until != null && until.isAfter(_clock())) {
        incomplete = true;
        skipped++;
        return;
      }
      try {
        await body();
      } on _ServiceTrouble {
        incomplete = true;
      }
    }

    bool missing(MetadataField f) => switch (f) {
          MetadataField.artist => artist == null,
          MetadataField.album => album == null,
          MetadataField.genre => genre == null,
          MetadataField.year => mbYear == null &&
              deezerYear == null &&
              itunesYear == null,
          MetadataField.bpm => bpm == null,
        };
    bool needsAny(Iterable<MetadataField> fields) =>
        fields.any((f) => wanted.contains(f) && missing(f));

    void takeIdentity(_Candidate c) {
      if (c.score > bestScore) {
        bestScore = c.score;
        title = c.title;
        artist = c.artist;
      }
    }

    // Deezer: BPM, album, genre (via the album), release date.
    if (needsAny(MetadataField.values)) {
      await service(_deezerHost, () async {
        final match = await _firstMatch(variants, _searchDeezer);
        if (match != null) {
          sources.add('deezer');
          takeIdentity(match);
          album ??= _nonEmpty(match.album);
          deezerYear = match.year;
          final details = await _deezerDetails(match.id,
              wantGenre: wanted.contains(MetadataField.genre));
          if (details.bpm != null) bpm = details.bpm;
          deezerYear = details.year ?? deezerYear;
          genre ??= details.genre;
        }
      });
    }

    // iTunes: genre, album, year.
    if (needsAny(const [
      MetadataField.artist,
      MetadataField.album,
      MetadataField.genre,
      MetadataField.year,
    ])) {
      await service(_itunesHost, () async {
        final match = await _firstMatch(variants, _searchItunes);
        if (match != null) {
          sources.add('itunes');
          takeIdentity(match);
          album ??= _nonEmpty(match.album);
          genre ??= _nonEmpty(match.genre);
          itunesYear = match.year;
        }
      });
    }

    // MusicBrainz: original release year and genre tags. Always asked when
    // a year is wanted — Deezer/iTunes often only know a remaster's year,
    // MusicBrainz knows the first release.
    if (wanted.contains(MetadataField.year) ||
        needsAny(const [
          MetadataField.artist,
          MetadataField.album,
          MetadataField.genre,
        ])) {
      await service(_musicBrainzHost, () async {
        final match = await _firstMatch(variants, _searchMusicBrainz);
        if (match != null) {
          sources.add('musicbrainz');
          takeIdentity(match);
          album ??= _nonEmpty(match.album);
          genre ??= _nonEmpty(match.genre);
          mbYear = match.year;
        }
      });
    }

    if (_answered == 0 && _hadTrouble) {
      // Not one service answered anything: the phone is offline.
      throw const MetadataLookupUnavailable('no service reachable');
    }
    if (_answered == 0 && skipped > 0 && sources.isEmpty) {
      // Every service needed is resting — wait for the first to wake up.
      final now = _clock();
      final next = _coolingUntil.values
          .where((t) => t.isAfter(now))
          .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
      throw MetadataLookupUnavailable('all services resting',
          retryAfter: next);
    }

    final years = [deezerYear, itunesYear].whereType<int>().toList();
    final year = mbYear ??
        (years.isEmpty ? null : years.reduce(math.min));
    return OnlineTrackMetadata(
      title: _nonEmpty(title),
      artist: _nonEmpty(artist),
      album: album,
      genre: genre,
      year: year,
      bpm: bpm,
      sources: sources,
      incomplete: incomplete,
    );
  }

  Future<_Candidate?> _firstMatch(List<TrackQuery> variants,
      Future<List<_Candidate>> Function(TrackQuery) search) async {
    for (final variant in variants) {
      final candidates = await search(variant);
      _Candidate? best;
      for (final c in candidates) {
        c.score = matchScore(variant, c.title, c.artist, c.durationMs);
        if (c.score >= minMatchScore && (best == null || c.score > best.score)) {
          best = c;
        }
      }
      if (best != null) return best;
    }
    return null;
  }

  // ---------------------------------------------------------------- Deezer

  Future<List<_Candidate>> _searchDeezer(TrackQuery q) async {
    final query = q.artist.isEmpty
        ? q.title
        : 'artist:"${q.artist}" track:"${q.title}"';
    var json = await _getJson(Uri.https(
        'api.deezer.com', '/search', {'q': query, 'limit': '10'}));
    var data = (json is Map ? json['data'] : null) as List?;
    if ((data == null || data.isEmpty) && q.artist.isNotEmpty) {
      json = await _getJson(Uri.https('api.deezer.com', '/search',
          {'q': '${q.artist} ${q.title}', 'limit': '10'}));
      data = (json is Map ? json['data'] : null) as List?;
    }
    return [
      for (final item in data ?? const [])
        if (item is Map)
          _Candidate(
            id: '${item['id']}',
            title: '${item['title'] ?? ''}',
            artist: '${(item['artist'] as Map?)?['name'] ?? ''}',
            album: '${(item['album'] as Map?)?['title'] ?? ''}',
            durationMs: (item['duration'] as num?) == null
                ? null
                : ((item['duration'] as num) * 1000).round(),
          ),
    ];
  }

  Future<({int? bpm, int? year, String? genre})> _deezerDetails(String id,
      {required bool wantGenre}) async {
    final track = await _getJson(Uri.https('api.deezer.com', '/track/$id'));
    if (track is! Map) return (bpm: null, year: null, genre: null);
    final rawBpm = track['bpm'];
    final bpm = rawBpm is num && rawBpm >= 30 && rawBpm <= 300
        ? rawBpm.round()
        : null;
    var year = _yearOf(track['release_date']);
    String? genre;
    final albumId = (track['album'] as Map?)?['id'];
    if (wantGenre && albumId != null) {
      final album = await _getJson(Uri.https('api.deezer.com', '/album/$albumId'));
      if (album is Map) {
        final genres = (album['genres'] as Map?)?['data'] as List?;
        if (genres != null && genres.isNotEmpty && genres.first is Map) {
          genre = _nonEmpty('${(genres.first as Map)['name'] ?? ''}');
        }
        year = _yearOf(album['release_date']) ?? year;
      }
    }
    return (bpm: bpm, year: year, genre: genre);
  }

  // ---------------------------------------------------------------- iTunes

  Future<List<_Candidate>> _searchItunes(TrackQuery q) async {
    final json = await _getJson(Uri.https('itunes.apple.com', '/search', {
      'term': [q.artist, q.title].where((s) => s.isNotEmpty).join(' '),
      'entity': 'song',
      'media': 'music',
      'limit': '10',
    }));
    final results = (json is Map ? json['results'] : null) as List?;
    return [
      for (final item in results ?? const [])
        if (item is Map)
          _Candidate(
            id: '${item['trackId']}',
            title: '${item['trackName'] ?? ''}',
            artist: '${item['artistName'] ?? ''}',
            album: '${item['collectionName'] ?? ''}',
            genre: '${item['primaryGenreName'] ?? ''}',
            year: _yearOf(item['releaseDate']),
            durationMs: (item['trackTimeMillis'] as num?)?.round(),
          ),
    ];
  }

  // ----------------------------------------------------------- MusicBrainz

  Future<List<_Candidate>> _searchMusicBrainz(TrackQuery q) async {
    String esc(String s) => s.replaceAll(RegExp(r'[\\"]'), ' ');
    final lucene = q.artist.isEmpty
        ? 'recording:"${esc(q.title)}"'
        : 'recording:"${esc(q.title)}" AND artist:"${esc(q.artist)}"';
    final json = await _getJson(Uri.https('musicbrainz.org', '/ws/2/recording',
        {'query': lucene, 'fmt': 'json', 'limit': '10'}));
    final recordings = (json is Map ? json['recordings'] : null) as List?;
    return [
      for (final item in recordings ?? const [])
        if (item is Map)
          _Candidate(
            id: '${item['id']}',
            title: '${item['title'] ?? ''}',
            artist: _musicBrainzArtist(item['artist-credit']),
            album: _musicBrainzAlbum(item['releases']),
            genre: _musicBrainzGenre(item['tags']),
            year: _yearOf(item['first-release-date']),
            durationMs: (item['length'] as num?)?.round(),
          ),
    ];
  }

  static String _musicBrainzArtist(Object? credits) {
    if (credits is! List) return '';
    final buffer = StringBuffer();
    for (final credit in credits) {
      if (credit is! Map) continue;
      buffer.write(credit['name'] ?? (credit['artist'] as Map?)?['name'] ?? '');
      buffer.write(credit['joinphrase'] ?? '');
    }
    return buffer.toString().trim();
  }

  /// The album a recording first came out on, preferring a regular album
  /// over singles and compilations.
  static String _musicBrainzAlbum(Object? releases) {
    if (releases is! List) return '';
    String? fallback;
    for (final release in releases) {
      if (release is! Map) continue;
      final group = release['release-group'] as Map?;
      final primary = '${group?['primary-type'] ?? ''}';
      final secondary = (group?['secondary-types'] as List?) ?? const [];
      final title = '${release['title'] ?? ''}';
      if (title.isEmpty) continue;
      if (primary == 'Album' && secondary.isEmpty) return title;
      fallback ??= title;
    }
    return fallback ?? '';
  }

  static String _musicBrainzGenre(Object? tags) {
    if (tags is! List || tags.isEmpty) return '';
    final sorted = tags.whereType<Map>().toList()
      ..sort((a, b) =>
          ((b['count'] as num?) ?? 0).compareTo((a['count'] as num?) ?? 0));
    if (sorted.isEmpty) return '';
    final name = '${sorted.first['name'] ?? ''}';
    return name
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // ---------------------------------------------------------------- shared

  Future<void> _throttle(String host) async {
    final gap = _spacing[host] ?? Duration.zero;
    final last = _lastCall[host];
    if (last != null && gap > Duration.zero) {
      final wait = gap - _clock().difference(last);
      if (wait > Duration.zero) await _sleep(wait);
    }
    _lastCall[host] = _clock();
  }

  /// GETs [uri] as JSON, paced per service. A rate-limit answer (429,
  /// 503/5xx, iTunes' 403, Deezer's in-body quota error) or a dropped
  /// connection is retried twice with growing waits (honoring
  /// `Retry-After`); after that the service rests for [cooldown] and
  /// `_ServiceTrouble` tells [lookup] to carry on without it. Any other
  /// non-200 is just "nothing here" (null).
  Future<Object?> _getJson(Uri uri) async {
    final host = uri.host;
    const backoff = [Duration(seconds: 2), Duration(seconds: 6)];
    var connectionOnly = true;
    for (var attempt = 0;; attempt++) {
      await _throttle(host);
      Duration? wait;
      try {
        final response = await _client.get(uri, headers: {
          'User-Agent': userAgent,
          'Accept': 'application/json',
        }).timeout(_timeout);
        _answered++;
        final code = response.statusCode;
        final rateLimited = code == 429 ||
            code >= 500 ||
            (code == 403 && host == _itunesHost);
        if (rateLimited) {
          connectionOnly = false;
          final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
          if (retryAfter != null && retryAfter > 0 && retryAfter <= 60) {
            wait = Duration(seconds: retryAfter);
          }
        } else if (code != 200) {
          return null;
        } else {
          final Object? decoded;
          try {
            decoded = jsonDecode(utf8.decode(response.bodyBytes));
          } catch (_) {
            return null;
          }
          // Deezer reports errors inside a 200 body; code 4 = quota.
          if (decoded is Map && decoded['error'] is Map) {
            if ((decoded['error'] as Map)['code'] != 4) return null;
            connectionOnly = false;
            wait = const Duration(seconds: 5); // its window is 5 s
          } else {
            return decoded;
          }
        }
      } on TimeoutException {
        // Counts as a connection problem.
      } catch (_) {
        // Socket/handshake/DNS failure.
      }
      if (attempt >= backoff.length) {
        _hadTrouble = true;
        if (!connectionOnly) _coolingUntil[host] = _clock().add(cooldown);
        throw _ServiceTrouble(host);
      }
      await _sleep(wait ?? backoff[attempt]);
    }
  }

  void close() => _client.close();
}

class _ServiceTrouble implements Exception {
  const _ServiceTrouble(this.host);
  final String host;
}

class _Candidate {
  _Candidate({
    required this.id,
    required this.title,
    required this.artist,
    this.album = '',
    this.genre = '',
    this.year,
    this.durationMs,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int? year;
  final int? durationMs;
  double score = 0;
}

String? _nonEmpty(String? s) {
  final trimmed = s?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

int? _yearOf(Object? date) {
  if (date == null) return null;
  final match = RegExp(r'(\d{4})').firstMatch('$date');
  final year = match == null ? null : int.tryParse(match.group(1)!);
  if (year == null || year < 1900 || year > DateTime.now().year + 1) return null;
  return year;
}

/// Junk words that mark a bracketed suffix as not part of the song title
/// ("(Official Video)", "[Lyrics]", "(HD)", ...).
final RegExp _junkBracket = RegExp(
    r'[\(\[\{][^\)\]\}]*\b(official|video|audio|lyrics?|visuali[sz]er|hd|hq|4k|'
    r'mv|m/v|explicit|clean|clip|music video|full song|free download)\b[^\)\]\}]*[\)\]\}]',
    caseSensitive: false);
final RegExp _featRegex =
    RegExp(r'\s*[\(\[]?\b(feat\.?|ft\.?|featuring)\s.*$', caseSensitive: false);

/// Strips download/upload noise from a title: track-number prefixes,
/// "(Official Video)"-style brackets, featured artists, underscores.
String cleanTitle(String raw) {
  var s = raw.replaceAll('_', ' ');
  s = s.replaceAll(_junkBracket, ' ');
  s = s.replaceAll(_featRegex, ' ');
  s = s.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-.)]\s+'), '');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s.replaceAll(RegExp(r'^[-–—\s]+|[-–—\s]+$'), '').trim();
}

/// The first-named artist of "A feat. B", "A & B", "A, B", "A x B".
String mainArtist(String raw) {
  final s = raw.replaceAll(_featRegex, '');
  final parts = s.split(RegExp(r'\s*(?:,|&|;|/|\s+x\s+|\s+and\s+)\s*',
      caseSensitive: false));
  return parts.first.trim();
}

/// Every spelling worth searching for [q], most specific first.
List<TrackQuery> queryVariants(TrackQuery q) {
  var title = cleanTitle(q.title);
  var artist = q.artist.trim();
  String? swappedTitle, swappedArtist;
  if (artist.isEmpty) {
    // "Artist - Title" filename (or a title tag that is one).
    final split = title.split(RegExp(r'\s+[-–—]\s+'));
    if (split.length >= 2) {
      artist = split.first.trim();
      title = cleanTitle(split.sublist(1).join(' - '));
      swappedTitle = artist;
      swappedArtist = title;
    }
  }
  final out = <TrackQuery>[];
  void add(String t, String a) {
    t = t.trim();
    a = a.trim();
    if (t.isEmpty) return;
    if (out.any((v) => v.title == t && v.artist == a)) return;
    out.add(TrackQuery(title: t, artist: a, durationMs: q.durationMs));
  }

  add(title, artist);
  add(title, mainArtist(artist));
  add(title.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), ''), mainArtist(artist));
  if (swappedTitle != null) add(swappedTitle, swappedArtist!);
  return out;
}

String _normalize(String s) {
  const accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ì': 'i', 'í': 'i',
    'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o',
    'ö': 'o', 'ø': 'o', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y',
    'ÿ': 'y', 'ß': 'ss',
  };
  final lower = s.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(accents[ch] ?? ch);
  }
  return buffer
      .toString()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r"['’`]"), '')
      .replaceAll(RegExp(r'[^a-z0-9Ѐ-ӿ぀-ヿ一-鿿]+'), ' ')
      .trim();
}

/// 0..1 word-overlap similarity (Dice over word sets, with a bonus when
/// one side fully contains the other — "Song" vs "Song (Radio Edit)").
double textSimilarity(String a, String b) {
  final na = _normalize(a), nb = _normalize(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;
  final wa = na.split(' ').where((w) => w.isNotEmpty && w != 'the').toSet();
  final wb = nb.split(' ').where((w) => w.isNotEmpty && w != 'the').toSet();
  if (wa.isEmpty || wb.isEmpty) return na == nb ? 1 : 0;
  final common = wa.intersection(wb).length;
  final dice = 2 * common / (wa.length + wb.length);
  final containment = common / math.min(wa.length, wb.length);
  return math.max(dice, containment * 0.9);
}

/// How well a found song (title/artist/length) matches [q], 0..1.
double matchScore(
    TrackQuery q, String title, String artist, int? candidateDurationMs) {
  final cleanCandidate = cleanTitle(title);
  final titleSim = math.max(
      textSimilarity(q.title, cleanCandidate), textSimilarity(q.title, title));
  double score;
  if (q.artist.isEmpty) {
    // Nothing to confirm the artist with: only a (near) exact title counts.
    score = titleSim >= 0.95 ? 0.75 + 0.1 * titleSim : titleSim * 0.6;
  } else {
    final artistSim = math.max(textSimilarity(q.artist, artist),
        textSimilarity(mainArtist(q.artist), mainArtist(artist)));
    if (artistSim < 0.5) return artistSim * 0.5;
    score = 0.6 * titleSim + 0.4 * artistSim;
  }
  final mine = q.durationMs, theirs = candidateDurationMs;
  if (mine != null && theirs != null && mine > 0 && theirs > 0) {
    final diff = (mine - theirs).abs();
    if (diff > 30000) {
      score *= 0.5;
    } else if (diff > 10000) {
      score *= 0.85;
    } else if (diff <= 3000) {
      score = math.min(1, score + 0.05);
    }
  }
  return score;
}
