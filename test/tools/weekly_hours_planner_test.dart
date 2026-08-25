import 'dart:convert';
import 'dart:io';

import 'package:besttodo/config.dart';
import 'package:besttodo/models/weekly_hours_plan.dart';
import 'package:besttodo/services/google_calendar_service.dart';
import 'package:besttodo/services/weekly_hours_service.dart';
import 'package:besttodo/ui/weekly_hours_planner_page.dart';
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
  group('WeeklyHoursPlan model', () {
    test('default plan totals 8:36 a day and 43:00 for the week', () {
      final plan = WeeklyHoursPlan.defaultPlan();
      expect(plan.days.length, 5);
      for (final day in plan.days) {
        expect(day.workedMinutes, 8 * 60 + 36);
        expect(day.lunchMinutes, 30);
      }
      expect(plan.plannedWeeklyMinutes, 43 * 60);
      expect(plan.targetWeeklyMinutes, 43 * 60);
      // No drag yet: Friday's theoretical end matches its actual end.
      expect(
        plan.theoreticalFridayEndMinutes,
        plan.days.last.afternoon.endMinutes,
      );
    });

    test('a Monday surplus pushes Friday\'s theoretical end time later', () {
      final base = WeeklyHoursPlan.defaultPlan();
      final monday = base.days[0];
      // Extend Monday's afternoon block by 1 hour (9:36 worked instead of
      // 8:36), so the week is 1 hour ahead of target before Friday starts.
      final extendedMonday = monday.copyWith(
        afternoon: monday.afternoon
            .copyWith(endMinutes: monday.afternoon.endMinutes + 60),
      );
      final plan = base.withDay(0, extendedMonday);

      expect(plan.carryoverBeforeFriday, 60);
      final friday = plan.days.last;
      final expectedEnd =
          friday.morning.startMinutes + friday.lunchMinutes + (8 * 60 + 36 - 60);
      expect(plan.theoreticalFridayEndMinutes, expectedEnd);
      // An hour ahead of schedule means Friday can theoretically end an hour
      // earlier than its own currently scheduled end time.
      expect(plan.theoreticalFridayEndMinutes,
          friday.afternoon.endMinutes - 60);
    });

    test('a Tuesday deficit pushes Friday\'s theoretical end time later', () {
      final base = WeeklyHoursPlan.defaultPlan();
      final tuesday = base.days[1];
      final shortenedTuesday = tuesday.copyWith(
        afternoon: tuesday.afternoon
            .copyWith(endMinutes: tuesday.afternoon.endMinutes - 45),
      );
      final plan = base.withDay(1, shortenedTuesday);

      expect(plan.carryoverBeforeFriday, -45);
      final friday = plan.days.last;
      expect(plan.theoreticalFridayEndMinutes,
          friday.afternoon.endMinutes + 45);
    });

    test('JSON round-trip preserves every day\'s blocks', () {
      final plan = WeeklyHoursPlan.defaultPlan();
      final restored = WeeklyHoursPlan.fromJson(
        jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>,
      );
      for (var i = 0; i < plan.days.length; i++) {
        expect(restored.days[i].morning.startMinutes,
            plan.days[i].morning.startMinutes);
        expect(restored.days[i].morning.endMinutes,
            plan.days[i].morning.endMinutes);
        expect(restored.days[i].afternoon.startMinutes,
            plan.days[i].afternoon.startMinutes);
        expect(restored.days[i].afternoon.endMinutes,
            plan.days[i].afternoon.endMinutes);
      }
    });

    test('fromJson pads a short or missing day list with defaults', () {
      final restored = WeeklyHoursPlan.fromJson(const {'days': []});
      expect(restored.days.length, 5);
      expect(restored.days.first.workedMinutes, 8 * 60 + 36);
    });
  });

  group('WeeklyHoursService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp();
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      WeeklyHoursService.instance.resetForTest();
    });

    File planFile() => File('${tempDir.path}/weekly_hours_plan.json');

    test('first load seeds and persists the default plan', () async {
      await WeeklyHoursService.instance.load();

      expect(WeeklyHoursService.instance.plan.value.days.length, 5);
      expect(await planFile().exists(), isTrue);
    });

    test('updatePlan persists a change and it survives a reload', () async {
      await WeeklyHoursService.instance.load();
      final base = WeeklyHoursService.instance.plan.value;
      final monday = base.days[0];
      final changed = base.withDay(
        0,
        monday.copyWith(
          morning: monday.morning.copyWith(startMinutes: 8 * 60),
        ),
      );
      await WeeklyHoursService.instance.updatePlan(changed);
      expect(WeeklyHoursService.instance.plan.value.days[0].morning
          .startMinutes, 8 * 60);

      WeeklyHoursService.instance.resetForTest();
      await WeeklyHoursService.instance.load();
      expect(WeeklyHoursService.instance.plan.value.days[0].morning
          .startMinutes, 8 * 60);
    });
  });

  group('WeeklyHoursPlannerPage', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp();
      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      WeeklyHoursService.instance.resetForTest();
    });

    tearDown(() {
      Config.googleCalendarUrl = '';
      GoogleCalendarService.fetchOverride = null;
    });

    testWidgets('shows every weekday and the weekly total',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: WeeklyHoursPlannerPage()),
      );
      for (var i = 0; i < 300 && find.text('Friday').evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      await tester.pump();

      expect(find.text('Weekly Hours Planner'), findsOneWidget);
      for (final day in WeeklyHoursPlan.weekdayNames) {
        expect(find.text(day), findsOneWidget);
      }
      expect(find.textContaining('43h 00m'), findsWidgets);
    });

    testWidgets(
        'dragging a block handle changes the weekly total, and reset '
        'restores it', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: WeeklyHoursPlannerPage()),
      );
      for (var i = 0; i < 300 && find.text('Friday').evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      await tester.pump();

      // At the default plan the week is exactly on target: no surplus chip.
      expect(find.textContaining('+'), findsNothing);

      // Drag Monday's afternoon-end handle further down (later) to extend
      // the day — the grid runs top-to-bottom, so a positive dy means later.
      await tester.drag(
        find.byKey(const ValueKey('handle-Monday-afternoonEnd')),
        const Offset(0, 40),
      );
      await tester.pump();

      expect(find.textContaining('+'), findsOneWidget);
      expect(WeeklyHoursService.instance.plan.value.plannedWeeklyMinutes,
          isNot(43 * 60));

      await tester.tap(find.byTooltip('Reset to default week'));
      await tester.pump();

      expect(find.textContaining('+'), findsNothing);
      expect(WeeklyHoursService.instance.plan.value.plannedWeeklyMinutes,
          43 * 60);
    });

    testWidgets(
        'an imported Google Calendar event shows on its weekday, translucent '
        'underneath the work blocks', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      // A 3-hour block, comfortably tall enough to render its label at any
      // viewport height the test harness uses.
      final eventStart = DateTime(monday.year, monday.month, monday.day, 8);
      final eventEnd = eventStart.add(const Duration(hours: 3));
      final ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:test-event@example.com
DTSTART:${_icsStamp(eventStart)}
DTEND:${_icsStamp(eventEnd)}
SUMMARY:Team Standup
END:VEVENT
END:VCALENDAR
''';
      Config.googleCalendarUrl = 'https://example.com/cal.ics';
      GoogleCalendarService.fetchOverride = (_) async => ics;

      await tester.pumpWidget(
        const MaterialApp(home: WeeklyHoursPlannerPage()),
      );
      for (var i = 0;
          i < 300 && find.text('Team Standup').evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }

      expect(find.text('Team Standup'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

String _icsStamp(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}${two(dt.month)}${two(dt.day)}T'
      '${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
}
