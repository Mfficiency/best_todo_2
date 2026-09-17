import 'dart:io';
import 'dart:ui' as ui;

import 'package:besttodo/config.dart';
import 'package:besttodo/main_music.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_player_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Best Music (lib/main_music.dart) is a separate app entry point built from
// this same codebase — no to-do/alarm/sync machinery, so it needs its own
// setUpAll (mirroring what main() does) rather than sharing
// home_page_screenshot_test.dart's.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Config.load();
    // An existing-but-empty folder unlocks the tabbed Library/Playlists UI
    // (otherwise the whole page is just the "choose a folder" empty state)
    // without needing a real, decodable audio file — so nothing here ever
    // triggers real playback.
    final musicDir = await Directory.systemTemp.createTemp('best_music_screenshots');
    Config.musicFolder = musicDir.path;
    await MusicLibraryService.instance.load();
    await MusicLibraryService.instance.rescan();
    await MusicPlaylistService.instance.load();
    await MusicPlayerService.init();
  });

  testWidgets('capture Best Music screenshots', (tester) async {
    final appBoundaryKey = GlobalKey();

    // Same virtual phone-portrait size as home_page_screenshot_test.dart, so
    // the two apps' screenshots are directly comparable.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: appBoundaryKey,
        child: const BestMusicApp(),
      ),
    );
    await tester.pumpAndSettle();

    final folder = Directory('build/e2e_screenshots_music');
    await folder.create(recursive: true);
    Future<void> capture(String name) async {
      final filePath = '${folder.path}/$name.png';
      try {
        await binding.takeScreenshot(name);
      } catch (_) {
        // Fallback for platforms where integration_test screenshot capture
        // is not implemented.
      }

      final boundaryContext = appBoundaryKey.currentContext;
      if (boundaryContext == null) {
        fail('Could not find repaint boundary context for screenshot.');
      }
      final boundary =
          boundaryContext.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        fail('Could not find repaint boundary render object for screenshot.');
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        fail('Could not encode screenshot for "$name".');
      }
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      await File(filePath).writeAsBytes(bytes, flush: true);
    }

    // Every subpage here is pushed via buildSubpageAppBar, whose back button
    // is tooltip "Back to Home" rather than the default "Back" — falling
    // back to a raw Navigator.pop keeps this working either way (same
    // pattern as home_page_screenshot_test.dart's popCurrentPage).
    Future<void> popCurrentPage() async {
      final backButton = find.byTooltip('Back to Home');
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton.first);
        await tester.pumpAndSettle();
        return;
      }
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pop();
      await tester.pumpAndSettle();
    }

    Future<void> openDrawerEntry(String label) async {
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    // Root page: Library tab (empty — no tracks in the seeded folder) with
    // the Playlists tab alongside it.
    await capture('music_home_library_tab');
    await tester.tap(find.text('Playlists'));
    await tester.pumpAndSettle();
    await capture('music_home_playlists_tab');

    // Favorites is one of the two system playlists MusicPlaylistService
    // self-seeds; always present regardless of library contents.
    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    await capture('music_playlist_detail_page');
    await popCurrentPage();

    // New rule playlist editor — always the first Playlists-tab entry.
    await tester.tap(find.text('New rule playlist'));
    await tester.pumpAndSettle();
    await capture('rule_playlist_editor_page');
    await popCurrentPage();

    await openDrawerEntry('MP3 Downloader');
    await capture('mp3_downloader_page');
    await tester.tap(find.byTooltip('Downloads'));
    await tester.pumpAndSettle();
    await capture('mp3_downloads_page');
    await popCurrentPage(); // Downloads -> MP3 Downloader
    await popCurrentPage(); // MP3 Downloader -> Best Music home

    await openDrawerEntry('Settings');
    await capture('music_settings_page');
    await popCurrentPage();

    await openDrawerEntry('Changelog');
    await capture('music_changelog_page');
    await popCurrentPage();

    await openDrawerEntry('Startup Times');
    await capture('music_startup_times_page');
    await popCurrentPage();

    await openDrawerEntry('App Logs');
    await capture('music_app_logs_page');
    await popCurrentPage();

    await openDrawerEntry('About');
    await capture('music_about_page');
    await popCurrentPage();
  });
}
