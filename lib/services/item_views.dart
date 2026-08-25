import '../models/task.dart';
import '../models/view_filter_rules.dart';
import '../utils/date_utils.dart';
import '../utils/label_utils.dart';
import '../utils/task_utils.dart';

/// The views layer: every surface that shows items — home tabs, wishlist,
/// project boards, project cards — is a *query over the one task list*,
/// and this is where those queries live. Pure, synchronous selectors: no
/// I/O, no state, so they cost nothing at startup and can be unit-tested
/// without pumping widgets.
///
/// Membership flags on the task (`isWish`, `isEatingHabit`, `projectId`,
/// `kanbanStatus`) remain the stored representation for now (dual-write
/// era); pages just no longer hand-roll the same `where(...)` chains.
class ItemViews {
  ItemViews._();

  /// Index of the Future tab, the bucket for undated tasks.
  static const int futureTabIndex = 5;

  /// Sentinel due date meaning "parked in the Future tab" (kept from the
  /// home page's historical convention).
  static final DateTime futureSentinelDate = DateTime(2300, 1, 1);

  static bool isFutureSentinel(DateTime date) =>
      date.year == futureSentinelDate.year &&
      date.month == futureSentinelDate.month &&
      date.day == futureSentinelDate.day;

  /// A task freshly pulled in from Todoist is stamped with
  /// [waitingApprovalToken] and stays out of every other view until a human
  /// approves or denies it in the Waiting for Approval page — see that
  /// token's doc.
  static bool isApproved(Task task) => !hasWaitingApprovalToken(task.label);

  /// Whether [task] belongs to every main view — home tabs, schedule view,
  /// wishlist, projects, the home-screen widget, Todoist sync — as opposed
  /// to being gated into exactly one dedicated tool. Combines the Todoist
  /// approval gate with the Food Diary gate ([Task.isEatingHabit]): a food
  /// diary entry is visible only in the Food Diary tool itself and, once
  /// deleted there, the deleted/archived lists.
  static bool isVisibleInMainViews(Task task) =>
      isApproved(task) && !task.isEatingHabit;

  /// Whether [task] belongs to home tab [tabIndex] relative to [today].
  /// Bucketing is by date-only distance: `<= 0` Today (overdue included),
  /// 1 Tomorrow, 2 Day After, 3–29 Next Week, 30+ Next Month, and the
  /// sentinel or no date at all → Future.
  static bool inHomeBucket(Task task, int tabIndex, DateTime today) {
    final due = task.dueDate;
    if (due == null) return tabIndex == futureTabIndex;
    final diff = dateDiffInDays(due, today);
    final isFuture = isFutureSentinel(due);
    switch (tabIndex) {
      case 0:
        return diff <= 0;
      case 1:
        return diff == 1;
      case 2:
        return diff == 2;
      case 3:
        return diff >= 3 && diff < 30;
      case 4:
        return diff >= 30 && !isFuture;
      default:
        return isFuture;
    }
  }

  /// Whether [task] passes the user-configured [rules] (Settings →
  /// Filtering rules): hidden if it carries any [ViewFilterRules.excludeTags]
  /// token, or — when [ViewFilterRules.includeTags] is non-empty — kept only
  /// if it carries at least one of them. A null or empty [rules] passes
  /// everything.
  static bool passesFilterRules(Task task, ViewFilterRules? rules) {
    if (rules == null || rules.isEmpty) return true;
    final tokens =
        splitLabelTokens(task.label).map((t) => t.toLowerCase()).toSet();
    if (rules.excludeTags.any((t) => tokens.contains(t.toLowerCase()))) {
      return false;
    }
    if (rules.includeTags.isNotEmpty &&
        !rules.includeTags.any((t) => tokens.contains(t.toLowerCase()))) {
      return false;
    }
    return true;
  }

  /// [tasks] narrowed to those passing [passesFilterRules].
  static List<Task> applyFilterRules(List<Task> tasks, ViewFilterRules? rules) {
    if (rules == null || rules.isEmpty) return tasks;
    return tasks.where((t) => passesFilterRules(t, rules)).toList();
  }

  /// The tasks of home tab [tabIndex], sorted like the home list (open
  /// first, then by ranking). [where] adds an extra predicate (search).
  /// [rules] is the configured Home view filter, see [passesFilterRules].
  static List<Task> homeBucket(
    List<Task> tasks,
    int tabIndex,
    DateTime today, {
    bool Function(Task task)? where,
    ViewFilterRules? rules,
  }) {
    final list = tasks
        .where((t) =>
            isVisibleInMainViews(t) &&
            (where == null || where(t)) &&
            inHomeBucket(t, tabIndex, today) &&
            passesFilterRules(t, rules))
        .toList();
    sortTasks(list);
    return list;
  }

  /// The wishlist: wish-flagged tasks, exactly like opening a project.
  static List<Task> wishlist(List<Task> tasks, {ViewFilterRules? rules}) =>
      tasks
          .where((t) =>
              t.isWish &&
              isVisibleInMainViews(t) &&
              passesFilterRules(t, rules))
          .toList();

  /// The Food Diary: eating-habit-flagged tasks, exactly like opening the
  /// wishlist. [isApproved] rather than [isVisibleInMainViews] since the
  /// latter itself excludes eating-habit tasks.
  static List<Task> foodDiary(List<Task> tasks) =>
      tasks.where((t) => t.isEatingHabit && isApproved(t)).toList();

  /// All non-deleted tasks (the Projects page's top pane).
  static List<Task> active(List<Task> tasks, {ViewFilterRules? rules}) =>
      tasks
          .where((t) =>
              t.deletedAt == null &&
              isVisibleInMainViews(t) &&
              passesFilterRules(t, rules))
          .toList();

  /// A project's tasks, regardless of board stage.
  static List<Task> projectTasks(List<Task> tasks, String projectId,
          {ViewFilterRules? rules}) =>
      tasks
          .where((t) =>
              t.deletedAt == null &&
              t.projectId == projectId &&
              isVisibleInMainViews(t) &&
              passesFilterRules(t, rules))
          .toList();

  /// One Kanban column of a project's board.
  static List<Task> boardColumn(
          List<Task> tasks, String projectId, String stage,
          {ViewFilterRules? rules}) =>
      tasks
          .where((t) =>
              t.deletedAt == null &&
              t.projectId == projectId &&
              t.kanbanStatus == stage &&
              isVisibleInMainViews(t) &&
              passesFilterRules(t, rules))
          .toList();

  /// Tasks pulled from Todoist that are still waiting for a human decision
  /// (see [waitingApprovalToken]) — the Waiting for Approval page's list.
  /// [rules] is the configured Waiting for Approval view filter, an extra
  /// layer on top of the structural pending/non-deleted gate, see
  /// [passesFilterRules].
  static List<Task> waitingApproval(List<Task> tasks, {ViewFilterRules? rules}) =>
      tasks
          .where((t) =>
              t.deletedAt == null &&
              !isApproved(t) &&
              passesFilterRules(t, rules))
          .toList();
}
