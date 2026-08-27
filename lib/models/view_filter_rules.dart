import '../utils/label_utils.dart';

/// A user-configured tag filter for one view (Settings → Filtering rules).
///
/// Tasks whose [Task.label] carries any token in [excludeTags] are hidden;
/// when [includeTags] is non-empty, only tasks carrying at least one of
/// those tokens are shown. Matching is case-insensitive and token-based (see
/// `splitLabelTokens`), and reaches beyond the literal label string to a
/// task's synthetic state tags too (Wish, Project, Archived, Deleted, ... —
/// see `ItemViews.stateTags`), so a rule can reference "Wish" even though no
/// task ever literally carries that word in its label. This sits on top of a
/// view's own structural filter (e.g. the wishlist still only ever shows
/// [Task.isWish] items) — it is an extra, optional layer the user configures
/// per view.
class ViewFilterRules {
  /// View ids this feature covers today; keep these stable, they are the
  /// persisted map keys (`Config.viewFilterRules`).
  static const String home = 'home';
  static const String wishlist = 'wishlist';
  static const String approval = 'approval';
  static const String projects = 'projects';
  static const String foodDiary = 'fooddiary';
  static const String alarms = 'alarms';
  static const String countdown = 'countdown';
  static const String archived = 'archived';
  static const String bin = 'bin';

  static const List<String> viewIds = [
    home,
    wishlist,
    approval,
    projects,
    foodDiary,
    alarms,
    countdown,
    archived,
    bin,
  ];

  static const Map<String, String> viewLabels = {
    home: 'Home',
    wishlist: 'Wishlist',
    approval: 'Waiting for Approval',
    projects: 'Projects',
    foodDiary: 'Food Diary',
    alarms: 'Alarms',
    countdown: 'Countdown',
    archived: 'Archived items',
    bin: 'Deleted bin',
  };

  static const Map<String, String> viewDescriptions = {
    home: 'The Today / Tomorrow / ... tabs on the home screen',
    wishlist: 'Tools → Wishlist',
    approval: 'Tools → Waiting for Approval',
    projects: 'Tools → Projects, including every project board',
    foodDiary: 'Tools → Food Diary',
    alarms: 'Alarms, filtered by the tags set on each alarm',
    countdown: 'Countdown, filtered by the tags set on each timer',
    archived: 'Archived Items (the drawer entry)',
    bin: 'The real Deleted bin, opened from Archived Items',
  };

  /// Read-only summary of the business logic each view already enforces on
  /// its own, regardless of anything configured below — shown above the
  /// editable chip rows so the "built in" exclusions this view lives by
  /// (asked for directly: "the home view doesn't have anything that's not
  /// approved, deleted, or archived") are visible, not just implied. Empty
  /// for [archived]/[bin]/[alarms]/[countdown]: all four take an item list
  /// handed to them directly, not one of the structural gates below.
  static const Map<String, String> builtInRules = {
    home: 'Always excludes Waiting for Approval, Archived, and Deleted '
        'items — enforced regardless of the rule below.',
    wishlist: 'Always shows Wish items only, and always excludes Waiting '
        'for Approval, Archived, and Deleted — enforced regardless of the '
        'rule below.',
    approval: 'Always shows only items still tagged Waiting for Approval, '
        'and never a deleted one — enforced regardless of the rule below.',
    projects: 'Always excludes Archived and Deleted items, and anything '
        'still Waiting for Approval — enforced regardless of the rule '
        'below.',
    foodDiary: 'Always shows Food Diary entries only, and always excludes '
        'Waiting for Approval — enforced regardless of the rule below.',
    alarms: '',
    countdown: '',
    archived: '',
    bin: '',
  };

  /// Sensible starting rules for a fresh install (Settings → Filtering
  /// rules), seeded once by `Config.seedViewFilterRuleDefaultsIfNeeded`.
  /// Only fills gaps that never contradict a view's own documented,
  /// already-working overlap — e.g. Home deliberately still shows a
  /// project's or wishlist's tasks by due date (see `Task.isWish`,
  /// `task_tile.dart`'s project chip), and the Projects page's top pane must
  /// keep showing unassigned tasks to drag onto a project — so this never
  /// defaults `excludeTags`/`includeTags` to something that would hide
  /// those. Every entry here is otherwise redundant with a structural gate
  /// the view already enforces (see [builtInRules]), so seeding it changes
  /// nothing visible; it only makes the tag *nameable* once a rule engine
  /// exists to match it (see `ItemViews.stateTags`). Returns null for a view
  /// with no seeded default.
  static ViewFilterRules? defaultsFor(String viewId) {
    switch (viewId) {
      case home:
        return ViewFilterRules(excludeTags: [
          archivedToken,
          deletedToken,
          waitingApprovalToken,
          fooddiaryToken,
        ]);
      case wishlist:
        return ViewFilterRules(
          excludeTags: [
            archivedToken,
            deletedToken,
            waitingApprovalToken,
            fooddiaryToken,
            alarmToken,
            countdownToken,
          ],
          includeTags: [wishToken],
        );
      case approval:
        return ViewFilterRules(
          excludeTags: [archivedToken, deletedToken],
          includeTags: [waitingApprovalToken],
        );
      case projects:
        return ViewFilterRules(excludeTags: [
          archivedToken,
          deletedToken,
          waitingApprovalToken,
          fooddiaryToken,
        ]);
      case foodDiary:
        return ViewFilterRules(
          excludeTags: [
            archivedToken,
            deletedToken,
            waitingApprovalToken,
          ],
          includeTags: [fooddiaryToken],
        );
      case archived:
        return ViewFilterRules(
          excludeTags: [deletedToken],
          includeTags: [archivedToken],
        );
      case bin:
        return ViewFilterRules(
          excludeTags: [archivedToken],
          includeTags: [deletedToken],
        );
      default:
        return null;
    }
  }

  List<String> excludeTags;
  List<String> includeTags;

  ViewFilterRules({List<String>? excludeTags, List<String>? includeTags})
      : excludeTags = excludeTags ?? <String>[],
        includeTags = includeTags ?? <String>[];

  bool get isEmpty => excludeTags.isEmpty && includeTags.isEmpty;

  factory ViewFilterRules.fromJson(Map<String, dynamic> json) =>
      ViewFilterRules(
        excludeTags: (json['excludeTags'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        includeTags: (json['includeTags'] as List?)
            ?.map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'excludeTags': excludeTags,
        'includeTags': includeTags,
      };
}
