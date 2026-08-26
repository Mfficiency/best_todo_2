import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/food_diary_page.dart';
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
    Config.swipeLeftDelete = true;
    // Opt out of the one-time Todo.md import so tests only see their own
    // items.
    await File('${tempDir.path}/${StorageService.wishlistImportFlagFileName}')
        .writeAsString('done');
  });

  Future<void> pumpFoodDiary(
    WidgetTester tester, {
    required List<Task> tasks,
    required String marker,
  }) async {
    // Pre-saving and the page's initState load are real file I/O, which must
    // run on the real event loop (runAsync), not the fake-async test zone.
    await tester.runAsync(() => StorageService().saveTaskList(tasks));
    await tester.pumpWidget(const MaterialApp(home: FoodDiaryPage()));
    final markerFinder = find.text(marker);
    for (var i = 0; i < 300 && markerFinder.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    await tester.pump();
    expect(markerFinder, findsOneWidget,
        reason: 'FoodDiaryPage never loaded the tasks');
  }

  Future<void> settleWrites(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Future<List<dynamic>> readJsonList(WidgetTester tester, String name) async {
    return await tester.runAsync(() async {
      final file = File('${tempDir.path}/$name');
      if (!await file.exists()) return <dynamic>[];
      return jsonDecode(await file.readAsString()) as List<dynamic>;
    }) as List<dynamic>;
  }

  testWidgets('shows only food diary entries, never plain tasks',
      (tester) async {
    await pumpFoodDiary(
      tester,
      tasks: [
        Task(
          title: 'Greek yogurt',
          description: 'With honey',
          label: 'sugar, lactose',
          dueDate: DateTime.now(),
          hasExplicitTime: true,
          isEatingHabit: true,
        ),
        Task(title: 'Feed the zebra', dueDate: DateTime.now()),
        Task(title: 'Buy a telescope', isWish: true),
      ],
      marker: 'Greek yogurt',
    );

    expect(find.text('With honey'), findsOneWidget);
    expect(find.text('sugar'), findsOneWidget);
    expect(find.text('lactose'), findsOneWidget);
    expect(find.text('Feed the zebra'), findsNothing);
    expect(find.text('Buy a telescope'), findsNothing);
  });

  testWidgets('groups past days into collapsed sections', (tester) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    await pumpFoodDiary(
      tester,
      tasks: [
        Task(
          title: 'Today lunch',
          dueDate: DateTime(now.year, now.month, now.day, 12),
          hasExplicitTime: true,
          isEatingHabit: true,
        ),
        Task(
          title: 'Yesterday breakfast',
          dueDate: yesterday.add(const Duration(hours: 8)),
          hasExplicitTime: true,
          isEatingHabit: true,
        ),
        Task(
          title: 'Yesterday dinner',
          dueDate: yesterday.add(const Duration(hours: 19)),
          hasExplicitTime: true,
          isEatingHabit: true,
        ),
      ],
      marker: 'Today lunch',
    );

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('2 entries'), findsOneWidget);
    expect(find.text('Yesterday breakfast'), findsNothing);
    expect(find.text('Yesterday dinner'), findsNothing);

    await tester.tap(find.text('2 entries'));
    await tester.pumpAndSettle();

    expect(find.text('Yesterday breakfast'), findsOneWidget);
    expect(find.text('Yesterday dinner'), findsOneWidget);
  });

  testWidgets('add dialog creates a tagged entry with a title and time',
      (tester) async {
    await pumpFoodDiary(
      tester,
      tasks: [Task(title: 'Greek yogurt', isEatingHabit: true)],
      marker: 'Greek yogurt',
    );

    await tester.tap(find.byTooltip('Add food diary entry'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Apple');
    await tester.enterText(
        find.widgetWithText(TextField, 'Description'), 'Afternoon snack');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('Afternoon snack'), findsOneWidget);

    final saved = await readJsonList(tester, 'tasks.json');
    final added =
        saved.cast<Map<String, dynamic>>().firstWhere((t) => t['title'] == 'Apple');
    expect(added['isEatingHabit'], isTrue);
    expect(added['dueDate'], isNotNull);
  });

  testWidgets('swiping an entry deletes it and moves it to the deleted list',
      (tester) async {
    await pumpFoodDiary(
      tester,
      tasks: [Task(title: 'Greek yogurt', isEatingHabit: true)],
      marker: 'Greek yogurt',
    );

    await tester.drag(find.text('Greek yogurt'), const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Greek yogurt'), findsNothing);
    expect(find.text('Deleted "Greek yogurt"'), findsOneWidget);

    await tester.pump(Config.delayDuration + const Duration(milliseconds: 50));
    await settleWrites(tester);

    final tasks = await readJsonList(tester, 'tasks.json');
    expect(tasks, isEmpty);
    final deleted = await readJsonList(tester, 'deleted_tasks.json');
    expect(deleted.single['title'], 'Greek yogurt');
    expect(deleted.single['deletedAt'], isNotNull);
  });

  testWidgets('tapping an entry opens the edit dialog with its values',
      (tester) async {
    await pumpFoodDiary(
      tester,
      tasks: [
        Task(
          title: 'Greek yogurt',
          description: 'With honey',
          label: 'sugar',
          isEatingHabit: true,
        ),
      ],
      marker: 'Greek yogurt',
    );

    await tester.tap(find.text('Greek yogurt'));
    await tester.pumpAndSettle();

    expect(find.text('Edit entry'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
    final titleField =
        tester.widget<TextField>(find.widgetWithText(TextField, 'Title'));
    expect(titleField.controller?.text, 'Greek yogurt');
  });
}
