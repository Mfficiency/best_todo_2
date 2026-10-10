import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/ui/dice_timer_page.dart';
import 'package:besttodo/ui/dice_timer_settings.dart';
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
    DiceTimerController.instance.resetForTest();
    // Config is global static state; put the dice settings back to their
    // shipped defaults so each test starts from the same place.
    Config.diceTimerAlertMode = 'notification';
    Config.diceTimerMelody = 'Classic';
    Config.diceTimerVolume = 0.8;
    Config.diceTimerAlsoVibrate = false;
    Config.diceTimerDefaultMinutes = 20;
    Config.enableNotifications = false;
  });

  group('diceAlertPlan', () {
    test('the default is a notification, silent when notifications are off',
        () {
      expect(Config.diceTimerAlertMode, 'notification');

      final off = diceAlertPlan(notificationsEnabled: false);
      expect(off.notification, isFalse);
      expect(off.melody, isFalse);
      expect(off.vibrate, isFalse);
      expect(off.isSilent, isTrue, reason: 'the dial alone says 0:00');

      final on = diceAlertPlan(notificationsEnabled: true);
      expect(on.notification, isTrue);
      expect(on.melody, isFalse);
      expect(on.isSilent, isFalse);
    });

    test('melody mode rings, and notifies as well when notifications are on',
        () {
      final plan = diceAlertPlan(mode: 'melody', notificationsEnabled: true);
      expect(plan.melody, isTrue);
      expect(plan.notification, isTrue);
      expect(plan.vibrate, isFalse);

      final quiet = diceAlertPlan(mode: 'melody', notificationsEnabled: false);
      expect(quiet.melody, isTrue, reason: 'the melody does not need them');
      expect(quiet.notification, isFalse);
    });

    test('vibrate mode buzzes only; silent mode does nothing at all', () {
      final buzz = diceAlertPlan(mode: 'vibrate', notificationsEnabled: true);
      expect(buzz.vibrate, isTrue);
      expect(buzz.melody, isFalse);
      expect(buzz.notification, isFalse);

      final silent = diceAlertPlan(mode: 'silent', notificationsEnabled: true);
      expect(silent.isSilent, isTrue);
    });

    test('"also vibrate" adds a buzz to the melody and notification modes', () {
      expect(
        diceAlertPlan(mode: 'melody', alsoVibrate: true).vibrate,
        isTrue,
      );
      expect(
        diceAlertPlan(mode: 'notification', alsoVibrate: true).vibrate,
        isTrue,
      );
      // Silent stays silent no matter what the vibrate switch says.
      expect(
        diceAlertPlan(mode: 'silent', alsoVibrate: true).isSilent,
        isTrue,
      );
    });

    test('an unknown stored mode falls back to the notification default', () {
      final plan =
          diceAlertPlan(mode: 'nonsense', notificationsEnabled: true);
      expect(plan.notification, isTrue);
      expect(plan.melody, isFalse);
    });
  });

  group('dice timer settings round trip', () {
    test('alert settings survive a save/load cycle', () async {
      Config.diceTimerAlertMode = 'melody';
      Config.diceTimerMelody = 'Marimba';
      Config.diceTimerVolume = 0.35;
      Config.diceTimerAlsoVibrate = true;
      Config.diceTimerDefaultMinutes = 45;
      await Config.save();

      Config.diceTimerAlertMode = 'silent';
      Config.diceTimerMelody = 'Classic';
      Config.diceTimerVolume = 1.0;
      Config.diceTimerAlsoVibrate = false;
      Config.diceTimerDefaultMinutes = 20;
      await Config.load();

      expect(Config.diceTimerAlertMode, 'melody');
      expect(Config.diceTimerMelody, 'Marimba');
      expect(Config.diceTimerVolume, closeTo(0.35, 1e-9));
      expect(Config.diceTimerAlsoVibrate, isTrue);
      expect(Config.diceTimerDefaultMinutes, 45);
    });

    test('a bogus stored alert mode is ignored', () {
      Config.applyMap({'diceTimerAlertMode': 'trumpet'});
      expect(Config.diceTimerAlertMode, 'notification');
    });
  });

  group('DiceTimerPage', () {
    Future<void> pumpDicePage(WidgetTester tester, {Task? task}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DiceTimerPage(
            task: task ?? Task(title: 'Sort the socks'),
            onTaskDone: () {},
            onTaskPostponed: () {},
            onRingAlert: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Turns the dial back a quarter turn from the 20-minute default
    /// (3 o'clock → 12 o'clock, −15 min → 5 min) and lets go, which starts the
    /// countdown — same gesture as dice_timer_test.dart.
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

    testWidgets('the dial opens at the configured default length',
        (tester) async {
      Config.diceTimerDefaultMinutes = 10;
      await pumpDicePage(tester);
      expect(find.text('10 min'), findsOneWidget);
    });

    testWidgets('a silent alert shows 0:00 instead of shouting',
        (tester) async {
      Config.diceTimerAlertMode = 'silent';
      await pumpDicePage(tester);

      await windBackToFive(tester);
      await tester.pump(const Duration(minutes: 5, seconds: 1));

      expect(find.text('0:00'), findsOneWidget);
      expect(find.text("Time's up"), findsOneWidget);
      expect(find.text("Time's up!"), findsNothing);
      // The finish actions are still there — only the noise is gone.
      expect(find.text('Postpone to tomorrow'), findsOneWidget);

      DiceTimerController.instance.clear();
      await tester.pump();
    });

    testWidgets('an audible alert keeps the loud "Time\'s up!" face',
        (tester) async {
      Config.enableNotifications = true;
      await pumpDicePage(tester);

      await windBackToFive(tester);
      await tester.pump(const Duration(minutes: 5, seconds: 1));

      expect(find.text("Time's up!"), findsOneWidget);
      expect(find.text('0:00'), findsNothing);

      DiceTimerController.instance.clear();
      await tester.pump();
    });

    testWidgets('the gear opens the timer settings and changes stick',
        (tester) async {
      await pumpDicePage(tester);

      await tester.tap(find.byTooltip('Timer settings'));
      await tester.pumpAndSettle();

      expect(find.text('Dice timer settings'), findsOneWidget);
      expect(find.text('Alert at zero'), findsOneWidget);
      // Notifications are off in this test, so the default mode says so.
      expect(find.textContaining('Notifications are switched off'),
          findsOneWidget);

      // Switch the alert to the melody: the melody and volume rows appear.
      await tester.tap(find.text('Notification').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Melody').last);
      // Config.save() writes a real file; walk the event loop so it lands.
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(Config.diceTimerAlertMode, 'melody');
      expect(find.text('Volume'), findsOneWidget);
      expect(find.byTooltip('Preview melody'), findsOneWidget);
      expect(find.text('Also vibrate'), findsOneWidget);
    });
  });

  group('DiceTimerSettingsList', () {
    testWidgets('the default timer length is editable on its own',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(
          child: DiceTimerSettingsList(),
        )),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Default timer length'), findsOneWidget);
      await tester.tap(find.text('20 min').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('45 min').last);
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(Config.diceTimerDefaultMinutes, 45);
      expect(DiceTimerController.defaultDuration,
          const Duration(minutes: 45));
    });
  });
}
