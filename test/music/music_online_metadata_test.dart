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

MusicOnlineMetadataLookup _lookup(http.Client client) =>
    MusicOnlineMetadataLookup(
        client: client, musicBrainzSpacing: Duration.zero);

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

    test('server trouble is "unavailable", not "no match"', () async {
      final lookup = _lookup(
          MockClient((_) async => http.Response('busy', 503)));
      expect(
          lookup.lookup(const TrackQuery(title: 'Song', artist: 'Band'),
              _allFields),
          throwsA(isA<MetadataLookupUnavailable>()));
      final offline = _lookup(MockClient((_) async => throw Exception('no net')));
      expect(
          offline.lookup(const TrackQuery(title: 'Song', artist: 'Band'),
              _allFields),
          throwsA(isA<MetadataLookupUnavailable>()));
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
