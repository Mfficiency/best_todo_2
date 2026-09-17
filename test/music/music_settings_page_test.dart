import 'package:besttodo/config.dart';
import 'package:besttodo/ui/music_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Best Music's Settings page (SPEC.md §10.6f): just the music folder and its
/// excluded subfolders, standalone from BestToDo's monolithic settings_page.dart.
void main() {
  setUp(() {
    Config.musicFolder = '';
    Config.musicExcludedSubfolders = [];
  });

  tearDown(() {
    Config.musicFolder = '';
    Config.musicExcludedSubfolders = [];
  });

  testWidgets('prompts to choose a folder when none is set', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: MusicSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Not set — choose the folder your music lives in'),
        findsOneWidget);
    expect(find.text('Forget this folder'), findsNothing);
    expect(find.text('Excluded subfolders'), findsNothing);
  });

  testWidgets('shows the folder path and exclusion controls once set',
      (tester) async {
    Config.musicFolder = '/does/not/matter/for/this/test';
    Config.musicExcludedSubfolders = ['Podcasts'];

    await tester.pumpWidget(const MaterialApp(home: MusicSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('/does/not/matter/for/this/test'), findsOneWidget);
    expect(find.text('Forget this folder'), findsOneWidget);
    expect(find.text('Excluded subfolders'), findsOneWidget);
    expect(find.text('Podcasts'), findsOneWidget);
  });

  testWidgets('"Forget this folder" clears the folder and its exclusions',
      (tester) async {
    Config.musicFolder = '/does/not/matter/for/this/test';
    Config.musicExcludedSubfolders = ['Podcasts'];

    await tester.pumpWidget(const MaterialApp(home: MusicSettingsPage()));
    await tester.pumpAndSettle();

    // Config.save() inside the tap handler is real (best-effort, errors
    // swallowed) file I/O — run the tap under runAsync so its Future can
    // actually complete instead of hanging the fake-async zone.
    await tester.runAsync(() async {
      await tester.tap(find.text('Forget this folder'));
      await tester.pump();
    });
    await tester.pumpAndSettle();

    expect(Config.musicFolder, isEmpty);
    expect(Config.musicExcludedSubfolders, isEmpty);
    expect(find.text('Not set — choose the folder your music lives in'),
        findsOneWidget);
  });
}
