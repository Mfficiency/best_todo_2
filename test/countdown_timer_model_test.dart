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
      createdAt: created,
      editedAt: edited,
    );

    final restored = CountdownTimerItem.fromJson(item.toJson());

    expect(restored.uid, 'abc');
    expect(restored.label, 'Launch');
    expect(restored.notifyOnZero, isTrue);
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
  });
}
