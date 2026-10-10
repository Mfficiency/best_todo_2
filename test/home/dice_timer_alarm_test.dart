import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/alarm_ids.dart';
import 'package:besttodo/services/project_service.dart';
import 'package:besttodo/ui/dice_timer_page.dart';
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
    Config.diceTimerAlertMode = 'notification';
    Config.diceTimerAlsoVibrate = false;
    Config.diceTimerDefaultMinutes = 20;
    // The alert must not be silent, or the ring deliberately stays in the dial.
    Config.enableNotifications = true;
  });

  tearDown(() {
    DiceTimerController.instance.resetForTest();
    Config.enableNotifications = false;
  });

  group('diceOsAlarmAction', () {
    test('a running countdown with the app away arms the OS ring', () {
      expect(
        diceOsAlarmAction(
          phase: DiceTimerPhase.running,
          appResumed: false,
          alertSilent: false,
        ),
        DiceOsAlarmAction.arm,
      );
    });

    test('with the app in front the ring is handled in-app, not by the OS', () {
      expect(
        diceOsAlarmAction(
          phase: DiceTimerPhase.running,
          appResumed: true,
          alertSilent: false,
        ),
        DiceOsAlarmAction.cancel,
      );
    });

    test('a silent alert never arms anything', () {
      expect(
        diceOsAlarmAction(
          phase: DiceTimerPhase.running,
          appResumed: false,
          alertSilent: true,
        ),
        DiceOsAlarmAction.cancel,
      );
    });

    test('pausing or rewinding drops the armed ring', () {
      for (final phase in [DiceTimerPhase.paused, DiceTimerPhase.setting]) {
        expect(
          diceOsAlarmAction(
            phase: phase,
            appResumed: false,
            alertSilent: false,
          ),
          DiceOsAlarmAction.cancel,
          reason: '$phase should cancel',
        );
      }
    });

    test('a ring that is already going is left alone', () {
      expect(
        diceOsAlarmAction(
          phase: DiceTimerPhase.ringing,
          appResumed: true,
          alertSilent: false,
        ),
        DiceOsAlarmAction.leave,
      );
      expect(
        diceOsAlarmAction(
          phase: DiceTimerPhase.ringing,
          appResumed: false,
          alertSilent: false,
        ),
        DiceOsAlarmAction.leave,
      );
    });
  });

  group('diceRingPayload', () {
    test('carries the dice uid, the task and no melody by default', () {
      final payload = diceRingPayload('Wash the dog');
      expect(payload['uid'], kDiceTimerUid);
      expect(payload['name'], 'Time is up');
      expect(payload['body'], 'Wash the dog');
      expect(payload['snoozeEnabled'], isFalse);
      expect(payload['snoozeId'], kDiceTimerNotificationId);
      expect(payload.containsKey('melody'), isFalse);
      expect(payload.containsKey('volume'), isFalse);
    });

    test('carries melody and volume when the alert plays one', () {
      final payload = diceRingPayload('Iron shirts',
          melody: 'Marimba', volume: 0.4, vibrate: true);
      expect(payload['melody'], 'Marimba');
      expect(payload['volume'], 0.4);
      expect(payload['vibrate'], isTrue);
    });

    test('an empty task title still says something', () {
      expect(diceRingPayload('   ')['body'], 'Your timer finished');
    });
  });

  group('ringing away from the timer page', () {
    /// Opens the dice timer from a host page, so the timer can be left behind
    /// (Back to Home) while the countdown keeps running.
    Future<void> pumpAndOpenTimer(WidgetTester tester, Task task) async {
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
                        onTaskDone: () {},
                        onTaskPostponed: () {},
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

    /// Quarter turn back from the 20-minute default → 5 minutes, then let go.
    Future<void> windBackToFive(WidgetTester tester) async {
      final center = tester.getCenter(find.byType(DiceTimerDial));
      final gesture = await tester.startGesture(center + const Offset(100, 0));
      await tester.pump();
      await gesture.moveTo(center + const Offset(70.7, -70.7));
      await tester.pump();
      await gesture.moveTo(center + const Offset(0, -100));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    testWidgets('zero takes over the screen with the alarm ring page',
        (tester) async {
      Map<String, dynamic>? presented;
      DiceTimerController.presentFullScreenRing = (p) => presented = p;

      await pumpAndOpenTimer(tester, Task(title: 'Knit a scarf'));
      await windBackToFive(tester);
      expect(find.text('5:00'), findsOneWidget);

      // Leave the timer running and go back to the list.
      await tester.tap(find.byTooltip('Back to Home'));
      await tester.pumpAndSettle();
      expect(find.byType(DiceTimerPage), findsNothing);

      await tester.pump(const Duration(minutes: 5, seconds: 1));

      expect(presented, isNotNull,
          reason: 'the ring should present the full-screen alarm');
      expect(presented!['uid'], kDiceTimerUid);
      expect(presented!['body'], 'Knit a scarf');

      DiceTimerController.instance.clear();
      await tester.pump();
    });

    testWidgets('the alarm screen stays away while the timer page is open',
        (tester) async {
      Map<String, dynamic>? presented;
      DiceTimerController.presentFullScreenRing = (p) => presented = p;

      await pumpAndOpenTimer(tester, Task(title: 'Water plants'));
      await windBackToFive(tester);
      await tester.pump(const Duration(minutes: 5, seconds: 1));

      expect(presented, isNull, reason: 'the dial itself shows the ring');
      expect(find.text('Postpone to tomorrow'), findsOneWidget);

      DiceTimerController.instance.clear();
      await tester.pump();
    });

    testWidgets('a silent alert never takes over the screen', (tester) async {
      Config.diceTimerAlertMode = 'silent';
      Map<String, dynamic>? presented;
      DiceTimerController.presentFullScreenRing = (p) => presented = p;

      await pumpAndOpenTimer(tester, Task(title: 'Sweep the porch'));
      await windBackToFive(tester);
      await tester.tap(find.byTooltip('Back to Home'));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(minutes: 5, seconds: 1));

      expect(presented, isNull);
      expect(DiceTimerController.instance.phase, DiceTimerPhase.ringing);

      DiceTimerController.instance.clear();
      await tester.pump();
    });
  });
}
