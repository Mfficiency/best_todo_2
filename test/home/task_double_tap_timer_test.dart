import 'dart:io';

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

  /// Two quick taps on [finder] — close enough together to register as a
  /// double tap (past kDoubleTapMinTime, well inside kDoubleTapTimeout).
  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'double-tapping a task offers Start timer, which opens the timer '
      'already counting down the default 20 minutes', (tester) async {
    await pumpHome(
      tester,
      [Task(title: 'Feed the zebra', dueDate: DateTime.now())],
    );

    await doubleTap(tester, find.text('Feed the zebra'));

    // The little menu, with (for now) just the one action.
    expect(find.text('Start timer'), findsOneWidget);
    expect(find.textContaining('Counts down 20 min'), findsOneWidget);

    await tester.tap(find.text('Start timer'));
    await tester.pumpAndSettle();

    // The egg-timer page is up for this task and — unlike a dice roll —
    // already running at the 20-minute default. The settle above advances
    // fake time in 100 ms steps, so a tick or two may already have passed:
    // assert the running state, not an exact remaining second.
    expect(find.byType(DiceTimerPage), findsOneWidget);
    expect(find.text('Timer for'), findsOneWidget);
    expect(find.text('Feed the zebra'), findsOneWidget);
    expect(DiceTimerController.instance.phase, DiceTimerPhase.running);
    final remaining = DiceTimerController.instance.remaining;
    expect(remaining.inSeconds, lessThanOrEqualTo(20 * 60));
    expect(remaining.inSeconds, greaterThan(19 * 60));
    expect(find.text('100% left'), findsOneWidget);
    expect(find.textContaining('Ends at'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);

    // Stop the still-running ticker before the test ends.
    DiceTimerController.instance.clear();
    await tester.pump();
  });

  testWidgets('the started timer is still editable on the dial',
      (tester) async {
    await pumpHome(
      tester,
      [Task(title: 'Water plants', dueDate: DateTime.now())],
    );

    await doubleTap(tester, find.text('Water plants'));
    await tester.tap(find.text('Start timer'));
    await tester.pumpAndSettle();
    expect(DiceTimerController.instance.phase, DiceTimerPhase.running);

    // Grabbing the dial pauses the countdown for rewinding, exactly like the
    // dice timer: a quarter turn back (3 o'clock → 12 o'clock) lands on 5
    // minutes, and letting go restarts from there.
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

    expect(find.text('5:00'), findsOneWidget);
    expect(find.text('100% left'), findsOneWidget);

    DiceTimerController.instance.clear();
    await tester.pump();
  });

  testWidgets('dismissing the menu starts nothing', (tester) async {
    await pumpHome(
      tester,
      [Task(title: 'Iron shirts', dueDate: DateTime.now())],
    );

    await doubleTap(tester, find.text('Iron shirts'));
    expect(find.text('Start timer'), findsOneWidget);

    // Tap the barrier above the sheet to dismiss it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Start timer'), findsNothing);
    expect(find.byType(DiceTimerPage), findsNothing);
    expect(DiceTimerController.instance.isActive, isFalse);
  });

  testWidgets(
      'double-tapping the task whose timer is running returns to it '
      'instead of restarting', (tester) async {
    await pumpHome(
      tester,
      [Task(title: 'Knit a scarf', dueDate: DateTime.now())],
    );

    await doubleTap(tester, find.text('Knit a scarf'));
    await tester.tap(find.text('Start timer'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(DiceTimerController.instance.remaining.inSeconds,
        lessThanOrEqualTo(19 * 60 + 30));

    // Back to the home page — the countdown keeps running.
    await tester.tap(find.byTooltip('Back to Home'));
    await tester.pumpAndSettle();
    expect(DiceTimerController.instance.isActive, isTrue);

    await doubleTap(tester, find.text('Knit a scarf'));
    await tester.tap(find.text('Start timer'));
    await tester.pumpAndSettle();

    // Still the same countdown, not a fresh 20 minutes.
    expect(find.byType(DiceTimerPage), findsOneWidget);
    expect(DiceTimerController.instance.phase, DiceTimerPhase.running);
    final remaining = DiceTimerController.instance.remaining;
    expect(remaining.inSeconds, lessThanOrEqualTo(19 * 60 + 30));
    expect(remaining.inSeconds, greaterThan(18 * 60));

    DiceTimerController.instance.clear();
    await tester.pump();
  });
}
