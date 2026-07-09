/// One-time import of the historical `Todo.md` backlog into the wishlist.
///
/// The repo's `Todo.md` predates the Wishlist tool; its still-open ideas
/// (the "After MVP → TODO" and "Later" sections, verbatim including typos)
/// are baked in here so every install can migrate them into
/// `wishlist.json` exactly once. Items already finished (the DONE
/// sections) are intentionally not imported.
class LegacyTodoItem {
  final String title;
  final String description;

  const LegacyTodoItem(this.title, [this.description = '']);
}

/// Label given to every imported item so old backlog entries are
/// recognizable in the wishlist.
const String legacyTodoImportLabel = 'old';

/// Lowercases and collapses whitespace so "Calendar view" and
/// "calendar  view" count as the same wishlist entry when deduplicating.
String normalizeWishlistTitle(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

const List<LegacyTodoItem> legacyTodoWishlistItems = <LegacyTodoItem>[
  // Todo.md — "After MVP" → TODO
  LegacyTodoItem(
      'add a setting to enable or disable people you are sending it to, so you dont just have to delete there number'),
  LegacyTodoItem('full testing suite, only merge if all test are complete'),
  LegacyTodoItem('calendar view'),
  LegacyTodoItem(
      'build on github: have a manual action to build the apk on github so i can work remotely'),
  LegacyTodoItem('ios mode'),
  LegacyTodoItem(
      'receiving sms to send you back the task list, so if my friend sends me : "tasks" it automatically sends back todays tasks'),
  LegacyTodoItem('send emails'),
  LegacyTodoItem('send in app to each other'),
  LegacyTodoItem(
      'add more settings to controll the days of the week on the swiping motion and different icons and the cancel color etc'),
  LegacyTodoItem(
      'search function should also be able to show when you type a date and it should show items from the dates around it as well, it should prioritize the tiltel but also look in the description'),
  LegacyTodoItem(
    'have extra function for the countdown timer "when is"',
    'this will show you the closest round numbers, when they fall and the option to send you a reminder',
  ),
  LegacyTodoItem(
    'add another tool just as a test the "chronize" tool',
    'it list all the tasks from the task list but on a 24hr calendar view and on the right hand side you have 3 sliders, one for the hour, day and month, so you can scroll the list for fine detail, hour roller for going 3 days in one top to bottom scroll, 15 days in a top to bottom scroll and 12 months in a top to bottom scroll.',
  ),
  LegacyTodoItem('add a sync function with google calendars'),
  LegacyTodoItem(
      'add clever filter functions to sort and filter all the timers and events'),
  LegacyTodoItem('add optional week numbers to the date selectors everythere'),
  LegacyTodoItem(
      'Completed task behavior: Auto-hide completed tasks after X time, or show them grouped at bottom.'),
  LegacyTodoItem(
      'Auto-delete completed tasks: Optional cleanup rule (e.g., after 7/30 days).'),
  LegacyTodoItem(
      'Default due bucket: When creating a task quickly, choose default target list (Today vs Future).'),
  LegacyTodoItem(
      'Confirmation toggles: Per-action confirmations: delete, clear completed, move all.'),
  LegacyTodoItem(
      'Sort mode per list: Manual only vs by created time / priority / due date.'),
  LegacyTodoItem('Settings onepager, click on top tabs to scroll down'),
  LegacyTodoItem('improve integration test with screenshots'),
  LegacyTodoItem('improve recurring tasks'),
  LegacyTodoItem('add home to menu'),
  LegacyTodoItem(
      'on the start screen, have 3 buttons, populate with example data or start fresh or import previous data'),
  LegacyTodoItem('1 working automatic test when building or pushing'),
  LegacyTodoItem('add a simplified mode'),
  LegacyTodoItem('delete all, select before delete'),
  LegacyTodoItem(
      'have a way to sent a notification about that item in 5- 20 or 60 minutes'),
  LegacyTodoItem(
      'extra stats, when is the most productive day. When is the most productive time? When is the time where I plan the most? Which day do I postpone the most? All those kinds of variants'),
  LegacyTodoItem(
      'add an advanced mode switch in the menu that hides a lot of the settings for the non-advanced users.'),
  LegacyTodoItem(
      'settings for green progress bar to be green when 3 or less tasks are left, orange when 4 tasks are left and red when 5 or more tasks are left. to change the colors and the thresholds.'),
  LegacyTodoItem('Make icons even bigger?'),
  LegacyTodoItem(
      'show in daily stats a different color if you have cleared tasks from a future date.'),
  LegacyTodoItem(
      'add a demo mode that you can toggle, like an interactive walktrough'),
  LegacyTodoItem('add a language selection somewhere.'),
  // Todo.md — "Later"
  LegacyTodoItem('add logo in banners etc'),
  LegacyTodoItem('link to google calendar'),
  LegacyTodoItem('add video to youtube channel'),
  LegacyTodoItem('add story and vision to about page'),
  LegacyTodoItem('add to f-droid store if possible'),
  LegacyTodoItem('add to galaxy store if possible'),
  LegacyTodoItem('update startup times'),
  LegacyTodoItem('web version'),
  LegacyTodoItem('add to apple store (much later)'),
  LegacyTodoItem(
      'make header like google mail 2 menus with search in the middle'),
  LegacyTodoItem('make a menu on the top right with sorting options'),
  LegacyTodoItem(
      'make it an option that the menu is always visible on the left but only the icons'),
  LegacyTodoItem(
    'add setting pro mode',
    'easy mode is default and it hides certain settings',
  ),
  LegacyTodoItem('filter on labels'),
  LegacyTodoItem('complete a tab statistics'),
  LegacyTodoItem('sliver app bar and floating'),
  LegacyTodoItem('have selectable text everyhere'),
  LegacyTodoItem('make a tab wishlist'),
  LegacyTodoItem('bulk edit (also for labels)'),
  LegacyTodoItem('encrypt the local db'),
  LegacyTodoItem('add a web version to your own server'),
  LegacyTodoItem('automatic backup to any cloud service'),
  LegacyTodoItem('make calendar view'),
  LegacyTodoItem('ask feedback sanja'),
  LegacyTodoItem('let user chose a time for the deadline'),
  LegacyTodoItem('daily notification of tasks due today'),
  LegacyTodoItem('reports on what you did'),
];
