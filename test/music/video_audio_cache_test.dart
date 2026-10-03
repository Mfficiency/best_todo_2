import 'dart:io';

import 'package:besttodo/models/track.dart';
import 'package:besttodo/services/video_audio_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late DateTime now;
  late List<String> downloads;
  late VideoAudioCache cache;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('video_cache');
    now = DateTime(2026, 10, 3, 12);
    downloads = [];
    cache = VideoAudioCache(
      root: () async => root,
      now: () => now,
      download: (result, dir) async {
        downloads.add(result.videoId);
        final file = File('$dir/${result.title}.m4a');
        await file.writeAsString('audio');
        await file.setLastModified(now);
        return file.path;
      },
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Track video(String id) =>
      Track.youtube(videoId: id, title: 'Episode $id', artist: 'Channel');

  test('starting a feed video downloads it once and serves it from disk',
      () async {
    await cache.cacheInBackground(video('v1'));
    await cache.cacheInBackground(video('v1')); // already on its way
    await cache.idle;
    expect(downloads, ['v1']);
    final file = await cache.cachedFile('v1');
    expect(file, isNotNull);
    expect(await file!.readAsString(), 'audio');

    await cache.cacheInBackground(video('v1')); // cached: no re-download
    await cache.idle;
    expect(downloads, ['v1']);
  });

  test('songs streamed from YouTube are not cached here', () async {
    await cache.cacheInBackground(
        Track.youtube(videoId: 's1', title: 'Song', song: true));
    await cache.idle;
    expect(downloads, isEmpty);
  });

  test('kept for a week after last play, then purged', () async {
    await cache.cacheInBackground(video('v1'));
    await cache.idle;

    now = now.add(const Duration(days: 6));
    final file = await cache.cachedFile('v1');
    expect(file, isNotNull);
    await cache.touch(file!); // played again: countdown restarts

    now = now.add(const Duration(days: 6));
    expect(await cache.cachedFile('v1'), isNotNull);

    now = now.add(const Duration(days: 2));
    expect(await cache.cachedFile('v1'), isNull);
    await cache.purgeExpired();
    expect(await Directory('${root.path}/v1').exists(), isFalse);
  });

  test('a failed download leaves nothing behind', () async {
    final failing = VideoAudioCache(
      root: () async => root,
      now: () => now,
      download: (_, __) async => throw Exception('offline'),
    );
    await failing.cacheInBackground(video('v2'));
    await failing.idle;
    expect(await failing.cachedFile('v2'), isNull);
    expect(failing.isCaching('v2'), isFalse);
    expect(await Directory('${root.path}/v2').exists(), isFalse);
  });
}
