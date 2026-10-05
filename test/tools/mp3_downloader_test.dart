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
        ..downloadOverride = null;
      Mp3DownloadManager.instance.resetForTest();
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
