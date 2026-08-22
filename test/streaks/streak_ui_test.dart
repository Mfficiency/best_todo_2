import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/streak_kind.dart';
import 'package:besttodo/models/streak_reminder.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/services/storage_service.dart';
import 'package:besttodo/services/streak_service.dart';
import 'package:besttodo/ui/home_page.dart';
import 'package:besttodo/ui/settings_page.dart';
import 'package:besttodo/ui/streak_flame_button.dart';
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
    Config.streakReminders = [];
    for (final key in Config.streakKindKeys) {
      Config.streakKindEnabled[key] = true;
    }
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

  /// The streak page stacks a challenge selector, a big flame and three cards;
  /// a taller surface keeps the stats on screen so they can be tapped.
  void enlarge(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

    expect(find.byTooltip('Finish a task: no streak yet'), findsOneWidget);
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
    await settleIo(tester);

    expect(find.byTooltip('Finish a task: 1-day streak'), findsOneWidget);
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
    enlarge(tester);
    await pumpHome(
      tester,
      [Task(title: 'Solo task', dueDate: DateTime.now())],
      streak: {dayKeyAgo(1): 1, dayKeyAgo(0): 2},
    );

    await tester.tap(find.byTooltip('Finish a task: 2-day streak'));
    // The streak page's flame flickers forever — never pumpAndSettle here.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('2-day streak'), findsOneWidget);
    expect(find.text('Longest streak ever'), findsOneWidget);
    expect(find.text('Days with a done task'), findsOneWidget);
    expect(find.byTooltip('Streak settings'), findsOneWidget);
  });

  testWidgets('streak page lists the challenges with an earned count',
      (tester) async {
    // 7 active days ending today → Week of Fire (and more) earned.
    await tester.runAsync(() => seedStreakFile(
        {for (var back = 0; back < 7; back++) dayKeyAgo(back): 1}));
    await tester.runAsync(() => StreakService.instance.load());
    await tester.pumpWidget(const MaterialApp(home: StreakPage()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.scrollUntilVisible(find.text('Challenges'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Challenges'), findsOneWidget);
    expect(find.textContaining('/ 26 earned'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Week of Fire'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Week of Fire'), findsOneWidget);
    expect(find.text('Keep a 7-day streak'), findsOneWidget);
    // Earned challenges get the amber check mark.
    expect(find.byIcon(Icons.check_circle), findsWidgets);
  });

  testWidgets('earned challenges sink below the ones still to play for',
      (tester) async {
    // 7 days with one completion each: the streak-length challenges up to
    // Week of Fire are earned, the per-day-count ones (Perfect Ten) are not.
    await tester.runAsync(() => seedStreakFile(
        {for (var back = 0; back < 7; back++) dayKeyAgo(back): 1}));
    await tester.runAsync(() => StreakService.instance.load());
    await tester.pumpWidget(const MaterialApp(home: StreakPage()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.scrollUntilVisible(find.text('Challenges'), 150,
        scrollable: find.byType(Scrollable).first);

    // The card is one list child, so every tile in it is laid out — the
    // off-screen ones included, which is exactly what the order is about.
    final header = tester.getTopLeft(find.text('Earned')).dy;
    expect(tester.getTopLeft(find.text('Perfect Ten')).dy, lessThan(header));
    expect(tester.getTopLeft(find.text('Week of Fire')).dy, greaterThan(header));
  });

  testWidgets('longest streak tile opens the yearly calendar with the range',
      (tester) async {
    enlarge(tester);
    await tester.runAsync(() => seedStreakFile(
        {dayKeyAgo(3): 1, dayKeyAgo(2): 1, dayKeyAgo(1): 1}));
    await tester.runAsync(() => StreakService.instance.load());
    await tester.pumpWidget(const MaterialApp(home: StreakPage()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.scrollUntilVisible(find.text('Longest streak ever'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Longest streak ever'));
    // The calendar page has no infinite animation, but the streak page's
    // flame below it does — pump fixed frames instead of settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Streak calendar'), findsOneWidget);
    expect(find.text('Longest streak: 3 days'), findsOneWidget);
    expect(find.textContaining('From '), findsOneWidget);
    // The calendar opens on the year the longest streak started.
    final startYear = StreakService.instance.longestStreakRange()!.start.year;
    expect(find.text('$startYear'), findsOneWidget);
    // All 12 months of the year are drawn.
    expect(find.text('January'), findsOneWidget);
    expect(find.text('December'), findsOneWidget);
  });

  testWidgets('streak page without a streak invites lighting the flame',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StreakPage()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No streak yet'), findsOneWidget);
    expect(find.text('Complete one task today to light the flame.'),
        findsOneWidget);
  });

  /// Opens the settings page on the Streak section.
  ///
  /// Jumps via the section chip header instead of scrolling blindly (the
  /// horizontal chip list is also a Scrollable, so `.first` is ambiguous).
  /// The chip row itself scrolls horizontally: later sections sit off-screen
  /// until it is dragged (scroll the chip row only — ensureVisible would also
  /// move the settings list underneath it). Tapping the chip expands the
  /// section, which — like every section — starts collapsed.
  Future<void> openStreakSettings(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await settleIo(tester);

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
  }

  testWidgets('settings has the Streak section with all its settings',
      (tester) async {
    await openStreakSettings(tester);

    expect(find.text('Show streak'), findsOneWidget);
    expect(find.text('Streak grace period'), findsOneWidget);
    expect(find.text('Active challenges'), findsOneWidget);
    expect(find.text('Streak reminders'), findsOneWidget);
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
    expect(find.text('Streak reminders'), findsOneWidget);
  });

  testWidgets('the flame cycles through the active challenges',
      (tester) async {
    // The cycle is off under the test binding (a repeating timer would keep
    // pumpAndSettle from ever settling), so ask for it explicitly and pump
    // fixed frames.
    StreakFlameButton.debugForceCycle = true;
    addTearDown(() => StreakFlameButton.debugForceCycle = false);
    await tester.runAsync(() => seedStreakFile({dayKeyAgo(0): 1}));
    await tester.runAsync(() => StreakService.instance.load());

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        appBar: null,
        body: Row(children: [StreakFlameButton()]),
      ),
    ));
    await tester.pump();
    expect(find.byTooltip('Finish a task: 1-day streak'), findsOneWidget);

    await tester.pump(StreakFlameButton.cycleInterval);
    expect(find.byTooltip('Create a task: no streak yet'), findsOneWidget);

    await tester.pump(StreakFlameButton.cycleInterval);
    expect(find.byTooltip('Plan ahead: no streak yet'), findsOneWidget);

    // ...and back around to the first one.
    await tester.pump(StreakFlameButton.cycleInterval);
    expect(find.byTooltip('Finish a task: 1-day streak'), findsOneWidget);
  });

  testWidgets('all three challenges done settles on one steady red flame',
      (tester) async {
    StreakFlameButton.debugForceCycle = true;
    addTearDown(() => StreakFlameButton.debugForceCycle = false);
    // Every challenge done today, with different streak lengths behind them.
    await tester.runAsync(() => File('$tempPath/streak.json').writeAsString(
          jsonEncode({
            'completionsByDay': {dayKeyAgo(0): 1, dayKeyAgo(1): 1},
            'createsByDay': {dayKeyAgo(0): 1},
            'planByDay': {dayKeyAgo(0): 1},
          }),
        ));
    await tester.runAsync(() => StreakService.instance.load());

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Row(children: [StreakFlameButton()])),
    ));
    await tester.pump();

    // One flame badged with the highest of the three counts (2, not 1)...
    expect(find.byTooltip('All 3 challenges done today — 2-day streak'),
        findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    // ...lit, steady red...
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    expect(
      tester
          .widget<Icon>(find.byIcon(Icons.local_fire_department))
          .color,
      StreakFlameButton.allDoneColor,
    );

    // ...and it no longer cycles through the per-challenge flames.
    await tester.pump(StreakFlameButton.cycleInterval);
    expect(find.byTooltip('All 3 challenges done today — 2-day streak'),
        findsOneWidget);
    await tester.pump(StreakFlameButton.cycleInterval);
    expect(find.byTooltip('All 3 challenges done today — 2-day streak'),
        findsOneWidget);
  });

  testWidgets('one challenge still open keeps the flame cycling',
      (tester) async {
    StreakFlameButton.debugForceCycle = true;
    addTearDown(() => StreakFlameButton.debugForceCycle = false);
    await tester.runAsync(() => File('$tempPath/streak.json').writeAsString(
          jsonEncode({
            'completionsByDay': {dayKeyAgo(0): 1},
            'createsByDay': {dayKeyAgo(0): 1},
          }),
        ));
    await tester.runAsync(() => StreakService.instance.load());

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Row(children: [StreakFlameButton()])),
    ));
    await tester.pump();

    expect(find.byTooltip('Finish a task: 1-day streak'), findsOneWidget);
    await tester.pump(StreakFlameButton.cycleInterval);
    expect(find.byTooltip('Create a task: 1-day streak'), findsOneWidget);
    await tester.pump(StreakFlameButton.cycleInterval);
    expect(find.byTooltip('Plan ahead: no streak yet'), findsOneWidget);
  });

  testWidgets('a challenge switched off drops out of the flame',
      (tester) async {
    Config.streakKindEnabled['complete'] = false;
    StreakFlameButton.debugForceCycle = true;
    addTearDown(() => StreakFlameButton.debugForceCycle = false);
    await tester.runAsync(() => seedStreakFile({dayKeyAgo(0): 1}));
    await tester.runAsync(() => StreakService.instance.load());

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Row(children: [StreakFlameButton()])),
    ));
    await tester.pump();

    expect(find.byTooltip('Create a task: no streak yet'), findsOneWidget);
    await tester.pump(StreakFlameButton.cycleInterval);
    expect(find.byTooltip('Plan ahead: no streak yet'), findsOneWidget);
    // The completion flame never comes around again.
    await tester.pump(StreakFlameButton.cycleInterval);
    expect(find.byTooltip('Create a task: no streak yet'), findsOneWidget);
  });

  testWidgets('a day still open keeps the flame grey and pulsing white',
      (tester) async {
    // The pulse is a repeating animation — off under the test binding for the
    // same reason the cycle is, so ask for it explicitly and pump frames.
    StreakFlameButton.debugForceCycle = true;
    addTearDown(() => StreakFlameButton.debugForceCycle = false);
    Config.streakKindEnabled['create'] = false;
    Config.streakKindEnabled['plan'] = false;
    // Yesterday counted, today has not happened yet.
    await tester.runAsync(() => seedStreakFile({dayKeyAgo(1): 1}));
    await tester.runAsync(() => StreakService.instance.load());

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Row(children: [StreakFlameButton()])),
    ));
    await tester.pump();

    expect(find.byTooltip('Finish a task: 1-day streak — still open today'),
        findsOneWidget);
    // Unlit: the outlined flame in the theme's disabled grey...
    expect(find.byIcon(Icons.local_fire_department_outlined), findsOneWidget);
    Color flameColor() => tester
        .widget<Icon>(find.byIcon(Icons.local_fire_department_outlined))
        .color!;
    final grey = flameColor();
    expect(grey, ThemeData().disabledColor);

    // ...that breathes towards white and back.
    await tester.pump(StreakFlameButton.pulseInterval ~/ 2);
    final lit = flameColor();
    expect(lit.computeLuminance(), greaterThan(grey.computeLuminance()));

    // Another one and a half breaths lands back at the start of the cycle.
    await tester.pump(StreakFlameButton.pulseInterval * 3 ~/ 2);
    expect(flameColor().computeLuminance(), lessThan(lit.computeLuminance()));
  });

  testWidgets('doing the day\'s action lights the greyed-out flame',
      (tester) async {
    await pumpHome(
      tester,
      [Task(title: 'Solo task', dueDate: DateTime.now())],
      streak: {dayKeyAgo(1): 1},
    );

    expect(find.byIcon(Icons.local_fire_department_outlined), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await settleIo(tester);

    expect(find.byTooltip('Finish a task: 2-day streak'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    expect(tester.widget<Icon>(find.byIcon(Icons.local_fire_department)).color,
        isNot(ThemeData().disabledColor));
  });

  testWidgets('adding a task keeps the create streak', (tester) async {
    await pumpHome(tester, [Task(title: 'Solo task', dueDate: DateTime.now())]);
    expect(
        StreakService.instance
            .isDayDone(DateTime.now(), kind: StreakKind.create),
        isFalse);

    await tester.enterText(find.byType(TextField).first, 'Plan the week');
    await tester.tap(find.byIcon(Icons.add).first);
    await settleIo(tester);

    expect(
        StreakService.instance
            .isDayDone(DateTime.now(), kind: StreakKind.create),
        isTrue);
  });

  testWidgets('finishing the whole day keeps the plan-ahead streak',
      (tester) async {
    await pumpHome(tester, [Task(title: 'Solo task', dueDate: DateTime.now())]);
    expect(
        StreakService.instance.isDayDone(DateTime.now(), kind: StreakKind.plan),
        isFalse);

    await tester.tap(find.byType(Checkbox).first);
    await settleIo(tester);

    // The day's only task is done — the day was dealt with.
    expect(
        StreakService.instance.isDayDone(DateTime.now(), kind: StreakKind.plan),
        isTrue);
  });

  testWidgets('the streak page lists today per challenge and switches kind',
      (tester) async {
    enlarge(tester);
    await tester.runAsync(() => seedStreakFile({dayKeyAgo(0): 1}));
    await tester.runAsync(() => StreakService.instance.load());
    await tester.pumpWidget(const MaterialApp(home: StreakPage()));
    await tester.pump(const Duration(milliseconds: 100));

    // The "Today" card names every active challenge with its state.
    expect(find.text('Finish a task'), findsOneWidget);
    expect(find.text('Create a task'), findsOneWidget);
    expect(find.text('Plan ahead'), findsOneWidget);
    expect(find.text('Open'), findsNWidgets(2));

    // The page opens on the completion flame...
    expect(find.text('1-day streak'), findsOneWidget);
    expect(find.text('Days with a done task'), findsOneWidget);

    // ...and the chips switch it to another challenge.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Create 0'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No streak yet'), findsOneWidget);
    expect(find.text('Days with a new task'), findsOneWidget);
    expect(find.text('Add one task today to light the flame.'), findsOneWidget);
  });

  testWidgets('settings can turn a challenge off and manage reminders',
      (tester) async {
    enlarge(tester);
    await openStreakSettings(tester);

    // Every challenge starts on.
    for (final label in ['Finish a task', 'Create a task', 'Plan ahead']) {
      expect(find.widgetWithText(SwitchListTile, label), findsOneWidget);
    }
    await tester.ensureVisible(find.widgetWithText(SwitchListTile, 'Plan ahead'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Plan ahead'));
    await settleIo(tester);
    expect(Config.isStreakKindEnabled('plan'), isFalse);

    // Reminders: switching them on seeds the default evening nudge.
    await tester.ensureVisible(find.text('Streak reminders'));
    await tester.tap(find.widgetWithText(SwitchListTile, 'Streak reminders'));
    await settleIo(tester);
    expect(Config.streakReminders.length, 1);
    expect(find.text('22:00'), findsOneWidget);
    expect(find.text('Silent notification'), findsOneWidget);

    // Any number of them can be added...
    await tester.ensureVisible(find.text('Add reminder'));
    await tester.tap(find.text('Add reminder'));
    await settleIo(tester);
    expect(Config.streakReminders.length, 2);
    expect(find.text('23:00'), findsOneWidget);

    // ...each with its own alert mode...
    await tester.ensureVisible(find.text('Sound & vibration').first);
    await tester.tap(find.text('Sound & vibration').first);
    await settleIo(tester);
    expect(Config.streakReminders.first.mode, StreakAlertMode.sound);

    // ...and removed again.
    await tester.ensureVisible(find.byTooltip('Remove reminder').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove reminder').first);
    await settleIo(tester);
    expect(Config.streakReminders.length, 1);
  });
}
