import 'package:flutter_test/flutter_test.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/recurrence_service.dart';

Task _master({
  required DateTime dueDate,
  String frequency = 'daily',
  int interval = 1,
  List<int> weekdays = const [],
  String endType = 'never',
  DateTime? endDate,
  int? occurrenceCount,
  List<String> exceptions = const [],
}) {
  return Task(
    title: 'Series',
    dueDate: dueDate,
    isRecurring: true,
    recurrenceFrequency: frequency,
    recurrenceInterval: interval,
    recurrenceWeekdays: List.of(weekdays),
    recurrenceEndType: endType,
    recurrenceEndDate: endDate,
    recurrenceOccurrenceCount: occurrenceCount,
    recurrenceExceptionDates: List.of(exceptions),
  );
}

void main() {
  group('occurrenceDates', () {
    test('daily interval steps by N days until the end date', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        interval: 2,
        endType: 'date',
        endDate: DateTime(2026, 1, 7),
      );
      final dates = RecurrenceService.occurrenceDates(
        master,
        horizon: DateTime(2026, 1, 7),
      );
      expect(dates, [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 7),
      ]);
    });

    test('weekly on multiple weekdays generates each one every N weeks', () {
      // 2026-02-23 is a Monday.
      final master = _master(
        dueDate: DateTime(2026, 2, 23),
        frequency: 'weekly',
        interval: 2,
        weekdays: [DateTime.monday, DateTime.wednesday, DateTime.friday],
        endType: 'date',
        endDate: DateTime(2026, 3, 20),
      );
      final dates = RecurrenceService.occurrenceDates(
        master,
        horizon: DateTime(2026, 3, 20),
      );
      // Week of 2/23 (week 0): Mon 23, Wed 25, Fri 27.
      // Week of 3/2 (week 1): skipped, interval is every 2 weeks.
      // Week of 3/9 (week 2): Mon 9, Wed 11, Fri 13.
      expect(dates, [
        DateTime(2026, 2, 23),
        DateTime(2026, 2, 25),
        DateTime(2026, 2, 27),
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 11),
        DateTime(2026, 3, 13),
      ]);
    });

    test('monthly clamps to the last day of a shorter month', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 31),
        frequency: 'monthly',
        endType: 'date',
        endDate: DateTime(2026, 4, 30),
      );
      final dates = RecurrenceService.occurrenceDates(
        master,
        horizon: DateTime(2026, 4, 30),
      );
      expect(dates, [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });

    test('yearly steps by N years', () {
      final master = _master(
        dueDate: DateTime(2024, 2, 29),
        frequency: 'yearly',
        endType: 'date',
        endDate: DateTime(2028, 12, 31),
      );
      final dates = RecurrenceService.occurrenceDates(
        master,
        horizon: DateTime(2028, 12, 31),
      );
      expect(dates, [
        DateTime(2024, 2, 29),
        DateTime(2025, 2, 28),
        DateTime(2026, 2, 28),
        DateTime(2027, 2, 28),
        DateTime(2028, 2, 29),
      ]);
    });

    test('count end type stops after exactly N occurrences', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'count',
        occurrenceCount: 3,
      );
      final dates = RecurrenceService.occurrenceDates(
        master,
        horizon: DateTime(2026, 12, 31),
      );
      expect(dates.length, 3);
      expect(dates.last, DateTime(2026, 1, 3));
    });

    test('never-ending series generates through the given rolling horizon', () {
      final master = _master(dueDate: DateTime(2026, 1, 1));
      final dates = RecurrenceService.occurrenceDates(
        master,
        horizon: DateTime(2026, 1, 1).add(const Duration(days: 400)),
      );
      expect(dates.length, 401);
    });
  });

  group('planRefresh', () {
    test('generates every future occurrence for a fresh series', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'date',
        endDate: DateTime(2026, 1, 5),
      );
      final tasks = [master];
      final plan = RecurrenceService.planRefresh(master, tasks,
          now: DateTime(2026, 1, 1));
      expect(plan.toAdd.map((t) => t.dueDate), [
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 4),
        DateTime(2026, 1, 5),
      ]);
      expect(plan.toRemove, isEmpty);
      for (final child in plan.toAdd) {
        expect(child.recurrenceParentUid, master.uid);
        expect(child.title, master.title);
      }
    });

    test('a deleted occurrence stays gone across repeated refreshes', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'date',
        endDate: DateTime(2026, 1, 5),
      );
      final tasks = [master];
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));
      expect(tasks.length, 5);

      // User deletes the 1/3 occurrence "this event only": it goes on the
      // exception list and is removed from the live list, simulating what
      // home_page does on delete.
      final jan3 = tasks.firstWhere((t) => t.dueDate == DateTime(2026, 1, 3));
      master.recurrenceExceptionDates.add(jan3.recurrenceInstanceKey!);
      tasks.remove(jan3);
      expect(tasks.length, 4);

      // Simulate an app restart: refresh runs again from scratch. The
      // deleted slot must not come back — this is the core bug this
      // redesign fixes.
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));
      expect(tasks.length, 4);
      expect(tasks.any((t) => t.dueDate == DateTime(2026, 1, 3)), isFalse);
    });

    test('an overridden occurrence survives even if the schedule shrinks', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'date',
        endDate: DateTime(2026, 1, 10),
      );
      final tasks = [master];
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));
      final jan5 = tasks.firstWhere((t) => t.dueDate == DateTime(2026, 1, 5));
      jan5.recurrenceOverride = true;
      jan5.title = 'Special edit';

      // Shrink the series so 1/5 is no longer in the generated window.
      master.recurrenceEndDate = DateTime(2026, 1, 3);
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));

      expect(tasks.contains(jan5), isTrue);
      expect(jan5.title, 'Special edit');
      expect(tasks.any((t) => t.dueDate == DateTime(2026, 1, 4)), isFalse);
    });

    test('turning recurrence off removes every generated child', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'date',
        endDate: DateTime(2026, 1, 5),
      );
      final tasks = [master];
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));
      expect(tasks.length, 5);

      master.isRecurring = false;
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));
      expect(tasks, [master]);
    });

    test('a child task is left alone by refresh (only masters generate)', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'date',
        endDate: DateTime(2026, 1, 3),
      );
      final tasks = [master];
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));
      final child = tasks.firstWhere((t) => t != master);
      final plan = RecurrenceService.planRefresh(child, tasks);
      expect(plan.isEmpty, isTrue);
    });
  });

  group('promoteNextOccurrenceAsMaster', () {
    test('promotes the next occurrence and re-points the rest', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'date',
        endDate: DateTime(2026, 1, 10),
      );
      final tasks = [master];
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));

      final newMaster =
          RecurrenceService.promoteNextOccurrenceAsMaster(master, tasks)!;
      expect(newMaster.dueDate, DateTime(2026, 1, 2));
      expect(newMaster.isRecurring, isTrue);
      expect(newMaster.recurrenceParentUid, isNull);
      expect(newMaster.recurrenceEndDate, DateTime(2026, 1, 10));

      for (final t in tasks) {
        if (t.uid == newMaster.uid) continue;
        if (t.uid == master.uid) continue;
        expect(t.recurrenceParentUid, newMaster.uid);
      }
    });

    test('returns null when the series has no other occurrence', () {
      final master = _master(dueDate: DateTime(2026, 1, 1));
      final tasks = [master];
      expect(RecurrenceService.promoteNextOccurrenceAsMaster(master, tasks),
          isNull);
    });

    test('carries a count-based end forward minus the consumed occurrence', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'count',
        occurrenceCount: 5,
      );
      final tasks = [master];
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));
      final newMaster =
          RecurrenceService.promoteNextOccurrenceAsMaster(master, tasks)!;
      expect(newMaster.recurrenceOccurrenceCount, 4);
    });
  });

  group('truncateSeriesBefore', () {
    test('deleting a middle occurrence and following ends the series there',
        () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'date',
        endDate: DateTime(2026, 1, 10),
      );
      final tasks = [master];
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));

      final tail = RecurrenceService.truncateSeriesBefore(
          master, tasks, DateTime(2026, 1, 5));
      expect(master.recurrenceEndDate, DateTime(2026, 1, 4));
      expect(tail.map((t) => t.dueDate).toSet(), {
        DateTime(2026, 1, 5),
        DateTime(2026, 1, 6),
        DateTime(2026, 1, 7),
        DateTime(2026, 1, 8),
        DateTime(2026, 1, 9),
        DateTime(2026, 1, 10),
      });

      for (final t in tail) {
        tasks.remove(t);
      }
      // Refreshing afterwards must not regenerate the truncated tail.
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));
      expect(
          tasks.any((t) => t.dueDate!.isAfter(DateTime(2026, 1, 4))), isFalse);
    });

    test('deleting "all events" returns the master plus every child', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'date',
        endDate: DateTime(2026, 1, 5),
      );
      final tasks = [master];
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));
      expect(tasks.length, 5);

      final tail = RecurrenceService.truncateSeriesBefore(
          master, tasks, master.dueDate!);
      expect(tail.length, 5);
      expect(tail, contains(master));
    });
  });

  group('reanchorSeriesFrom', () {
    test('this-and-following move splits the series and shifts the tail', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'date',
        endDate: DateTime(2026, 1, 10),
      );
      final tasks = [master];
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));
      final jan5 = tasks.firstWhere((t) => t.dueDate == DateTime(2026, 1, 5));

      final newMaster = RecurrenceService.reanchorSeriesFrom(
          master, tasks, jan5, DateTime(2026, 1, 8));

      expect(identical(newMaster, jan5), isTrue);
      expect(newMaster.dueDate, DateTime(2026, 1, 8));
      expect(newMaster.recurrenceParentUid, isNull);
      expect(newMaster.recurrenceEndDate, DateTime(2026, 1, 10));
      expect(master.recurrenceEndDate, DateTime(2026, 1, 4));

      // 1/6..1/10 (everything after the split, excluding jan5 itself, which
      // became the new master) now belong to the new master, each shifted
      // by the same +3 day delta the split date moved by.
      final shifted = tasks
          .where((t) => t.recurrenceParentUid == newMaster.uid)
          .map((t) => t.dueDate)
          .toSet();
      expect(shifted, {
        DateTime(2026, 1, 9),
        DateTime(2026, 1, 10),
        DateTime(2026, 1, 11),
        DateTime(2026, 1, 12),
        DateTime(2026, 1, 13),
      });
    });

    test('an override in the tail is re-parented but not shifted', () {
      final master = _master(
        dueDate: DateTime(2026, 1, 1),
        endType: 'date',
        endDate: DateTime(2026, 1, 10),
      );
      final tasks = [master];
      RecurrenceService.refresh(master, tasks, now: DateTime(2026, 1, 1));
      final jan5 = tasks.firstWhere((t) => t.dueDate == DateTime(2026, 1, 5));
      final jan7 = tasks.firstWhere((t) => t.dueDate == DateTime(2026, 1, 7));
      jan7.recurrenceOverride = true;
      jan7.dueDate = DateTime(2026, 1, 20); // manually moved far out

      final newMaster = RecurrenceService.reanchorSeriesFrom(
          master, tasks, jan5, DateTime(2026, 1, 8));

      expect(jan7.recurrenceParentUid, newMaster.uid);
      expect(jan7.dueDate, DateTime(2026, 1, 20));
    });
  });
}
