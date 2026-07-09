import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/ui/dice_timer_page.dart';
import 'package:besttodo/ui/home_page.dart';
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
    ProjectService.instance.resetForTest();
    DiceTimerController.instance.resetForTest();
  });

  /// Turns the dial back a quarter turn from the default 20 minutes
  /// (3 o'clock → 12 o'clock, −15 min → 5 min) and lets go, which starts the
  /// countdown.
  Future<void> windBackToFive(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(DiceTimerDial));
    final gesture = await tester.startGesture(center + const Offset(100, 0));
    await tester.pump();
    await gesture.moveTo(center + const Offset(70.7, -70.7));
    await tester.pump();
    await gesture.moveTo(center + const Offset(0, -100));
    await tester.pump();
    expect(find.text('5 min'), findsOneWidget);
    await gesture.up();
    await tester.pump();
  }

  group('dial math', () {
    test('dialAngle measures clockwise from 12 o\'clock', () {
      const center = Offset(100, 100);
      expect(dialAngle(center, const Offset(100, 0)), closeTo(0, 1e-9));
      expect(
          dialAngle(center, const Offset(200, 100)), closeTo(math.pi / 2, 1e-9));
      expect(dialAngle(center, const Offset(100, 200)), closeTo(math.pi, 1e-9));
      expect(dialAngle(center, const Offset(0, 100)),
          closeTo(3 * math.pi / 2, 1e-9));
    });

    test('dialAngleDelta takes the short way across 12 o\'clock', () {
      expect(dialAngleDelta(0.1, 2 * math.pi - 0.1), closeTo(-0.2, 1e-9));
      expect(dialAngleDelta(2 * math.pi - 0.1, 0.1), closeTo(0.2, 1e-9));
      expect(dialAngleDelta(1.0, 2.0), closeTo(1.0, 1e-9));
    });
  });

  group('DiceTimerPage', () {
    Future<void> pumpDicePage(
      WidgetTester tester, {
      required Task task,
      VoidCallback? onDone,
      VoidCallback? onPostponed,
      Future<void> Function(Task)? onRingAlert,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DiceTimerPage(
                        task: task,
                        onTaskDone: onDone ?? () {},
                        onTaskPostponed: onPostponed ?? () {},
                        onRingAlert: onRingAlert ?? (_) async {},
                      ),
                    ),
                  ),
                  child: const Text('open timer'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open timer'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'winding and releasing starts the countdown; at zero the ring '
        'actions appear and Done reports the task', (tester) async {
      var done = false;
      var postponed = false;
      var rang = 0;
      await pumpDicePage(
        tester,
        task: Task(title: 'Wash the dog'),
        onDone: () => done = true,
        onPostponed: () => postponed = true,
        onRingAlert: (_) async => rang++,
      );

      expect(find.text('Wash the dog'), findsOneWidget);
      // The dial opens pre-wound to the 20-minute default.
      expect(find.text('20 min'), findsOneWidget);

      await windBackToFive(tester);

      // Countdown running: remaining time, percentage left, end time, and the
      // early Done / Pause controls.
      expect(find.text('5:00'), findsOneWidget);
      expect(find.text('100% left'), findsOneWidget);
      expect(find.textContaining('Ends at'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.pump(const Duration(minutes: 5, seconds: 1));

      expect(rang, 1);
      expect(find.text("Time's up!"), findsOneWidget);
      expect(find.text('Postpone to tomorrow'), findsOneWidget);
      expect(find.text('+5 min'), findsOneWidget);

      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(done, isTrue);
      expect(postponed, isFalse);
      expect(find.byType(DiceTimerPage), findsNothing);
    });

    testWidgets('+5 min restarts the countdown and Postpone reports the task',
        (tester) async {
      var done = false;
      var postponed = false;
      var rang = 0;
      await pumpDicePage(
        tester,
        task: Task(title: 'Water plants'),
        onDone: () => done = true,
        onPostponed: () => postponed = true,
        onRingAlert: (_) async => rang++,
      );

      await windBackToFive(tester);
      await tester.pump(const Duration(minutes: 5, seconds: 1));
      expect(rang, 1);

      await tester.ensureVisible(find.text('+5 min'));
      await tester.tap(find.text('+5 min'));
      await tester.pump();

      // Running again for another 5 minutes; the ring's Postpone/extend
      // actions are gone, replaced by the running Done/Pause controls.
      expect(find.text('5:00'), findsOneWidget);
      expect(find.textContaining('Ends at'), findsOneWidget);
      expect(find.text('Postpone to tomorrow'), findsNothing);
      expect(find.text('Pause'), findsOneWidget);

      await tester.pump(const Duration(minutes: 5, seconds: 1));
      expect(rang, 2);

      await tester.ensureVisible(find.text('Postpone to tomorrow'));
      await tester.tap(find.text('Postpone to tomorrow'));
      await tester.pumpAndSettle();

      expect(postponed, isTrue);
      expect(done, isFalse);
      expect(find.byType(DiceTimerPage), findsNothing);
    });

    testWidgets('Pause freezes the countdown and Resume continues it',
        (tester) async {
      await pumpDicePage(
        tester,
        task: Task(title: 'Iron shirts'),
        onRingAlert: (_) async {},
      );

      await windBackToFive(tester);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('4:30'), findsOneWidget);

      await tester.ensureVisible(find.text('Pause'));
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);

      // Time stays put while paused.
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('4:30'), findsOneWidget);

      await tester.ensureVisible(find.text('Resume'));
      await tester.tap(find.text('Resume'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('4:00'), findsOneWidget);

      // Stop the still-running ticker before the test ends.
      DiceTimerController.instance.clear();
      await tester.pump();
    });

    testWidgets('Done stops the timer early and reports the task',
        (tester) async {
      var done = false;
      await pumpDicePage(
        tester,
        task: Task(title: 'Sweep the porch'),
        onDone: () => done = true,
        onRingAlert: (_) async {},
      );

      await windBackToFive(tester);
      await tester.pump(const Duration(seconds: 30));

      // Done is available mid-countdown, not only at the ring.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(done, isTrue);
      expect(find.byType(DiceTimerPage), findsNothing);
      expect(DiceTimerController.instance.isActive, isFalse);
    });
  });

  group('home page dice icon', () {
    Future<void> pumpHome(WidgetTester tester, List<Task> tasks) async {
      // All real file I/O (pre-saving tasks, HomePage's initState loads) must
      // run on the real event loop via runAsync, not the fake-async test zone.
      await tester.runAsync(() => StorageService().saveTaskList(tasks));
      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      final marker = find.text(tasks.first.title);
      for (var i = 0; i < 300 && marker.evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(marker, findsOneWidget, reason: 'HomePage never loaded the tasks');
    }

    testWidgets('rolls today\'s only open task and opens the dice timer',
        (tester) async {
      await pumpHome(
        tester,
        [Task(title: 'Feed the zebra', dueDate: DateTime.now())],
      );

      await tester.tap(find.byTooltip('Roll a random task timer'));
      await tester.pumpAndSettle();

      expect(find.byType(DiceTimerPage), findsOneWidget);
      expect(find.text('Feed the zebra'), findsOneWidget);
      expect(find.text('20 min'), findsOneWidget);
    });

    testWidgets('shows a message when today has no open tasks',
        (tester) async {
      await pumpHome(
        tester,
        [Task(title: 'Already handled', dueDate: DateTime.now(), isDone: true)],
      );

      await tester.tap(find.byTooltip('Roll a random task timer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('No open tasks for today'), findsOneWidget);
      expect(find.byType(DiceTimerPage), findsNothing);
    });

    testWidgets('a running timer survives leaving and is reopened by the dice',
        (tester) async {
      await pumpHome(
        tester,
        [Task(title: 'Knit a scarf', dueDate: DateTime.now())],
      );

      await tester.tap(find.byTooltip('Roll a random task timer'));
      await tester.pumpAndSettle();
      await windBackToFive(tester);
      expect(find.text('5:00'), findsOneWidget);

      // Back to the home page — the timer keeps running in the controller.
      await tester.tap(find.byTooltip('Back to Home'));
      await tester.pumpAndSettle();
      expect(find.byType(DiceTimerPage), findsNothing);
      expect(DiceTimerController.instance.isActive, isTrue);

      // The dice now offers to return to the running timer, and does.
      await tester.tap(find.byTooltip('Return to the running task timer'));
      await tester.pumpAndSettle();
      expect(find.byType(DiceTimerPage), findsOneWidget);
      expect(find.text('Knit a scarf'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('20 min'), findsNothing);

      // Stop the still-running ticker before the test ends.
      DiceTimerController.instance.clear();
      await tester.pump();
    });
  });
}
