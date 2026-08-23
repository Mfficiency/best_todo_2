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
const String waitingApprovalToken = 'waiting-for-approval';

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
      lower == waitingApprovalToken) {
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
