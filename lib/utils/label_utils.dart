import '../models/label.dart';

/// Splitting/classification helpers for the label token string on tasks.
/// The split regex matches the wishlist priority helpers in
/// `wishlist_page.dart` — one string, tokens separated by commas/whitespace.

final RegExp _tokenSeparator = RegExp(r'[,\s]+');

/// Label token given to the one-time Todo.md wishlist import
/// (see `wishlist_migration.dart`).
const String legacyImportToken = 'old';

/// Label token the app stamps on a wishlist item it completed by itself,
/// because the feature behind it shipped (see `wishlist_shipped.dart`).
const String autoCompletedToken = 'autocompleted';

/// Label token stamped on every task newly pulled in from Todoist (see
/// `TodoistSyncService._taskFromRemote`). Keeps it out of every list —
/// home tabs, wishlist, project boards — until a human approves or denies
/// it in the Waiting for Approval view (`waiting_approval_page.dart`):
/// approving strips the token (making the task visible wherever it belongs),
/// denying deletes the task outright.
///
/// Underscored on purpose (0.1.260): tokens split on commas AND whitespace,
/// so a Todoist label spelled "Waiting for Approval" arrives as three
/// separate tags ("Waiting", "for", "Approval") that match nothing. One
/// underscored word survives the split as a single tag on both sides.
const String waitingApprovalToken = 'Waiting_for_approval';

/// Earlier spellings of [waitingApprovalToken] still sitting on tasks that
/// were pulled in before 0.1.260. Recognized everywhere the current token is
/// (so those tasks stay gated) and stripped alongside it on approval, but
/// never written again.
const List<String> legacyWaitingApprovalTokens = <String>[
  'waiting-for-approval',
];

/// Whether [token] is the approval gate under any of its spellings.
bool isWaitingApprovalToken(String token) {
  final lower = token.toLowerCase();
  return lower == waitingApprovalToken.toLowerCase() ||
      legacyWaitingApprovalTokens.any((t) => t.toLowerCase() == lower);
}

/// Reserved tokens naming an item's built-in state or tool membership rather
/// than a plain user tag — the canonical display casing shown in Settings →
/// Filtering rules and used by `ItemViews.stateTags`. Typed by hand onto a
/// task's own label, most of these do nothing (the state they name is a
/// structural flag elsewhere — [isWish], [projectId], ...); [waitingApprovalToken]
/// is the one exception already wired to actually gate visibility (see
/// [hasWaitingApprovalToken]). Every chip renderer still colors all of them
/// the same protected way (see `label_style.dart`), since typing one is
/// always at least a naming collision worth flagging — like typing a
/// filename that happens to match a reserved system extension.
const String wishToken = 'Wish';
const String projectToken = 'Project';
const String archivedToken = 'Archived';
const String deletedToken = 'Deleted';
const String fooddiaryToken = 'Fooddiary';
const String alarmToken = 'Alarm';
const String countdownToken = 'Countdown';

/// Reserved like the rest, but with no dedicated view/page yet (the
/// Changelog tool shows CHANGELOG.md text, not a task list) — kept here so
/// it still renders as a protected chip and can still be named in another
/// view's Hide list, ahead of a future Changelog view.
const String changelogToken = 'Changelog';

/// Every reserved state token, in the order shown in Settings → Filtering
/// rules templates. Keep [waitingApprovalToken] last — it is the only one
/// matched case-and-spelling-insensitively via [isWaitingApprovalToken]
/// rather than a plain string compare.
const List<String> protectedStateTokens = <String>[
  wishToken,
  projectToken,
  archivedToken,
  deletedToken,
  fooddiaryToken,
  alarmToken,
  countdownToken,
  changelogToken,
  waitingApprovalToken,
];

/// Whether [token] is one of [protectedStateTokens], under any spelling.
bool isProtectedToken(String token) {
  final lower = token.trim().toLowerCase();
  if (lower.isEmpty) return false;
  return isWaitingApprovalToken(token) ||
      protectedStateTokens.any((t) => t.toLowerCase() == lower);
}

/// The wishlist priority tokens, lowest first (mirrors `wishPriorityLabels`).
const List<String> priorityTokens = <String>[
  'priority-low',
  'priority-medium',
  'priority-high',
];

/// Tokens that place a wishlist item in the "Next release" / "Soon" release
/// groups (see `wishlist_page.dart`'s `WishReleaseGroup`). Ordinary tags —
/// applied by hand or, via "Propose for next", by Claude in Todoist and
/// pulled in on the next sync.
const String releaseNextToken = 'release-next';
const String releaseSoonToken = 'release-soon';
const List<String> releaseGroupTokens = <String>[
  releaseNextToken,
  releaseSoonToken,
];

/// Splits a task's label string into its distinct tokens, order-preserving.
List<String> splitLabelTokens(String label) {
  final seen = <String>{};
  final tokens = <String>[];
  for (final raw in label.split(_tokenSeparator)) {
    final token = raw.trim();
    if (token.isEmpty) continue;
    if (seen.add(token.toLowerCase())) tokens.add(token);
  }
  return tokens;
}

/// Joins tokens back into the canonical on-task representation.
String joinLabelTokens(Iterable<String> tokens) => tokens.join(', ');

/// The [Label] kind a raw token belongs to.
String labelKindFor(String token) {
  final lower = token.toLowerCase();
  if (priorityTokens.contains(lower)) return Label.kindPriority;
  if (lower == legacyImportToken ||
      lower == autoCompletedToken ||
      isProtectedToken(token)) {
    return Label.kindSystem;
  }
  return Label.kindTag;
}

/// Whether [label]'s tokens include [token] (case-insensitive).
bool labelHasToken(String label, String token) {
  final lower = token.toLowerCase();
  return splitLabelTokens(label).any((t) => t.toLowerCase() == lower);
}

/// Adds [token] to [label] if not already present.
String addLabelToken(String label, String token) =>
    joinLabelTokens(splitLabelTokens('$label $token'));

/// Removes [token] from [label], preserving the others' order.
String removeLabelToken(String label, String token) {
  final lower = token.toLowerCase();
  return joinLabelTokens(
      splitLabelTokens(label).where((t) => t.toLowerCase() != lower));
}

/// Whether [label] carries the approval gate under any of its spellings.
bool hasWaitingApprovalToken(String label) =>
    splitLabelTokens(label).any(isWaitingApprovalToken);

/// Strips the approval gate from [label] under every spelling — what
/// approving a task does (`waiting_approval_page.dart`), so a task never
/// stays hidden because of a token this app no longer writes.
String removeWaitingApprovalToken(String label) => joinLabelTokens(
    splitLabelTokens(label).where((t) => !isWaitingApprovalToken(t)));
