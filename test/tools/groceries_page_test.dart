import 'dart:convert';
import 'dart:io';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/grocery_category_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/groceries_page.dart';
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
    GroceryCategoryService.instance.resetForTest();
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  Future<void> pumpGroceries(WidgetTester tester,
      {required List<Task> tasks, required String marker}) async {
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: GroceriesPage()));
    final markerFinder = find.text(marker);
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
    expect(markerFinder, findsOneWidget,
        reason: 'GroceriesPage never loaded the tasks');
  }

  Future<void> settleWrites(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<List<dynamic>> readTasks(WidgetTester tester) async {
    return await tester.runAsync(() async => jsonDecode(
            await File('${tempDir.path}/tasks.json').readAsString())
        as List<dynamic>) as List<dynamic>;
  }

  testWidgets(
      'shows only grocery items, sectioned by category in the configured '
      'order, unknown categories under Other', (tester) async {
    await pumpGroceries(
      tester,
      tasks: [
        Task(title: 'Plain task', dueDate: DateTime.now()),
        Task(title: 'Pasta', isGrocery: true, groceryCategory: 'Pasta & rice'),
        Task(title: 'Apples', isGrocery: true,
            groceryCategory: 'Fruit & vegetables'),
        Task(title: 'Glue', isGrocery: true, groceryCategory: 'Spaceships'),
      ],
      marker: 'Pasta',
    );
    expect(find.text('Plain task'), findsNothing);
    double topOf(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(find.text('Fruit & vegetables (1/1)'), findsOneWidget);
    expect(find.text('Pasta & rice (1/1)'), findsOneWidget);
    expect(find.text('Other (1/1)'), findsOneWidget);
    expect(topOf('Fruit & vegetables (1/1)'),
        lessThan(topOf('Pasta & rice (1/1)')));
    expect(topOf('Pasta & rice (1/1)'), lessThan(topOf('Other (1/1)')));
  });

  testWidgets('Check all and Reset list check / uncheck everything',
      (tester) async {
    await pumpGroceries(
      tester,
      tasks: [
        Task(title: 'Milk', isGrocery: true),
        Task(title: 'Eggs', isGrocery: true, isDone: true),
      ],
      marker: 'Milk',
    );
    await tester.tap(find.text('Check all'));
    await tester.pump();
    await settleWrites(tester);
    var saved = await readTasks(tester);
    expect(saved.every((t) => t['isDone'] == true), isTrue);

    await tester.tap(find.text('Reset list'));
    await tester.pump();
    await settleWrites(tester);
    saved = await readTasks(tester);
    expect(saved.every((t) => t['isDone'] == false), isTrue);
    // Still on the list after the reset — it's reusable.
    expect(saved.length, 2);
  });

  testWidgets(
      'adding an item already on the list unchecks it instead of adding a '
      'duplicate', (tester) async {
    await pumpGroceries(
      tester,
      tasks: [Task(title: 'Milk', isGrocery: true, isDone: true)],
      marker: 'Milk',
    );
    await tester.tap(find.byTooltip('Add grocery item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Item'), 'milk');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    final saved = await readTasks(tester);
    expect(saved.length, 1);
    expect(saved.single['isDone'], isFalse);
  });

  testWidgets('a new item is added to the chosen category', (tester) async {
    await pumpGroceries(
      tester,
      tasks: [Task(title: 'Milk', isGrocery: true)],
      marker: 'Milk',
    );
    await tester.tap(find.byTooltip('Add grocery item'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Item'), 'Bread');
    await tester.tap(find.text('Automatic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bread & bakery').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    final saved = await readTasks(tester);
    final bread = saved.firstWhere((t) => t['title'] == 'Bread');
    expect(bread['isGrocery'], isTrue);
    expect(bread['groceryCategory'], 'Bread & bakery');
    expect(find.text('Bread & bakery (1/1)'), findsOneWidget);
  });
}
