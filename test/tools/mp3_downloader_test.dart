import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/media_scanner_service.dart';
import 'package:besttodo/services/mp3_download_manager.dart';
import 'package:besttodo/services/mp3_downloader_service.dart';
import 'package:besttodo/ui/mp3_downloader_page.dart';
import 'package:besttodo/ui/mp3_downloads_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The real end-to-end download (live YouTube, real bytes on disk) is
/// `tool/check_mp3_download.dart`, run by hand — see its header. These tests
/// cover everything around it with fakes so they stay offline and fast.
void main() {
  group('looksLikeYoutubeUrl / extractYoutubeVideoId', () {
    test('matches common YouTube URL forms and captures the video id', () {
      expect(
        looksLikeYoutubeUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        true,
      );
      expect(
        extractYoutubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ'),
        'dQw4w9WgXcQ',
      );
      expect(looksLikeYoutubeUrl('https://youtu.be/dQw4w9WgXcQ'), true);
      expect(
        extractYoutubeVideoId('https://youtu.be/dQw4w9WgXcQ?t=10'),
        'dQw4w9WgXcQ',
      );
      expect(
        looksLikeYoutubeUrl('https://m.youtube.com/watch?v=dQw4w9WgXcQ'),
        true,
      );
      expect(
        looksLikeYoutubeUrl('https://www.youtube.com/shorts/dQw4w9WgXcQ'),
        true,
      );
    });

    test('does not treat a plain title search as a URL', () {
      expect(looksLikeYoutubeUrl('never gonna give you up'), false);
      expect(extractYoutubeVideoId('never gonna give you up'), null);
    });
  });

  group('sanitizeAudioFileName', () {
    test('strips characters illegal on Windows/Android filesystems', () {
      expect(
        sanitizeAudioFileName('AC/DC: Thunderstruck?', 'm4a'),
        'AC_DC_ Thunderstruck_.m4a',
      );
    });

    test('collapses whitespace and falls back for an empty title', () {
      expect(sanitizeAudioFileName('  a   b  ', 'm4a'), 'a b.m4a');
      expect(sanitizeAudioFileName('   ', 'webm'), 'audio.webm');
    });

    test('caps very long titles so the save always succeeds', () {
      final name = sanitizeAudioFileName('x' * 200, 'm4a');
      expect(name.length, lessThanOrEqualTo(124));
      expect(name.endsWith('.m4a'), true);
    });
  });

  group('formatViewCount', () {
    test('abbreviates the way YouTube does', () {
      expect(formatViewCount(999), '999');
      expect(formatViewCount(1500), '1.5K');
      expect(formatViewCount(15000), '15K');
      expect(formatViewCount(1500000), '1.5M');
      expect(formatViewCount(376336046), '376M');
      expect(formatViewCount(1800000000), '1.8B');
    });

    test('renders nothing when YouTube reported no count', () {
      expect(formatViewCount(null), '');
    });
  });

  group('looksLikeYoutubePlaylistUrl', () {
    test('matches a playlist URL', () {
      expect(
        looksLikeYoutubePlaylistUrl(
            'https://www.youtube.com/playlist?list=PLabc123'),
        true,
      );
    });

    test('matches a video URL that also carries a list param', () {
      expect(
        looksLikeYoutubePlaylistUrl(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc123',
        ),
        true,
      );
    });

    test('does not match a plain video URL', () {
      expect(looksLikeYoutubePlaylistUrl('https://youtu.be/dQw4w9WgXcQ'),
          false);
    });

    test('does not misfire on an ordinary single-word search query', () {
      // youtube_explode_dart's own PlaylistId parser would treat either of
      // these as "a valid raw playlist id" — this has its own domain-anchored
      // check specifically so a search query never gets routed as a playlist.
      expect(looksLikeYoutubePlaylistUrl('lofi'), false);
      expect(looksLikeYoutubePlaylistUrl('workoutmix2024'), false);
    });
  });

  group('existingTrackBaseNames', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mp3_dedup_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('finds audio files recursively, case-insensitively, by base name',
        () async {
      await File('${tempDir.path}/Artist - Song.m4a').writeAsBytes([0]);
      final sub = Directory('${tempDir.path}/sub')..createSync();
      await File('${sub.path}/Other Artist - Other Song.webm')
          .writeAsBytes([0]);
      await File('${tempDir.path}/not audio.txt').writeAsBytes([0]);

      final names = await existingTrackBaseNames(tempDir.path);
      expect(names, contains('artist - song'));
      expect(names, contains('other artist - other song'));
      expect(names, hasLength(2));
    });

    test('a missing folder yields an empty set rather than an error',
        () async {
      final names = await existingTrackBaseNames('${tempDir.path}/missing');
      expect(names, isEmpty);
    });
  });

  group('Mp3DownloaderService.resolvePlaylist', () {
    tearDown(() => Mp3DownloaderService.instance.playlistOverride = null);

    test('maps playlist tracks the same way search/resolve do', () async {
      Mp3DownloaderService.instance.playlistOverride = (input) async {
        expect(input, 'https://www.youtube.com/playlist?list=PLtest');
        return const Mp3PlaylistInfo(title: 'My Mix', tracks: [
          Mp3SearchResult(
            videoId: 'a',
            title: 'Artist - One',
            channel: 'Artist',
            duration: Duration(minutes: 3),
          ),
        ]);
      };
      final info = await Mp3DownloaderService.instance
          .resolvePlaylist('https://www.youtube.com/playlist?list=PLtest');
      expect(info.title, 'My Mix');
      expect(info.tracks, hasLength(1));
      expect(info.tracks.first.videoId, 'a');
    });
  });

  group('Mp3DownloadJob', () {
    test('round-trips through JSON', () {
      final job = Mp3DownloadJob(
        id: 'j1',
        videoId: 'v1',
        title: 'Track',
        channel: 'Chan',
        destinationDir: '/tmp',
        status: Mp3DownloadStatus.completed,
        receivedBytes: 10,
        totalBytes: 20,
        filePath: '/tmp/Track.m4a',
      );
      final restored = Mp3DownloadJob.fromJson(job.toJson());
      expect(restored.id, 'j1');
      expect(restored.title, 'Track');
      expect(restored.status, Mp3DownloadStatus.completed);
      expect(restored.filePath, '/tmp/Track.m4a');
      expect(restored.progress, 0.5);
    });

    test('a job still running when the app closed comes back as interrupted',
        () {
      final job = Mp3DownloadJob(
        id: 'j2',
        videoId: 'v2',
        title: 'Track',
        channel: 'Chan',
        destinationDir: '/tmp',
        status: Mp3DownloadStatus.running,
        receivedBytes: 5,
        totalBytes: 100,
      );
      final restored = Mp3DownloadJob.fromJson(job.toJson());
      // Otherwise the downloads page would show a progress bar that can
      // never move again.
      expect(restored.status, Mp3DownloadStatus.failed);
      expect(restored.error, contains('Interrupted'));
      expect(restored.isActive, false);
    });

    test('progress is null until the total size is known', () {
      final job = Mp3DownloadJob(
        id: 'j3',
        videoId: 'v3',
        title: 'Track',
        channel: 'Chan',
        destinationDir: '/tmp',
      );
      expect(job.progress, isNull);
      expect(job.isActive, true);
    });
  });

  group('Mp3DownloadManager', () {
    tearDown(() {
      Mp3DownloaderService.instance.downloadOverride = null;
      MediaScannerService.scanOverride = null;
      Mp3DownloadManager.instance.resetForTest();
    });

    test('a completed download notifies the media database of the new file',
        () async {
      Mp3DownloaderService.instance.downloadOverride =
          (result, dir, onProgress) async => '$dir/${result.title}.m4a';
      final scanned = <String>[];
      MediaScannerService.scanOverride = (path) async => scanned.add(path);

      final manager = Mp3DownloadManager.instance;
      final job = manager.enqueue(
        const Mp3SearchResult(
          videoId: 'v1',
          title: 'Track',
          channel: 'Chan',
          duration: null,
        ),
        '/music',
      );
      while (job.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(scanned, ['/music/Track.m4a']);
    });

    test('a failed download never touches the media database', () async {
      Mp3DownloaderService.instance.downloadOverride =
          (result, dir, onProgress) async {
        throw Mp3DownloadException('boom');
      };
      final scanned = <String>[];
      MediaScannerService.scanOverride = (path) async => scanned.add(path);

      final manager = Mp3DownloadManager.instance;
      final job = manager.enqueue(
        const Mp3SearchResult(
          videoId: 'v2',
          title: 'Track',
          channel: 'Chan',
          duration: null,
        ),
        '/music',
      );
      while (job.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(scanned, isEmpty);
    });

    test('runs a queued job and records where it landed', () async {
      Mp3DownloaderService.instance.downloadOverride =
          (result, dir, onProgress) async {
        onProgress?.call(512, 1024);
        onProgress?.call(1024, 1024);
        return '$dir/${result.title}.m4a';
      };
      final manager = Mp3DownloadManager.instance;
      final job = manager.enqueue(
        const Mp3SearchResult(
          videoId: 'v1',
          title: 'Track',
          channel: 'Chan',
          duration: null,
        ),
        '/music',
      );
      // The download runs off the page, so the caller gets the job back
      // straight away (already picked up by the queue) and watches it from
      // there rather than awaiting the transfer.
      expect(job.isActive, true);

      while (job.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(job.status, Mp3DownloadStatus.completed);
      expect(job.filePath, '/music/Track.m4a');
      expect(job.receivedBytes, 1024);
      expect(job.progress, 1.0);
      expect(manager.activeCount, 0);
    });

    test('a failing download keeps the message instead of vanishing',
        () async {
      Mp3DownloaderService.instance.downloadOverride =
          (result, dir, onProgress) async {
        throw Mp3DownloadException('YouTube refused the rest of this track');
      };
      final manager = Mp3DownloadManager.instance;
      final job = manager.enqueue(
        const Mp3SearchResult(
          videoId: 'v2',
          title: 'Blocked',
          channel: 'Chan',
          duration: null,
        ),
        '/music',
      );
      while (job.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(job.status, Mp3DownloadStatus.failed);
      expect(job.error, contains('refused'));
    });

    test('cancelling a queued job stops it before it starts', () async {
      final started = <String>[];
      Mp3DownloaderService.instance.downloadOverride =
          (result, dir, onProgress) async {
        started.add(result.title);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return '$dir/${result.title}.m4a';
      };
      final manager = Mp3DownloadManager.instance;
      const template = Mp3SearchResult(
        videoId: 'v',
        title: 'First',
        channel: 'Chan',
        duration: null,
      );
      final first = manager.enqueue(template, '/music');
      // Downloads run one at a time, so the second is still queued and can
      // be cancelled without any bytes being fetched.
      final second = manager.enqueue(
        const Mp3SearchResult(
            videoId: 'v2', title: 'Second', channel: 'Chan', duration: null),
        '/music',
      );
      manager.cancel(second.id);
      expect(second.status, Mp3DownloadStatus.cancelled);

      while (first.isActive) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(started, ['First']);
    });

    test('clearFinished keeps active jobs', () async {
      final manager = Mp3DownloadManager.instance;
      manager.jobs.value = [
        Mp3DownloadJob(
          id: 'done',
          videoId: 'v',
          title: 'Done',
          channel: '',
          destinationDir: '/m',
          status: Mp3DownloadStatus.completed,
        ),
        Mp3DownloadJob(
          id: 'busy',
          videoId: 'v',
          title: 'Busy',
          channel: '',
          destinationDir: '/m',
          status: Mp3DownloadStatus.running,
        ),
      ];
      await manager.clearFinished();
      expect(manager.jobs.value.map((j) => j.id), ['busy']);
    });
  });

  group('Mp3DownloaderPage', () {
    tearDown(() {
      Mp3DownloaderService.instance
        ..searchOverride = null
        ..resolveOverride = null
        ..playlistOverride = null
        ..downloadOverride = null;
      Mp3DownloadManager.instance.resetForTest();
      Config.mp3DownloadFolder = '';
    });

    testWidgets('a text query shows up to 5 candidates with plays',
        (tester) async {
      Mp3DownloaderService.instance.searchOverride = (query, limit) async {
        expect(query, 'lofi beats');
        return List.generate(
          7,
          (i) => Mp3SearchResult(
            videoId: 'id$i',
            title: 'Track $i',
            channel: 'Channel $i',
            duration: Duration(minutes: i + 1),
            viewCount: (i + 1) * 1000000,
          ),
        ).take(limit).toList();
      };

      await tester.pumpWidget(const MaterialApp(home: Mp3DownloaderPage()));
      await tester.enterText(find.byType(TextField), 'lofi beats');
      await tester.tap(find.text('Find & download'));
      await tester.pumpAndSettle();

      expect(find.text('Track 0'), findsOneWidget);
      expect(find.text('Channel 0 · 1:00 · 1.0M plays'), findsOneWidget);
      expect(find.text('Channel 4 · 5:00 · 5.0M plays'), findsOneWidget);
      expect(find.text('Track 5'), findsNothing);
    });

    testWidgets('a result without a play count just omits it', (tester) async {
      Mp3DownloaderService.instance.searchOverride = (query, limit) async => [
            const Mp3SearchResult(
              videoId: 'id0',
              title: 'Live now',
              channel: 'Someone',
              duration: Duration(minutes: 2),
            ),
          ];

      await tester.pumpWidget(const MaterialApp(home: Mp3DownloaderPage()));
      await tester.enterText(find.byType(TextField), 'live');
      await tester.tap(find.text('Find & download'));
      await tester.pumpAndSettle();

      expect(find.text('Someone · 2:00'), findsOneWidget);
    });

    testWidgets('no results shows an error instead of an empty list',
        (tester) async {
      Mp3DownloaderService.instance.searchOverride =
          (query, limit) async => <Mp3SearchResult>[];

      await tester.pumpWidget(const MaterialApp(home: Mp3DownloaderPage()));
      await tester.enterText(find.byType(TextField), 'asdkjfhaslkdjfh');
      await tester.tap(find.text('Find & download'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No results found'), findsOneWidget);
    });

    testWidgets('a pasted URL resolves directly without showing a picker',
        (tester) async {
      var resolved = false;
      Mp3DownloaderService.instance.resolveOverride = (id) async {
        resolved = true;
        return Mp3SearchResult(
          videoId: id,
          title: 'Direct video',
          channel: 'Some channel',
          duration: const Duration(minutes: 3),
        );
      };

      await tester.pumpWidget(const MaterialApp(home: Mp3DownloaderPage()));
      await tester.enterText(
        find.byType(TextField),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      await tester.tap(find.text('Find & download'));
      await tester.pumpAndSettle();

      expect(resolved, true);
      // A direct URL never shows the ambiguous-results picker.
      expect(find.text('Direct video'), findsNothing);
    });

    testWidgets(
        'a playlist link shows every track, pre-unselecting ones already '
        'downloaded', (tester) async {
      late Directory tempDir;
      // Real file I/O must run on the real event loop via runAsync, not the
      // fake-async test zone — see test/README.md.
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('mp3_playlist_a');
        Config.mp3DownloadFolder = tempDir.path;
        // Already sitting in the (fake) music folder under the exact name a
        // fresh download of the first track would use.
        await File('${tempDir.path}/Artist - Already Have This.m4a')
            .writeAsBytes([0]);
      });
      addTearDown(() => tempDir.delete(recursive: true));

      Mp3DownloaderService.instance.playlistOverride = (input) async {
        expect(input, contains('list=PLtest'));
        return const Mp3PlaylistInfo(title: 'My Mix', tracks: [
          Mp3SearchResult(
            videoId: 'a',
            title: 'Artist - Already Have This',
            channel: 'Artist',
            duration: Duration(minutes: 3),
          ),
          Mp3SearchResult(
            videoId: 'b',
            title: 'Artist - New Track',
            channel: 'Artist',
            duration: Duration(minutes: 4),
          ),
        ]);
      };

      await tester.pumpWidget(const MaterialApp(home: Mp3DownloaderPage()));
      await tester.enterText(
        find.byType(TextField),
        'https://www.youtube.com/playlist?list=PLtest',
      );
      await tester.tap(find.text('Find & download'));
      // Real folder-scanning I/O (existingTrackBaseNames) runs off the tap,
      // outside the fake-async zone — poll until the resolved stage renders.
      final marker = find.text('My Mix · 1 of 2 selected');
      for (var i = 0; i < 60 && marker.evaluate().isEmpty; i++) {
        await tester
            .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(marker, findsOneWidget);
      expect(find.text('Already downloaded'), findsOneWidget);
      expect(find.text('Download 1'), findsOneWidget);
    });

    testWidgets('All/None bulk-select, then Download N queues the checked '
        'tracks', (tester) async {
      late Directory tempDir;
      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('mp3_playlist_b');
        Config.mp3DownloadFolder = tempDir.path;
      });
      addTearDown(() => tempDir.delete(recursive: true));

      Mp3DownloaderService.instance.playlistOverride = (input) async =>
          const Mp3PlaylistInfo(title: 'Mix', tracks: [
            Mp3SearchResult(
                videoId: 'a', title: 'A - One', channel: 'A', duration: null),
            Mp3SearchResult(
                videoId: 'b', title: 'B - Two', channel: 'B', duration: null),
          ]);
      final queued = <String>[];
      Mp3DownloaderService.instance.downloadOverride =
          (result, dir, onProgress) async {
        queued.add(result.videoId);
        return '$dir/${result.title}.m4a';
      };

      await tester.pumpWidget(const MaterialApp(home: Mp3DownloaderPage()));
      await tester.enterText(
        find.byType(TextField),
        'https://www.youtube.com/playlist?list=PLx',
      );
      await tester.tap(find.text('Find & download'));
      final marker = find.text('Mix · 2 of 2 selected');
      for (var i = 0; i < 60 && marker.evaluate().isEmpty; i++) {
        await tester
            .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(marker, findsOneWidget);

      await tester.tap(find.text('None'));
      await tester.pump();
      expect(find.text('Mix · 0 of 2 selected'), findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.pump();
      expect(find.text('Mix · 2 of 2 selected'), findsOneWidget);

      await tester.tap(find.text('Download 2'));
      // Downloads run one at a time (Mp3DownloadManager._drain) and each one
      // saves history via path_provider, real I/O that needs the real event
      // loop like any other dart:io call — poll with runAsync rather than
      // trusting pumpAndSettle to catch a frame scheduled only once that
      // resolves.
      for (var i = 0; i < 60 && queued.length < 2; i++) {
        await tester
            .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      expect(queued, containsAll(<String>['a', 'b']));
      // Queuing resets the page back to idle rather than leaving the
      // just-downloaded checklist on screen.
      expect(find.text('Mix · 2 of 2 selected'), findsNothing);
    });

    testWidgets('the downloads button badges whatever is still running',
        (tester) async {
      final manager = Mp3DownloadManager.instance;
      await tester.pumpWidget(
        MaterialApp(home: Mp3DownloaderPage(manager: manager)),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Downloads'), findsOneWidget);
      expect(find.text('1'), findsNothing);

      manager.jobs.value = [
        Mp3DownloadJob(
          id: 'busy',
          videoId: 'v',
          title: 'Busy',
          channel: '',
          destinationDir: '/m',
          status: Mp3DownloadStatus.running,
        ),
      ];
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
    });
  });

  group('Mp3DownloadsPage', () {
    tearDown(() => Mp3DownloadManager.instance.resetForTest());

    testWidgets('lists running and finished downloads', (tester) async {
      final manager = Mp3DownloadManager.instance;
      manager.jobs.value = [
        Mp3DownloadJob(
          id: 'a',
          videoId: 'v1',
          title: 'Running track',
          channel: 'Chan',
          destinationDir: '/m',
          status: Mp3DownloadStatus.running,
          receivedBytes: 1024 * 1024,
          totalBytes: 4 * 1024 * 1024,
        ),
        Mp3DownloadJob(
          id: 'b',
          videoId: 'v2',
          title: 'Old track',
          channel: 'Chan',
          destinationDir: '/m',
          status: Mp3DownloadStatus.completed,
          filePath: '/m/Old track.m4a',
        ),
        Mp3DownloadJob(
          id: 'c',
          videoId: 'v3',
          title: 'Bad track',
          channel: 'Chan',
          destinationDir: '/m',
          status: Mp3DownloadStatus.failed,
          error: 'YouTube refused the rest of this track',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(home: Mp3DownloadsPage(manager: manager)),
      );
      await tester.pump();

      expect(find.text('Running track'), findsOneWidget);
      expect(find.textContaining('1.0 MB of 4.0 MB · 25%'), findsOneWidget);
      expect(find.text('Saved to /m/Old track.m4a'), findsOneWidget);
      expect(
        find.text('YouTube refused the rest of this track'),
        findsOneWidget,
      );
    });

    testWidgets('shows an empty state before anything is downloaded',
        (tester) async {
      final manager = Mp3DownloadManager.instance;
      await tester.pumpWidget(
        MaterialApp(home: Mp3DownloadsPage(manager: manager)),
      );
      await tester.pump();
      expect(find.text('No downloads yet.'), findsOneWidget);
    });
  });
}
