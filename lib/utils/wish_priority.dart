import '../models/task.dart';

/// Priority labels a wishlist item can carry inside [Task.label], ordered
/// from lowest to highest. Shared by BestToDo's Wishlist tool
/// (`wishlist_page.dart`) and Best Music's Wishlist tool
/// (`music_wishlist_page.dart`) so a priority set by either app reads the
/// same in the other — both write the identical [Task] JSON record.
const List<String> wishPriorityLabels = <String>[
  'priority-low',
  'priority-medium',
  'priority-high',
];

/// 0 for no priority label, 1..3 for low..high.
int wishPriorityRank(Task task) {
  final labels = task.label
      .toLowerCase()
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .toSet();
  for (var i = wishPriorityLabels.length - 1; i >= 0; i--) {
    if (labels.contains(wishPriorityLabels[i])) return i + 1;
  }
  return 0;
}

/// Rewrites [task]'s label so [priorityLabel] is its only priority label;
/// all other labels are kept.
void setWishPriority(Task task, String priorityLabel) {
  final labels = task.label
      .split(RegExp(r'[,\s]+'))
      .map((label) => label.trim())
      .where((label) => label.isNotEmpty)
      .where((label) => !wishPriorityLabels.contains(label.toLowerCase()))
      .toList();
  labels.insert(0, priorityLabel);
  task.label = labels.join(', ');
}

/// Raises [task]'s priority one step: none → low → medium → high (capped).
void bumpWishPriority(Task task) {
  final rank = wishPriorityRank(task);
  final next =
      rank >= wishPriorityLabels.length ? wishPriorityLabels.length - 1 : rank;
  setWishPriority(task, wishPriorityLabels[next]);
}
