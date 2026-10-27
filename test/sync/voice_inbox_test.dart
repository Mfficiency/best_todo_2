import 'package:besttodo/models/home_contexts.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/grocery_category_service.dart';
import 'package:besttodo/services/item_views.dart';
import 'package:besttodo/utils/label_utils.dart';
import 'package:besttodo/utils/voice_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseVoiceMarkers', () {
    test('reads leading markers in any order and strips them', () {
      final (visible, m) = parseVoiceMarkers(
          '[Group: Research]\n[Source: Walk]\n[Suggest: active]\nThe real text');
      expect(visible, 'The real text');
      expect(m.group, 'Research');
      expect(m.source, 'Walk');
      expect(m.suggest, 'active');
    });

    test('keeps the old same-line [Source:] form working', () {
      final (visible, m) = parseVoiceMarkers('[Source: Trip] Book flights');
      expect(visible, 'Book flights');
      expect(m.source, 'Trip');
    });

    test('finds a marker on its own line anywhere, e.g. an appended '
        '[Obsidian:] link', () {
      final (visible, m) =
          parseVoiceMarkers('Some notes\n\n[Obsidian: obsidian://open?x]\n');
      expect(visible, 'Some notes');
      expect(m.obsidian, 'obsidian://open?x');
    });

    test('leaves text without markers untouched', () {
      final (visible, m) = parseVoiceMarkers('  plain [not a marker] text');
      expect(visible, '  plain [not a marker] text');
      expect(m.isEmpty, isTrue);
    });

    test('a blank value counts as absent', () {
      final (_, m) = parseVoiceMarkers('[Group: ]\nx');
      expect(m.group, isNull);
    });
  });

  group('ApprovalGroups', () {
    test('normalizes aliases and falls back to Other', () {
      expect(ApprovalGroups.normalize('MLR'), ApprovalGroups.migros);
      expect(ApprovalGroups.normalize('Food diary'), ApprovalGroups.food);
      expect(ApprovalGroups.normalize('grocery'), ApprovalGroups.groceries);
      expect(ApprovalGroups.normalize('wishlist'), ApprovalGroups.backlog);
      expect(ApprovalGroups.normalize('whatever'), ApprovalGroups.other);
      expect(ApprovalGroups.of(null), ApprovalGroups.other);
    });

    test('suggestions map onto tabs and states', () {
      expect(suggestedTabIndex('Tomorrow'), 1);
      expect(suggestedTabIndex('day after tomorrow'), 2);
      expect(suggestedTabIndex('next'), isNull);
      expect(suggestedState('Next'), BacklogStates.next);
      expect(suggestedState('archive'), BacklogStates.someday);
      expect(suggestedState('tomorrow'), isNull);
    });
  });

  group('backlog states', () {
    test('are stored as the release tokens, other labels kept', () {
      final task = Task(title: 'x', label: 'gift');
      expect(backlogStateOf(task), BacklogStates.someday);
      setBacklogState(task, BacklogStates.active);
      expect(task.label, 'gift, release-next');
      expect(backlogStateOf(task), BacklogStates.active);
      setBacklogState(task, BacklogStates.next);
      expect(task.label, 'gift, release-soon');
      setBacklogState(task, BacklogStates.someday);
      expect(task.label, 'gift');
    });
  });

  group('HomeContexts', () {
    final today = DateTime.now();
    final regular = Task(title: 'regular', dueDate: today);
    final mlr = Task(title: 'mlr', label: worklistToken, dueDate: today);
    final lemmon = Task(title: 'lemmon', label: lemmonToken, dueDate: today);
    final all = [regular, mlr, lemmon];

    List<String> shown(HomeContexts? contexts) => ItemViews.homeBucket(
          all,
          0,
          today,
          contexts: contexts,
        ).map((t) => t.title).toList();

    test('the defaults show regular items only, like before the toggles', () {
      expect(shown(HomeContexts.defaults), ['regular']);
      expect(shown(null), ['regular']);
    });

    test('each toggle shows its context, alone or combined', () {
      expect(shown(const HomeContexts(todo: false, mlr: true)), ['mlr']);
      expect(shown(const HomeContexts(todo: false, lemmon: true)), ['lemmon']);
      expect(
          shown(const HomeContexts(todo: true, mlr: true, lemmon: true))
            ..sort(),
          ['lemmon', 'mlr', 'regular']);
      expect(shown(const HomeContexts(todo: false)), isEmpty);
    });

    test('Lemmon items stay out of the other main views', () {
      expect(ItemViews.isVisibleInMainViews(lemmon), isFalse);
      expect(ItemViews.isVisibleInMainViews(lemmon, includeLemmonItems: true),
          isTrue);
      expect(ItemViews.isVisibleInMainViews(lemmon, includeWorklistItems: true),
          isTrue);
    });

    test('round-trips through JSON', () {
      const c = HomeContexts(todo: false, mlr: true, lemmon: true);
      expect(HomeContexts.fromJson(c.toJson()), c);
      expect(HomeContexts.fromJson(const {}), HomeContexts.defaults);
    });
  });

  group('groceries', () {
    test('grocery items are gated out of every main view', () {
      final item = Task(title: 'Milk', isGrocery: true);
      expect(ItemViews.isVisibleInMainViews(item), isFalse);
      expect(ItemViews.groceries([item]).single, same(item));
      expect(ItemViews.homeVisible([item]), isEmpty);
    });

    test('adding an item already on the list unchecks it instead', () {
      final milk = Task(
          title: 'Milk',
          isGrocery: true,
          isDone: true,
          groceryCategory: 'Dairy & eggs');
      final tasks = [milk];
      final again = Task(title: ' milk ');
      final kept = GroceryList.add(tasks, again);
      expect(kept, same(milk));
      expect(milk.isDone, isFalse);
      expect(again.isGrocery, isFalse);
    });

    test('a new item takes the given category, else the remembered one', () {
      final tasks = <Task>[];
      final bread = GroceryList.add(tasks, Task(title: 'Bread'),
          category: 'Bread & bakery');
      expect(bread.isGrocery, isTrue);
      expect(bread.groceryCategory, 'Bread & bakery');
    });

    test('categories normalize: trimmed, deduplicated, Other last', () {
      expect(
        GroceryCategoryService.normalize([' Dairy ', 'Other', 'dairy', '', 'Fruit']),
        ['Dairy', 'Fruit', 'Other'],
      );
    });

    test('an unknown or missing category resolves to Other', () {
      final service = GroceryCategoryService.instance..resetForTest();
      expect(service.resolve('dairy & EGGS'), 'Dairy & eggs');
      expect(service.resolve('Spaceships'), 'Other');
      expect(service.resolve(null), 'Other');
    });
  });
}
