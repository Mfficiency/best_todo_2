import 'dart:convert';
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
  late String tempPath;

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp();
    tempPath = tempDir.path;
    PathProviderPlatform.instance = _FakePathProvider(tempPath);
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

  /// Seeds `streak.json` with plain file I/O — deliberately NOT through
  /// StreakService/SafeFile: a chained SafeFile write started from the
  /// fake-async test zone never completes and deadlocks any later write to
  /// the same file. An existing file (even `{}`) also marks the history as
  /// seeded, so HomePage skips the dev-stats backfill and tests stay
  /// deterministic.
  Future<void> seedStreakFile(Map<String, int> completionsByDay) =>
      File('$tempPath/streak.json')
          .writeAsString(jsonEncode({'completionsByDay': completionsByDay}));

  Future<void> pumpHome(
    WidgetTester tester,
    List<Task> tasks, {
    Map<String, int> streak = const {},
  }) async {
    // Real file I/O must run on the real event loop (see test/README.md).
    await tester.runAsync(() => seedStreakFile(streak));
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

  /// Rounds of real-loop slices + pump so I/O kicked off by a tap (task
  /// save, streak save) completes inside the fake zone (see CLAUDE.md).
  Future<void> settleIo(WidgetTester tester, [int rounds = 60]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
  }

  Finder flameIcon() => find.byWidgetPredicate((w) =>
      w is Icon &&
      (w.icon == Icons.local_fire_department ||
          w.icon == Icons.local_fire_department_outlined));

  String dayKeyAgo(int daysBack) => StreakService.dayKey(
      DateTime.now().subtract(Duration(days: daysBack)));

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
    // The tile's double-tap menu holds every tap in the gesture arena for the
    // double-tap window; advance the clock past it so the checkbox tap lands.
    await tester.pump(const Duration(milliseconds: 350));
    await settleIo(tester);

    expect(find.byTooltip('Streak: 1 day'), findsOneWidget);
    expect(find.text('1'), findsWidgets); // badge label
  });

  testWidgets('first completion of the day plays the celebration',
      (tester) async {
    Config.streakCompletionAnimation = true;
    await pumpHome(tester, [Task(title: 'Solo task', dueDate: DateTime.now())]);

    await tester.tap(find.byType(Checkbox).first);
    // First pump builds the overlay and starts its ticker; the second one
    // advances well past the 1.4s animation so the overlay removes itself.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Streak started! 🔥'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.text('Streak started! 🔥'), findsNothing);

    await settleIo(tester);
  });

  testWidgets('tapping the flame opens the streak page with stats',
      (tester) async {
    await pumpHome(
      tester,
      [Task(title: 'Solo task', dueDate: DateTime.now())],
      streak: {dayKeyAgo(1): 1, dayKeyAgo(0): 2},
    );

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
    await settleIo(tester);

    // Jump via the section chip header instead of scrolling blindly (the
    // horizontal chip list is also a Scrollable, so `.first` is ambiguous).
    // The chip row itself scrolls horizontally: later sections sit off-screen
    // until it is dragged (scroll the chip row only — ensureVisible would also
    // move the settings list underneath it).
    final streakChip = find.widgetWithText(ChoiceChip, 'Streak');
    final chipRow = find
        .ancestor(
          of: find.widgetWithText(ChoiceChip, 'Appearance'),
          matching: find.byType(Scrollable),
        )
        .first;
    // (Every chip is built even when off-screen, so scrollUntilVisible /
    // dragUntilVisible would skip straight to their trailing ensureVisible,
    // which drags the settings list to the bottom instead. Drag by rect.)
    for (var i = 0; i < 12 && tester.getRect(streakChip).right > 780; i++) {
      await tester.drag(chipRow, const Offset(-120, 0));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await tester.tap(streakChip);
    // _jumpToSection walks the lazily-built sliver one viewport per animation
    // and awaits each one, so a single pumpAndSettle can return between two
    // hops; settle repeatedly until the section is mounted.
    for (var i = 0; i < 25 && find.text('Show streak').evaluate().isEmpty; i++) {
      await tester.pumpAndSettle();
    }

    expect(find.text('Show streak'), findsOneWidget);
    expect(find.text('Streak grace period'), findsOneWidget);
    expect(find.text('Streak reminder'), findsOneWidget);
    expect(find.text('Streak celebration'), findsOneWidget);

    // The grace period is a 24h/48h choice.
    await tester.ensureVisible(find.text('48h'));
    await tester.pump();
    await tester.tap(find.text('48h'), warnIfMissed: false);
    await tester.pump();
    expect(Config.streakGraceHours, 48);
    expect(find.textContaining('one missed day is forgiven'), findsOneWidget);
    Config.streakGraceHours = 24;
  });

  testWidgets('streak search entries jump to the Streak section',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await settleIo(tester);

    await tester.tap(find.byTooltip('Search settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'flame');
    await tester.pump();

    expect(find.text('Show streak'), findsOneWidget);
    expect(find.text('Streak reminder'), findsOneWidget);
  });
}
