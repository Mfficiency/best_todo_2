import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/models/countdown_milestone.dart';
import 'package:besttodo/models/countdown_timer.dart';

/// A timer at a fixed target with exactly the given milestones.
CountdownTimerItem _timerWith(
  List<CountdownMilestone> milestones, {
  DateTime? target,
}) {
  return CountdownTimerItem(
    label: 'Launch',
    target: target ?? DateTime(2026, 6, 1, 12, 0),
    notifyRoundNumbers: true,
    milestones: milestones,
  );
}

void main() {
  test('CountdownTimerItem serializes created/edited timestamps', () {
    final created = DateTime(2026, 1, 2, 3, 4, 5);
    final edited = DateTime(2026, 2, 3, 4, 5, 6);
    final item = CountdownTimerItem(
      uid: 'abc',
      label: 'Launch',
      target: DateTime(2026, 6, 1, 12, 0),
      notifyOnZero: true,
      notifyRoundNumbers: true,
      createdAt: created,
      editedAt: edited,
    );

    final restored = CountdownTimerItem.fromJson(item.toJson());

    expect(restored.uid, 'abc');
    expect(restored.label, 'Launch');
    expect(restored.notifyOnZero, isTrue);
    expect(restored.notifyRoundNumbers, isTrue);
    expect(restored.createdAt, created);
    expect(restored.editedAt, edited);
    expect(restored.target, DateTime(2026, 6, 1, 12, 0));
  });

  test('milestones survive a round trip', () {
    final item = _timerWith([
      CountdownMilestone(value: 3, unit: MilestoneUnit.weeks),
      CountdownMilestone(
        value: 500,
        unit: MilestoneUnit.hours,
        direction: MilestoneDirection.after,
      ),
    ]);

    final restored = CountdownTimerItem.fromJson(item.toJson());

    expect(restored.milestones, hasLength(2));
    expect(restored.milestones[0].value, 3);
    expect(restored.milestones[0].unit, MilestoneUnit.weeks);
    expect(restored.milestones[0].direction, MilestoneDirection.both);
    expect(restored.milestones[1].value, 500);
    expect(restored.milestones[1].unit, MilestoneUnit.hours);
    expect(restored.milestones[1].direction, MilestoneDirection.after);
  });

  test('editedAt defaults to createdAt when omitted', () {
    final created = DateTime(2026, 1, 1);
    final item = CountdownTimerItem(
      label: 'x',
      target: DateTime(2026, 1, 8),
      createdAt: created,
    );
    expect(item.editedAt, created);
  });

  test('legacy json without timestamps or milestones still loads', () {
    final item = CountdownTimerItem.fromJson({
      'uid': 'u1',
      'label': 'Old',
      'target': DateTime(2026, 5, 1).toIso8601String(),
    });
    expect(item.label, 'Old');
    // Missing timestamps fall back to a sensible non-null default.
    expect(item.createdAt, isNotNull);
    expect(item.editedAt, isNotNull);
    // Missing round-number flag defaults to off.
    expect(item.notifyRoundNumbers, isFalse);
    // A timer saved before milestones existed inherits the defaults, so
    // switching the bell on keeps behaving sensibly.
    expect(item.milestones, hasLength(7));
  });

  test('milestones with a non-positive value are dropped on load', () {
    final item = CountdownTimerItem.fromJson({
      'uid': 'u1',
      'label': 'Old',
      'target': DateTime(2026, 5, 1).toIso8601String(),
      'milestones': [
        {'value': 0, 'unit': 'days', 'direction': 'both'},
        {'value': 5, 'unit': 'days', 'direction': 'both'},
      ],
    });
    expect(item.milestones, hasLength(1));
    expect(item.milestones.single.value, 5);
  });

  test('defaults are 10 years/months/weeks/days plus the three big counts', () {
    final defaults = CountdownTimerItem.defaultMilestones();
    expect(
      defaults.map((m) => '${m.value} ${m.unit.name}').toList(),
      [
        '10 years',
        '10 months',
        '10000000 seconds',
        '10 weeks',
        '100000 minutes',
        '1000 hours',
        '10 days',
      ],
    );
    // The declared order is already longest-first.
    final lengths = defaults.map((m) => m.approximateSeconds).toList();
    expect(lengths, [...lengths]..sort((a, b) => b.compareTo(a)));
    // Every default fires on both sides of the event.
    expect(
      defaults.every((m) => m.direction == MilestoneDirection.both),
      isTrue,
    );
  });

  group('CountdownMilestone.shift', () {
    final base = DateTime(2026, 6, 1, 12, 0);

    test('fixed-length units add a plain duration', () {
      expect(
        CountdownMilestone.shift(base, MilestoneUnit.seconds, -90),
        DateTime(2026, 6, 1, 11, 58, 30),
      );
      expect(
        CountdownMilestone.shift(base, MilestoneUnit.hours, 5),
        DateTime(2026, 6, 1, 17, 0),
      );
      expect(
        CountdownMilestone.shift(base, MilestoneUnit.weeks, -2),
        DateTime(2026, 5, 18, 12, 0),
      );
    });

    test('months and years follow the calendar', () {
      expect(
        CountdownMilestone.shift(base, MilestoneUnit.months, 10),
        DateTime(2027, 4, 1, 12, 0),
      );
      expect(
        CountdownMilestone.shift(base, MilestoneUnit.months, -10),
        DateTime(2025, 8, 1, 12, 0),
      );
      expect(
        CountdownMilestone.shift(base, MilestoneUnit.years, -10),
        DateTime(2016, 6, 1, 12, 0),
      );
    });

    test('the day is clamped into a shorter target month', () {
      // 31 March minus one month has no 31st to land on.
      expect(
        CountdownMilestone.shift(
          DateTime(2026, 3, 31, 8, 30),
          MilestoneUnit.months,
          -1,
        ),
        DateTime(2026, 2, 28, 8, 30),
      );
      // ...and does in a leap year.
      expect(
        CountdownMilestone.shift(
          DateTime(2028, 3, 31, 8, 30),
          MilestoneUnit.months,
          -1,
        ),
        DateTime(2028, 2, 29, 8, 30),
      );
    });

    test('shifting back across a year boundary rolls the year down', () {
      expect(
        CountdownMilestone.shift(
          DateTime(2026, 2, 10, 9, 0),
          MilestoneUnit.months,
          -3,
        ),
        DateTime(2025, 11, 10, 9, 0),
      );
    });
  });

  group('dueMilestone', () {
    test('fires when the before-instant falls inside the window', () {
      final timer =
          _timerWith([CountdownMilestone(value: 10, unit: MilestoneUnit.days)]);
      // 10 days before 2026-06-01 12:00 is 2026-05-22 12:00.
      final hit = timer.dueMilestone(
        previousNow: DateTime(2026, 5, 22, 11, 59, 59),
        now: DateTime(2026, 5, 22, 12, 0, 0),
      );
      expect(hit, isNotNull);
      expect(hit!.isAfter, isFalse);
      expect(hit.milestone.value, 10);
      expect(hit.message, '10 days to go');
    });

    test('fires when the after-instant falls inside the window', () {
      final timer =
          _timerWith([CountdownMilestone(value: 10, unit: MilestoneUnit.days)]);
      // 10 days after the target is 2026-06-11 12:00.
      final hit = timer.dueMilestone(
        previousNow: DateTime(2026, 6, 11, 11, 59, 59),
        now: DateTime(2026, 6, 11, 12, 0, 0),
      );
      expect(hit, isNotNull);
      expect(hit!.isAfter, isTrue);
      expect(hit.message, '10 days since');
    });

    test('reports nothing when no instant falls in the window', () {
      final timer =
          _timerWith([CountdownMilestone(value: 10, unit: MilestoneUnit.days)]);
      expect(
        timer.dueMilestone(
          previousNow: DateTime(2026, 5, 22, 12, 0, 1),
          now: DateTime(2026, 5, 22, 12, 0, 2),
        ),
        isNull,
      );
      // The window is half-open, so an instant exactly at its start already
      // fired on the previous tick and must not repeat.
      expect(
        timer.dueMilestone(
          previousNow: DateTime(2026, 5, 22, 12, 0, 0),
          now: DateTime(2026, 5, 22, 12, 0, 5),
        ),
        isNull,
      );
    });

    test('a before-only milestone never fires after the event', () {
      final timer = _timerWith([
        CountdownMilestone(
          value: 10,
          unit: MilestoneUnit.days,
          direction: MilestoneDirection.before,
        ),
      ]);
      expect(
        timer.dueMilestone(
          previousNow: DateTime(2026, 6, 11, 11, 59, 59),
          now: DateTime(2026, 6, 11, 12, 0, 0),
        ),
        isNull,
      );
      expect(
        timer.dueMilestone(
          previousNow: DateTime(2026, 5, 22, 11, 59, 59),
          now: DateTime(2026, 5, 22, 12, 0, 0),
        ),
        isNotNull,
      );
    });

    test('an after-only milestone never fires before the event', () {
      final timer = _timerWith([
        CountdownMilestone(
          value: 10,
          unit: MilestoneUnit.days,
          direction: MilestoneDirection.after,
        ),
      ]);
      expect(
        timer.dueMilestone(
          previousNow: DateTime(2026, 5, 22, 11, 59, 59),
          now: DateTime(2026, 5, 22, 12, 0, 0),
        ),
        isNull,
      );
      expect(
        timer.dueMilestone(
          previousNow: DateTime(2026, 6, 11, 11, 59, 59),
          now: DateTime(2026, 6, 11, 12, 0, 0),
        ),
        isNotNull,
      );
    });

    test('reports only the most recent milestone after a large jump', () {
      // App closed from well before the event until well after it: the 10-day
      // and 1-day before-instants and the 1-day after-instant all passed, but
      // only the latest one notifies.
      final timer = _timerWith([
        CountdownMilestone(value: 10, unit: MilestoneUnit.days),
        CountdownMilestone(value: 1, unit: MilestoneUnit.days),
      ]);
      final hit = timer.dueMilestone(
        previousNow: DateTime(2026, 5, 1),
        now: DateTime(2026, 6, 5),
      );
      expect(hit, isNotNull);
      // 1 day after the target (2026-06-02 12:00) is the most recent.
      expect(hit!.isAfter, isTrue);
      expect(hit.milestone.value, 1);
      expect(hit.message, '1 day since');
    });

    test('mixed units all resolve against the same target', () {
      final timer = _timerWith([
        CountdownMilestone(value: 100, unit: MilestoneUnit.seconds),
        CountdownMilestone(value: 3, unit: MilestoneUnit.months),
      ]);
      // 3 months before 2026-06-01 12:00 is 2026-03-01 12:00.
      final monthHit = timer.dueMilestone(
        previousNow: DateTime(2026, 3, 1, 11, 59, 59),
        now: DateTime(2026, 3, 1, 12, 0, 0),
      );
      expect(monthHit?.message, '3 months to go');
      // 100 seconds before is 2026-06-01 11:58:20.
      final secondHit = timer.dueMilestone(
        previousNow: DateTime(2026, 6, 1, 11, 58, 19),
        now: DateTime(2026, 6, 1, 11, 58, 20),
      );
      expect(secondHit?.message, '100 seconds to go');
    });

    test('a timer with no milestones reports nothing', () {
      final timer = _timerWith([]);
      expect(
        timer.dueMilestone(
          previousNow: DateTime(2026, 1, 1),
          now: DateTime(2027, 1, 1),
        ),
        isNull,
      );
    });
  });

  group('formatting', () {
    test('labels group thousands and singularize', () {
      expect(
        CountdownMilestone(value: 10000000, unit: MilestoneUnit.seconds).label,
        '10,000,000 seconds',
      );
      expect(
        CountdownMilestone(value: 1, unit: MilestoneUnit.days).label,
        '1 day',
      );
      expect(
        CountdownMilestone(value: 10, unit: MilestoneUnit.days).label,
        '10 days',
      );
    });

    test('direction labels read plainly', () {
      expect(
        CountdownMilestone(value: 1, unit: MilestoneUnit.days).directionLabel,
        'before & after',
      );
      expect(
        CountdownMilestone(
          value: 1,
          unit: MilestoneUnit.days,
          direction: MilestoneDirection.before,
        ).directionLabel,
        'before',
      );
    });
  });

  test('sortedMilestones orders longest first regardless of unit', () {
    final timer = _timerWith([
      CountdownMilestone(value: 100, unit: MilestoneUnit.seconds),
      CountdownMilestone(value: 2, unit: MilestoneUnit.years),
      CountdownMilestone(value: 3, unit: MilestoneUnit.days),
      CountdownMilestone(value: 5, unit: MilestoneUnit.hours),
    ]);
    expect(
      timer.sortedMilestones.map((m) => m.label).toList(),
      ['2 years', '3 days', '5 hours', '100 seconds'],
    );
  });
}
