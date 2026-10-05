import 'dart:convert';

import 'package:besttodo/services/music_online_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// A fake of all three services: [deezer]/[itunes]/[musicbrainz] are the
/// search results; [deezerTrack]/[deezerAlbum] the detail endpoints.
MockClient _fakeServices({
  List<Map<String, dynamic>> deezer = const [],
  Map<String, dynamic>? deezerTrack,
  Map<String, dynamic>? deezerAlbum,
  List<Map<String, dynamic>> itunes = const [],
  List<Map<String, dynamic>> musicbrainz = const [],
  List<Uri>? calls,
}) {
  return MockClient((request) async {
    calls?.add(request.url);
    final url = request.url;
    if (url.host == 'api.deezer.com') {
      if (url.path == '/search') return _json({'data': deezer});
      if (url.path.startsWith('/track/')) return _json(deezerTrack ?? {});
      if (url.path.startsWith('/album/')) return _json(deezerAlbum ?? {});
    }
    if (url.host == 'itunes.apple.com') return _json({'results': itunes});
    if (url.host == 'musicbrainz.org') {
      expect(request.headers['User-Agent'], contains('BestMusic'));
      return _json({'recordings': musicbrainz});
    }
    return http.Response('not found', 404);
  });
}

/// No pacing and no real waiting; [sleeps] records every wait asked for.
MusicOnlineMetadataLookup _lookup(http.Client client,
        {List<Duration>? sleeps,
        Map<String, Duration>? spacing,
        DateTime Function()? clock}) =>
    MusicOnlineMetadataLookup(
      client: client,
      spacing: spacing ??
          {
            for (final host in MusicOnlineMetadataLookup.defaultSpacing.keys)
              host: Duration.zero,
          },
      sleep: (d) async => sleeps?.add(d),
      clock: clock,
    );

const _allFields = {
  MetadataField.artist,
  MetadataField.album,
  MetadataField.genre,
  MetadataField.year,
  MetadataField.bpm,
};

void main() {
  group('cleanTitle / mainArtist', () {
    test('strips video noise, featured artists and track numbers', () {
      expect(cleanTitle('Blinding Lights (Official Video)'), 'Blinding Lights');
      expect(cleanTitle('03 - Levitating [Lyrics] ft. DaBaby'), 'Levitating');
      expect(cleanTitle('Song_Name_HQ'), 'Song Name HQ');
      expect(cleanTitle('Hello (Remix)'), 'Hello (Remix)');
    });

    test('mainArtist keeps the first credited artist', () {
      expect(mainArtist('Calvin Harris feat. Rihanna'), 'Calvin Harris');
      expect(mainArtist('Simon & Garfunkel'), 'Simon');
      expect(mainArtist('Daft Punk'), 'Daft Punk');
    });
  });

  group('queryVariants', () {
    test('splits an "Artist - Title" filename when there is no artist tag', () {
      final variants = queryVariants(
          const TrackQuery(title: 'Daft Punk - One More Time (Official Audio)'));
      expect(variants.first.artist, 'Daft Punk');
      expect(variants.first.title, 'One More Time');
      // And the swapped reading, for "Title - Artist" filenames.
      expect(variants.any((v) => v.artist == 'One More Time'), isTrue);
    });

    test('adds a main-artist variant for collaborations', () {
      final variants = queryVariants(
          const TrackQuery(title: 'This Is What You Came For', artist: 'Calvin Harris, Rihanna'));
      expect(variants.map((v) => v.artist),
          containsAll(['Calvin Harris, Rihanna', 'Calvin Harris']));
    });
  });

  group('matchScore', () {
    const q = TrackQuery(
        title: 'One More Time', artist: 'Daft Punk', durationMs: 320000);

    test('exact match scores high, a different song low', () {
      expect(matchScore(q, 'One More Time', 'Daft Punk', 320357),
          greaterThan(MusicOnlineMetadataLookup.minMatchScore));
      expect(matchScore(q, 'Around the World', 'Daft Punk', 300000),
          lessThan(MusicOnlineMetadataLookup.minMatchScore));
      expect(matchScore(q, 'One More Time', 'Britney Spears', 210000),
          lessThan(MusicOnlineMetadataLookup.minMatchScore));
    });

    test('a very different length (live/extended version) is rejected', () {
      expect(matchScore(q, 'One More Time', 'Daft Punk', 620000),
          lessThan(MusicOnlineMetadataLookup.minMatchScore));
    });

    test('accents and punctuation don\'t matter', () {
      expect(
          matchScore(const TrackQuery(title: 'Déjà Vu', artist: 'Beyoncé'),
              'Deja Vu', 'Beyonce', null),
          greaterThan(0.95));
    });
  });

  group('lookup', () {
    test('combines Deezer BPM/genre with the MusicBrainz original year',
        () async {
      final lookup = _lookup(_fakeServices(
        deezer: [
          {
            'id': 3135556,
            'title': 'One More Time',
            'duration': 320,
            'artist': {'name': 'Daft Punk'},
            'album': {'title': 'Discovery'},
          },
        ],
        deezerTrack: {
          'bpm': 122.6,
          'release_date': '2001-03-07',
          'album': {'id': 302127},
        },
        deezerAlbum: {
          'release_date': '2001-03-07',
          'genres': {
            'data': [
              {'name': 'Electro'}
            ]
          },
        },
        itunes: [
          {
            'trackId': 1,
            'trackName': 'One More Time',
            'artistName': 'Daft Punk',
            'collectionName': 'Discovery',
            'primaryGenreName': 'Dance',
            'releaseDate': '2001-03-12T08:00:00Z',
            'trackTimeMillis': 320357,
          },
        ],
        musicbrainz: [
          {
            'id': 'mb1',
            'title': 'One More Time',
            'length': 320000,
            'first-release-date': '2000-11-13',
            'artist-credit': [
              {'name': 'Daft Punk', 'joinphrase': ''}
            ],
            'releases': [
              {
                'title': 'One More Time',
                'release-group': {'primary-type': 'Single'}
              },
            ],
            'tags': [
              {'name': 'french house', 'count': 5},
              {'name': 'house', 'count': 2},
            ],
          },
        ],
      ));
      final result = await lookup.lookup(
          const TrackQuery(
              title: 'One More Time', artist: 'Daft Punk', durationMs: 320000),
          _allFields);
      expect(result.bpm, 123);
      expect(result.album, 'Discovery');
      expect(result.genre, 'Electro');
      expect(result.year, 2000, reason: 'MusicBrainz knows the first release');
      // Deezer already covered what iTunes adds, so it was skipped.
      expect(result.sources, ['deezer', 'musicbrainz']);
    });

    test('ignores results that are a different song', () async {
      final lookup = _lookup(_fakeServices(
        deezer: [
          {
            'id': 1,
            'title': 'Totally Different',
            'duration': 200,
            'artist': {'name': 'Someone Else'},
            'album': {'title': 'Nope'},
          },
        ],
      ));
      final result = await lookup.lookup(
          const TrackQuery(title: 'My Song', artist: 'Me'), _allFields);
      expect(result.isEmpty, isTrue);
    });

    test('Deezer BPM 0 means unknown', () async {
      final lookup = _lookup(_fakeServices(
        deezer: [
          {
            'id': 1,
            'title': 'Song',
            'artist': {'name': 'Band'},
            'album': {'title': 'LP'},
          },
        ],
        deezerTrack: {'bpm': 0, 'album': {'id': 9}},
      ));
      final result = await lookup.lookup(
          const TrackQuery(title: 'Song', artist: 'Band'), {MetadataField.bpm});
      expect(result.bpm, isNull);
      expect(result.album, 'LP');
    });

    test('only asks the services it still needs', () async {
      final calls = <Uri>[];
      final lookup = _lookup(_fakeServices(
        calls: calls,
        deezer: [
          {
            'id': 1,
            'title': 'Song',
            'artist': {'name': 'Band'},
            'album': {'title': 'LP'},
          },
        ],
        deezerTrack: {'bpm': 128, 'album': {'id': 9}},
      ));
      final result = await lookup.lookup(
          const TrackQuery(title: 'Song', artist: 'Band'), {MetadataField.bpm});
      expect(result.bpm, 128);
      expect(calls.map((u) => u.host).toSet(), {'api.deezer.com'});
    });

    test('a filename-only song gets its artist and title from the match',
        () async {
      final lookup = _lookup(_fakeServices(
        itunes: [
          {
            'trackId': 1,
            'trackName': 'Get Lucky (feat. Pharrell Williams)',
            'artistName': 'Daft Punk',
            'collectionName': 'Random Access Memories',
            'primaryGenreName': 'Dance',
            'releaseDate': '2013-05-17T07:00:00Z',
          },
        ],
      ));
      final result = await lookup.lookup(
          const TrackQuery(title: 'Daft Punk - Get Lucky (Official Video)'),
          _allFields);
      expect(result.artist, 'Daft Punk');
      expect(result.genre, 'Dance');
      expect(result.year, 2013);
      expect(result.album, 'Random Access Memories');
    });

    test('offline (nothing answers) is "unavailable", not "no match"',
        () async {
      final offline =
          _lookup(MockClient((_) async => throw Exception('no net')));
      expect(
          offline.lookup(const TrackQuery(title: 'Song', artist: 'Band'),
              _allFields),
          throwsA(isA<MetadataLookupUnavailable>()
              .having((e) => e.retryAfter, 'retryAfter', isNull)));
    });
  });

  group('rate limits', () {
    const song = TrackQuery(title: 'Song', artist: 'Band');
    final deezerHit = {
      'id': 1,
      'title': 'Song',
      'artist': {'name': 'Band'},
      'album': {'title': 'LP'},
    };
    final itunesHit = {
      'trackId': 1,
      'trackName': 'Song',
      'artistName': 'Band',
      'collectionName': 'LP',
      'primaryGenreName': 'Rock',
      'releaseDate': '1999-01-01T00:00:00Z',
    };

    test('a Deezer quota error is waited out and retried, not a pause',
        () async {
      var deezerSearches = 0;
      final sleeps = <Duration>[];
      final lookup = _lookup(MockClient((request) async {
        final url = request.url;
        if (url.host == 'api.deezer.com' && url.path == '/search') {
          deezerSearches++;
          if (deezerSearches == 1) {
            return _json({
              'error': {'type': 'Exception', 'message': 'Quota limit exceeded', 'code': 4}
            });
          }
          return _json({'data': [deezerHit]});
        }
        if (url.host == 'api.deezer.com') return _json({'bpm': 128});
        return _json({'results': [], 'recordings': []});
      }), sleeps: sleeps);
      final result = await lookup.lookup(song, {MetadataField.bpm});
      expect(result.bpm, 128);
      expect(result.incomplete, isFalse);
      expect(sleeps, contains(const Duration(seconds: 5)));
    });

    test('a service that keeps refusing rests; the others carry on',
        () async {
      var now = DateTime(2026, 10, 5, 12);
      final calls = <String>[];
      final lookup = _lookup(MockClient((request) async {
        calls.add(request.url.host);
        if (request.url.host == 'api.deezer.com') {
          return http.Response('slow down', 429);
        }
        if (request.url.host == 'itunes.apple.com') {
          return _json({'results': [itunesHit]});
        }
        return _json({'recordings': []});
      }), clock: () => now);

      final first = await lookup.lookup(song, _allFields);
      expect(first.genre, 'Rock', reason: 'iTunes still answered');
      expect(first.incomplete, isTrue);
      expect(calls.where((h) => h == 'api.deezer.com'), hasLength(3),
          reason: 'one try + two retries');

      // Next song: Deezer is resting and not asked at all.
      calls.clear();
      final second = await lookup.lookup(song, _allFields);
      expect(second.incomplete, isTrue);
      expect(calls, isNot(contains('api.deezer.com')));

      // After the rest it's asked again.
      now = now.add(MusicOnlineMetadataLookup.cooldown);
      calls.clear();
      await lookup.lookup(song, _allFields);
      expect(calls, contains('api.deezer.com'));

      // resetCooldowns lifts a rest right away.
      calls.clear();
      await lookup.lookup(song, _allFields); // rests again
      lookup.resetCooldowns();
      calls.clear();
      await lookup.lookup(song, _allFields);
      expect(calls, contains('api.deezer.com'));
    });

    test('every service resting → unavailable with a retry time', () async {
      final now = DateTime(2026, 10, 5, 12);
      final lookup = _lookup(
          MockClient((_) async => http.Response('busy', 503)),
          clock: () => now);
      final first = await lookup.lookup(song, _allFields);
      expect(first.isEmpty, isTrue);
      expect(first.incomplete, isTrue);
      expect(
          lookup.lookup(song, _allFields),
          throwsA(isA<MetadataLookupUnavailable>().having((e) => e.retryAfter,
              'retryAfter', now.add(MusicOnlineMetadataLookup.cooldown))));
    });

    test('iTunes\' 403 is its rate limit', () async {
      final lookup = _lookup(MockClient((request) async {
        if (request.url.host == 'itunes.apple.com') {
          return http.Response('', 403);
        }
        return _json({'data': [], 'recordings': []});
      }));
      final result = await lookup.lookup(song, {MetadataField.genre});
      expect(result.incomplete, isTrue);
    });

    test('requests to one service are spaced out', () async {
      var now = DateTime(2026, 10, 5, 12);
      final sleeps = <Duration>[];
      final lookup = MusicOnlineMetadataLookup(
        client: MockClient((_) async {
          now = now.add(const Duration(milliseconds: 10));
          return _json({'data': [], 'results': [], 'recordings': []});
        }),
        sleep: (d) async {
          sleeps.add(d);
          now = now.add(d);
        },
        clock: () => now,
      );
      await lookup.lookup(song, _allFields);
      // Several Deezer searches (one per spelling + fallbacks) → waits.
      expect(sleeps, isNotEmpty);
      expect(
          sleeps.every((d) =>
              d <= MusicOnlineMetadataLookup.defaultSpacing.values
                  .reduce((a, b) => a > b ? a : b)),
          isTrue);
    });
  });

  test('OnlineTrackMetadata JSON round-trip', () {
    const m = OnlineTrackMetadata(
        title: 'T', artist: 'A', album: 'L', genre: 'G', year: 1999, bpm: 90,
        sources: ['deezer']);
    final back = OnlineTrackMetadata.fromJson(m.toJson());
    expect(back.toJson(), m.toJson());
    expect(const OnlineTrackMetadata().isEmpty, isTrue);
  });
}
