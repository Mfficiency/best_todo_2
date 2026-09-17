import 'dart:io';

import 'package:besttodo/models/music_playlist.dart';
import 'package:besttodo/models/playlist_rule.dart';
import 'package:besttodo/services/music_library_service.dart';
import 'package:besttodo/services/music_playlist_service.dart';
import 'package:besttodo/ui/rule_playlist_editor_page.dart';
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
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    MusicLibraryService.instance.resetForTest();
    MusicPlaylistService.instance.resetForTest();
    // Real file I/O (seeding + persisting the two system playlists) — done
    // here in setUp, which runs outside testWidgets' fake-async zone, per
    // CLAUDE.md's "Real file I/O hangs inside testWidgets" note.
    await MusicPlaylistService.instance.load();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// Pushes [page] on top of a dummy first route, so the page's own
  /// `Navigator.pop()` on save has somewhere to return to.
  Future<void> pushPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => page)),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Taps Save, then drains the real file-write the handler awaits before
  /// popping — a single runAsync delay only advances ~one I/O hop, so this
  /// loops a fixed number of rounds instead of `pumpAndSettle()` (which
  /// never resolves a real dart:io Future inside the fake-async zone). Same
  /// pattern CLAUDE.md documents for a save-on-tap handler.
  Future<void> tapSaveAndDrain(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Save'));
    for (var i = 0; i < 60; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('creating a rule playlist with the default genre-equals row',
      (tester) async {
    await pushPage(tester, const RulePlaylistEditorPage());
    await tester.enterText(find.byType(TextField).at(0), 'Rock only');
    await tester.enterText(find.byType(TextField).at(1), 'Rock');

    await tapSaveAndDrain(tester);

    final created = MusicPlaylistService.instance.playlists.value
        .where((p) => p.kind == PlaylistKind.rule)
        .toList();
    expect(created, hasLength(1));
    expect(created.single.name, 'Rock only');
    expect(created.single.ruleSet!.conditions.single.field, RuleField.genre);
    expect(
        created.single.ruleSet!.conditions.single.operator, RuleOperator.equals);
    expect(created.single.ruleSet!.conditions.single.values, ['Rock']);
    // The page popped back to the dummy route.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('saving without a name shows a snackbar and creates nothing',
      (tester) async {
    await pushPage(tester, const RulePlaylistEditorPage());

    await tester.tap(find.byTooltip('Save'));
    await tester.pump();

    expect(find.text('Give the playlist a name'), findsOneWidget);
    expect(
      MusicPlaylistService.instance.playlists.value
          .where((p) => p.kind == PlaylistKind.rule),
      isEmpty,
    );
  });

  testWidgets('editing an existing rule playlist pre-fills its name and rule',
      (tester) async {
    late MusicPlaylist existing;
    await tester.runAsync(() async {
      existing = await MusicPlaylistService.instance.createRulePlaylist(
        'Old name',
        const PlaylistRuleSet(conditions: [
          RuleCondition(
              field: RuleField.artist,
              operator: RuleOperator.contains,
              values: ['Queen']),
        ]),
      );
    });

    await pushPage(tester, RulePlaylistEditorPage(existing: existing));

    expect(find.text('Old name'), findsOneWidget);
    expect(find.text('Queen'), findsOneWidget);
  });
}
