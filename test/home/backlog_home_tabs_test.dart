import 'package:besttodo/models/home_contexts.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/item_views.dart';
import 'package:besttodo/utils/label_utils.dart';
import 'package:besttodo/utils/voice_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

/// With the drawer's Backlog toggle on, wishes sit in the home tabs by their
/// backlog state (Active → Today, Next → Next Week, Someday → Future), not by
/// due date; with it off they keep going by date.
void main() {
  final today = DateTime(2026, 10, 28);
  const backlogOn = HomeContexts(backlog: true);
  const backlogOff = HomeContexts();

  Task wish(String title, String state, {DateTime? due}) {
    final t = Task(title: title, isWish: true, dueDate: due);
    setBacklogState(t, state);
    return t;
  }

  List<String> titlesIn(List<Task> tasks, int tab, HomeContexts? contexts) =>
      ItemViews.homeBucket(tasks, tab, today, contexts: contexts)
          .map((t) => t.title)
          .toList();

  group('backlogTabIndex', () {
    test('maps Active/Next/Someday to Today/Next Week/Future', () {
      final due = today.add(const Duration(days: 40));
      expect(ItemViews.backlogTabIndex(
              wish('a', BacklogStates.active, due: due), backlogOn),
          0);
      expect(
          ItemViews.backlogTabIndex(
              wish('n', BacklogStates.next, due: today), backlogOn),
          3);
      expect(
          ItemViews.backlogTabIndex(
              wish('s', BacklogStates.someday, due: today), backlogOn),
          ItemViews.futureTabIndex);
    });

    test('is null with the toggle off, without contexts, or for non-wishes',
        () {
      final w = wish('a', BacklogStates.active);
      expect(ItemViews.backlogTabIndex(w, backlogOff), isNull);
      expect(ItemViews.backlogTabIndex(w, null), isNull);
      expect(
          ItemViews.backlogTabIndex(
              Task(title: 'todo', label: releaseNextToken), backlogOn),
          isNull);
    });
  });

  test('backlogStateForTab is the inverse mapping', () {
    expect(ItemViews.backlogStateForTab(0), BacklogStates.active);
    for (final tab in [1, 2, 3]) {
      expect(ItemViews.backlogStateForTab(tab), BacklogStates.next);
    }
    for (final tab in [4, 5]) {
      expect(ItemViews.backlogStateForTab(tab), BacklogStates.someday);
    }
    for (final state in BacklogStates.all) {
      final w = wish('w', state);
      final tab = ItemViews.backlogTabIndex(w, backlogOn)!;
      expect(ItemViews.backlogStateForTab(tab), state);
    }
  });

  group('homeBucket', () {
    final tasks = [
      Task(title: 'todo today', dueDate: today),
      Task(title: 'todo next week', dueDate: today.add(const Duration(days: 5))),
      // Due dates deliberately disagree with the state.
      wish('active wish', BacklogStates.active,
          due: today.add(const Duration(days: 40))),
      wish('next wish', BacklogStates.next, due: today),
      wish('someday wish', BacklogStates.someday,
          due: today.add(const Duration(days: 1))),
    ];

    test('toggle on: wishes go by state, todos by date', () {
      expect(titlesIn(tasks, 0, backlogOn),
          unorderedEquals(['todo today', 'active wish']));
      expect(titlesIn(tasks, 1, backlogOn), isEmpty);
      expect(titlesIn(tasks, 3, backlogOn),
          unorderedEquals(['todo next week', 'next wish']));
      expect(titlesIn(tasks, 4, backlogOn), isEmpty);
      expect(titlesIn(tasks, ItemViews.futureTabIndex, backlogOn),
          ['someday wish']);
    });

    test('toggle off (or no contexts): every task goes by date', () {
      for (final contexts in [backlogOff, null]) {
        expect(titlesIn(tasks, 0, contexts),
            unorderedEquals(['todo today', 'next wish']));
        expect(titlesIn(tasks, 1, contexts), ['someday wish']);
        expect(titlesIn(tasks, 3, contexts), ['todo next week']);
        expect(titlesIn(tasks, 4, contexts), ['active wish']);
        expect(titlesIn(tasks, ItemViews.futureTabIndex, contexts), isEmpty);
      }
    });

    test('each wish lands in exactly one tab', () {
      for (final w in tasks.where((t) => t.isWish)) {
        final tabs = [
          for (var tab = 0; tab <= ItemViews.futureTabIndex; tab++)
            if (titlesIn(tasks, tab, backlogOn).contains(w.title)) tab
        ];
        expect(tabs, hasLength(1), reason: w.title);
      }
    });
  });
}
