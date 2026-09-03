import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/food_diary_page.dart';
import 'package:besttodo/utils/date_time_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  test('formats exports as a readable list grouped and ordered by day', () {
    final previous24HourFormat = Config.use24HourFormat;
    final previousDateFormat = Config.dateFormat;
    addTearDown(() {
      Config.use24HourFormat = previous24HourFormat;
      Config.dateFormat = previousDateFormat;
    });
    Config.use24HourFormat = true;
    Config.dateFormat = 'yyyy-MM-dd';
    final text = foodDiaryExportText([
      Task(
        title: 'Dinner',
        description: 'With friends',
        label: 'restaurant',
        dueDate: DateTime(2026, 8, 29, 19, 30),
      ),
      Task(title: 'Breakfast', dueDate: DateTime(2026, 8, 29, 8)),
      Task(title: 'Older lunch', dueDate: DateTime(2026, 8, 28, 12, 15)),
    ]);

    expect(text, startsWith('# Food Diary\n\n## Summary\n'));
    expect(
      text,
      contains('- 3 entries across 2 days (2026-08-28 – 2026-08-29)'),
    );
    expect(text, contains('- Tags: restaurant (1)'));
    expect(text, contains('\n\n## 2026-08-29'));
    expect(
      text.indexOf('08:00 — Breakfast'),
      lessThan(text.indexOf('19:30 — Dinner')),
    );
    expect(
      text.indexOf('## 2026-08-29'),
      lessThan(text.indexOf('## 2026-08-28')),
    );
    expect(text, contains('  - Tags: restaurant'));
    expect(text, contains('  - Notes: With friends'));
  });

  test('formats a plain-text copy as bullet points with no Markdown syntax',
      () {
    final previous24HourFormat = Config.use24HourFormat;
    final previousDateFormat = Config.dateFormat;
    addTearDown(() {
      Config.use24HourFormat = previous24HourFormat;
      Config.dateFormat = previousDateFormat;
    });
    Config.use24HourFormat = true;
    Config.dateFormat = 'yyyy-MM-dd';
    final text = foodDiaryPlainText([
      Task(
        title: 'Dinner',
        description: 'With friends',
        label: 'restaurant',
        dueDate: DateTime(2026, 8, 29, 19, 30),
      ),
      Task(title: 'Breakfast', dueDate: DateTime(2026, 8, 29, 8)),
      Task(title: 'Older lunch', dueDate: DateTime(2026, 8, 28, 12, 15)),
    ]);

    expect(text, isNot(contains('#')));
    expect(text, isNot(contains('**')));
    expect(
      text,
      '2026-08-29\n'
      '- 08:00 — Breakfast\n'
      '- 19:30 — Dinner\n'
      '  restaurant\n'
      '  With friends\n'
      '\n'
      '2026-08-28\n'
      '- 12:15 — Older lunch',
    );
  });

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

    expect(find.text('sugar'), findsOneWidget);
    expect(find.text('lactose'), findsOneWidget);
    // The description sits behind a chevron toggle, tags first.
    expect(find.text('With honey'), findsNothing);
    await tester.tap(find.text('Description'));
    await tester.pump();
    expect(find.text('With honey'), findsOneWidget);
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

    expect(find.text('Today · ${formatWeekdayShort(now)}'), findsOneWidget);
    expect(find.text('2 entries'), findsOneWidget);
    expect(find.text('Yesterday breakfast'), findsNothing);
    expect(find.text('Yesterday dinner'), findsNothing);

    expect(
      find.text('${formatWeekdayShort(yesterday)}, ${formatTimerDate(yesterday)}'),
      findsOneWidget,
    );
    await tester.tap(find.text('2 entries'));
    await tester.pumpAndSettle();

    expect(find.text('Yesterday breakfast'), findsOneWidget);
    expect(find.text('Yesterday dinner'), findsOneWidget);
  });

  testWidgets('tints entry cards for morning, noon and evening',
      (tester) async {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    await pumpFoodDiary(
      tester,
      tasks: [
        Task(
          title: 'Morning meal',
          dueDate: day.add(const Duration(hours: 8)),
          hasExplicitTime: true,
          isEatingHabit: true,
        ),
        Task(
          title: 'Noon meal',
          dueDate: day.add(const Duration(hours: 13)),
          hasExplicitTime: true,
          isEatingHabit: true,
        ),
        Task(
          title: 'Evening meal',
          dueDate: day.add(const Duration(hours: 19)),
          hasExplicitTime: true,
          isEatingHabit: true,
        ),
      ],
      marker: 'Morning meal',
    );

    Card cardFor(String title) => tester.widget<Card>(
          find.ancestor(of: find.text(title), matching: find.byType(Card)),
        );

    expect(cardFor('Morning meal').color, const Color(0xFFE3F2FD));
    expect(cardFor('Noon meal').color, const Color(0xFFFFF8D6));
    expect(cardFor('Evening meal').color, const Color(0xFFF3E1E6));
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
    // The description sits behind a chevron toggle until tapped.
    expect(find.text('Afternoon snack'), findsNothing);
    await tester.tap(find.text('Description'));
    await tester.pump();
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

  testWidgets('copies a previous food entry to the current time',
      (tester) async {
    final now = DateTime.now();
    final previousTime = DateTime(now.year, now.month, now.day);
    await pumpFoodDiary(
      tester,
      tasks: [
        Task(
          title: 'Greek yogurt',
          description: 'With honey',
          label: 'sugar lactose',
          dueDate: previousTime,
          hasExplicitTime: true,
          isEatingHabit: true,
        ),
      ],
      marker: 'Greek yogurt',
    );

    final beforeCopy = DateTime.now();
    await tester.tap(find.byTooltip('Copy entry to now'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    expect(find.text('Greek yogurt'), findsNWidgets(2));
    expect(find.text('Copied "Greek yogurt" to now'), findsOneWidget);

    final saved = (await readJsonList(tester, 'tasks.json'))
        .cast<Map<String, dynamic>>();
    final copies =
        saved.where((task) => task['title'] == 'Greek yogurt').toList();
    expect(copies, hasLength(2));
    final copied = copies.firstWhere((task) => task['uid'] != copies.last['uid']);
    expect(copied['description'], 'With honey');
    expect(copied['label'], 'sugar lactose');
    expect(copied['isEatingHabit'], isTrue);
    expect(
      DateTime.parse(copied['dueDate'] as String).isBefore(beforeCopy),
      isFalse,
    );
  });

  testWidgets(
      'add dialog copy-from-yesterday button fills the fields without '
      'changing the time', (tester) async {
    final now = DateTime.now();
    final yesterday =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    await pumpFoodDiary(
      tester,
      tasks: [
        Task(
          title: 'Oatmeal',
          description: 'With banana',
          label: 'gluten',
          dueDate: yesterday.add(const Duration(hours: 7, minutes: 30)),
          hasExplicitTime: true,
          isEatingHabit: true,
        ),
      ],
      marker: 'Oatmeal',
    );

    await tester.tap(find.byTooltip('Add food diary entry'));
    await tester.pumpAndSettle();

    final breakfastButton =
        find.byTooltip("Copy yesterday's breakfast: Oatmeal");
    expect(breakfastButton, findsOneWidget);

    await tester.tap(breakfastButton);
    await tester.pump();

    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, 'Title')).controller?.text,
      'Oatmeal',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await settleWrites(tester);

    final saved = (await readJsonList(tester, 'tasks.json'))
        .cast<Map<String, dynamic>>();
    final oatmealEntries =
        saved.where((t) => t['title'] == 'Oatmeal').toList();
    expect(oatmealEntries, hasLength(2));
    // The new entry keeps the dialog's own time ("now"), not yesterday's.
    final added = oatmealEntries.firstWhere((t) {
      final due = DateTime.parse(t['dueDate'] as String);
      return DateTime(due.year, due.month, due.day) ==
          DateTime(now.year, now.month, now.day);
    });
    expect(added['description'], 'With banana');
    expect(added['label'], 'gluten');
  });

  testWidgets(
      'nutritionist view groups by day, expanded, with a tag summary',
      (tester) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
    await pumpFoodDiary(
      tester,
      tasks: [
        Task(
          title: 'Today lunch',
          label: 'sugar',
          dueDate: DateTime(now.year, now.month, now.day, 12),
          hasExplicitTime: true,
          isEatingHabit: true,
        ),
        Task(
          title: 'Yesterday breakfast',
          label: 'sugar, dairy',
          dueDate: yesterday.add(const Duration(hours: 8)),
          hasExplicitTime: true,
          isEatingHabit: true,
        ),
      ],
      marker: 'Today lunch',
    );

    // Diary view starts with yesterday collapsed.
    expect(find.text('Yesterday breakfast'), findsNothing);

    await tester.tap(find.byTooltip('Switch to nutritionist view'));
    await tester.pumpAndSettle();

    // Nutritionist view shows every day expanded, no tap needed.
    expect(find.textContaining('Today lunch'), findsOneWidget);
    expect(find.textContaining('Yesterday breakfast'), findsOneWidget);
    expect(find.text('2 entries across 2 days'), findsOneWidget);
    expect(find.text('sugar (2)'), findsOneWidget);
    expect(find.text('dairy (1)'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to diary view'));
    await tester.pumpAndSettle();

    expect(find.text('Yesterday breakfast'), findsNothing);
  });

  testWidgets(
      'copy-days dialog copies only the selected days to the clipboard as '
      'plain text', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(call.arguments['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

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
      ],
      marker: 'Today lunch',
    );

    await tester.tap(find.byTooltip('Copy days as text'));
    await tester.pumpAndSettle();

    expect(find.text('Copy days as text'), findsOneWidget);
    // Both days start checked, one entry apiece.
    expect(find.text('1 entry'), findsNWidgets(2));

    // Uncheck yesterday, leaving only today selected.
    await tester.tap(find.text(
        '${formatWeekdayShort(yesterday)}, ${formatTimerDate(yesterday)}'));
    await tester.pump();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect(copied.single, contains('Today lunch'));
    expect(copied.single, isNot(contains('Yesterday breakfast')));
    expect(find.text('Copied 1 day to clipboard'), findsOneWidget);
  });

  testWidgets(
      'add dialog copy-from-yesterday button is disabled when nothing was '
      'logged for that meal', (tester) async {
    await pumpFoodDiary(
      tester,
      tasks: [Task(title: 'Greek yogurt', isEatingHabit: true)],
      marker: 'Greek yogurt',
    );

    await tester.tap(find.byTooltip('Add food diary entry'));
    await tester.pumpAndSettle();

    final breakfastButton =
        find.byTooltip('No breakfast logged yesterday');
    expect(breakfastButton, findsOneWidget);
    final button = tester.widget<IconButton>(
        find.ancestor(of: breakfastButton, matching: find.byType(IconButton)));
    expect(button.onPressed, isNull);
  });
}
