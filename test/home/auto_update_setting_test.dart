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
    Config.autoUpdateCheckEnabled = true;
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

  Future<void> openSection(WidgetTester tester, String title) async {
    final header = find.byTooltip('Expand $title');
    await tester.scrollUntilVisible(header, 80,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();
  }

  testWidgets('the Updates section switch persists to Config', (tester) async {
    expect(Config.autoUpdateCheckEnabled, isTrue);

    await pumpSettings(tester);
    await openSection(tester, 'Updates');

    expect(find.text('Automatically check for updates'), findsOneWidget);
    await tester.tap(find.text('Automatically check for updates'));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    expect(Config.autoUpdateCheckEnabled, isFalse);

    // The switch was persisted, not just flipped in memory.
    Config.autoUpdateCheckEnabled = true;
    await tester.runAsync(Config.load);
    expect(Config.autoUpdateCheckEnabled, isFalse);
  });

  testWidgets('the setting is findable through settings search',
      (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'auto update');
    await tester.pump();

    expect(find.text('Automatically check for updates'), findsOneWidget);
    expect(find.text('Updates'), findsWidgets);
  });
}
