import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/services/item_views.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 7, 17);

  Task dated(String title, DateTime due, {bool done = false}) =>
      Task(title: title, dueDate: due, isDone: done);

  group('home buckets', () {
    test('date-only distance decides the tab, overdue lands in Today', () {
      // Explicit rankings make the within-bucket order deterministic
      // (sortTasks compares by listRanking; ties have no guaranteed order).
      final overdue = dated('overdue', DateTime(2026, 7, 10))
        ..listRanking = 1;
      final todayTask = dated('today', DateTime(2026, 7, 17, 23))
        ..listRanking = 2;
      final tomorrow = dated('tomorrow', DateTime(2026, 7, 18, 0, 5));
      final dayAfter = dated('day after', DateTime(2026, 7, 19));
      final nextWeek = dated('next week', DateTime(2026, 7, 22));
      final nextMonth = dated('next month', DateTime(2026, 9, 1));
      final parked = dated('parked', ItemViews.futureSentinelDate)
        ..listRanking = 1;
      final undated = Task(title: 'someday')..listRanking = 2;
      final all = [
        overdue,
        todayTask,
        tomorrow,
        dayAfter,
        nextWeek,
        nextMonth,
        parked,
        undated,
      ];

      List<String> bucket(int tab) => ItemViews.homeBucket(all, tab, today)
          .map((t) => t.title)
          .toList();

      expect(bucket(0), ['overdue', 'today']);
      expect(bucket(1), ['tomorrow']);
      expect(bucket(2), ['day after']);
      expect(bucket(3), ['next week']);
      expect(bucket(4), ['next month']);
      expect(bucket(ItemViews.futureTabIndex), ['parked', 'someday']);
    });

    test('the where predicate narrows a bucket (search)', () {
      final a = dated('write report', today);
      final b = dated('walk dog', today);
      final titles = ItemViews.homeBucket([a, b], 0, today,
              where: (t) => t.title.contains('dog'))
          .map((t) => t.title);
      expect(titles, ['walk dog']);
    });

    test('buckets sort open tasks before done ones', () {
      final done = dated('done', today, done: true)..listRanking = 1;
      final open = dated('open', today)..listRanking = 2;
      final titles =
          ItemViews.homeBucket([done, open], 0, today).map((t) => t.title);
      expect(titles, ['open', 'done']);
    });
  });

  group('wishlist / project queries', () {
    test('wishlist selects only wish-flagged tasks', () {
      final wish = Task(title: 'telescope', isWish: true);
      final plain = Task(title: 'chore');
      expect(ItemViews.wishlist([wish, plain]).map((t) => t.title),
          ['telescope']);
    });

    test('active drops soft-deleted tasks', () {
      final gone = Task(title: 'gone', deletedAt: DateTime(2026, 7, 1));
      final kept = Task(title: 'kept');
      expect(ItemViews.active([gone, kept]).map((t) => t.title), ['kept']);
    });

    test('board columns filter by project and stage, skipping deleted', () {
      final todo = Task(title: 'todo', projectId: 'p1');
      final ongoing = Task(title: 'ongoing', projectId: 'p1')
        ..kanbanStatus = Task.kanbanOngoing;
      final otherProject = Task(title: 'other', projectId: 'p2');
      final deleted = Task(
          title: 'deleted', projectId: 'p1', deletedAt: DateTime(2026, 7, 1));
      final all = [todo, ongoing, otherProject, deleted];

      expect(
          ItemViews.boardColumn(all, 'p1', Task.kanbanTodo)
              .map((t) => t.title),
          ['todo']);
      expect(
          ItemViews.boardColumn(all, 'p1', Task.kanbanOngoing)
              .map((t) => t.title),
          ['ongoing']);
      expect(ItemViews.projectTasks(all, 'p1').map((t) => t.title),
          ['todo', 'ongoing']);
    });
  });

  group('food diary', () {
    test('foodDiary selects only eating-habit-flagged tasks', () {
      final entry = Task(title: 'yogurt', isEatingHabit: true);
      final plain = Task(title: 'chore');
      expect(ItemViews.foodDiary([entry, plain]).map((t) => t.title),
          ['yogurt']);
    });

    test('an eating-habit task is hidden from every other view, even with '
        'a due date and project assignment', () {
      final entry = Task(
        title: 'yogurt',
        dueDate: today,
        isEatingHabit: true,
        projectId: 'p1',
      );
      final ok = Task(title: 'normal', dueDate: today);
      final boardTask = Task(title: 'board', projectId: 'p1');

      expect(ItemViews.homeBucket([entry, ok], 0, today).map((t) => t.title),
          ['normal']);
      expect(ItemViews.active([entry, ok]).map((t) => t.title), ['normal']);
      expect(
          ItemViews.projectTasks([entry, boardTask], 'p1').map((t) => t.title),
          ['board']);
      expect(
          ItemViews.boardColumn([entry, boardTask], 'p1', Task.kanbanTodo)
              .map((t) => t.title),
          ['board']);
      final wishAndEating = Task(
          title: 'wish and eating', isWish: true, isEatingHabit: true);
      final wish = Task(title: 'wish', isWish: true);
      expect(ItemViews.wishlist([wish, wishAndEating]).map((t) => t.title),
          ['wish']);
    });
  });

  group('waiting for approval', () {
    Task pending(String title) =>
        Task(title: title, label: 'Waiting_for_approval');

    test('the pre-0.1.260 waiting-for-approval spelling still gates a task',
        () {
      final legacy = Task(title: 'old pending', label: 'waiting-for-approval');
      final ok = Task(title: 'normal', dueDate: today);
      expect(ItemViews.active([ok, legacy]).map((t) => t.title), ['normal']);
      expect(ItemViews.waitingApproval([ok, legacy]).map((t) => t.title),
          ['old pending']);
    });

    test('a task tagged Waiting_for_approval is hidden from every other '
        'view', () {
      final waiting = pending('from todoist');
      final ok = Task(title: 'normal', dueDate: today);
      final wish = Task(title: 'wish', isWish: true);
      final waitingWish = pending('wish pending')..isWish = true;
      final boardTask = Task(title: 'board', projectId: 'p1');
      final waitingBoard = pending('board pending')..projectId = 'p1';

      expect(
          ItemViews.homeBucket([waiting..dueDate = today, ok], 0, today)
              .map((t) => t.title),
          ['normal']);
      expect(ItemViews.wishlist([wish, waitingWish]).map((t) => t.title),
          ['wish']);
      expect(ItemViews.active([ok, waiting]).map((t) => t.title), ['normal']);
      expect(
          ItemViews.projectTasks([boardTask, waitingBoard], 'p1')
              .map((t) => t.title),
          ['board']);
      expect(
          ItemViews.boardColumn([boardTask, waitingBoard], 'p1',
                  Task.kanbanTodo)
              .map((t) => t.title),
          ['board']);
    });

    test('waitingApproval lists only pending, non-deleted tasks', () {
      final waiting = pending('pending');
      final approved = Task(title: 'approved');
      final deletedWaiting = pending('gone')..deletedAt = DateTime(2026, 7, 1);
      expect(
          ItemViews.waitingApproval([waiting, approved, deletedWaiting])
              .map((t) => t.title),
          ['pending']);
    });

    test('waitingApproval applies rules on top of the structural gate', () {
      final keep = pending('keep')..label = 'Waiting_for_approval, urgent';
      final drop = pending('drop');
      final result = ItemViews.waitingApproval(
        [keep, drop],
        rules: ViewFilterRules(includeTags: ['urgent']),
      );
      expect(result.map((t) => t.title), ['keep']);
    });
  });
}
