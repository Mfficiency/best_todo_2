import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory appDocsDir;
  late Directory musicDir;

  setUp(() async {
    appDocsDir = await Directory.systemTemp.createTemp('besttodo_app_docs_');
    PathProviderPlatform.instance = _FakePathProvider(appDocsDir.path);
    musicDir = await Directory.systemTemp.createTemp('besttodo_music_');
    Config.musicFolder = musicDir.path;
    Config.musicExcludedSubfolders = [];
    MusicLibraryService.instance.resetForTest();
  });

  tearDown(() async {
    Config.musicFolder = '';
    Config.musicExcludedSubfolders = [];
    await appDocsDir.delete(recursive: true);
    await musicDir.delete(recursive: true);
  });

  Future<void> writeFile(String relativePath, [List<int>? bytes]) async {
    final file = File('${musicDir.path}/$relativePath');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes ?? [0, 0, 0]);
  }

  group('isExcludedRelativeDir', () {
    test('matches the folder itself and anything nested under it', () {
      const excluded = ['Podcasts', 'Ringtones/Old'];
      expect(MusicLibraryService.isExcludedRelativeDir('Podcasts', excluded),
          isTrue);
      expect(
          MusicLibraryService.isExcludedRelativeDir(
              'Podcasts/Season1', excluded),
          isTrue);
      expect(
          MusicLibraryService.isExcludedRelativeDir(
              'Ringtones/Old', excluded),
          isTrue);
      expect(
          MusicLibraryService.isExcludedRelativeDir('Ringtones', excluded),
          isFalse);
      expect(MusicLibraryService.isExcludedRelativeDir('Albums', excluded),
          isFalse);
    });

    test('the root folder (empty relative dir) is never excluded', () {
      expect(MusicLibraryService.isExcludedRelativeDir('', ['Podcasts']),
          isFalse);
    });

    test('backslashes are normalized like forward slashes', () {
      expect(
          MusicLibraryService.isExcludedRelativeDir(
              r'Ringtones\Old', ['Ringtones/Old']),
          isTrue);
    });
  });

  group('rescan', () {
    test('finds supported audio files recursively and skips unsupported ones',
        () async {
      await writeFile('top.mp3');
      await writeFile('Albums/Best Of/track.flac');
      await writeFile('notes.txt');

      final tracks = await MusicLibraryService.instance.rescan();

      final titles = tracks.map((t) => t.fileBaseName).toSet();
      expect(titles, {'top', 'track'});
    });

    test('excluded subfolders (and their nested folders) are skipped',
        () async {
      await writeFile('keep.mp3');
      await writeFile('Podcasts/episode1.mp3');
      await writeFile('Podcasts/2024/episode2.mp3');
      Config.musicExcludedSubfolders = ['Podcasts'];

      final tracks = await MusicLibraryService.instance.rescan();

      expect(tracks.map((t) => t.fileBaseName).toSet(), {'keep'});
    });

    test('an mp3 with no readable ID3 tag falls back to the filename',
        () async {
      await writeFile('My Untagged Song.mp3');

      final tracks = await MusicLibraryService.instance.rescan();

      expect(tracks, hasLength(1));
      expect(tracks.single.title, 'My Untagged Song');
      expect(tracks.single.source.name, 'local');
    });

    test('an empty/unset music folder clears the library', () async {
      Config.musicFolder = '';
      final tracks = await MusicLibraryService.instance.rescan();
      expect(tracks, isEmpty);
    });

    test('a missing folder leaves the previously cached library untouched',
        () async {
      await writeFile('keep.mp3');
      await MusicLibraryService.instance.rescan();
      expect(MusicLibraryService.instance.tracks.value, hasLength(1));

      Config.musicFolder = '${musicDir.path}/does_not_exist';
      final tracks = await MusicLibraryService.instance.rescan();

      expect(tracks, hasLength(1));
    });

    test('results persist across a resetForTest + load()', () async {
      await writeFile('persisted.mp3');
      await MusicLibraryService.instance.rescan();

      MusicLibraryService.instance.resetForTest();
      expect(MusicLibraryService.instance.tracks.value, isEmpty);

      await MusicLibraryService.instance.load();
      expect(MusicLibraryService.instance.tracks.value, hasLength(1));
      expect(MusicLibraryService.instance.tracks.value.single.fileBaseName,
          'persisted');
    });
  });

  group('listSubfolders', () {
    test('lists every nested subfolder as a relative path', () async {
      await writeFile('Albums/Best Of/track.mp3');
      await writeFile('Podcasts/episode1.mp3');

      final subfolders = await MusicLibraryService.instance.listSubfolders();

      expect(subfolders, containsAll(['Albums', 'Albums/Best Of', 'Podcasts']));
    });

    test('an unset music folder returns no subfolders', () async {
      Config.musicFolder = '';
      expect(await MusicLibraryService.instance.listSubfolders(), isEmpty);
    });
  });

  test('byId finds a scanned track by its id', () async {
    await writeFile('findme.mp3');
    final tracks = await MusicLibraryService.instance.rescan();

    final found = MusicLibraryService.instance.byId(tracks.single.id);
    expect(found, isNotNull);
    expect(found!.fileBaseName, 'findme');
    expect(MusicLibraryService.instance.byId('local:/nope.mp3'), isNull);
  });
}
