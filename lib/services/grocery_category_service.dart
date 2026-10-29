import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/task.dart';

/// The Groceries tool's categories: an ordered, user-editable list of names
/// (Settings ▸ Groceries / the Groceries page's "Edit categories"). The list
/// order is the order the Groceries checklist shows its sections in. Seeded
/// with a supermarket-ish default on first run, persisted to
/// `grocery_categories.json`. Mirrors `ApprovalQuickTagService`'s load/save
/// shape.
///
/// [otherCategory] always exists and always comes last: it's where an item
/// with no (or an unknown, or a deleted) category is shown.
class GroceryCategoryService {
  GroceryCategoryService._();

  static final GroceryCategoryService instance = GroceryCategoryService._();

  static const String fileName = 'grocery_categories.json';

  static const String otherCategory = 'Other';

  static const List<String> defaultCategories = [
    'Fruit & vegetables',
    'Bread & bakery',
    'Dairy & eggs',
    'Meat & fish',
    'Pasta & rice',
    'Canned & jars',
    'Frozen',
    'Snacks & sweets',
    'Drinks',
    'Household',
    otherCategory,
  ];

  final ValueNotifier<List<String>> categories =
      ValueNotifier<List<String>>(List.of(defaultCategories));
  bool _loaded = false;

  List<String> get list => categories.value;

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  /// Trims, drops blanks and case-insensitive duplicates, and moves
  /// [otherCategory] to the end (adding it if missing).
  static List<String> normalize(Iterable<String> names) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      if (name.toLowerCase() == otherCategory.toLowerCase()) continue;
      if (seen.add(name.toLowerCase())) result.add(name);
    }
    return [...result, otherCategory];
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        await _save();
        return;
      }
      final List<dynamic> data = jsonDecode(await file.readAsString());
      categories.value = normalize(data.whereType<String>());
    } catch (_) {}
  }

  Future<void> save(List<String> next) async {
    categories.value = normalize(next);
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(categories.value), flush: true);
    } catch (_) {}
  }

  /// The configured category [raw] names (case-insensitive), or
  /// [otherCategory] when it's empty or not in the list.
  String resolve(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v.isEmpty) return otherCategory;
    for (final name in list) {
      if (name.toLowerCase() == v) return name;
    }
    return otherCategory;
  }

  @visibleForTesting
  void resetForTest() {
    categories.value = List.of(defaultCategories);
    _loaded = false;
  }
}

/// Grocery-list rules shared by the Groceries page and the approval page,
/// kept pure so they're testable without either page.
class GroceryList {
  GroceryList._();

  static String _key(String title) =>
      title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// The grocery item already on the list with [title] (case- and
  /// whitespace-insensitive), or null.
  static Task? existing(List<Task> tasks, String title) {
    final key = _key(title);
    for (final t in tasks) {
      if (t.isGrocery && t.deletedAt == null && _key(t.title) == key) return t;
    }
    return null;
  }

  /// The category the item named [title] had the last time it was on the
  /// list (so "milk" lands in Dairy every time after the first), or null.
  static String? rememberedCategory(List<Task> tasks, String title) =>
      existing(tasks, title)?.groceryCategory;

  /// Puts [item] on the list: if an item with the same name is already
  /// there it is unchecked (and takes [item]'s category when it had none)
  /// instead of adding a duplicate — returns that existing item. Otherwise
  /// flags [item] as a grocery item (category: [category], else the
  /// remembered one) and returns it; the caller keeps it in the task list.
  static Task add(List<Task> tasks, Task item, {String? category}) {
    final match = existing(tasks.where((t) => !identical(t, item)).toList(),
        item.title);
    if (match != null) {
      match.isDone = false;
      match.completedAt = null;
      match.groceryCategory ??= category ?? item.groceryCategory;
      return match;
    }
    item.isGrocery = true;
    item.isDone = false;
    item.groceryCategory = category ??
        item.groceryCategory ??
        rememberedCategory(tasks, item.title);
    return item;
  }
}
