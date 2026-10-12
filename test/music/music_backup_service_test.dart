import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
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
    Config.musicFolder = '/music/after';

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
}
