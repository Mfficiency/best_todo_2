import '../models/task.dart';
import '../utils/label_utils.dart';

/// One-time import of the historical `Todo.md` backlog into the wishlist.
///
/// The repo's `Todo.md` predates the Wishlist tool; its still-open ideas
/// (the "After MVP → TODO" and "Later" sections, verbatim including typos)
/// are baked in here so every install can migrate them into
/// `wishlist.json` exactly once. Items already finished (the DONE
/// sections) are intentionally not imported.
class LegacyTodoItem {
  /// Stable identity of this backlog entry, used verbatim as the imported
  /// [Task.uid]. Hand-assigned and permanent: the shipped-wish registry in
  /// `wishlist_shipped.dart` references these ids to auto-complete an item
  /// once its feature is actually built, so renaming or reusing one silently
  /// retargets that automation. Never change or recycle an id — retire it.
  final String uid;
  final String title;
  final String description;

  const LegacyTodoItem(this.uid, this.title, [this.description = '']);
}

/// Label given to every imported item so old backlog entries are
/// recognizable in the wishlist.
const String legacyTodoImportLabel = 'old';

/// Prefix every stable backlog id carries.
const String legacyTodoUidPrefix = 'wish-';

/// Lowercases and collapses whitespace so "Calendar view" and
/// "calendar  view" count as the same wishlist entry when deduplicating.
String normalizeWishlistTitle(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

const List<LegacyTodoItem> legacyTodoWishlistItems = <LegacyTodoItem>[
  // Todo.md — "After MVP" → TODO
  LegacyTodoItem('wish-sms-recipient-toggle',
      'add a setting to enable or disable people you are sending it to, so you dont just have to delete there number'),
  LegacyTodoItem('wish-full-testing-suite',
      'full testing suite, only merge if all test are complete'),
  LegacyTodoItem('wish-calendar-view', 'calendar view'),
  LegacyTodoItem('wish-github-manual-apk-build',
      'build on github: have a manual action to build the apk on github so i can work remotely'),
  LegacyTodoItem('wish-ios-mode', 'ios mode'),
  LegacyTodoItem('wish-sms-task-list-reply',
      'receiving sms to send you back the task list, so if my friend sends me : "tasks" it automatically sends back todays tasks'),
  LegacyTodoItem('wish-send-emails', 'send emails'),
  LegacyTodoItem('wish-send-in-app', 'send in app to each other'),
  LegacyTodoItem('wish-swipe-settings',
      'add more settings to controll the days of the week on the swiping motion and different icons and the cancel color etc'),
  LegacyTodoItem('wish-search-dates',
      'search function should also be able to show when you type a date and it should show items from the dates around it as well, it should prioritize the tiltel but also look in the description'),
  LegacyTodoItem(
    'wish-countdown-when-is',
    'have extra function for the countdown timer "when is"',
    'this will show you the closest round numbers, when they fall and the option to send you a reminder',
  ),
  LegacyTodoItem(
    'wish-chronize-tool',
    'add another tool just as a test the "chronize" tool',
    'it list all the tasks from the task list but on a 24hr calendar view and on the right hand side you have 3 sliders, one for the hour, day and month, so you can scroll the list for fine detail, hour roller for going 3 days in one top to bottom scroll, 15 days in a top to bottom scroll and 12 months in a top to bottom scroll.',
  ),
  LegacyTodoItem(
      'wish-google-calendar-sync', 'add a sync function with google calendars'),
  LegacyTodoItem('wish-timer-filters',
      'add clever filter functions to sort and filter all the timers and events'),
  LegacyTodoItem('wish-week-numbers',
      'add optional week numbers to the date selectors everythere'),
  LegacyTodoItem('wish-completed-task-behavior',
      'Completed task behavior: Auto-hide completed tasks after X time, or show them grouped at bottom.'),
  LegacyTodoItem('wish-auto-delete-completed',
      'Auto-delete completed tasks: Optional cleanup rule (e.g., after 7/30 days).'),
  LegacyTodoItem('wish-default-due-bucket',
      'Default due bucket: When creating a task quickly, choose default target list (Today vs Future).'),
  LegacyTodoItem('wish-confirmation-toggles',
      'Confirmation toggles: Per-action confirmations: delete, clear completed, move all.'),
  LegacyTodoItem('wish-sort-mode-per-list',
      'Sort mode per list: Manual only vs by created time / priority / due date.'),
  LegacyTodoItem('wish-settings-onepager',
      'Settings onepager, click on top tabs to scroll down'),
  LegacyTodoItem('wish-screenshot-integration-tests',
      'improve integration test with screenshots'),
  LegacyTodoItem('wish-improve-recurring-tasks', 'improve recurring tasks'),
  LegacyTodoItem('wish-home-in-menu', 'add home to menu'),
  LegacyTodoItem('wish-start-screen-data-choice',
      'on the start screen, have 3 buttons, populate with example data or start fresh or import previous data'),
  LegacyTodoItem('wish-ci-automatic-test',
      '1 working automatic test when building or pushing'),
  LegacyTodoItem('wish-simplified-mode', 'add a simplified mode'),
  LegacyTodoItem(
      'wish-delete-all-with-selection', 'delete all, select before delete'),
  LegacyTodoItem('wish-quick-item-reminder',
      'have a way to sent a notification about that item in 5- 20 or 60 minutes'),
  LegacyTodoItem('wish-extra-productivity-stats',
      'extra stats, when is the most productive day. When is the most productive time? When is the time where I plan the most? Which day do I postpone the most? All those kinds of variants'),
  LegacyTodoItem('wish-advanced-mode-switch',
      'add an advanced mode switch in the menu that hides a lot of the settings for the non-advanced users.'),
  LegacyTodoItem('wish-progress-bar-thresholds',
      'settings for green progress bar to be green when 3 or less tasks are left, orange when 4 tasks are left and red when 5 or more tasks are left. to change the colors and the thresholds.'),
  LegacyTodoItem('wish-bigger-icons', 'Make icons even bigger?'),
  LegacyTodoItem('wish-daily-stats-future-color',
      'show in daily stats a different color if you have cleared tasks from a future date.'),
  LegacyTodoItem('wish-demo-walkthrough',
      'add a demo mode that you can toggle, like an interactive walktrough'),
  LegacyTodoItem(
      'wish-language-selection', 'add a language selection somewhere.'),
  // Todo.md — "Later"
  LegacyTodoItem('wish-logo-in-banners', 'add logo in banners etc'),
  LegacyTodoItem('wish-google-calendar-link', 'link to google calendar'),
  LegacyTodoItem('wish-youtube-video', 'add video to youtube channel'),
  LegacyTodoItem(
      'wish-about-story-vision', 'add story and vision to about page'),
  LegacyTodoItem('wish-fdroid-store', 'add to f-droid store if possible'),
  LegacyTodoItem('wish-galaxy-store', 'add to galaxy store if possible'),
  LegacyTodoItem('wish-update-startup-times', 'update startup times'),
  LegacyTodoItem('wish-web-version', 'web version'),
  LegacyTodoItem('wish-apple-store', 'add to apple store (much later)'),
  LegacyTodoItem('wish-gmail-style-header',
      'make header like google mail 2 menus with search in the middle'),
  LegacyTodoItem('wish-top-right-sort-menu',
      'make a menu on the top right with sorting options'),
  LegacyTodoItem('wish-icon-rail-menu',
      'make it an option that the menu is always visible on the left but only the icons'),
  LegacyTodoItem(
    'wish-pro-mode-setting',
    'add setting pro mode',
    'easy mode is default and it hides certain settings',
  ),
  LegacyTodoItem('wish-filter-on-labels', 'filter on labels'),
  LegacyTodoItem('wish-statistics-tab', 'complete a tab statistics'),
  LegacyTodoItem('wish-sliver-app-bar', 'sliver app bar and floating'),
  LegacyTodoItem('wish-selectable-text', 'have selectable text everyhere'),
  LegacyTodoItem('wish-wishlist-tab', 'make a tab wishlist'),
  LegacyTodoItem('wish-bulk-edit', 'bulk edit (also for labels)'),
  LegacyTodoItem('wish-encrypt-local-db', 'encrypt the local db'),
  LegacyTodoItem(
      'wish-self-hosted-web', 'add a web version to your own server'),
  LegacyTodoItem(
      'wish-cloud-backup', 'automatic backup to any cloud service'),
  LegacyTodoItem('wish-make-calendar-view', 'make calendar view'),
  LegacyTodoItem('wish-feedback-sanja', 'ask feedback sanja'),
  LegacyTodoItem(
      'wish-deadline-time', 'let user chose a time for the deadline'),
  LegacyTodoItem(
      'wish-daily-due-notification', 'daily notification of tasks due today'),
  LegacyTodoItem('wish-activity-reports', 'reports on what you did'),
];

/// The backlog keyed by its stable uid.
final Map<String, LegacyTodoItem> legacyTodoItemsByUid =
    <String, LegacyTodoItem>{
  for (final item in legacyTodoWishlistItems) item.uid: item,
};

/// Whether [task] was created by the one-time Todo.md import — the `old`
/// token is what the import stamps on every entry it adds, and it is the
/// only thing that tells an imported item apart from a user's own item
/// that happens to carry the same title.
bool isLegacyImportedWish(Task task) => splitLabelTokens(task.label)
    .any((token) => token.toLowerCase() == legacyTodoImportLabel);

/// Re-identifies backlog items imported before stable uids existed
/// (0.1.100–0.1.231 gave every imported entry a fresh uuid), so the
/// shipped-wish registry can address them. Matches on normalized title,
/// restricted to items carrying the `old` import label, and never takes a
/// uid another item in [items] already holds. Returns true when something
/// changed.
///
/// Callers must run this BEFORE snapshotting the item-history journal
/// baseline: re-identifying an item is bookkeeping, not history, and a uid
/// swap seen by the journal diff would read as a delete plus a create.
bool backfillLegacyWishUids(List<Task> items) {
  final stableByTitle = <String, String>{
    for (final item in legacyTodoWishlistItems)
      normalizeWishlistTitle(item.title): item.uid,
  };
  final taken = items.map((item) => item.uid).toSet();
  var changed = false;
  for (final item in items) {
    final stable = stableByTitle[normalizeWishlistTitle(item.title)];
    if (stable == null || item.uid == stable) continue;
    if (!isLegacyImportedWish(item)) continue;
    if (!taken.add(stable)) continue;
    taken.remove(item.uid);
    item.uid = stable;
    changed = true;
  }
  return changed;
}
