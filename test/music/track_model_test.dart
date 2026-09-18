import 'package:besttodo/models/track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Track', () {
    test('local factory builds a stable path-prefixed id', () {
      final track = Track.local(
        filePath: '/storage/emulated/0/Music/Song.mp3',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        durationMs: 12345,
      );

      expect(track.id, 'local:/storage/emulated/0/Music/Song.mp3');
      expect(track.source, TrackSource.local);
      expect(track.remoteId, isNull);
    });

    test('subsonic factory builds a remoteId-prefixed id', () {
      final track = Track.subsonic(remoteId: 'abc123', title: 'Remote Song');

      expect(track.id, 'subsonic:abc123');
      expect(track.source, TrackSource.subsonic);
      expect(track.filePath, isNull);
    });

    test('fileBaseName strips directory and extension', () {
      final windowsStyle = Track.local(
        filePath: r'C:\Music\Sub\My Song.mp3',
        title: 'x',
      );
      final posixStyle = Track.local(
        filePath: '/music/sub/My Song.mp3',
        title: 'x',
      );

      expect(windowsStyle.fileBaseName, 'My Song');
      expect(posixStyle.fileBaseName, 'My Song');
    });

    test('toJson/fromJson round-trips every field', () {
      final track = Track.local(
        filePath: '/a/b.mp3',
        title: 'Title',
        artist: 'Artist',
        album: 'Album',
        durationMs: 9000,
        genre: 'Rock',
        year: 2021,
        dateAdded: DateTime.utc(2024, 3, 1, 12),
        playCount: 4,
        metadataEdited: true,
      );

      final restored = Track.fromJson(track.toJson());

      expect(restored.id, track.id);
      expect(restored.source, track.source);
      expect(restored.filePath, track.filePath);
      expect(restored.title, track.title);
      expect(restored.artist, track.artist);
      expect(restored.album, track.album);
      expect(restored.durationMs, track.durationMs);
      expect(restored.genre, 'Rock');
      expect(restored.year, 2021);
      expect(restored.dateAdded, track.dateAdded);
      expect(restored.playCount, 4);
      expect(restored.metadataEdited, isTrue);
    });

    test('fromJson tolerates missing keys', () {
      final restored = Track.fromJson({'id': 'local:/x.mp3'});

      expect(restored.id, 'local:/x.mp3');
      expect(restored.source, TrackSource.local);
      expect(restored.title, '');
      expect(restored.artist, '');
      expect(restored.album, '');
      expect(restored.durationMs, isNull);
      expect(restored.genre, '');
      expect(restored.year, isNull);
      expect(restored.dateAdded, isNull);
      expect(restored.playCount, 0);
      expect(restored.metadataEdited, isFalse);
    });

    test('copyWith replaces only the given fields', () {
      final track = Track.local(filePath: '/a.mp3', title: 'Original', genre: 'Pop');

      final updated = track.copyWith(playCount: 3, genre: 'Rock', metadataEdited: true);

      expect(updated.id, track.id);
      expect(updated.title, 'Original');
      expect(updated.genre, 'Rock');
      expect(updated.playCount, 3);
      expect(updated.metadataEdited, isTrue);
      // The original is untouched — Track is immutable.
      expect(track.playCount, 0);
      expect(track.genre, 'Pop');
      expect(track.metadataEdited, isFalse);
    });

    test('equality/hashCode is based on id alone', () {
      final a = Track.local(filePath: '/a.mp3', title: 'A');
      final b = Track.local(filePath: '/a.mp3', title: 'Different title');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
