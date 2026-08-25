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

    File actualsFile() => File('${tempDir.path}/weekly_hours_actuals.json');

    test('actualFor returns a zeroed, unpersisted record for an untouched week',
        () async {
      await WeeklyHoursService.instance.loadActuals();
      final monday = WeeklyActual.mondayOf(DateTime(2026, 8, 25));
      final actual = WeeklyHoursService.instance.actualFor(monday);

      expect(actual.weekStart, monday);
      expect(actual.overUndertimeMinutes, 0);
      expect(await actualsFile().exists(), isFalse);
    });

    test('saveActual persists a record and it survives a reload', () async {
      await WeeklyHoursService.instance.loadActuals();
      final monday = WeeklyActual.mondayOf(DateTime(2026, 8, 25));
      await WeeklyHoursService.instance
          .saveActual(WeeklyActual(weekStart: monday, overUndertimeMinutes: 90));

      expect(await actualsFile().exists(), isTrue);

      WeeklyHoursService.instance.resetForTest();
      await WeeklyHoursService.instance.loadActuals();
      expect(WeeklyHoursService.instance.actualFor(monday).overUndertimeMinutes,
          90);
    });

    test('saveActual drops the record once it goes back to zero', () async {
      await WeeklyHoursService.instance.loadActuals();
      final monday = WeeklyActual.mondayOf(DateTime(2026, 8, 25));
      await WeeklyHoursService.instance
          .saveActual(WeeklyActual(weekStart: monday, overUndertimeMinutes: 90));
      expect(WeeklyHoursService.instance.actuals.value, hasLength(1));

      await WeeklyHoursService.instance
          .saveActual(WeeklyActual(weekStart: monday, overUndertimeMinutes: 0));
      expect(WeeklyHoursService.instance.actuals.value, isEmpty);
    });

    test('saveActual replaces the existing record for the same week', () async {
      await WeeklyHoursService.instance.loadActuals();
      final monday = WeeklyActual.mondayOf(DateTime(2026, 8, 25));
      await WeeklyHoursService.instance
          .saveActual(WeeklyActual(weekStart: monday, overUndertimeMinutes: 30));
      await WeeklyHoursService.instance
          .saveActual(WeeklyActual(weekStart: monday, overUndertimeMinutes: -45));

      expect(WeeklyHoursService.instance.actuals.value, hasLength(1));
      expect(WeeklyHoursService.instance.actualFor(monday).overUndertimeMinutes,
          -45);
    });
  });

  group('WeeklyActual model', () {
    test('mondayOf normalizes a mid-week date to that week\'s Monday', () {
      // 2026-08-25 is a Tuesday.
      final monday = WeeklyActual.mondayOf(DateTime(2026, 8, 25, 14, 30));
      expect(monday, DateTime(2026, 8, 24));
      expect(monday.weekday, DateTime.monday);
    });

    test('weekKey is the Monday as yyyy-MM-dd', () {
      final actual = WeeklyActual(weekStart: DateTime(2026, 1, 5));
      expect(actual.weekKey, '2026-01-05');
    });

    test('toJson/fromJson round-trips weekStart and overUndertimeMinutes', () {
      final actual = WeeklyActual(
        weekStart: DateTime(2026, 8, 24),
        overUndertimeMinutes: -75,
      );
      final restored = WeeklyActual.fromJson(actual.toJson());

      expect(restored.weekStart, actual.weekStart);
      expect(restored.overUndertimeMinutes, -75);
    });

    test('copyWith replaces overUndertimeMinutes and keeps weekStart', () {
      final actual = WeeklyActual(weekStart: DateTime(2026, 8, 24));
      final changed = actual.copyWith(overUndertimeMinutes: 60);

      expect(changed.weekStart, actual.weekStart);
      expect(changed.overUndertimeMinutes, 60);
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

    testWidgets('week navigation shows each week\'s own actual over/undertime',
        (tester) async {
      final thisMonday = WeeklyActual.mondayOf(DateTime.now());
      // Pre-saving is real file I/O, which must run on the real event loop
      // (runAsync), not the fake-async test zone.
      await tester.runAsync(() => WeeklyHoursService.instance.saveActual(
            WeeklyActual(weekStart: thisMonday, overUndertimeMinutes: 120),
          ));

      await tester.pumpWidget(
        const MaterialApp(home: WeeklyHoursPlannerPage()),
      );
      for (var i = 0; i < 300 && find.text('Friday').evaluate().isEmpty; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
      }
      await tester.pump();

      final field = find.byKey(const ValueKey('over-undertime-field'));
      expect(
        (tester.widget<TextField>(field).controller!.text),
        '+2',
      );

      await tester.tap(find.byTooltip('Next week'));
      await tester.pump();
      expect((tester.widget<TextField>(field).controller!.text), '');
      expect(find.text('Back to this week'), findsOneWidget);

      await tester.tap(find.text('Back to this week'));
      await tester.pump();
      expect((tester.widget<TextField>(field).controller!.text), '+2');
      expect(find.text('Back to this week'), findsNothing);
    });

    testWidgets(
        'typing an over/undertime value updates the weekly total immediately',
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

      expect(find.textContaining('Total: 43h 00m'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('over-undertime-field')),
        '2',
      );
      await tester.pump();

      expect(find.textContaining('Total: 45h 00m'), findsOneWidget);
    });

    testWidgets(
        'editing the over/undertime field persists it and survives a reload',
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

      await tester.enterText(
        find.byKey(const ValueKey('over-undertime-field')),
        '-1.5',
      );
      await tester.pump();
      // Fires the 500ms save debounce (fake clock), then lets the real
      // dart:io write it kicks off actually complete.
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }

      final thisMonday = WeeklyActual.mondayOf(DateTime.now());
      final reloaded = await tester.runAsync(() async {
        WeeklyHoursService.instance.resetForTest();
        await WeeklyHoursService.instance.loadActuals();
        return WeeklyHoursService.instance.actualFor(thisMonday);
      });
      expect(reloaded!.overUndertimeMinutes, -90);
    });
  });
}

String _icsStamp(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}${two(dt.month)}${two(dt.day)}T'
      '${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
}
