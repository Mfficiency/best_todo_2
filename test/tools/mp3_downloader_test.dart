import 'package:besttodo/services/mp3_downloader_service.dart';
import 'package:besttodo/ui/mp3_downloader_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('sanitizeMp3FileName', () {
    test('strips characters illegal on Windows/Android filesystems', () {
      expect(
        sanitizeMp3FileName('AC/DC: Thunderstruck?'),
        'AC_DC_ Thunderstruck_.mp3',
      );
    });

    test('collapses whitespace and falls back for an empty title', () {
      expect(sanitizeMp3FileName('  a   b  '), 'a b.mp3');
      expect(sanitizeMp3FileName('   '), 'audio.mp3');
    });

    test('caps very long titles so the save always succeeds', () {
      final name = sanitizeMp3FileName('x' * 200);
      expect(name.length, lessThanOrEqualTo(124));
      expect(name.endsWith('.mp3'), true);
    });
  });

  group('Mp3DownloaderPage', () {
    tearDown(() {
      Mp3DownloaderService.instance
        ..searchOverride = null
        ..resolveOverride = null
        ..downloadOverride = null;
    });

    testWidgets('a text query shows up to 5 candidates with channel/duration',
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
          ),
        ).take(limit).toList();
      };

      await tester.pumpWidget(const MaterialApp(home: Mp3DownloaderPage()));
      await tester.enterText(find.byType(TextField), 'lofi beats');
      await tester.tap(find.text('Find & download'));
      await tester.pumpAndSettle();

      expect(find.text('Track 0'), findsOneWidget);
      expect(find.text('Channel 0 · 1:00'), findsOneWidget);
      expect(find.text('Track 4'), findsOneWidget);
      expect(find.text('Track 5'), findsNothing);
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
  });
}
