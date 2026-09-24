import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/ui/music_metadata_scan_page.dart';
import 'package:flutter/material.dart';
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

  Future<void> writeFile(String relativePath) async {
    final file = File('${musicDir.path}/$relativePath');
    await file.create(recursive: true);
    await file.writeAsBytes([0, 0, 0]);
  }

  /// The scan runs from `initState`, doing real file I/O — a fixed
  /// `pumpAndSettle()` never resolves that inside testWidgets' fake-async
  /// zone (see CLAUDE.md's "Real file I/O hangs inside testWidgets" note),
  /// so this polls with real delays until the progress indicator (shown
  /// only while `_scanning` is true) disappears.
  Future<void> pumpUntilScanDone(WidgetTester tester, {int maxRounds = 100}) async {
    for (var i = 0; i < maxRounds; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) return;
    }
  }

  testWidgets('scans on open and lists every track found, with a genre/year status',
      (tester) async {
    await writeFile('untagged.mp3'); // no ID3 tags -> no genre, no year
    await writeFile('notes.txt'); // not a supported extension

    await tester.pumpWidget(const MaterialApp(home: MusicMetadataScanPage()));
    await pumpUntilScanDone(tester);

    expect(find.textContaining('1 track(s)'), findsOneWidget);
    expect(find.text('untagged'), findsOneWidget);
    expect(find.textContaining('no genre'), findsOneWidget);
    expect(find.textContaining('no year'), findsOneWidget);
  });

  testWidgets('shows Export/Import CSV actions alongside Scan again',
      (tester) async {
    // Not tapped: Export/Import go through real platform channels (the
    // share sheet, the OS file picker) with no test seam in this codebase
    // (music_player_page.dart's M3U import is the same, untapped-in-tests
    // pattern) — this only checks the buttons are there.
    await tester.pumpWidget(const MaterialApp(home: MusicMetadataScanPage()));
    await pumpUntilScanDone(tester);

    expect(find.byTooltip('Export metadata CSV'), findsOneWidget);
    expect(find.byTooltip('Import filled-in CSV'), findsOneWidget);
    expect(find.byTooltip('Scan again'), findsOneWidget);
  });

  testWidgets('the refresh action re-runs the scan', (tester) async {
    await writeFile('a.mp3');

    await tester.pumpWidget(const MaterialApp(home: MusicMetadataScanPage()));
    await pumpUntilScanDone(tester);
    expect(find.textContaining('1 track(s)'), findsOneWidget);

    await writeFile('b.mp3');
    await tester.tap(find.byTooltip('Scan again'));
    await pumpUntilScanDone(tester);

    expect(find.textContaining('2 track(s)'), findsOneWidget);
  });

  testWidgets('an empty music folder reports no tracks found', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MusicMetadataScanPage()));
    await pumpUntilScanDone(tester);

    expect(find.textContaining('No tracks found'), findsOneWidget);
  });
}
