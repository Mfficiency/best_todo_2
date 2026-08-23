import '../models/task.dart';
import '../utils/date_utils.dart';
import '../utils/label_utils.dart';
import '../utils/task_utils.dart';

/// The views layer: every surface that shows items — home tabs, wishlist,
/// project boards, project cards — is a *query over the one task list*,
/// and this is where those queries live. Pure, synchronous selectors: no
/// I/O, no state, so they cost nothing at startup and can be unit-tested
/// without pumping widgets.
///
/// Membership flags on the task (`isWish`, `projectId`, `kanbanStatus`)
/// remain the stored representation for now (dual-write era); pages just no
/// longer hand-roll the same `where(...)` chains.
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
  static bool _isApproved(Task task) =>
      !hasWaitingApprovalToken(task.label);

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

  /// The tasks of home tab [tabIndex], sorted like the home list (open
  /// first, then by ranking). [where] adds an extra predicate (search).
  static List<Task> homeBucket(
    List<Task> tasks,
    int tabIndex,
    DateTime today, {
    bool Function(Task task)? where,
  }) {
    final list = tasks
        .where((t) =>
            _isApproved(t) &&
            (where == null || where(t)) &&
            inHomeBucket(t, tabIndex, today))
        .toList();
    sortTasks(list);
    return list;
  }

  /// The wishlist: wish-flagged tasks, exactly like opening a project.
  static List<Task> wishlist(List<Task> tasks) =>
      tasks.where((t) => t.isWish && _isApproved(t)).toList();

  /// All non-deleted tasks (the Projects page's top pane).
  static List<Task> active(List<Task> tasks) =>
      tasks.where((t) => t.deletedAt == null && _isApproved(t)).toList();

  /// A project's tasks, regardless of board stage.
  static List<Task> projectTasks(List<Task> tasks, String projectId) => tasks
      .where((t) =>
          t.deletedAt == null && t.projectId == projectId && _isApproved(t))
      .toList();

  /// One Kanban column of a project's board.
  static List<Task> boardColumn(
          List<Task> tasks, String projectId, String stage) =>
      tasks
          .where((t) =>
              t.deletedAt == null &&
              t.projectId == projectId &&
              t.kanbanStatus == stage &&
              _isApproved(t))
          .toList();

  /// Tasks pulled from Todoist that are still waiting for a human decision
  /// (see [waitingApprovalToken]) — the Waiting for Approval page's list.
  static List<Task> waitingApproval(List<Task> tasks) => tasks
      .where((t) => t.deletedAt == null && !_isApproved(t))
      .toList();
}
