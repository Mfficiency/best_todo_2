import 'package:besttodo/models/home_contexts.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/item_views.dart';
import 'package:besttodo/utils/voice_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

/// Backlog items (wishes) in the home tabs go by due date like any task.
/// Moving one to Next Week also makes it Next, to Next Month or Future makes
/// it Someday; nearer moves leave its state alone.
void main() {
  final today = DateTime(2026, 10, 29);
  const backlogOn = HomeContexts(backlog: true);

  Task wish(String title, String state, {DateTime? due}) {
    final t = Task(title: title, isWish: true, dueDate: due);
    setBacklogState(t, state);
    return t;
  }

  test('backlogStateForTab: only Next Week and further change the state', () {
    for (final tab in [0, 1, 2]) {
      expect(ItemViews.backlogStateForTab(tab), isNull);
    }
    expect(ItemViews.backlogStateForTab(3), BacklogStates.next);
    expect(ItemViews.backlogStateForTab(4), BacklogStates.someday);
    expect(ItemViews.backlogStateForTab(ItemViews.futureTabIndex),
        BacklogStates.someday);
  });

  group('syncBacklogStateToDueDate', () {
    test('a near move keeps the state', () {
      for (final days in [0, 1, 2]) {
        final w = wish('w', BacklogStates.active,
            due: today.add(Duration(days: days)));
        expect(ItemViews.syncBacklogStateToDueDate(w, today), isNull);
        expect(backlogStateOf(w), BacklogStates.active);
      }
    });

    test('Next Week → Next', () {
      final w = wish('w', BacklogStates.active,
          due: today.add(const Duration(days: 5)));
      expect(ItemViews.syncBacklogStateToDueDate(w, today), BacklogStates.next);
      expect(backlogStateOf(w), BacklogStates.next);
    });

    test('Next Month and Future → Someday', () {
      for (final due in [
        today.add(const Duration(days: 40)),
        ItemViews.futureSentinelDate,
        null,
      ]) {
        final w = wish('w', BacklogStates.next, due: due);
        expect(ItemViews.syncBacklogStateToDueDate(w, today),
            BacklogStates.someday);
        expect(backlogStateOf(w), BacklogStates.someday);
      }
    });

    test('already in that state, or not a wish: nothing changes', () {
      final w = wish('w', BacklogStates.next,
          due: today.add(const Duration(days: 5)));
      expect(ItemViews.syncBacklogStateToDueDate(w, today), isNull);
      final todo = Task(title: 't', dueDate: today.add(const Duration(days: 40)));
      expect(ItemViews.syncBacklogStateToDueDate(todo, today), isNull);
      expect(todo.label, isEmpty);
    });
  });

  test('homeBucket places wishes by due date, whatever their state', () {
    final tasks = [
      wish('active, due in 40 days', BacklogStates.active,
          due: today.add(const Duration(days: 40))),
      wish('someday, due tomorrow', BacklogStates.someday,
          due: today.add(const Duration(days: 1))),
      wish('next, due today', BacklogStates.next, due: today),
    ];
    List<String> titlesIn(int tab) =>
        ItemViews.homeBucket(tasks, tab, today, contexts: backlogOn)
            .map((t) => t.title)
            .toList();
    expect(titlesIn(0), ['next, due today']);
    expect(titlesIn(1), ['someday, due tomorrow']);
    expect(titlesIn(4), ['active, due in 40 days']);
  });
}
