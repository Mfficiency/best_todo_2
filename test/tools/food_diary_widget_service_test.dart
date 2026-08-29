import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/food_diary_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 8, 25);

  Task foodEntry(DateTime due) => Task(
        title: 'Meal',
        createdAt: today,
        dueDate: due,
        hasExplicitTime: true,
        isEatingHabit: true,
      );

  test('no entries today leaves every checkpoint unlogged', () {
    final result = FoodDiaryWidgetService.computeHasEntry([], today);
    expect(result, [false, false, false]);
  });

  test('an entry in each window marks all three checkpoints logged', () {
    final tasks = [
      foodEntry(DateTime(2026, 8, 25, 8, 15)),
      foodEntry(DateTime(2026, 8, 25, 13, 0)),
      foodEntry(DateTime(2026, 8, 25, 20, 45)),
    ];

    final result = FoodDiaryWidgetService.computeHasEntry(tasks, today);

    expect(result, [true, true, true]);
  });

  test('an entry just before a checkpoint counts toward the earlier window',
      () {
    final tasks = [foodEntry(DateTime(2026, 8, 25, 12, 59))];

    final result = FoodDiaryWidgetService.computeHasEntry(tasks, today);

    expect(result, [true, false, false]);
  });

  test('an entry on a different day is ignored', () {
    final tasks = [foodEntry(DateTime(2026, 8, 24, 8, 0))];

    final result = FoodDiaryWidgetService.computeHasEntry(tasks, today);

    expect(result, [false, false, false]);
  });

  test('a plain (non-eating-habit) task never counts', () {
    final tasks = [
      Task(
        title: 'Not food',
        createdAt: today,
        dueDate: DateTime(2026, 8, 25, 8, 0),
        hasExplicitTime: true,
      ),
    ];

    final result = FoodDiaryWidgetService.computeHasEntry(tasks, today);

    expect(result, [false, false, false]);
  });

  test('an entry with no time never counts', () {
    final tasks = [
      Task(title: 'No time', createdAt: today, isEatingHabit: true),
    ];

    final result = FoodDiaryWidgetService.computeHasEntry(tasks, today);

    expect(result, [false, false, false]);
  });

  test('a started unlogged checkpoint marks the widget as missed', () {
    expect(
      FoodDiaryWidgetService.hasMissedCheckpoint(
        [true, false, false],
        DateTime(2026, 8, 25, 13),
      ),
      isTrue,
    );
    expect(
      FoodDiaryWidgetService.hasMissedCheckpoint(
        [true, true, false],
        DateTime(2026, 8, 25, 19),
      ),
      isFalse,
    );
  });
}
