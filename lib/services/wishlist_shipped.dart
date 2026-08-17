import '../models/task.dart';
import '../utils/label_utils.dart';
import 'wishlist_migration.dart';

/// Wishes the app completes for itself, once their feature is actually built.
///
/// Every backlog entry in `wishlist_migration.dart` has a permanent uid. When
/// a feature from that backlog ships, add its uid to [shippedWishes]; the next
/// launch ticks the matching wishlist item off, tags it
/// [autoCompletedLabel] and records which release delivered it in the item's
/// note. Nothing else is touched: a user's own wish never matches (uids are
/// only assigned by the backlog import), an item the user already ticked off
/// keeps its own `completedAt`, and once an item carries the tag it is never
/// visited again — so an undo or a re-open sticks.
///
/// The registry is the whole workflow: shipping a wishlist feature is
/// "implement it, then add one line here", and the app does the bookkeeping.

/// Tag added to a wishlist item the app completed by itself. Same token the
/// structured-label registry classifies as a system label.
const String autoCompletedLabel = autoCompletedToken;

/// One built wish: which wishlist item, and which release delivered it.
class ShippedWish {
  /// The item to tick off. Either a [LegacyTodoItem.uid] (`wish-<slug>`,
  /// which every install shares because the backlog import assigns it) or the
  /// raw uuid of a wish the user added themselves — those are minted per
  /// install, so such an entry only ever matches on the device that created
  /// it, which is exactly what is wanted: it is that user's own idea. Uuids
  /// survive the wishlist's JSON export/import, so the match also survives a
  /// reinstall restored from a backup.
  final String uid;

  /// App version whose install auto-completes the wish. This is the release
  /// that added the entry here — not necessarily the release that first
  /// built the feature, which [note] records instead.
  final String version;

  /// What actually delivered it, for the item's note.
  final String note;

  const ShippedWish(this.uid, this.version, this.note);
}

/// Built wishes, newest batch last. Only add an entry once the feature is
/// really in the app — this ticks the item off on every install.
const List<ShippedWish> shippedWishes = <ShippedWish>[
  // 0.1.232 — the first sweep: backlog entries whose feature had already
  // shipped long before the auto-complete mechanism existed.
  ShippedWish('wish-calendar-view', '0.1.232',
      'Built: Tools → Calendar (lib/ui/calendar_view_page.dart).'),
  ShippedWish('wish-make-calendar-view', '0.1.232',
      'Built: Tools → Calendar (lib/ui/calendar_view_page.dart).'),
  ShippedWish('wish-chronize-tool', '0.1.232',
      'Built: Tools → Chronize, the continuous timeline (SPEC 10.1).'),
  ShippedWish('wish-wishlist-tab', '0.1.232',
      'Built: Tools → Wishlist (SPEC 10.6) — this list itself.'),
  ShippedWish('wish-statistics-tab', '0.1.232',
      'Built: Tools → Productivity Stats (SPEC 10.3).'),
  ShippedWish('wish-update-startup-times', '0.1.232',
      'Built: Tools → Startup Times, with history chart and verdicts.'),
  ShippedWish('wish-simplified-mode', '0.1.232',
      'Built: simple mode, chosen in the intro and switchable in Settings (SPEC 4.6).'),
  ShippedWish('wish-advanced-mode-switch', '0.1.232',
      'Built: simple mode plus the per-feature switches that hide settings (SPEC 4.6).'),
  ShippedWish('wish-pro-mode-setting', '0.1.232',
      'Built: simple mode is the default; full mode is the "pro" side (SPEC 4.6).'),
  ShippedWish('wish-github-manual-apk-build', '0.1.232',
      'Built: .github/workflows/build-apk.yml, runnable by hand (workflow_dispatch).'),
  ShippedWish('wish-ci-automatic-test', '0.1.232',
      'Built: .github/workflows/flutter_test.yml runs the suite on every push.'),
  ShippedWish('wish-screenshot-integration-tests', '0.1.232',
      'Built: integration_test/home_page_screenshot_test.dart + the screenshot-changelog workflow.'),
  // 0.1.232 — hand-added wishes (uuids read from the owner's wishlist export,
  // so they match on that install only).
  ShippedWish('0a534906-5444-4b9d-a8d2-ddb9f114bb96', '0.1.232',
      'Built in v0.1.148: LinkifiedText auto-detects http/https URLs (no manual marking) and makes them tappable on every item surface — home tile title and description, task detail, wishlist, projects, board cards, deleted items, Chronize.'),
  // 0.1.233 — built for this release.
  ShippedWish('wish-home-in-menu', '0.1.233',
      'Built: the drawer opens with a Home entry that closes any tool page, drops an active search and returns to the start tab (SPEC 4.3).'),
  ShippedWish('wish-default-due-bucket', '0.1.233',
      'Built: Settings → Tasks → "New tasks go to" pins quick-added tasks to a list; the add row names the target (SPEC 4.3).'),
  ShippedWish('wish-quick-item-reminder', '0.1.233',
      'Built: the Notify bell on an expanded task asks when — in 5 minutes, 20 minutes, 1 hour, or the default delay (SPEC 4.3).'),
];

/// The registry keyed by uid.
final Map<String, ShippedWish> shippedWishesByUid = <String, ShippedWish>{
  for (final wish in shippedWishes) wish.uid: wish,
};

/// Auto-completes the wishlist items in [items] whose feature has shipped.
///
/// For each wish task whose uid is in [shippedWishes] and that does not
/// already carry [autoCompletedLabel]: ticks it done, stamps [now]
/// (defaulting to the current time) on `completedAt` unless the user beat us
/// to it, appends the tag to the item's labels and the release note to its
/// note. Returns true when anything changed, so the caller knows to save.
///
/// Idempotent by the tag, which is why removing the tick or the tag by hand
/// is respected: the tag stays, so the item is never re-completed.
bool applyShippedWishes(List<Task> items, {DateTime? now}) {
  if (shippedWishes.isEmpty) return false;
  final at = now ?? DateTime.now();
  var changed = false;
  for (final item in items) {
    if (!item.isWish) continue;
    final shipped = shippedWishesByUid[item.uid];
    if (shipped == null) continue;
    final tokens = splitLabelTokens(item.label);
    if (tokens.any((token) => token.toLowerCase() == autoCompletedLabel)) {
      continue;
    }
    item.label = joinLabelTokens(<String>[...tokens, autoCompletedLabel]);
    if (!item.isDone) {
      item.isDone = true;
      item.completedAt = at;
    }
    item.completedAt ??= at;
    final note = 'Auto-completed in v${shipped.version}. ${shipped.note}';
    item.note = item.note.trim().isEmpty ? note : '${item.note.trim()}\n$note';
    changed = true;
  }
  return changed;
}
