import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_metadata_enricher.dart';
import 'package:besttodo/services/music_online_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// Answers from [answers] keyed by title; records every query.
class _FakeLookup extends MusicOnlineMetadataLookup {
  _FakeLookup(this.answers);

  final Map<String, OnlineTrackMetadata> answers;
  final List<String> queried = [];
  bool offline = false;

  @override
  Future<OnlineTrackMetadata> lookup(
      TrackQuery query, Set<MetadataField> wanted) async {
    if (offline) throw const MetadataLookupUnavailable('offline');
    queried.add(query.title);
    return answers[query.title] ?? const OnlineTrackMetadata();
  }
}

Track _track(String name,
        {String artist = 'Band', int? bpm, String genre = '', int? year}) =>
    Track.local(
      filePath: '/music/$name.mp3',
      title: name,
      artist: artist,
      album: 'LP',
      genre: genre,
      year: year,
      bpm: bpm,
    );

void main() {
  late Directory dir;
  final library = MusicLibraryService.instance;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('besttodo_enricher_');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    library.resetForTest();
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  MusicMetadataEnricher enricher(_FakeLookup lookup,
          {Future<int?> Function(Track)? detect}) =>
      MusicMetadataEnricher(
        library: library,
        lookup: lookup,
        detectBpm: detect ?? (_) async => null,
        storageDir: () async => dir,
        debounce: const Duration(milliseconds: 10),
      );

  test('fills only the missing fields from the online lookup', () async {
    library.tracks.value = [_track('A', genre: 'Rock')];
    final lookup = _FakeLookup({
      'A': const OnlineTrackMetadata(genre: 'Pop', year: 1999, bpm: 120),
    });
    final e = enricher(lookup);
    await e.start();
    await e.whenIdle();
    final t = library.byId('local:/music/A.mp3')!;
    expect(t.genre, 'Rock', reason: 'an existing value is never replaced');
    expect(t.year, 1999);
    expect(t.bpm, 120);
    expect(t.metadataEdited, isFalse);
    e.stop();
  });

  test('a complete song is never looked up', () async {
    library.tracks.value = [_track('A', genre: 'Rock', year: 2000, bpm: 90)];
    final lookup = _FakeLookup({});
    final e = enricher(lookup);
    await e.start();
    await e.whenIdle();
    expect(lookup.queried, isEmpty);
    e.stop();
  });

  test('remembers what it found: no second lookup, and a rescan gets it back',
      () async {
    library.tracks.value = [_track('A')];
    final lookup = _FakeLookup({
      'A': const OnlineTrackMetadata(genre: 'Pop', year: 1999, bpm: 120),
    });
    var e = enricher(lookup);
    await e.start();
    await e.whenIdle();
    e.stop();
    final saved = jsonDecode(
        await File('${dir.path}/${MusicMetadataEnricher.fileName}')
            .readAsString()) as Map;
    expect(saved.keys, ['local:/music/A.mp3']);

    // Next launch: a fresh enricher, and a rescan rebuilt the track from
    // its (still empty) tags.
    lookup.queried.clear();
    e = enricher(lookup);
    await e.start();
    library.tracks.value = [_track('A')];
    await e.whenIdle();
    final t = library.byId('local:/music/A.mp3')!;
    expect(t.genre, 'Pop');
    expect(t.bpm, 120);
    expect(lookup.queried, isEmpty);
    e.stop();
  });

  test('detects BPM on device when online found it for under 90%', () async {
    library.tracks.value = [
      for (final n in ['A', 'B', 'C']) _track(n, genre: 'Rock', year: 2000),
    ];
    final lookup = _FakeLookup({
      'A': const OnlineTrackMetadata(bpm: 100),
    });
    final detected = <String>[];
    final e = enricher(lookup, detect: (t) async {
      detected.add(t.title);
      return 140;
    });
    await e.start();
    await e.whenIdle();
    expect(detected, unorderedEquals(['B', 'C']));
    expect(library.byId('local:/music/A.mp3')!.bpm, 100);
    expect(library.byId('local:/music/B.mp3')!.bpm, 140);
    expect(e.status.value, contains('3 with a BPM'));
    e.stop();
  });

  test('no on-device detection once 90% have a BPM', () async {
    library.tracks.value = [
      for (var i = 0; i < 10; i++)
        _track('S$i', genre: 'Rock', year: 2000, bpm: i < 9 ? 120 : null),
    ];
    final detected = <String>[];
    final e = enricher(_FakeLookup({}), detect: (t) async {
      detected.add(t.title);
      return 99;
    });
    await e.start();
    await e.whenIdle();
    expect(detected, isEmpty);
    e.stop();
  });

  test('offline: nothing is marked done and no detection runs yet', () async {
    library.tracks.value = [_track('A')];
    final lookup = _FakeLookup({'A': const OnlineTrackMetadata(bpm: 128)})
      ..offline = true;
    final detected = <String>[];
    final e = enricher(lookup, detect: (t) async {
      detected.add(t.title);
      return 99;
    });
    await e.start();
    await e.whenIdle();
    expect(e.entries, isEmpty);
    expect(detected, isEmpty);
    expect(e.status.value, contains('paused'));

    // Back online: the next library change picks it up.
    lookup.offline = false;
    library.tracks.value = List.of(library.tracks.value);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await e.whenIdle();
    expect(library.byId('local:/music/A.mp3')!.bpm, 128);
    e.stop();
  });

  test('fillMissingMetadata replaces a filename title only with no artist',
      () async {
    library.tracks.value = [
      Track.local(filePath: '/music/daft punk - get lucky.mp3',
          title: 'daft punk - get lucky'),
      Track.local(filePath: '/music/x.mp3', title: 'Real Title', artist: 'Me'),
    ];
    const fill = OnlineTrackMetadata(title: 'Get Lucky', artist: 'Daft Punk');
    final changed = await library.fillMissingMetadata({
      'local:/music/daft punk - get lucky.mp3': fill,
      'local:/music/x.mp3': fill,
    });
    expect(changed, 1);
    expect(library.byId('local:/music/daft punk - get lucky.mp3')!.title,
        'Get Lucky');
    expect(library.byId('local:/music/x.mp3')!.title, 'Real Title');
    expect(library.byId('local:/music/x.mp3')!.artist, 'Me');
  });
}
