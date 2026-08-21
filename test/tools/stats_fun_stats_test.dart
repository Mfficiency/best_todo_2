import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/models/daily_task_stats.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/your_stats_page.dart';

Widget _wrap(
  List<Task> tasks, {
  List<Task> deleted = const <Task>[],
  Map<String, DailyTaskStats> dailyStats = const {},
}) {
  return MaterialApp(
    home: YourStatsPage(
      tasks: tasks,
      deletedItems: deleted,
      dailyStatsByDay: dailyStats,
    ),
  );
}

/// Scrolls the page's own list (the heatmaps below it hold scrollables of
/// their own) down to the fun stats at the bottom.
Future<void> scrollToFunStats(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Fun stats'), 400,
      scrollable: find.byType(Scrollable).first);
}

void main() {
  testWidgets('fun stats sum up the all-time trivia', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final day = DateTime.now().subtract(const Duration(days: 3));
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(day.year, day.month, day.day, hour, minute);

    final tasks = <Task>[
      // Two finished the same morning — one of them before 08:00.
      Task(
        title: 'Feed the zebra',
        createdAt: at(6),
        completedAt: at(6, 30),
        isDone: true,
      ),
      Task(
        title: 'Water plants',
        createdAt: at(5),
        completedAt: at(9),
        isDone: true,
      ),
      // Still open, and the oldest thing on the list.
      Task(
        title: 'Learn the tuba',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      ),
    ];

    await tester.pumpWidget(_wrap(tasks));
    await tester.pumpAndSettle();
    await scrollToFunStats(tester);

    expect(find.text('Fun stats'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Items completed'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Items ever created'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Completion rate'), findsOneWidget);

    // 2 of 3 items done, both on the same day.
    expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Items completed'),
          matching: find.text('2'),
        ),
        findsOneWidget);
    expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Completion rate'),
          matching: find.text('67%'),
        ),
        findsOneWidget);
    expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Busiest day'),
          matching: find.text('2'),
        ),
        findsOneWidget);

    // Timing trivia: one early-bird finish, a 30-minute fastest turnaround
    // and a 4-hour longest wait.
    expect(find.widgetWithText(ListTile, 'Early bird finishes'), findsOneWidget);
    expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Fastest finish'),
          matching: find.text('30 min'),
        ),
        findsOneWidget);
    expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Longest wait'),
          matching: find.text('4 h'),
        ),
        findsOneWidget);

    // Planning: two of the three were written down at 05:00 and 06:00, so no
    // hour wins twice — the tile just names the busiest one.
    expect(find.widgetWithText(ListTile, 'Planning hour'), findsOneWidget);
    expect(find.textContaining('Most items get written down'), findsOneWidget);

    // The one item nobody has touched, and the open count.
    expect(find.widgetWithText(ListTile, 'Oldest open item'), findsOneWidget);
    expect(find.text('Learn the tuba'), findsOneWidget);
    expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Open right now'),
          matching: find.text('1'),
        ),
        findsOneWidget);
  });

  testWidgets(
      'tapping a fun stat opens a sheet listing the items behind it',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final day = DateTime.now().subtract(const Duration(days: 3));
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(day.year, day.month, day.day, hour, minute);

    final tasks = <Task>[
      Task(
        title: 'Feed the zebra',
        createdAt: at(6),
        completedAt: at(6, 30),
        isDone: true,
      ),
      Task(
        title: 'Water plants',
        createdAt: at(5),
        completedAt: at(9),
        isDone: true,
      ),
    ];

    await tester.pumpWidget(_wrap(tasks));
    await tester.pumpAndSettle();
    await scrollToFunStats(tester);

    final itemsCompletedTile =
        find.widgetWithText(ListTile, 'Items completed');
    await tester.ensureVisible(itemsCompletedTile);
    await tester.pumpAndSettle();
    await tester.tap(itemsCompletedTile);
    await tester.pumpAndSettle();

    // The sheet names both completed items and when each finished.
    final sheet = find.byType(DraggableScrollableSheet);
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Feed the zebra')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Water plants')),
        findsOneWidget);
  });

  testWidgets('a stat with nothing behind it stays a plain row',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(
      [Task(title: 'Anything', createdAt: DateTime.now())],
    ));
    await tester.pumpAndSettle();
    await scrollToFunStats(tester);

    // Nothing has ever completed, so 'Open right now' carries no detail
    // list and tapping it must not open a sheet.
    final openNowTile = find.widgetWithText(ListTile, 'Open right now');
    await tester.ensureVisible(openNowTile);
    await tester.pumpAndSettle();
    await tester.tap(openNowTile);
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsNothing);
  });

  testWidgets('postponed items are counted from the daily stats',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final stats = DailyTaskStats(
      dayKey: '2026-08-10',
      openingTaskIds: {'a', 'b', 'c'},
      movedFromOpeningTaskIds: {'a', 'b', 'zzz'},
    );

    await tester.pumpWidget(_wrap(
      [Task(title: 'Anything', createdAt: DateTime.now())],
      dailyStats: {stats.dayKey: stats},
    ));
    await tester.pumpAndSettle();
    await scrollToFunStats(tester);

    // Only ids that were actually due that day count — 'zzz' does not.
    expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'Times postponed'),
          matching: find.text('2'),
        ),
        findsOneWidget);
    // ...and the day key names the weekday it happened on (2026-08-10 is a
    // Monday).
    expect(find.text('Monday is when things get pushed'), findsOneWidget);
  });

  testWidgets('an empty history says so instead of showing zeroes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(const <Task>[]));
    await tester.pumpAndSettle();
    await scrollToFunStats(tester);

    expect(find.text('Complete a few items and the trivia shows up here.'),
        findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Items completed'), findsNothing);
  });
}
