import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/home_contexts.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:besttodo/utils/label_utils.dart';
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
    ProjectService.instance.resetForTest();
    Config.homeContexts = HomeContexts.defaults;
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  tearDown(() {
    Config.homeContexts = HomeContexts.defaults;
    Config.viewFilterRules = {};
  });

  Future<void> pumpHome(WidgetTester tester, Widget home,
      {required String marker}) async {
    final now = DateTime.now();
    await tester.runAsync(() => StorageService().saveTaskList([
          Task(title: 'Regular item', dueDate: now),
          Task(title: 'Migros item', label: worklistToken, dueDate: now),
          Task(title: 'Lemmon item', label: lemmonToken, dueDate: now),
          Task(title: 'Backlog item', isWish: true, dueDate: now),
        ]));
    await tester.pumpWidget(MaterialApp(home: home));
    final markerFinder = find.text(marker);
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(markerFinder, findsOneWidget,
        reason: 'HomePage never loaded the tasks');
  }

  testWidgets(
      'by default the home list shows regular items only; the Home row\'s '
      'arrow folds out toggles that show MLR / Lemmon items and are saved',
      (tester) async {
    await pumpHome(tester, const HomePage(), marker: 'Regular item');
    expect(find.text('Migros item'), findsNothing);
    expect(find.text('Lemmon item'), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('MLR'), findsNothing);
    await tester.tap(find.byTooltip('Show home filters'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MLR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todo'));
    await tester.pumpAndSettle();
    expect(Config.homeContexts,
        const HomeContexts(todo: false, mlr: true, lemmon: false));

    // Close the drawer and look at the list.
    await tester.tapAt(const Offset(790, 300));
    await tester.pumpAndSettle();
    expect(find.text('Migros item'), findsOneWidget);
    expect(find.text('Regular item'), findsNothing);
    expect(find.text('Lemmon item'), findsNothing);

    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    final settings = await tester.runAsync(() async =>
        jsonDecode(await File('${tempDir.path}/settings.json').readAsString())
            as Map<String, dynamic>);
    expect(settings!['homeContexts'],
        {'todo': false, 'mlr': true, 'lemmon': false, 'backlog': false});
  });

  testWidgets('the Backlog toggle shows wishlist items on the home list',
      (tester) async {
    // The seeded Home rules hide wishes; the toggle lifts that.
    Config.viewFilterRules = {
      ViewFilterRules.home: ViewFilterRules.defaultsFor(ViewFilterRules.home)!,
    };
    await pumpHome(tester, const HomePage(), marker: 'Regular item');
    expect(find.text('Backlog item'), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show home filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Backlog'));
    await tester.pumpAndSettle();
    expect(Config.homeContexts, const HomeContexts(backlog: true));

    await tester.tapAt(const Offset(790, 300));
    await tester.pumpAndSettle();
    expect(find.text('Backlog item'), findsOneWidget);
    expect(find.text('Regular item'), findsOneWidget);
    expect(find.text('Migros item'), findsNothing);
  });

  testWidgets('Tools ▸ Lemmon shows only lemmon-tagged items',
      (tester) async {
    await pumpHome(
      tester,
      const HomePage(tagFilter: lemmonToken, toolTitle: 'Lemmon'),
      marker: 'Lemmon item',
    );
    expect(find.text('Regular item'), findsNothing);
    expect(find.text('Migros item'), findsNothing);
  });

  test('Lemmon and Groceries are registered as features and start tools', () {
    for (final key in ['lemmon', 'groceries']) {
      expect(Config.featureKeys, contains(key));
      expect(Config.startToolOptions, contains(key));
    }
    expect(Config.featureKeys.length, Config.featureLabels.length);
    expect(Config.featureKeys.length, Config.featureDescriptions.length);
    expect(Config.startToolOptions.length, Config.startToolLabels.length);
  });
}
