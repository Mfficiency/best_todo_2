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
      );

      final restored = Track.fromJson(track.toJson());

      expect(restored.id, track.id);
      expect(restored.source, track.source);
      expect(restored.filePath, track.filePath);
      expect(restored.title, track.title);
      expect(restored.artist, track.artist);
      expect(restored.album, track.album);
      expect(restored.durationMs, track.durationMs);
    });

    test('fromJson tolerates missing keys', () {
      final restored = Track.fromJson({'id': 'local:/x.mp3'});

      expect(restored.id, 'local:/x.mp3');
      expect(restored.source, TrackSource.local);
      expect(restored.title, '');
      expect(restored.artist, '');
      expect(restored.album, '');
      expect(restored.durationMs, isNull);
    });

    test('equality/hashCode is based on id alone', () {
      final a = Track.local(filePath: '/a.mp3', title: 'A');
      final b = Track.local(filePath: '/a.mp3', title: 'Different title');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
