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
    for (final key in Config.featureKeys) {
      Config.featureEnabled[key] = true;
    }
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    // initState kicks off the SMS config file load; walk real-event-loop
    // slices so the dart:io future completes inside testWidgets.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pump();
  }

  testWidgets('full mode lists the feature switches and every section',
      (tester) async {
    await pumpSettings(tester);

    expect(find.widgetWithText(ChoiceChip, 'Mode & features'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Streak'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'SMS report'), findsOneWidget);

    // The feature switches are searchable and point at their section.
    await search(tester, 'alarms');
    expect(find.widgetWithText(ListTile, 'Alarms'), findsOneWidget);
    expect(find.text('Mode & features'), findsWidgets);
  });

  testWidgets('simple mode drops the feature-owned sections and switches',
      (tester) async {
    Config.simpleMode = true;
    await pumpSettings(tester);

    // Chips (and content) of features that simple mode switches off are gone.
    expect(find.widgetWithText(ChoiceChip, 'Streak'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'SMS report'), findsNothing);
    expect(find.text('Show streak'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Mode & features'), findsOneWidget);

    // So are their entries in the settings search, and the per-feature
    // switches (they only apply in full mode).
    await search(tester, 'streak');
    expect(find.text('No settings match your search'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'alarms');
    await tester.pump();
    expect(find.text('No settings match your search'), findsOneWidget);
  });

  testWidgets('switching a feature off hides its settings section',
      (tester) async {
    Config.setFeatureEnabled('streak', false);
    await pumpSettings(tester);

    expect(find.widgetWithText(ChoiceChip, 'Streak'), findsNothing);
    expect(find.text('Show streak'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'SMS report'), findsOneWidget);
  });

  testWidgets('the simple mode switch persists and updates the page',
      (tester) async {
    await pumpSettings(tester);

    await tester.scrollUntilVisible(find.text('Simple mode'), 80,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simple mode'));
    // The handler awaits Config.save() before the rebuild lands.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    expect(Config.simpleMode, isTrue);
    expect(
      find.text(
          'Simple mode hides every optional feature. Turn it off to pick '
          'the features you want.'),
      findsOneWidget,
    );

    Config.simpleMode = false;
    await tester.runAsync(Config.load);
    expect(Config.simpleMode, isTrue);
  });
}
