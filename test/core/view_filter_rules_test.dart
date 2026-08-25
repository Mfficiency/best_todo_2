import 'package:besttodo/config.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/services/item_views.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    Config.viewFilterRules = {};
  });

  Task tagged(String label) => Task(title: 'x', label: label);

  group('ViewFilterRules view registry', () {
    test('approval is a registered view alongside home and wishlist', () {
      expect(ViewFilterRules.viewIds, contains(ViewFilterRules.approval));
      expect(ViewFilterRules.viewLabels[ViewFilterRules.approval],
          isNotNull);
      expect(ViewFilterRules.viewDescriptions[ViewFilterRules.approval],
          isNotNull);
    });

    test('every view id has a builtInRules entry (possibly empty)', () {
      for (final id in ViewFilterRules.viewIds) {
        expect(ViewFilterRules.builtInRules.containsKey(id), isTrue,
            reason: '$id is missing a builtInRules entry');
      }
    });

    test('home, wishlist, approval and projects describe a built-in rule',
        () {
      for (final id in [
        ViewFilterRules.home,
        ViewFilterRules.wishlist,
        ViewFilterRules.approval,
        ViewFilterRules.projects,
      ]) {
        expect(ViewFilterRules.builtInRules[id], isNotEmpty,
            reason: '$id should describe its always-on business logic');
      }
    });
  });

  group('ViewFilterRules JSON round trip', () {
    test('round-trips exclude and include tags', () {
      final rules = ViewFilterRules(
        excludeTags: ['Waiting_for_approval', 'later'],
        includeTags: ['urgent'],
      );
      final restored = ViewFilterRules.fromJson(rules.toJson());
      expect(restored.excludeTags, rules.excludeTags);
      expect(restored.includeTags, rules.includeTags);
    });

    test('missing keys parse as empty (isEmpty true)', () {
      final restored = ViewFilterRules.fromJson(const {});
      expect(restored.isEmpty, isTrue);
    });
  });

  group('ItemViews.passesFilterRules', () {
    test('null or empty rules pass everything', () {
      final task = tagged('anything');
      expect(ItemViews.passesFilterRules(task, null), isTrue);
      expect(ItemViews.passesFilterRules(task, ViewFilterRules()), isTrue);
    });

    test('excludeTags hides a matching task, case-insensitively', () {
      final rules = ViewFilterRules(excludeTags: ['Waiting_for_approval']);
      expect(
        ItemViews.passesFilterRules(
            tagged('waiting_for_approval, other'), rules),
        isFalse,
      );
      expect(ItemViews.passesFilterRules(tagged('other'), rules), isTrue);
    });

    test('includeTags keeps only a matching task', () {
      final rules = ViewFilterRules(includeTags: ['wishlist']);
      expect(ItemViews.passesFilterRules(tagged('wishlist'), rules), isTrue);
      expect(ItemViews.passesFilterRules(tagged('other'), rules), isFalse);
      expect(ItemViews.passesFilterRules(tagged(''), rules), isFalse);
    });

    test('exclude wins over include when both match', () {
      final rules =
          ViewFilterRules(includeTags: ['a'], excludeTags: ['a']);
      expect(ItemViews.passesFilterRules(tagged('a'), rules), isFalse);
    });
  });

  group('ItemViews.applyFilterRules', () {
    test('returns the same list instance when rules are empty', () {
      final tasks = [tagged('a'), tagged('b')];
      expect(ItemViews.applyFilterRules(tasks, null), same(tasks));
    });

    test('filters out excluded tasks', () {
      final keep = tagged('keep');
      final drop = tagged('drop');
      final result = ItemViews.applyFilterRules(
        [keep, drop],
        ViewFilterRules(excludeTags: ['drop']),
      );
      expect(result, [keep]);
    });
  });

  group('view queries respect configured rules', () {
    test('homeBucket applies rules on top of bucket + search', () {
      final today = DateTime(2024, 1, 10);
      final visible = Task(title: 'Visible', dueDate: today, label: 'ok');
      final hidden =
          Task(title: 'Hidden', dueDate: today, label: 'Waiting_for_approval');
      final result = ItemViews.homeBucket(
        [visible, hidden],
        0,
        today,
        rules: ViewFilterRules(excludeTags: ['Waiting_for_approval']),
      );
      expect(result, [visible]);
    });

    test('wishlist applies rules on top of the isWish flag', () {
      final keep = Task(title: 'keep', isWish: true, label: 'a');
      final drop = Task(title: 'drop', isWish: true, label: 'b');
      final notWish = Task(title: 'not wish', label: 'a');
      final result = ItemViews.wishlist(
        [keep, drop, notWish],
        rules: ViewFilterRules(includeTags: ['a']),
      );
      expect(result, [keep]);
    });

    test('active applies rules on top of deletedAt == null', () {
      final keep = Task(title: 'keep', label: 'ok');
      final dropped = Task(title: 'dropped', label: 'later');
      final deleted =
          Task(title: 'deleted', label: 'ok', deletedAt: DateTime.now());
      final result = ItemViews.active(
        [keep, dropped, deleted],
        rules: ViewFilterRules(excludeTags: ['later']),
      );
      expect(result, [keep]);
    });

    test('projectTasks and boardColumn apply rules', () {
      final keep =
          Task(title: 'keep', projectId: 'p1', label: 'ok');
      final dropped =
          Task(title: 'dropped', projectId: 'p1', label: 'later');
      final rules = ViewFilterRules(excludeTags: ['later']);
      expect(
        ItemViews.projectTasks([keep, dropped], 'p1', rules: rules),
        [keep],
      );
      expect(
        ItemViews.boardColumn([keep, dropped], 'p1', Task.kanbanTodo,
            rules: rules),
        [keep],
      );
    });
  });

  group('Config.viewFilterRules persistence', () {
    test('round-trips through toMap/applyMap', () {
      Config.viewFilterRules = {
        ViewFilterRules.home: ViewFilterRules(excludeTags: ['later']),
        ViewFilterRules.wishlist: ViewFilterRules(includeTags: ['wishlist']),
      };
      final map = Config.toMap();
      Config.viewFilterRules = {};
      Config.applyMap(map);
      expect(Config.viewFilterRules[ViewFilterRules.home]?.excludeTags,
          ['later']);
      expect(Config.viewFilterRules[ViewFilterRules.wishlist]?.includeTags,
          ['wishlist']);
    });

    test('applyMap ignores a missing or malformed key', () {
      Config.viewFilterRules = {
        ViewFilterRules.home: ViewFilterRules(excludeTags: ['later']),
      };
      Config.applyMap(const {'viewFilterRules': 'not a map'});
      expect(Config.viewFilterRules[ViewFilterRules.home]?.excludeTags,
          ['later']);
    });
  });
}
