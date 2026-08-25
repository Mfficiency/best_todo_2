import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/models/gcal_event.dart';
import 'package:besttodo/services/google_calendar_service.dart';

/// Tests for the .ics importer behind the Weekly Hours Planner's "Google
/// Calendar" setting: parsing VEVENT blocks (including folded lines,
/// all-day dates and escaped text) and expanding RRULE recurrences for a
/// given date range. All pure Dart — no network or disk access — so these
/// run without a fake path provider.
void main() {
  group('parseIcs', () {
    test('parses a single timed event', () {
      const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:evt1@example.com
DTSTART:20260826T090000
DTEND:20260826T100000
SUMMARY:Standup
END:VEVENT
END:VCALENDAR
''';
      final events = GoogleCalendarService.parseIcs(ics);
      expect(events, hasLength(1));
      final e = events.single;
      expect(e.title, 'Standup');
      expect(e.start, DateTime(2026, 8, 26, 9, 0));
      expect(e.end, DateTime(2026, 8, 26, 10, 0));
      expect(e.allDay, isFalse);
      expect(e.rrule, isNull);
    });

    test('parses an all-day event as allDay with a date-only range', () {
      const ics = '''
BEGIN:VEVENT
UID:evt2@example.com
DTSTART;VALUE=DATE:20260827
DTEND;VALUE=DATE:20260828
SUMMARY:Holiday
END:VEVENT
''';
      final e = GoogleCalendarService.parseIcs(ics).single;
      expect(e.allDay, isTrue);
      expect(e.start, DateTime(2026, 8, 27));
      expect(e.end, DateTime(2026, 8, 28));
    });

    test('joins folded (continuation) lines back into one property', () {
      const ics = 'BEGIN:VEVENT\r\n'
          'UID:evt3@example.com\r\n'
          'DTSTART:20260828T100000\r\n'
          'DTEND:20260828T110000\r\n'
          'SUMMARY:This is a long summary that\r\n'
          ' continues on the next line\r\n'
          'END:VEVENT\r\n';
      final e = GoogleCalendarService.parseIcs(ics).single;
      expect(e.title, 'This is a long summary that continues on the next line');
    });

    test('unescapes commas, semicolons and backslashes in text values', () {
      const ics = r'''
BEGIN:VEVENT
UID:evt4@example.com
DTSTART:20260829T100000
DTEND:20260829T110000
SUMMARY:Foo\, Bar\; Baz\\qux
END:VEVENT
''';
      final e = GoogleCalendarService.parseIcs(ics).single;
      expect(e.title, r'Foo, Bar; Baz\qux');
    });

    test('an event with no DTEND or DURATION keeps a zero-length window', () {
      const ics = '''
BEGIN:VEVENT
UID:evt5@example.com
DTSTART:20260830T120000
SUMMARY:Point in time
END:VEVENT
''';
      final e = GoogleCalendarService.parseIcs(ics).single;
      expect(e.start, e.end);
    });

    test('captures the RRULE and EXDATE values', () {
      const ics = '''
BEGIN:VEVENT
UID:evt6@example.com
DTSTART:20260803T140000
DTEND:20260803T150000
RRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4
EXDATE:20260810T140000
SUMMARY:Sync
END:VEVENT
''';
      final e = GoogleCalendarService.parseIcs(ics).single;
      expect(e.rrule, 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4');
      expect(e.exdates, [DateTime(2026, 8, 10, 14, 0)]);
    });
  });

  group('eventsInRange (recurrence expansion)', () {
    // 2026-08-03 is a Monday.
    final weeklySync = GCalRawEvent(
      uid: 'sync@example.com',
      title: 'Sync',
      start: DateTime(2026, 8, 3, 14, 0),
      end: DateTime(2026, 8, 3, 15, 0),
      rrule: 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4',
    );

    test('expands FREQ=WEEKLY;BYDAY into the right occurrences, honouring COUNT',
        () {
      final events = GoogleCalendarService.eventsInRange(
        [weeklySync],
        DateTime(2026, 7, 1),
        DateTime(2026, 12, 31),
      );
      expect(events.map((e) => e.start), [
        DateTime(2026, 8, 3, 14, 0),
        DateTime(2026, 8, 5, 14, 0),
        DateTime(2026, 8, 10, 14, 0),
        DateTime(2026, 8, 12, 14, 0),
      ]);
      for (final e in events) {
        expect(e.title, 'Sync');
        expect(e.end.difference(e.start), const Duration(hours: 1));
      }
    });

    test('only returns occurrences overlapping the requested range', () {
      final events = GoogleCalendarService.eventsInRange(
        [weeklySync],
        DateTime(2026, 8, 9),
        DateTime(2026, 8, 20),
      );
      expect(events.map((e) => e.start),
          [DateTime(2026, 8, 10, 14, 0), DateTime(2026, 8, 12, 14, 0)]);
    });

    test('EXDATE removes one occurrence from the expansion', () {
      final withExdate = GCalRawEvent(
        uid: weeklySync.uid,
        title: weeklySync.title,
        start: weeklySync.start,
        end: weeklySync.end,
        rrule: weeklySync.rrule,
        exdates: [DateTime(2026, 8, 10, 14, 0)],
      );
      final events = GoogleCalendarService.eventsInRange(
        [withExdate],
        DateTime(2026, 7, 1),
        DateTime(2026, 12, 31),
      );
      expect(events.map((e) => e.start), [
        DateTime(2026, 8, 3, 14, 0),
        DateTime(2026, 8, 5, 14, 0),
        DateTime(2026, 8, 12, 14, 0),
      ]);
    });

    test('a non-recurring event is included only when it overlaps the range',
        () {
      final oneOff = GCalRawEvent(
        uid: 'one-off',
        title: 'One-off',
        start: DateTime(2026, 8, 15, 9, 0),
        end: DateTime(2026, 8, 15, 10, 0),
      );
      expect(
        GoogleCalendarService.eventsInRange(
            [oneOff], DateTime(2026, 8, 14), DateTime(2026, 8, 16)),
        hasLength(1),
      );
      expect(
        GoogleCalendarService.eventsInRange(
            [oneOff], DateTime(2026, 9, 1), DateTime(2026, 9, 2)),
        isEmpty,
      );
    });

    test('a daily recurrence with INTERVAL steps by that many days', () {
      final everyOtherDay = GCalRawEvent(
        uid: 'daily',
        title: 'Every other day',
        start: DateTime(2026, 8, 1, 8, 0),
        end: DateTime(2026, 8, 1, 8, 30),
        rrule: 'FREQ=DAILY;INTERVAL=2;COUNT=3',
      );
      final events = GoogleCalendarService.eventsInRange(
        [everyOtherDay],
        DateTime(2026, 7, 1),
        DateTime(2026, 12, 31),
      );
      expect(events.map((e) => e.start), [
        DateTime(2026, 8, 1, 8, 0),
        DateTime(2026, 8, 3, 8, 0),
        DateTime(2026, 8, 5, 8, 0),
      ]);
    });
  });
}
