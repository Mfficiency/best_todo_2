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

/// The wishlist priority tokens, lowest first (mirrors `wishPriorityLabels`).
const List<String> priorityTokens = <String>[
  'priority-low',
  'priority-medium',
  'priority-high',
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
  if (lower == legacyImportToken || lower == autoCompletedToken) {
    return Label.kindSystem;
  }
  return Label.kindTag;
}
