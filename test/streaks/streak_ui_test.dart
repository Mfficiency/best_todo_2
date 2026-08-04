import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/streak_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:besttodo/ui/settings_page.dart';
import 'package:besttodo/ui/streak_page.dart';
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
    ProjectService.instance.resetForTest();
    StorageService.resetJournalBaselineForTest();
    StreakService.instance.resetForTest();
    Config.showStreak = true;
    Config.streakGraceHours = 24;
    Config.streakReminderEnabled = false;
    // Off by default in tests so toggling tasks doesn't overlay the tree;
    // the celebration test switches it back on explicitly.
    Config.streakCompletionAnimation = false;
  });

  tearDown(() {
    Config.showStreak = true;
    Config.streakCompletionAnimation = true;
  });

  Future<void> pumpHome(WidgetTester tester, List<Task> tasks) async {
    // Real file I/O must run on the real event loop (see test/README.md).
    // Writing the streak file up front (even empty) marks the history as
    // already seeded, so HomePage skips the dev-stats backfill and tests
    // stay deterministic. SafeFile chains writes per path, so completions
    // recorded in the test body land in the file before this resolves.
    await tester.runAsync(() => StreakService.instance.saveNow());
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

  Finder flameIcon() => find.byWidgetPredicate((w) =>
      w is Icon &&
      (w.icon == Icons.local_fire_department ||
          w.icon == Icons.local_fire_department_outlined));

  testWidgets('flame sits in the home app bar next to the dice',
      (tester) async {
    await pumpHome(tester, [Task(title: 'Solo task', dueDate: DateTime.now())]);

    expect(find.byTooltip('Start a streak: complete a task today'),
        findsOneWidget);
    expect(find.byIcon(Icons.casino), findsOneWidget);
    expect(flameIcon(), findsOneWidget);
  });

  testWidgets('hiding the streak in settings removes the flame',
      (tester) async {
    Config.showStreak = false;
    await pumpHome(tester, [Task(title: 'Solo task', dueDate: DateTime.now())]);
    expect(flameIcon(), findsNothing);
  });

  testWidgets('completing a task lights the flame with a 1-day badge',
      (tester) async {
    await pumpHome(tester, [Task(title: 'Solo task', dueDate: DateTime.now())]);

    await tester.tap(find.byType(Checkbox).first);
    // The toggle handler saves tasks and the streak before setState settles;
    // fixed rounds of real-loop slices (see CLAUDE.md).
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    expect(find.byTooltip('Streak: 1 day'), findsOneWidget);
    expect(find.text('1'), findsWidgets); // badge label
  });

  testWidgets('first completion of the day plays the celebration',
      (tester) async {
    Config.streakCompletionAnimation = true;
    await pumpHome(tester, [Task(title: 'Solo task', dueDate: DateTime.now())]);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Streak started! 🔥'), findsOneWidget);

    // The overlay removes itself when the animation finishes.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();
    expect(find.text('Streak started! 🔥'), findsNothing);

    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  });

  testWidgets('tapping the flame opens the streak page with stats',
      (tester) async {
    StreakService.instance.recordCompletion(
        DateTime.now().subtract(const Duration(days: 1)));
    StreakService.instance.recordCompletion(DateTime.now());
    await pumpHome(tester, [Task(title: 'Solo task', dueDate: DateTime.now())]);

    await tester.tap(find.byTooltip('Streak: 2 days'));
    // The streak page's flame flickers forever — never pumpAndSettle here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('2-day streak'), findsOneWidget);
    expect(find.text('Longest streak ever'), findsOneWidget);
    expect(find.text('Days with a done task'), findsOneWidget);
    expect(find.byTooltip('Streak settings'), findsOneWidget);
  });

  testWidgets('streak page without a streak invites lighting the flame',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StreakPage()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No streak yet'), findsOneWidget);
    expect(find.text('Complete one task today to light the flame.'),
        findsOneWidget);
  });

  testWidgets('settings has the Streak section with all four settings',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    await tester.scrollUntilVisible(find.text('Show streak'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Show streak'), findsOneWidget);
    expect(find.text('Streak grace period'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Streak celebration'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Streak reminder'), findsOneWidget);
    expect(find.text('Streak celebration'), findsOneWidget);

    // The grace period is a 24h/48h choice.
    expect(find.text('24h'), findsOneWidget);
    expect(find.text('48h'), findsOneWidget);
    await tester.tap(find.text('48h'));
    await tester.pump();
    expect(Config.streakGraceHours, 48);
    expect(find.textContaining('one missed day is forgiven'), findsOneWidget);
    Config.streakGraceHours = 24;
  });

  testWidgets('streak search entries jump to the Streak section',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }

    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'flame');
    await tester.pump();

    expect(find.text('Show streak'), findsOneWidget);
    expect(find.text('Streak reminder'), findsOneWidget);
  });
}
