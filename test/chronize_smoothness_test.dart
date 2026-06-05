import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/models/task.dart';
import 'package:besttodo/ui/chronize_page.dart';

/// Tests for the Chronize continuous time ruler.
///
/// The smooth appearance/disappearance of marks while zooming can't be asserted
/// perceptually, so these pin the invariant that *produces* it: a mark level's
/// opacity is a smooth, monotonic function of how far apart its marks sit on
/// screen, and finer levels only reach full opacity at higher zoom than coarser
/// ones. Plus basic widget coverage of the zoom controls and Today button.
void main() {
  group('markLevelOpacity (the smooth fade)', () {
    test('the coarsest (day) level stays fully visible at any zoom', () {
      expect(
        markLevelOpacity(
          intervalMinutes: 1440,
          pixelsPerMinute: 0.001,
          alwaysVisible: true,
        ),
        1.0,
      );
    });

    test('a level is hidden when its marks are too close together', () {
      // 5-minute marks at a coarse zoom sit a few pixels apart -> hidden.
      expect(markLevelOpacity(intervalMinutes: 5, pixelsPerMinute: 0.9), 0.0);
    });

    test('a level is fully shown once its marks are far enough apart', () {
      // 5-minute marks 60px apart (>= kMarkFadeFullPx) -> fully visible.
      expect(markLevelOpacity(intervalMinutes: 5, pixelsPerMinute: 12), 1.0);
    });

    test('opacity ramps smoothly through the fade band', () {
      final midSpacing = (kMarkFadeStartPx + kMarkFadeFullPx) / 2;
      final opacity = markLevelOpacity(
        intervalMinutes: 30,
        pixelsPerMinute: midSpacing / 30,
      );
      expect(opacity, closeTo(0.5, 1e-9));
    });

    test('finer marks appear only after coarser marks as zoom increases', () {
      // At a zoom where the 30-minute marks are partly in, the finer 10- and
      // 5-minute marks must still be fully hidden.
      const ppm = 0.9;
      expect(markLevelOpacity(intervalMinutes: 30, pixelsPerMinute: ppm),
          greaterThan(0));
      expect(markLevelOpacity(intervalMinutes: 10, pixelsPerMinute: ppm), 0.0);
      expect(markLevelOpacity(intervalMinutes: 5, pixelsPerMinute: ppm), 0.0);
    });

    test('opacity increases monotonically as the user zooms in', () {
      double previous = -1;
      for (final ppm in [0.05, 0.3, 0.9, 2.0, 4.0, 8.0]) {
        final opacity =
            markLevelOpacity(intervalMinutes: 10, pixelsPerMinute: ppm);
        expect(opacity, greaterThanOrEqualTo(previous));
        previous = opacity;
      }
    });
  });

  group('Chronize page widget', () {
    Future<void> pumpPage(WidgetTester tester) async {
      final now = DateTime.now();
      final tasks = [
        Task(
          title: 'Today task',
          dueDate: DateTime(now.year, now.month, now.day, 18),
          listRanking: 1,
        ),
        Task(
          title: 'Tomorrow task',
          dueDate: DateTime(now.year, now.month, now.day + 1, 9),
          listRanking: 2,
        ),
      ];
      await tester.pumpWidget(MaterialApp(home: ChronizePage(tasks: tasks)));
      await tester.pumpAndSettle();
    }

    testWidgets('renders the ruler and the scroll wheels', (tester) async {
      await pumpPage(tester);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('Today'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the zoom buttons change the finest-visible granularity',
        (tester) async {
      await pumpPage(tester);
      expect(find.text('1 h'), findsOneWidget); // default

      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pumpAndSettle();
      expect(find.text('30 min'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.zoom_out));
      await tester.tap(find.byIcon(Icons.zoom_out));
      await tester.pumpAndSettle();
      expect(find.text('2 h'), findsOneWidget);
    });

    testWidgets('the Today button settles without error', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows prev/next navigator cards when no event is in view',
        (tester) async {
      final now = DateTime.now();
      final tasks = [
        Task(
          title: 'past',
          dueDate: now.subtract(const Duration(days: 30)),
          listRanking: 1,
        ),
        Task(
          title: 'future',
          dueDate: now.add(const Duration(days: 30)),
          listRanking: 2,
        ),
      ];
      await tester.pumpWidget(MaterialApp(home: ChronizePage(tasks: tasks)));
      await tester.pumpAndSettle();

      expect(find.text('Previous event'), findsOneWidget);
      expect(find.text('Next event'), findsOneWidget);
    });

    testWidgets('hides navigator cards when an event is in view',
        (tester) async {
      final now = DateTime.now();
      final tasks = [
        Task(
          title: 'now',
          dueDate: DateTime(now.year, now.month, now.day, now.hour),
          listRanking: 1,
        ),
      ];
      await tester.pumpWidget(MaterialApp(home: ChronizePage(tasks: tasks)));
      await tester.pumpAndSettle();

      expect(find.text('Previous event'), findsNothing);
      expect(find.text('Next event'), findsNothing);
    });

    testWidgets('tapping empty timeline opens the new-task dialog',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ChronizePage(tasks: const [], onCreateTask: (_, __) {}),
      ));
      await tester.pumpAndSettle();

      // Tap in the calendar body (left of the wheels, below the header).
      await tester.tapAt(const Offset(120, 320));
      await tester.pumpAndSettle();

      expect(find.text('New task'), findsOneWidget);
    });

    testWidgets('tapping a task opens the edit dialog', (tester) async {
      final now = DateTime.now();
      final tasks = [
        Task(
          title: 'meeting',
          dueDate: DateTime(now.year, now.month, now.day, now.hour),
          listRanking: 1,
        ),
      ];
      await tester.pumpWidget(MaterialApp(
        home: ChronizePage(tasks: tasks, onTaskChanged: () {}),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('meeting'));
      await tester.pumpAndSettle();

      expect(find.text('Edit task'), findsOneWidget);
    });
  });
}
