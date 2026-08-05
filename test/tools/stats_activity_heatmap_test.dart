import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/your_stats_page.dart';

/// Tasks created at [hour] on the same recent day, [count] of them.
List<Task> _createdAt(DateTime day, int hour, int count) {
  return List<Task>.generate(
    count,
    (i) => Task(
      title: 'task $hour-$i',
      createdAt: DateTime(day.year, day.month, day.day, hour, 5),
    ),
  );
}

Widget _wrap(List<Task> tasks) {
  return MaterialApp(
    home: YourStatsPage(
      tasks: tasks,
      deletedItems: const <Task>[],
      dailyStatsByDay: const {},
    ),
  );
}

void main() {
  testWidgets('activity heatmap caps its colour ramp below a huge outlier',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final day = DateTime.now().subtract(const Duration(days: 2));
    final tasks = <Task>[
      // One outlier slot that would otherwise flatten everything else.
      ..._createdAt(day, 9, 200),
      ..._createdAt(day, 10, 1),
      ..._createdAt(day, 11, 2),
      ..._createdAt(day, 12, 3),
      ..._createdAt(day, 13, 2),
    ];

    await tester.pumpWidget(_wrap(tasks));
    await tester.pumpAndSettle();

    // The ramp saturates near the ordinary range (counts 1-3), not at 200, so
    // the everyday slots still differ in shade.
    expect(find.textContaining('busiest slot: 200'), findsOneWidget);
    expect(find.textContaining('saturating at 5/h'), findsOneWidget);
  });

  testWidgets('activity heatmap legend is plain when there is no outlier',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final day = DateTime.now().subtract(const Duration(days: 2));
    final tasks = <Task>[
      ..._createdAt(day, 10, 1),
      ..._createdAt(day, 11, 1),
    ];

    await tester.pumpWidget(_wrap(tasks));
    await tester.pumpAndSettle();

    expect(find.text('Log scale.'), findsOneWidget);
  });
}
