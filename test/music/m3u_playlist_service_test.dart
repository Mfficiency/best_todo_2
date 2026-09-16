import 'dart:io';

import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/m3u_playlist_service.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    MusicPlaylistService.instance.resetForTest();
    MusicLibraryService.instance.resetForTest();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('parseEntries', () {
    test('skips blank lines, comments and #EXT directives', () {
      const content = '#EXTM3U\n'
          '#EXTINF:123,Artist - Title\n'
          '/music/Song One.mp3\n'
          '\n'
          '  \n'
          'relative/Song Two.mp3\n';

      final entries = M3uPlaylistService.parseEntries(content);

      expect(entries, ['/music/Song One.mp3', 'relative/Song Two.mp3']);
    });

    test('strips a leading byte-order mark', () {
      const content = '﻿#EXTM3U\n/music/Song.mp3\n';
      final entries = M3uPlaylistService.parseEntries(content);
      expect(entries, ['/music/Song.mp3']);
    });
  });

  group('importFile', () {
    test('matches by exact path, then by basename, and reports the rest',
        () async {
      await MusicPlaylistService.instance.load();
      final exactMatch =
          Track.local(filePath: '/music/Exact Match.mp3', title: 'Exact Match');
      final baseNameMatch = Track.local(
          filePath: '/music/Sub/Base Name Match.mp3', title: 'Base Name Match');
      MusicLibraryService.instance.tracks.value = [exactMatch, baseNameMatch];

      final m3uFile = File('${tempDir.path}/My Playlist.m3u8');
      await m3uFile.writeAsString(
        '#EXTM3U\n'
        '/music/Exact Match.mp3\n'
        '/completely/different/path/Base Name Match.mp3\n'
        '/nowhere/Unknown Song.mp3\n',
      );

      final result = await M3uPlaylistService.importFile(m3uFile);

      expect(result.playlist.name, 'My Playlist');
      expect(result.matchedCount, 2);
      expect(result.playlist.trackIds, [exactMatch.id, baseNameMatch.id]);
      expect(result.unmatchedEntries, ['/nowhere/Unknown Song.mp3']);

      // The playlist is actually persisted through MusicPlaylistService.
      expect(MusicPlaylistService.instance.byId(result.playlist.id)?.trackIds,
          [exactMatch.id, baseNameMatch.id]);
    });

    test('decodes file:// URIs before matching', () async {
      await MusicPlaylistService.instance.load();
      final track = Track.local(filePath: '/music/Song.mp3', title: 'Song');
      MusicLibraryService.instance.tracks.value = [track];

      final m3uFile = File('${tempDir.path}/uri.m3u');
      await m3uFile.writeAsString('file:///music/Song.mp3\n');

      final result = await M3uPlaylistService.importFile(m3uFile);

      expect(result.matchedCount, 1);
      expect(result.playlist.trackIds, [track.id]);
    });
  });
}
