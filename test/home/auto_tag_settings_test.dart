import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/auto_tag_group.dart';
import 'package:besttodo/services/auto_tag_service.dart';
import 'package:besttodo/ui/auto_tag_rules_page.dart';
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
    AutoTagService.instance.resetForTest();
  });

  tearDown(() {
    Config.autoTagEnabled = true;
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  testWidgets('Tasks section has an auto-tag switch and rules entry point',
      (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byTooltip('Expand Tasks'));
    await tester.pumpAndSettle();

    expect(find.text('Auto-tag new items'), findsOneWidget);
    final switchFinder = find.widgetWithText(SwitchListTile, 'Auto-tag new items');
    await tester.scrollUntilVisible(switchFinder, 80,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);

    await tester.tap(switchFinder);
    await tester.pump();
    expect(Config.autoTagEnabled, isFalse);
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);

    expect(find.text('Auto-tag rules'), findsOneWidget);
    await tester.tap(find.text('Auto-tag rules'));
    await tester.pumpAndSettle();
    expect(find.byType(AutoTagRulesPage), findsOneWidget);
  });

  testWidgets('Auto-tag rules page adds and deletes a tag group',
      (tester) async {
    await tester.runAsync(() => AutoTagService.instance.save([]));
    await tester.pumpWidget(
        const MaterialApp(home: AutoTagRulesPage()));
    await settle(tester);

    expect(find.textContaining('No auto-tag rules yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Add tag'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Tag to add'), 'kitchen');
    await tester.enterText(
        find.widgetWithText(TextField, 'Words'), 'lemon, lime');
    await tester.tap(find.text('Save'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('kitchen'), findsOneWidget);
    expect(find.text('lemon, lime'), findsOneWidget);
    expect(AutoTagService.instance.list.single,
        isA<AutoTagGroup>()
            .having((g) => g.tag, 'tag', 'kitchen')
            .having((g) => g.keywords, 'keywords', ['lemon', 'lime']));

    await tester.tap(find.byTooltip('Delete tag'));
    await settle(tester);
    expect(find.textContaining('No auto-tag rules yet'), findsOneWidget);
    expect(AutoTagService.instance.list, isEmpty);
  });
}
