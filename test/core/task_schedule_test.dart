import 'package:besttodo/models/task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy v1 record (dueDate only) upgrades to a deadline interval', () {
    final decoded = Task.fromJson(<String, dynamic>{
      'title': 'legacy',
      'dueDate': DateTime(2026, 8, 1, 18).toIso8601String(),
    });
    expect(decoded.startAt, DateTime(2026, 8, 1, 18));
    expect(decoded.endAt, DateTime(2026, 8, 1, 18));
    expect(decoded.dueDate, DateTime(2026, 8, 1, 18));
    expect(decoded.duration, Duration.zero);
  });

  test('toJson writes schema v2 with the interval and the dueDate mirror',
      () {
    final task = Task(title: 'x', dueDate: DateTime(2026, 8, 2, 18));
    final map = task.toJson();
    expect(map['schemaVersion'], Task.currentSchemaVersion);
    expect(map['startAt'], DateTime(2026, 8, 2, 18).toIso8601String());
    expect(map['endAt'], DateTime(2026, 8, 2, 18).toIso8601String());
    expect(map['dueDate'], DateTime(2026, 8, 2, 18).toIso8601String());
  });

  test('a real interval round-trips and keeps its duration', () {
    final task = Task(
      title: 'deep work',
      startAt: DateTime(2026, 8, 3, 9),
      endAt: DateTime(2026, 8, 3, 11, 30),
      hasExplicitTime: true,
    );
    expect(task.duration, const Duration(hours: 2, minutes: 30));
    // The legacy view is the deadline end.
    expect(task.dueDate, DateTime(2026, 8, 3, 11, 30));

    final decoded = Task.fromJson(task.toJson());
    expect(decoded.startAt, DateTime(2026, 8, 3, 9));
    expect(decoded.endAt, DateTime(2026, 8, 3, 11, 30));
  });

  test('writing dueDate collapses the interval to a deadline', () {
    final task = Task(
      title: 'was a range',
      startAt: DateTime(2026, 8, 3, 9),
      endAt: DateTime(2026, 8, 3, 11),
    );
    task.dueDate = DateTime(2026, 8, 4, 18);
    expect(task.startAt, DateTime(2026, 8, 4, 18));
    expect(task.endAt, DateTime(2026, 8, 4, 18));

    task.dueDate = null;
    expect(task.startAt, isNull);
    expect(task.endAt, isNull);
    expect(task.duration, isNull);
  });

  test('v2 record missing endAt falls back to the dueDate mirror', () {
    final decoded = Task.fromJson(<String, dynamic>{
      'schemaVersion': 2,
      'title': 'partial',
      'dueDate': DateTime(2026, 8, 5, 18).toIso8601String(),
    });
    expect(decoded.endAt, DateTime(2026, 8, 5, 18));
    expect(decoded.startAt, DateTime(2026, 8, 5, 18));
  });

  test('allDay derives from hasExplicitTime', () {
    expect(Task(title: 'a').allDay, isTrue);
    expect(Task(title: 'b', hasExplicitTime: true).allDay, isFalse);
  });

  test('undated tasks stay undated through the upgrade', () {
    final decoded = Task.fromJson(<String, dynamic>{'title': 'someday'});
    expect(decoded.startAt, isNull);
    expect(decoded.endAt, isNull);
    expect(decoded.dueDate, isNull);
  });
}
