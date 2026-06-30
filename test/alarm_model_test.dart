import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/alarm.dart';

void main() {
  test('alarms generate unique ids', () {
    final a = Alarm(name: 'a');
    final b = Alarm(name: 'b');
    expect(a.uid, isNotEmpty);
    expect(b.uid, isNotEmpty);
    expect(a.uid, isNot(b.uid));
  });

  test('timeLabel is zero padded', () {
    final alarm = Alarm(name: 'wake', hour: 7, minute: 5);
    expect(alarm.timeLabel, '07:05');
  });

  test('all fields serialize and deserialize', () {
    final date = DateTime(2026, 7, 1);
    final alarm = Alarm(
      name: 'Morning',
      description: 'Get up',
      volume: 0.5,
      melody: 'Radar',
      vibrate: false,
      hour: 6,
      minute: 30,
      date: date,
      isRepeating: true,
      repeatDays: [DateTime.monday, DateTime.friday],
      color: 0xFFE53935,
      snoozeEnabled: false,
      snoozeDurationMinutes: 5,
      snoozeMaxCount: 2,
      enabled: false,
    );

    final decoded = Alarm.fromJson(alarm.toJson());

    expect(decoded.name, 'Morning');
    expect(decoded.description, 'Get up');
    expect(decoded.volume, 0.5);
    expect(decoded.melody, 'Radar');
    expect(decoded.vibrate, isFalse);
    expect(decoded.hour, 6);
    expect(decoded.minute, 30);
    expect(decoded.date, date);
    expect(decoded.isRepeating, isTrue);
    expect(decoded.repeatDays, [DateTime.monday, DateTime.friday]);
    expect(decoded.color, 0xFFE53935);
    expect(decoded.snoozeEnabled, isFalse);
    expect(decoded.snoozeDurationMinutes, 5);
    expect(decoded.snoozeMaxCount, 2);
    expect(decoded.enabled, isFalse);
  });

  test('scheduleLabel summarizes repeat days', () {
    final everyDay = Alarm(
      name: 'a',
      isRepeating: true,
      repeatDays: [1, 2, 3, 4, 5, 6, 7],
    );
    expect(everyDay.scheduleLabel, 'Every day');

    final weekdays = Alarm(
      name: 'b',
      isRepeating: true,
      repeatDays: [1, 2, 3, 4, 5],
    );
    expect(weekdays.scheduleLabel, 'Weekdays');

    final weekends = Alarm(
      name: 'c',
      isRepeating: true,
      repeatDays: [6, 7],
    );
    expect(weekends.scheduleLabel, 'Weekends');
  });

  test('nextOccurrence finds the next repeating weekday', () {
    // 2026-06-30 is a Tuesday.
    final from = DateTime(2026, 6, 30, 10, 0);
    final alarm = Alarm(
      name: 'wed',
      hour: 9,
      minute: 0,
      isRepeating: true,
      repeatDays: [DateTime.wednesday],
    );
    final next = alarm.nextOccurrence(from);
    expect(next, DateTime(2026, 7, 1, 9, 0));
  });

  test('one-off alarm without date rolls to tomorrow when time passed', () {
    final from = DateTime(2026, 6, 30, 10, 0);
    final alarm = Alarm(name: 'past', hour: 9, minute: 0);
    final next = alarm.nextOccurrence(from);
    expect(next, DateTime(2026, 7, 1, 9, 0));
  });
}
