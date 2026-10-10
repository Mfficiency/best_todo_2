import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/food_diary_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 8, 25);
  final yesterday = DateTime(2026, 8, 24);

  Task foodEntry(DateTime due, {String title = 'Meal'}) => Task(
        title: title,
        createdAt: today,
        dueDate: due,
        hasExplicitTime: true,
        isEatingHabit: true,
      );

  group('computeEntryCount', () {
    test('no entries today counts zero', () {
      expect(FoodDiaryWidgetService.computeEntryCount([], today), 0);
    });

    test('counts every entry due today regardless of time', () {
      final tasks = [
        foodEntry(DateTime(2026, 8, 25, 8, 15)),
        foodEntry(DateTime(2026, 8, 25, 13, 0)),
        foodEntry(DateTime(2026, 8, 25, 16, 45)),
        foodEntry(DateTime(2026, 8, 25, 20, 45)),
      ];

      expect(FoodDiaryWidgetService.computeEntryCount(tasks, today), 4);
    });

    test('an entry on a different day is ignored', () {
      final tasks = [foodEntry(DateTime(2026, 8, 24, 8, 0))];

      expect(FoodDiaryWidgetService.computeEntryCount(tasks, today), 0);
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

      expect(FoodDiaryWidgetService.computeEntryCount(tasks, today), 0);
    });

    test('an entry with no time never counts', () {
      final tasks = [
        Task(title: 'No time', createdAt: today, isEatingHabit: true),
      ];

      expect(FoodDiaryWidgetService.computeEntryCount(tasks, today), 0);
    });
  });

  group('isBehindSchedule', () {
    test('never behind before the first checkpoint', () {
      expect(
        FoodDiaryWidgetService.isBehindSchedule(0, DateTime(2026, 8, 25, 7, 59)),
        isFalse,
      );
    });

    test('needs 1 by 8:00, 2 by 13:00, 3 by 16:30 and 4 by 20:00', () {
      expect(
        FoodDiaryWidgetService.isBehindSchedule(0, DateTime(2026, 8, 25, 8, 0)),
        isTrue,
      );
      expect(
        FoodDiaryWidgetService.isBehindSchedule(1, DateTime(2026, 8, 25, 8, 0)),
        isFalse,
      );
      expect(
        FoodDiaryWidgetService.isBehindSchedule(1, DateTime(2026, 8, 25, 13, 0)),
        isTrue,
      );
      expect(
        FoodDiaryWidgetService.isBehindSchedule(2, DateTime(2026, 8, 25, 13, 0)),
        isFalse,
      );
      expect(
        FoodDiaryWidgetService.isBehindSchedule(2, DateTime(2026, 8, 25, 16, 30)),
        isTrue,
      );
      expect(
        FoodDiaryWidgetService.isBehindSchedule(3, DateTime(2026, 8, 25, 16, 30)),
        isFalse,
      );
      expect(
        FoodDiaryWidgetService.isBehindSchedule(3, DateTime(2026, 8, 25, 20, 0)),
        isTrue,
      );
      expect(
        FoodDiaryWidgetService.isBehindSchedule(4, DateTime(2026, 8, 25, 20, 0)),
        isFalse,
      );
    });

    test('a count above the requirement is never behind', () {
      expect(
        FoodDiaryWidgetService.isBehindSchedule(10, DateTime(2026, 8, 25, 20, 0)),
        isFalse,
      );
    });
  });

  group('latestEntryPerMealWindow', () {
    test('no entries yesterday leaves every meal empty', () {
      final result =
          FoodDiaryWidgetService.latestEntryPerMealWindow([], yesterday);
      expect(result, [null, null, null, null]);
    });

    test('an entry in each window is assigned to breakfast/lunch/snack/dinner',
        () {
      final breakfast = foodEntry(DateTime(2026, 8, 24, 7, 30));
      final lunch = foodEntry(DateTime(2026, 8, 24, 12, 0));
      final snack = foodEntry(DateTime(2026, 8, 24, 15, 0));
      final dinner = foodEntry(DateTime(2026, 8, 24, 19, 0));

      final result = FoodDiaryWidgetService.latestEntryPerMealWindow(
          [breakfast, lunch, snack, dinner], yesterday);

      expect(result, [breakfast, lunch, snack, dinner]);
    });

    test('a boundary time counts toward the later window', () {
      final tasks = [foodEntry(DateTime(2026, 8, 24, 13, 0))];

      final result =
          FoodDiaryWidgetService.latestEntryPerMealWindow(tasks, yesterday);

      expect(result, [null, null, tasks[0], null]);
    });

    test('a very late entry counts toward dinner', () {
      final tasks = [foodEntry(DateTime(2026, 8, 24, 23, 45))];

      final result =
          FoodDiaryWidgetService.latestEntryPerMealWindow(tasks, yesterday);

      expect(result, [null, null, null, tasks[0]]);
    });

    test('the later entry wins when a window has more than one', () {
      final earlier = foodEntry(DateTime(2026, 8, 24, 7, 0), title: 'Toast');
      final later = foodEntry(DateTime(2026, 8, 24, 7, 45), title: 'Eggs');

      final result = FoodDiaryWidgetService.latestEntryPerMealWindow(
          [earlier, later], yesterday);

      expect(result[0], later);
    });

    test('an entry on a different day is ignored', () {
      final tasks = [foodEntry(DateTime(2026, 8, 25, 8, 0))];

      final result =
          FoodDiaryWidgetService.latestEntryPerMealWindow(tasks, yesterday);

      expect(result, [null, null, null, null]);
    });

    test('a plain (non-eating-habit) task never counts', () {
      final tasks = [
        Task(
          title: 'Not food',
          createdAt: today,
          dueDate: DateTime(2026, 8, 24, 8, 0),
          hasExplicitTime: true,
        ),
      ];

      final result =
          FoodDiaryWidgetService.latestEntryPerMealWindow(tasks, yesterday);

      expect(result, [null, null, null, null]);
    });
  });
}
