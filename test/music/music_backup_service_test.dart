import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/music_backup_service.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/youtube_feed_service.dart';
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
  late Directory backupDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    backupDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    MusicPlaylistService.instance.resetForTest();
    MusicLibraryService.instance.resetForTest();
    YoutubeFeedService.instance.resetForTest();
    Config.autoBackupFrequency = 'off';
    Config.autoBackupDirectory = '';
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
    await backupDir.delete(recursive: true);
  });

  test('a backup restores playlists, wishlist and settings', () async {
    final playlists = MusicPlaylistService.instance;
    await playlists.load();
    final roadTrip = await playlists.createPlaylist('Road trip', ['t1', 't2']);
    await StorageService().saveTaskList([
      Task(title: 'Vinyl of Abbey Road', isWish: true),
    ]);
    Config.musicFolder = '/music/before';

    final file = await MusicBackupService.exportTo(backupDir.path);
    expect(file, isNotNull);
    expect(file!.path, contains('best_music_backup_'));
    final payload = jsonDecode(await file.readAsString()) as Map;
    expect(payload['app'], MusicBackupService.app);
    expect((payload['stores'] as Map).keys, contains('music_playlists.json'));
    expect(await MusicBackupService.lastRun(), isNotNull);

    // Lose everything, then restore.
    await playlists.deletePlaylist(roadTrip.id);
    await StorageService().saveTaskList([]);
    // A fresh install has no music folder yet: it takes the backup's.
    Config.musicFolder = '';

    final result = await MusicBackupService.restoreFile(file.path);
    expect(result.success, isTrue, reason: result.message);
    expect(playlists.byId(roadTrip.id)?.trackIds, ['t1', 't2']);
    final wishes = await StorageService().readTaskListRaw();
    expect(wishes.map((t) => t.title), ['Vinyl of Abbey Road']);
    expect(Config.musicFolder, '/music/before');
    expect(
        File('${tempDir.path}/${MusicBackupService.preRestoreFileName}')
            .existsSync(),
        isTrue);
  });

  test('refuses a BestToDo backup and junk files', () async {
    final besttodo = await MusicBackupService.restore({
      'export_version': 1,
      'settings': <String, dynamic>{},
      'tasks_bundle': <String, dynamic>{},
    });
    expect(besttodo.success, isFalse);
    expect(besttodo.message, contains('BestToDo'));

    expect((await MusicBackupService.restore([1, 2])).success, isFalse);

    final junk = File('${backupDir.path}/junk.json')
      ..writeAsStringSync('not json');
    expect((await MusicBackupService.restoreFile(junk.path)).success, isFalse);
  });

  test('maybeRun follows the automatic schedule', () async {
    expect(await MusicBackupService.maybeRun(), isNull); // off

    Config.autoBackupFrequency = 'daily';
    Config.autoBackupDirectory = backupDir.path;
    final first = await MusicBackupService.maybeRun(now: DateTime(2026, 1, 1, 9));
    expect(first, isNotNull);
    expect(await MusicBackupService.maybeRun(now: DateTime(2026, 1, 1, 20)),
        isNull);
    expect(await MusicBackupService.maybeRun(now: DateTime(2026, 1, 2, 8)),
        isNotNull);
  });

  group('songs keyed by path', () {
    const oldSong = '/old/Music/Rock/a.mp3';
    const newSong = '/new/Music/Rock/a.mp3';

    Future<void> seedOldPhone() async {
      Config.musicFolder = '/old/Music';
      File('${tempDir.path}/music_library.json').writeAsStringSync(jsonEncode([
        Track.local(
          filePath: oldSong,
          title: 'A',
          bpm: 128,
          playCount: 7,
          metadataEdited: true,
        ).toJson(),
      ]));
      File('${tempDir.path}/music_enrichment.json').writeAsStringSync(
          jsonEncode({'local:$oldSong': {'detectedBpm': 128}}));
      File('${tempDir.path}/youtube_feed.json').writeAsStringSync(jsonEncode({
        'progress': {
          'vid1': {'p': 60000, 'd': 120000}
        },
      }));
      File('${tempDir.path}/music_resume.json')
          .writeAsStringSync(jsonEncode({'currentId': 'local:$oldSong'}));
      await MusicPlaylistService.instance.load();
      await MusicPlaylistService.instance.toggleFavorite('local:$oldSong');
    }

    test('remapRoot moves paths, ids and keys under the old root only', () {
      final out = MusicBackupService.remapRoot({
        'local:$oldSong': ['/old/Music/b.mp3', 'local:/old/Musicals/c.mp3'],
        'filePath': '/old/Music/',
        'id': 'youtube:abc',
        'n': 3,
      }, '/old/Music/', '/new/Music');
      expect(out, {
        'local:$newSong': ['/new/Music/b.mp3', 'local:/old/Musicals/c.mp3'],
        'filePath': '/new/Music/',
        'id': 'youtube:abc',
        'n': 3,
      });
    });

    test('a restore onto a phone with another music folder keeps BPM, '
        'play counts, favourites, watch progress and the resume point',
        () async {
      await seedOldPhone();
      final file = await MusicBackupService.exportTo(backupDir.path);

      // The new phone: its own music folder, nothing else.
      for (final f in tempDir.listSync()) {
        f.deleteSync(recursive: true);
      }
      MusicPlaylistService.instance.resetForTest();
      MusicLibraryService.instance.resetForTest();
      YoutubeFeedService.instance.resetForTest();
      Config.musicFolder = '/new/Music';

      final result = await MusicBackupService.restoreFile(file!.path);
      expect(result.success, isTrue, reason: result.message);

      expect(Config.musicFolder, '/new/Music');
      final track = MusicLibraryService.instance.tracks.value.single;
      expect(track.id, 'local:$newSong');
      expect(track.filePath, newSong);
      expect(track.bpm, 128);
      expect(track.playCount, 7);
      expect(MusicPlaylistService.instance.isFavorite('local:$newSong'),
          isTrue);
      expect(
          jsonDecode(File('${tempDir.path}/music_enrichment.json')
              .readAsStringSync()),
          {'local:$newSong': {'detectedBpm': 128}});
      expect(YoutubeFeedService.instance.progress.value.keys, ['vid1']);
      expect(
          jsonDecode(
              File('${tempDir.path}/music_resume.json').readAsStringSync()),
          {'currentId': 'local:$newSong'});
    });

    test('relocateLibrary moves saved song data to a new folder', () async {
      await seedOldPhone();
      await MusicLibraryService.instance.load();

      expect(await MusicBackupService.relocateLibrary('/old/Music', '/new/Music'),
          isTrue);
      expect(MusicLibraryService.instance.tracks.value.single.id,
          'local:$newSong');
      expect(MusicPlaylistService.instance.isFavorite('local:$newSong'),
          isTrue);
      expect(await MusicBackupService.relocateLibrary('/new/Music', '/new/Music'),
          isFalse);
    });
  });
}
