import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/ui/settings_page.dart';
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
  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    Config.simpleMode = false;
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    // initState kicks off the SMS config file load; walk real-event-loop
    // slices so the dart:io future completes inside testWidgets (see
    // test/README.md).
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('sections collapse from their title, mode & features starts closed',
      (tester) async {
    await pumpSettings(tester);

    // Appearance is open, Mode & features is not.
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.text('Simple mode'), findsNothing);
    expect(find.byTooltip('Expand Mode & features'), findsOneWidget);

    // Tapping the title (the chevron sits inside it) closes Appearance.
    await tester.tap(find.byTooltip('Collapse Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsNothing);
    expect(find.byTooltip('Expand Appearance'), findsOneWidget);

    await tester.tap(find.byTooltip('Expand Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsOneWidget);
  });

  testWidgets('collapse all closes every section and turns into expand all',
      (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Collapse all'));
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsNothing);
    expect(find.text('Widget progress line'), findsNothing);
    expect(find.text('Collapse all'), findsNothing);

    await tester.tap(find.text('Expand all'));
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.text('Collapse all'), findsOneWidget);
  });

  testWidgets('jumping to a collapsed section opens it', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Mode & features'));
    await tester.pumpAndSettle();

    expect(find.text('Simple mode'), findsOneWidget);
  });
}
