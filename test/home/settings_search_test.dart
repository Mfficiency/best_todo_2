import 'dart:io';

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

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    // initState kicks off the SMS config file load; walk real-event-loop
    // slices so the dart:io future completes inside testWidgets (see
    // test/README.md / home_search_test.dart for the pattern).
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('settings search lists matching entries and jumps to section',
      (tester) async {
    await pumpSettings(tester);

    // The task-search field of the home page is not here; settings has its
    // own search toggled from the app bar.
    expect(find.byTooltip('Search settings'), findsOneWidget);
    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'quiet');
    await tester.pump();

    // Result tile with its section as subtitle.
    expect(find.text('Quiet hours'), findsOneWidget);
    expect(find.text('Notifications'), findsWidgets);
    // The regular sections are replaced by results while searching.
    expect(find.text('Dark mode'), findsNothing);

    await tester.tap(find.text('Quiet hours'));
    await tester.pumpAndSettle();

    // Search closed and the Notifications section scrolled into view.
    expect(find.byTooltip('Search settings'), findsOneWidget);
    expect(find.text('Enable notifications'), findsOneWidget);
  });

  testWidgets('matches keywords and reports empty results', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();

    // "theme" is a keyword of Dark mode, not part of any title.
    await tester.enterText(find.byType(TextField).first, 'theme');
    await tester.pump();
    expect(find.text('Dark mode'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz-no-match');
    await tester.pump();
    expect(find.text('No settings match your search'), findsOneWidget);

    // Close search restores the section chips and content.
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.byTooltip('Search settings'), findsOneWidget);
  });
}
