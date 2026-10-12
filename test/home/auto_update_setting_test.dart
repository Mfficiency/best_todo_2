import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/services/app_updates.dart';
import 'package:besttodo/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../update/update_fakes.dart';

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
    AppUpdates.controller?.dispose();
    AppUpdates.controller = null;
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

    expect(find.text('Automatically update'), findsOneWidget);
    await tester.tap(find.text('Automatically update'));
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

    expect(find.text('Automatically update'), findsOneWidget);
    expect(find.text('Updates'), findsWidgets);
  });

  testWidgets(
      'the switch is what the updates package reads as "check '
      'automatically"', (tester) async {
    final c = fakeController(
        github: FakeGithub(), downloader: FakeDownloader());
    await pumpSettings(tester);
    await openSection(tester, 'Updates');
    expect(c.config.autoCheck(), isTrue);

    await tester.tap(find.text('Automatically update'));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    expect(c.config.autoCheck(), isFalse);
  });

  testWidgets('Updates has the package\'s Check for updates row',
      (tester) async {
    final github = FakeGithub()..releases = [release('v0.2.106-1000')];
    final installer = FakeInstaller();
    addTearDown(installer.dispose);
    fakeController(github: github, downloader: FakeDownloader());
    await pumpSettings(tester);
    await openSection(tester, 'Updates');
    expect(find.text('Current version 0.2.106 (1000)'), findsOneWidget);

    await tester.tap(find.text('Check for updates'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(github.requests, hasLength(1));
    expect(find.text('Up to date'), findsOneWidget);
  });

  testWidgets('Check for updates is findable through settings search',
      (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'check for updates');
    await tester.pump();
    expect(find.text('Check for updates'), findsOneWidget);
  });
}
