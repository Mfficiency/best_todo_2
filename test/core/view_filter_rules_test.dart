import 'package:besttodo/config.dart';
import 'package:besttodo/models/label.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/models/view_filter_rules.dart';
import 'package:besttodo/services/item_views.dart';
import 'package:besttodo/utils/label_utils.dart';
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

  group('ViewFilterRules new view ids (fooddiary/research/alarms/countdown)',
      () {
    test('foodDiary, research, alarms and countdown are registered views',
        () {
      for (final id in [
        ViewFilterRules.foodDiary,
        ViewFilterRules.research,
        ViewFilterRules.alarms,
        ViewFilterRules.countdown,
      ]) {
        expect(ViewFilterRules.viewIds, contains(id));
        expect(ViewFilterRules.viewLabels[id], isNotNull);
        expect(ViewFilterRules.viewDescriptions[id], isNotNull);
        expect(ViewFilterRules.builtInRules.containsKey(id), isTrue);
      }
    });

    test('foodDiary and research describe a built-in rule; alarms/countdown '
        'do not (they filter their own item list directly)', () {
      expect(ViewFilterRules.builtInRules[ViewFilterRules.foodDiary],
          isNotEmpty);
      expect(
          ViewFilterRules.builtInRules[ViewFilterRules.research], isNotEmpty);
      expect(ViewFilterRules.builtInRules[ViewFilterRules.alarms], isEmpty);
      expect(
          ViewFilterRules.builtInRules[ViewFilterRules.countdown], isEmpty);
    });
  });

  group('ViewFilterRules.defaultsFor', () {
    test('returns null for an unknown view id', () {
      expect(ViewFilterRules.defaultsFor('not-a-view'), isNull);
    });

    /// Every reserved tag other than [own] — the "hide everything but your
    /// own tag" shape every view (except Home, Archived and the bin) follows.
    List<String> othersThan(String own) => <String>[
          wishToken,
          projectToken,
          archivedToken,
          deletedToken,
          fooddiaryToken,
          researchToken,
          alarmToken,
          countdownToken,
          changelogToken,
          waitingApprovalToken,
        ].where((t) => t != own).toList();

    test('home hides every reserved tag and shows nothing of its own', () {
      final defaults = ViewFilterRules.defaultsFor(ViewFilterRules.home)!;
      expect(
        defaults.excludeTags.toSet(),
        <String>{
          archivedToken,
          deletedToken,
          wishToken,
          waitingApprovalToken,
          fooddiaryToken,
          researchToken,
          alarmToken,
          countdownToken,
          changelogToken,
          projectToken,
        },
      );
      expect(defaults.includeTags, isEmpty);
    });

    test('wishlist hides every other reserved tag and shows only Wish', () {
      final defaults = ViewFilterRules.defaultsFor(ViewFilterRules.wishlist)!;
      expect(defaults.includeTags, [wishToken]);
      expect(defaults.excludeTags.toSet(), othersThan(wishToken).toSet());
    });

    test('approval hides Archived/Deleted/Changelog and shows only '
        'Waiting_for_approval', () {
      final defaults = ViewFilterRules.defaultsFor(ViewFilterRules.approval)!;
      expect(defaults.includeTags, [waitingApprovalToken]);
      expect(defaults.excludeTags,
          [archivedToken, deletedToken, changelogToken]);
    });

    test('projects hides Archived/Deleted/Waiting/Fooddiary/Alarm/Countdown/'
        'Changelog (not Wish) and shows only Project (the literal default; '
        'the assign pane compensates separately, see '
        'ProjectsPage._assignPaneRules)', () {
      final defaults = ViewFilterRules.defaultsFor(ViewFilterRules.projects)!;
      expect(defaults.includeTags, [projectToken]);
      expect(
        defaults.excludeTags.toSet(),
        <String>{
          archivedToken,
          deletedToken,
          waitingApprovalToken,
          fooddiaryToken,
          researchToken,
          alarmToken,
          countdownToken,
          changelogToken,
        },
      );
      expect(defaults.excludeTags, isNot(contains(wishToken)));
    });

    test('foodDiary hides every other reserved tag and shows only '
        'Fooddiary', () {
      final defaults =
          ViewFilterRules.defaultsFor(ViewFilterRules.foodDiary)!;
      expect(defaults.includeTags, [fooddiaryToken]);
      expect(
          defaults.excludeTags.toSet(), othersThan(fooddiaryToken).toSet());
    });

    test('research hides every other reserved tag and shows only '
        'Research', () {
      final defaults = ViewFilterRules.defaultsFor(ViewFilterRules.research)!;
      expect(defaults.includeTags, [researchToken]);
      expect(defaults.excludeTags.toSet(), othersThan(researchToken).toSet());
    });

    test('alarms hides every other reserved tag and shows only Alarm', () {
      final defaults = ViewFilterRules.defaultsFor(ViewFilterRules.alarms)!;
      expect(defaults.includeTags, [alarmToken]);
      expect(defaults.excludeTags.toSet(), othersThan(alarmToken).toSet());
    });

    test('countdown hides every other reserved tag and shows only '
        'Countdown', () {
      final defaults = ViewFilterRules.defaultsFor(ViewFilterRules.countdown)!;
      expect(defaults.includeTags, [countdownToken]);
      expect(
          defaults.excludeTags.toSet(), othersThan(countdownToken).toSet());
    });

    test('archived and bin only hide each other, matching the drawer split',
        () {
      final archived = ViewFilterRules.defaultsFor(ViewFilterRules.archived)!;
      expect(archived.excludeTags, [deletedToken]);
      expect(archived.includeTags, [archivedToken]);

      final bin = ViewFilterRules.defaultsFor(ViewFilterRules.bin)!;
      expect(bin.excludeTags, [archivedToken]);
      expect(bin.includeTags, [deletedToken]);
    });
  });

  group('protected state tokens', () {
    test('every reserved token classifies as a system label', () {
      for (final token in protectedStateTokens) {
        expect(labelKindFor(token), Label.kindSystem,
            reason: '$token should be a protected/system tag');
      }
    });

    test('isProtectedToken matches case-insensitively', () {
      expect(isProtectedToken('wish'), isTrue);
      expect(isProtectedToken('WISH'), isTrue);
      expect(isProtectedToken('project'), isTrue);
      expect(isProtectedToken('archived'), isTrue);
      expect(isProtectedToken('deleted'), isTrue);
      expect(isProtectedToken('fooddiary'), isTrue);
      expect(isProtectedToken('research'), isTrue);
      expect(isProtectedToken('alarm'), isTrue);
      expect(isProtectedToken('countdown'), isTrue);
      expect(isProtectedToken('waiting_for_approval'), isTrue);
      expect(isProtectedToken('waiting-for-approval'), isTrue);
      expect(isProtectedToken('urgent'), isFalse);
      expect(isProtectedToken(''), isFalse);
    });
  });

  group('ItemViews.stateTags', () {
    test('surfaces Wish, Fooddiary, Project and Waiting_for_approval', () {
      final task = Task(
        title: 'x',
        isWish: true,
        isEatingHabit: true,
        projectId: 'p1',
        label: waitingApprovalToken,
      );
      expect(
        ItemViews.stateTags(task),
        {wishToken, fooddiaryToken, projectToken, waitingApprovalToken},
      );
    });

    test('surfaces Research', () {
      final task = Task(title: 'x', isResearch: true);
      expect(ItemViews.stateTags(task), {researchToken});
    });

    test('archived/binned are supplied by the caller, not derived from the '
        'task itself', () {
      final task = Task(title: 'x');
      expect(ItemViews.stateTags(task), isEmpty);
      expect(ItemViews.stateTags(task, archived: true), {archivedToken});
      expect(ItemViews.stateTags(task, binned: true), {deletedToken});
    });
  });

  group('ItemViews.passesFilterRules matches synthetic state tags', () {
    test('excludeTags: Wish hides a wish task with no literal "Wish" label',
        () {
      final wish = Task(title: 'x', isWish: true, label: 'other');
      final rules = ViewFilterRules(excludeTags: [wishToken]);
      expect(ItemViews.passesFilterRules(wish, rules), isFalse);
    });

    test('includeTags: Project keeps only project-assigned tasks', () {
      final assigned = Task(title: 'x', projectId: 'p1');
      final unassigned = Task(title: 'y');
      final rules = ViewFilterRules(includeTags: [projectToken]);
      expect(ItemViews.passesFilterRules(assigned, rules), isTrue);
      expect(ItemViews.passesFilterRules(unassigned, rules), isFalse);
    });

    test('archived/binned flags gate the Archived/Deleted synthetic tags',
        () {
      final task = Task(title: 'x');
      final hideArchived = ViewFilterRules(excludeTags: [archivedToken]);
      expect(ItemViews.passesFilterRules(task, hideArchived), isTrue);
      expect(
          ItemViews.passesFilterRules(task, hideArchived, archived: true),
          isFalse);

      final hideDeleted = ViewFilterRules(excludeTags: [deletedToken]);
      expect(ItemViews.passesFilterRules(task, hideDeleted, archived: true),
          isTrue);
      expect(
          ItemViews.passesFilterRules(task, hideDeleted, binned: true),
          isFalse);
    });
  });

  group('ItemViews.passesTagRules / applyTagRules (non-Task tag strings)',
      () {
    test('passesTagRules matches a raw comma-separated tag string', () {
      final rules = ViewFilterRules(excludeTags: ['work']);
      expect(ItemViews.passesTagRules('work, urgent', rules), isFalse);
      expect(ItemViews.passesTagRules('urgent', rules), isTrue);
      expect(ItemViews.passesTagRules('', rules), isTrue);
    });

    test('applyTagRules filters a list of non-Task items by their own tag '
        'string', () {
      final items = ['work', 'home', 'work, urgent'];
      final rules = ViewFilterRules(excludeTags: ['work']);
      final result = ItemViews.applyTagRules(items, rules, (s) => s);
      expect(result, ['home']);
    });

    test('applyTagRules returns the same list instance when rules are empty',
        () {
      final items = ['a', 'b'];
      expect(ItemViews.applyTagRules(items, null, (s) => s), same(items));
    });
  });

  group('ItemViews.foodDiary respects rules', () {
    test('rules narrow the food diary entries on top of isEatingHabit', () {
      final keep =
          Task(title: 'keep', isEatingHabit: true, label: 'breakfast');
      final drop = Task(title: 'drop', isEatingHabit: true, label: 'dinner');
      final notEating = Task(title: 'not eating', label: 'breakfast');
      final result = ItemViews.foodDiary(
        [keep, drop, notEating],
        rules: ViewFilterRules(includeTags: ['breakfast']),
      );
      expect(result, [keep]);
    });
  });

  group('ItemViews.research respects rules', () {
    test('rules narrow the research items on top of isResearch', () {
      final keep = Task(title: 'keep', isResearch: true, label: 'papers');
      final drop = Task(title: 'drop', isResearch: true, label: 'links');
      final notResearch = Task(title: 'not research', label: 'papers');
      final result = ItemViews.research(
        [keep, drop, notResearch],
        rules: ViewFilterRules(includeTags: ['papers']),
      );
      expect(result, [keep]);
    });

    test('isVisibleInMainViews excludes research items, like food diary '
        'entries', () {
      final task = Task(title: 'x', isResearch: true);
      expect(ItemViews.isVisibleInMainViews(task), isFalse);
    });
  });

  group('Config.seedViewFilterRuleDefaultsIfNeeded', () {
    tearDown(() {
      Config.viewFilterRules = {};
      Config.viewFilterRulesSeedVersion = 0;
    });

    test('first run (version 0) fills every view with no entry from '
        'defaultsFor', () {
      Config.viewFilterRules = {};
      Config.viewFilterRulesSeedVersion = 0;
      Config.seedViewFilterRuleDefaultsIfNeeded();
      expect(Config.viewFilterRulesSeedVersion, 3);
      expect(Config.viewFilterRules[ViewFilterRules.wishlist]?.includeTags,
          [wishToken]);
      // Every view id now has a seeded default, including Alarms/Countdown.
      expect(Config.viewFilterRules[ViewFilterRules.alarms]?.includeTags,
          [alarmToken]);
      expect(Config.viewFilterRules[ViewFilterRules.countdown]?.includeTags,
          [countdownToken]);
      expect(Config.viewFilterRules[ViewFilterRules.research]?.includeTags,
          [researchToken]);
    });

    test('first run never overwrites a rule the user already configured, '
        'even an intentionally empty one', () {
      Config.viewFilterRules = {
        ViewFilterRules.home: ViewFilterRules(excludeTags: ['mine']),
        ViewFilterRules.wishlist: ViewFilterRules(),
      };
      Config.viewFilterRulesSeedVersion = 0;
      Config.seedViewFilterRuleDefaultsIfNeeded();
      expect(Config.viewFilterRules[ViewFilterRules.home]?.excludeTags,
          ['mine']);
      expect(Config.viewFilterRules[ViewFilterRules.wishlist]?.isEmpty,
          isTrue);
    });

    test('is a no-op once already at the current version', () {
      Config.viewFilterRules = {};
      Config.viewFilterRulesSeedVersion = 3;
      Config.seedViewFilterRuleDefaultsIfNeeded();
      expect(Config.viewFilterRules, isEmpty);
    });

    test('a template-version bump (e.g. from the fixed version 1 template) '
        're-syncs every view to the current defaultsFor, overwriting what '
        'the earlier template had seeded', () {
      Config.viewFilterRules = {
        // What the incorrect version-1 template used to seed for Home.
        ViewFilterRules.home: ViewFilterRules(excludeTags: [
          archivedToken,
          deletedToken,
          waitingApprovalToken,
          fooddiaryToken,
        ]),
      };
      Config.viewFilterRulesSeedVersion = 1;
      Config.seedViewFilterRuleDefaultsIfNeeded();
      expect(Config.viewFilterRulesSeedVersion, 3);
      expect(
        Config.viewFilterRules[ViewFilterRules.home]?.excludeTags,
        ViewFilterRules.defaultsFor(ViewFilterRules.home)!.excludeTags,
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
