import 'package:besttodo/services/mp3_download_manager.dart';
import 'package:besttodo/services/music_download_library_sync.dart';
import 'package:flutter_test/flutter_test.dart';

Mp3DownloadJob _job(
  String id, {
  Mp3DownloadStatus status = Mp3DownloadStatus.running,
  String dir = '/music',
}) =>
    Mp3DownloadJob(
      id: id,
      videoId: id,
      title: id,
      channel: '',
      destinationDir: dir,
      status: status,
      filePath: status == Mp3DownloadStatus.completed ? '$dir/$id.m4a' : null,
    );

void main() {
  late Mp3DownloadManager manager;
  late int rescans;
  late String folder;
  late MusicDownloadLibrarySync sync;

  setUp(() {
    manager = Mp3DownloadManager.instance..resetForTest();
    rescans = 0;
    folder = '/music';
    sync = MusicDownloadLibrarySync(
      manager: manager,
      rescan: () async => rescans++,
      musicFolder: () => folder,
    );
  });

  tearDown(() {
    sync.detach();
    manager.resetForTest();
  });

  test('rescans once a download into the library folder finishes', () {
    sync.attach();
    manager.jobs.value = [_job('a')];
    expect(rescans, 0);
    manager.jobs.value = [_job('a', status: Mp3DownloadStatus.completed)];
    expect(rescans, 1);
    // Republishing the same finished job doesn't rescan again.
    manager.jobs.value = List.of(manager.jobs.value);
    expect(rescans, 1);
  });

  test('waits for the queue to go idle: several songs, one rescan', () {
    sync.attach();
    manager.jobs.value = [
      _job('b'),
      _job('a', status: Mp3DownloadStatus.completed),
    ];
    expect(rescans, 0);
    manager.jobs.value = [
      _job('b', status: Mp3DownloadStatus.completed),
      _job('a', status: Mp3DownloadStatus.completed),
    ];
    expect(rescans, 1);
  });

  test('ignores downloads saved outside the library folder', () {
    sync.attach();
    manager.jobs.value = [
      _job('a', status: Mp3DownloadStatus.completed, dir: '/elsewhere'),
    ];
    manager.jobs.value = [
      _job('b', status: Mp3DownloadStatus.completed, dir: '/musicals'),
    ];
    expect(rescans, 0);
  });

  test('counts a subfolder of the library (playlist downloads)', () {
    sync.attach();
    manager.jobs.value = [
      _job('a', status: Mp3DownloadStatus.completed, dir: '/music/Mix/'),
    ];
    expect(rescans, 1);
  });

  test('failed or cancelled downloads never rescan', () {
    sync.attach();
    manager.jobs.value = [
      _job('a', status: Mp3DownloadStatus.failed),
      _job('b', status: Mp3DownloadStatus.cancelled),
    ];
    expect(rescans, 0);
  });

  test('history loaded before attach does not trigger a rescan', () {
    manager.jobs.value = [_job('old', status: Mp3DownloadStatus.completed)];
    sync.attach();
    manager.jobs.value = List.of(manager.jobs.value);
    expect(rescans, 0);
  });

  test('no library folder chosen means nothing to rescan', () {
    folder = '';
    sync.attach();
    manager.jobs.value = [_job('a', status: Mp3DownloadStatus.completed)];
    expect(rescans, 0);
  });
}
