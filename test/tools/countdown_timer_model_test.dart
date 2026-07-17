import 'package:flutter_test/flutter_test.dart';

import 'package:besttodo/models/countdown_timer.dart';

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

  test('editedAt defaults to createdAt when omitted', () {
    final created = DateTime(2026, 1, 1);
    final item = CountdownTimerItem(
      label: 'x',
      target: DateTime(2026, 1, 8),
      createdAt: created,
    );
    expect(item.editedAt, created);
  });

  test('legacy json without timestamps still loads', () {
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
  });

  group('crossedRoundMilestone', () {
    test('reports a milestone once the remaining time falls to or below it',
        () {
      expect(
        CountdownTimerItem.crossedRoundMilestone(
          previousSeconds: 100001,
          currentSeconds: 99999,
        ),
        100000,
      );
      // Landing exactly on the milestone counts as crossing it.
      expect(
        CountdownTimerItem.crossedRoundMilestone(
          previousSeconds: 100001,
          currentSeconds: 100000,
        ),
        100000,
      );
    });

    test('reports nothing without a crossing', () {
      // Still above the milestone.
      expect(
        CountdownTimerItem.crossedRoundMilestone(
          previousSeconds: 100002,
          currentSeconds: 100001,
        ),
        isNull,
      );
      // Already at the milestone before — no re-fire while sitting below it.
      expect(
        CountdownTimerItem.crossedRoundMilestone(
          previousSeconds: 100000,
          currentSeconds: 99999,
        ),
        isNull,
      );
      // Between milestones the whole time.
      expect(
        CountdownTimerItem.crossedRoundMilestone(
          previousSeconds: 5000,
          currentSeconds: 4000,
        ),
        isNull,
      );
    });

    test('reports only the most recent milestone after a large jump', () {
      // e.g. the app was backgrounded from 2,000,000 s out until 9,000 s out:
      // 1,000,000 / 100,000 / 10,000 were all passed; only the latest fires.
      expect(
        CountdownTimerItem.crossedRoundMilestone(
          previousSeconds: 2000000,
          currentSeconds: 9000,
        ),
        10000,
      );
    });

    test('reports nothing for a timer at or past zero', () {
      expect(
        CountdownTimerItem.crossedRoundMilestone(
          previousSeconds: 1500,
          currentSeconds: 0,
        ),
        isNull,
      );
      expect(
        CountdownTimerItem.crossedRoundMilestone(
          previousSeconds: 1500,
          currentSeconds: -10,
        ),
        isNull,
      );
    });

    test('count-up: reports a milestone once the elapsed time reaches it', () {
      expect(
        CountdownTimerItem.crossedRoundMilestoneUp(
          previousSeconds: 99999,
          currentSeconds: 100001,
        ),
        100000,
      );
      // Landing exactly on the milestone counts as crossing it.
      expect(
        CountdownTimerItem.crossedRoundMilestoneUp(
          previousSeconds: 99999,
          currentSeconds: 100000,
        ),
        100000,
      );
    });

    test('count-up: reports nothing without a crossing', () {
      // Still below the milestone.
      expect(
        CountdownTimerItem.crossedRoundMilestoneUp(
          previousSeconds: 99998,
          currentSeconds: 99999,
        ),
        isNull,
      );
      // Already at the milestone before — no re-fire while sitting above it.
      expect(
        CountdownTimerItem.crossedRoundMilestoneUp(
          previousSeconds: 100000,
          currentSeconds: 100001,
        ),
        isNull,
      );
      // Just crossed zero — nothing until 1,000 s elapsed.
      expect(
        CountdownTimerItem.crossedRoundMilestoneUp(
          previousSeconds: -5,
          currentSeconds: 3,
        ),
        isNull,
      );
    });

    test('count-up: reports only the most recent milestone after a large jump',
        () {
      // e.g. the app was closed from 9,000 s elapsed until 2,000,000 s
      // elapsed: 10,000 / 100,000 / 1,000,000 were all passed; only the
      // latest (largest) fires.
      expect(
        CountdownTimerItem.crossedRoundMilestoneUp(
          previousSeconds: 9000,
          currentSeconds: 2000000,
        ),
        1000000,
      );
    });

    test('milestones are the descending powers of ten from 1e9 to 1e3', () {
      expect(CountdownTimerItem.roundMilestones, [
        1000000000,
        100000000,
        10000000,
        1000000,
        100000,
        10000,
        1000,
      ]);
    });
  });
}
