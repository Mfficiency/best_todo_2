import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/f1_reminder.dart';
import 'package:besttodo/services/f1_reminder_service.dart';
import 'package:besttodo/ui/f1_reminder_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sent = <String>[];

  setUp(() async {
    // Saving re-arms the reminder alarm; tests run as Android, so stub the
    // alarm-manager plugin.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(
          'dev.fluttercommunity.plus/android_alarm_manager', JSONMethodCodec()),
      (call) async => true,
    );
    final tempDir = await Directory.systemTemp.createTemp();
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    sent.clear();
    F1ReminderService.sendOverride = (phone, message) async {
      sent.add('$phone|$message');
      return null;
    };
  });

  tearDown(() => F1ReminderService.sendOverride = null);

  group('calendar', () {
    test('holds the eight remaining races in order, on the given days', () {
      expect(kF1Races, hasLength(8));
      expect(F1ReminderService.formatDateTime(kF1Races.first.start),
          'Saturday 10 October, 11:00');
      expect(F1ReminderService.formatDateTime(kF1Races[2].start),
          'Sunday 25 October, 21:00');
      expect(kF1Races[2].name, 'United States GP');
      expect(F1ReminderService.formatDateTime(kF1Races[5].start),
          'Sunday 22 November, 05:00');
      expect(F1ReminderService.formatDateTime(kF1Races.last.start),
          'Sunday 6 December, 14:00');
      for (var i = 1; i < kF1Races.length; i++) {
        expect(kF1Races[i].start.isAfter(kF1Races[i - 1].start), isTrue);
      }
    });
  });

  group('nextPending', () {
    test('is the first race, 4 hours before its start', () {
      final p = F1ReminderService.nextPending(F1ReminderConfig(),
          now: DateTime(2026, 9, 27))!;
      expect(p.race.name, 'Singapore GP Sprint');
      expect(p.sendAt, DateTime(2026, 10, 10, 7, 0));
    });

    test('skips handled races', () {
      final config = F1ReminderConfig(handledRaces: {kF1Races[0].key});
      final p =
          F1ReminderService.nextPending(config, now: DateTime(2026, 9, 27))!;
      expect(p.race.name, 'Singapore GP');
    });

    test('keeps a missed reminder until 30 minutes before the start', () {
      final race = kF1Races[3]; // Mexico City, 21:00
      final late = F1ReminderService.nextPending(F1ReminderConfig(),
          now: DateTime(2026, 11, 1, 19, 0))!;
      expect(late.race.key, race.key);
      final tooLate = F1ReminderService.nextPending(F1ReminderConfig(),
          now: DateTime(2026, 11, 1, 20, 40))!;
      expect(tooLate.race.name, 'Brazilian GP');
    });

    test('is null after the season', () {
      expect(
          F1ReminderService.nextPending(F1ReminderConfig(),
              now: DateTime(2026, 12, 7)),
          isNull);
    });
  });

  group('render', () {
    test('fills every token, 4 hours out by default', () {
      final out = F1ReminderService.render(
          '{race}|{time}|{date}|{countdown}', kF1Races[4]);
      expect(out, 'Brazilian GP|18:00|Sunday 8 November|4 hours');
    });

    test('a late send gets an honest countdown', () {
      final out = F1ReminderService.render('{countdown}', kF1Races[4],
          now: DateTime(2026, 11, 8, 15, 40));
      expect(out, '2 hours 20 minutes');
    });

    test('default template reads well', () {
      final out = F1ReminderService.render(kDefaultF1Template, kF1Races[7]);
      expect(out, contains('Lights out in 4 hours'));
      expect(out, contains('Abu Dhabi GP starts at 14:00'));
    });
  });

  group('config', () {
    test('JSON round-trip', () {
      final config = F1ReminderConfig(
        enabled: true,
        phoneNumber: '+31 6 1234',
        template: 'Hi {race}',
        handledRaces: {kF1Races[0].key},
      )..addHistory(F1SendRecord(
          at: DateTime(2026, 10, 10, 7),
          message: 'Hi',
          success: false,
          error: 'boom'));
      final back = F1ReminderConfig.fromJson(config.toJson());
      expect(back.enabled, isTrue);
      expect(back.phoneNumber, '+31 6 1234');
      expect(back.template, 'Hi {race}');
      expect(back.handledRaces, {kF1Races[0].key});
      expect(back.history.single.error, 'boom');
    });

    test('tolerates missing keys', () {
      final back = F1ReminderConfig.fromJson({});
      expect(back.enabled, isFalse);
      expect(back.template, kDefaultF1Template);
      expect(back.handledRaces, isEmpty);
    });

    test('start overrides round-trip and move the race', () {
      final race = kF1Races[3]; // Mexico City, 1 Nov 21:00
      final config = F1ReminderConfig(handledRaces: {race.key})
        ..setStart(race, DateTime(2026, 11, 2, 1, 0));
      // Moving a race re-arms its reminder.
      expect(config.handledRaces, isEmpty);
      final back = F1ReminderConfig.fromJson(config.toJson());
      final moved = back.races.firstWhere((r) => r.key == race.key);
      expect(moved.start, DateTime(2026, 11, 2, 1, 0));
      expect(moved.name, 'Mexico City GP');
      final p = F1ReminderService.nextPending(back,
          now: DateTime(2026, 11, 1, 22, 0))!;
      expect(p.race.key, race.key);
      expect(p.sendAt, DateTime(2026, 11, 1, 21, 0));

      // Setting the calendar's own time drops the override.
      back.setStart(moved, race.start);
      expect(back.startOverrides, isEmpty);
    });

    test('an edit can reorder the races', () {
      final config = F1ReminderConfig()
        ..setStart(kF1Races[0], DateTime(2026, 10, 12, 9, 0));
      expect(config.races.first.name, 'Singapore GP');
      expect(config.races[1].name, 'Singapore GP Sprint');
    });

    test('history is capped', () {
      final config = F1ReminderConfig();
      for (var i = 0; i < F1ReminderConfig.maxHistory + 5; i++) {
        config.addHistory(
            F1SendRecord(at: DateTime(2026), message: '$i', success: true));
      }
      expect(config.history, hasLength(F1ReminderConfig.maxHistory));
      expect(config.history.first.message, '5');
    });
  });

  group('runDue', () {
    test('sends the due reminder once and marks it handled', () async {
      await F1ReminderService.save(
          F1ReminderConfig(enabled: true, phoneNumber: '+111'));
      final at = DateTime(2026, 10, 25, 17, 0);
      // Skip the two Singapore races.
      final c = await F1ReminderService.load();
      c.handledRaces.addAll([kF1Races[0].key, kF1Races[1].key]);
      await F1ReminderService.save(c);

      expect(await F1ReminderService.runDue(now: at), isTrue);
      expect(sent.single, startsWith('+111|'));
      expect(sent.single, contains('United States GP'));
      expect(sent.single, contains('4 hours'));

      expect(await F1ReminderService.runDue(now: at), isFalse);
      expect(sent, hasLength(1));
      final after = await F1ReminderService.load();
      expect(after.handledRaces, contains(kF1Races[2].key));
      expect(after.history.single.success, isTrue);
    });

    test('does nothing before the send time or when disabled', () async {
      await F1ReminderService.save(
          F1ReminderConfig(enabled: true, phoneNumber: '+111'));
      expect(await F1ReminderService.runDue(now: DateTime(2026, 9, 27)),
          isFalse);
      await F1ReminderService.save(
          F1ReminderConfig(enabled: false, phoneNumber: '+111'));
      expect(
          await F1ReminderService.runDue(now: DateTime(2026, 10, 10, 7)),
          isFalse);
      expect(sent, isEmpty);
    });

    test('welcome message names the next race', () async {
      final config = F1ReminderConfig(phoneNumber: '+222');
      final error = await F1ReminderService.sendWelcome(config,
          now: DateTime(2026, 10, 12));
      expect(error, isNull);
      expect(sent.single, startsWith('+222|Welcome'));
      expect(sent.single, contains('United States GP, Sunday 25 October'));
    });
  });

  group('page', () {
    Future<void> settle(WidgetTester tester, {int rounds = 60}) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
    }

    testWidgets('shows next text, all races and the welcome button',
        (tester) async {
      await tester.runAsync(() => F1ReminderService.save(
          F1ReminderConfig(enabled: true, phoneNumber: '+333')));
      await tester.pumpWidget(MaterialApp(
          home: F1ReminderPage(now: DateTime(2026, 9, 27, 12))));
      await settle(tester);

      expect(find.text('Next text: Saturday 10 October, 07:00'), findsOneWidget);
      expect(find.text('Send welcome message'), findsOneWidget);
      expect(find.text('+333'), findsOneWidget);
      final list = find.byKey(const Key('f1-reminder-list'));
      await tester.scrollUntilVisible(find.text('Abu Dhabi GP'), 200,
          scrollable: find.descendant(
              of: list, matching: find.byType(Scrollable)).first);
      expect(find.text('Sunday 6 December, 14:00\nText at 10:00'),
          findsOneWidget);
      expect(find.byTooltip('Edit time'), findsWidgets);
    });

    testWidgets('an edited race shows its new time and can be reset',
        (tester) async {
      final race = kF1Races[2]; // United States GP, 21:00
      await tester.runAsync(() => F1ReminderService.save(F1ReminderConfig(
            enabled: true,
            phoneNumber: '+333',
            startOverrides: {race.key: DateTime(2026, 10, 25, 20, 0)},
          )));
      await tester.pumpWidget(MaterialApp(
          home: F1ReminderPage(now: DateTime(2026, 9, 27, 12))));
      await settle(tester);
      final list = find.byKey(const Key('f1-reminder-list'));
      final tile = find.byKey(Key('f1-race-${race.key}'));
      await tester.scrollUntilVisible(tile, 200,
          scrollable: find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first);
      expect(
          find.text('Sunday 25 October, 20:00 (edited)\nText at 16:00'),
          findsOneWidget);

      await tester.tap(
          find.descendant(of: tile, matching: find.byTooltip('Reset time')));
      await settle(tester);
      expect(find.text('Sunday 25 October, 21:00\nText at 17:00'),
          findsOneWidget);
      final saved = await tester.runAsync(F1ReminderService.load);
      expect(saved!.startOverrides, isEmpty);
    });

    testWidgets('Edit time opens a date then a 24-hour time picker',
        (tester) async {
      // Phone-sized portrait screen, like the real device.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      // The stock time picker's input mode overflows by a few pixels with
      // the test font (every glyph a full square); not this page's layout.
      final onError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        onError?.call(details);
      };
      addTearDown(() => FlutterError.onError = onError);
      await tester.runAsync(() => F1ReminderService.save(
          F1ReminderConfig(enabled: true, phoneNumber: '+333')));
      await tester.pumpWidget(MaterialApp(
          home: F1ReminderPage(now: DateTime(2026, 9, 27, 12))));
      await settle(tester);
      final tile = find.byKey(Key('f1-race-${kF1Races[0].key}'));
      await tester.scrollUntilVisible(tile, 200,
          scrollable: find
              .descendant(
                  of: find.byKey(const Key('f1-reminder-list')),
                  matching: find.byType(Scrollable))
              .first);
      await tester.tap(
          find.descendant(of: tile, matching: find.byTooltip('Edit time')));
      await tester.pumpAndSettle();
      expect(find.text('Singapore GP Sprint — race day'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Singapore GP Sprint — lights out'), findsOneWidget);
      // Switch to text entry and type a new start time.
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(fields.evaluate().length - 2), '12');
      await tester.enterText(fields.last, '30');
      await tester.tap(find.text('OK'));
      await settle(tester);
      expect(find.text('Saturday 10 October, 12:30 (edited)\nNext text at 08:30'),
          findsOneWidget);
      await tester.drag(
          find.byKey(const Key('f1-reminder-list')), const Offset(0, 3000));
      await tester.pumpAndSettle();
      expect(find.text('Next text: Saturday 10 October, 08:30'), findsOneWidget);
    });

    testWidgets('toggle off shows reminders are off', (tester) async {
      await tester.runAsync(() => F1ReminderService.save(
          F1ReminderConfig(enabled: false, phoneNumber: '+333')));
      await tester.pumpWidget(MaterialApp(
          home: F1ReminderPage(now: DateTime(2026, 9, 27, 12))));
      await settle(tester);
      expect(find.text('Reminders are off'), findsOneWidget);
    });
  });

  test('registered as a tool', () {
    expect(Config.featureKeys, contains('f1_reminder'));
    expect(Config.startToolOptions, contains('f1_reminder'));
    expect(Config.featureKeys.length, Config.featureLabels.length);
    expect(Config.featureKeys.length, Config.featureDescriptions.length);
    expect(Config.startToolOptions.length, Config.startToolLabels.length);
  });
}
