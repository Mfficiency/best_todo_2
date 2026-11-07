/// The voice inbox (`docs/proposals/voice-inbox.md`): a Pocket recording is
/// split and sorted by a Claude routine into Todoist tasks whose description
/// carries one-line markers (`[Group: …]`, `[Suggest: …]`, …). This file is
/// the app's half of that contract — the group/suggestion vocabulary and the
/// marker parser — kept pure so it's unit-testable without a sync run.
library;

import '../models/task.dart';
import 'label_utils.dart';

/// The voice-inbox categories, in the order the Waiting for Approval page
/// shows them.
class ApprovalGroups {
  ApprovalGroups._();

  static const String todo = 'todo';
  static const String migros = 'migros';
  static const String lemmon = 'lemmon';
  static const String backlog = 'backlog';
  static const String research = 'research';
  static const String groceries = 'groceries';
  static const String food = 'food';
  static const String other = 'other';

  /// Every group, in display order. [food] is listed for completeness but a
  /// food entry never waits for approval (it goes straight into the Food
  /// Diary on pull), so it only shows up here if one was dragged into it.
  static const List<String> all = [
    todo,
    migros,
    lemmon,
    backlog,
    research,
    groceries,
    food,
    other,
  ];

  /// The groups an item can be moved into from the Other picker / a drag.
  static const List<String> pickable = [
    todo,
    migros,
    lemmon,
    backlog,
    research,
    groceries,
  ];

  static String title(String group) {
    switch (group) {
      case todo:
        return 'Todo';
      case migros:
        return 'Migros';
      case lemmon:
        return 'Lemmon';
      case backlog:
        return 'Backlog';
      case research:
        return 'Research';
      case groceries:
        return 'Groceries';
      case food:
        return 'Food diary';
      default:
        return 'Other';
    }
  }

  /// [raw] (a marker value, any case, a few aliases) as one of [all];
  /// anything unrecognized is [other].
  static String normalize(String? raw) {
    final v = (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    switch (v) {
      case 'todo':
      case 'task':
        return todo;
      case 'migros':
      case 'mlr':
      case 'worklist':
        return migros;
      case 'lemmon':
        return lemmon;
      case 'backlog':
      case 'wishlist':
      case 'wish':
        return backlog;
      case 'research':
        return research;
      case 'groceries':
      case 'grocery':
      case 'shopping':
        return groceries;
      case 'food':
      case 'fooddiary':
        return food;
      default:
        return other;
    }
  }

  /// The group a pending item sits in: its stored [stored] group, or Other
  /// when the routine hasn't sorted it yet.
  static String of(String? stored) =>
      stored == null ? other : normalize(stored);

  /// Groups whose approve-side swipe offers the day buckets.
  static bool isDated(String group) =>
      group == todo || group == migros || group == lemmon;

  /// Groups whose approve-side swipe offers Active / Next / Someday.
  static bool isStateful(String group) =>
      group == backlog || group == research;
}

/// The state words for Backlog and Research items. Stored as the existing
/// wishlist release tokens (`release-next` = Active, `release-soon` = Next,
/// neither = Someday) so the Wishlist's sections, swipes and the
/// build automation keep working unchanged.
class BacklogStates {
  BacklogStates._();

  static const String active = 'active';
  static const String next = 'next';
  static const String someday = 'someday';

  static const List<String> all = [active, next, someday];

  static String title(String state) {
    switch (state) {
      case active:
        return 'Active';
      case next:
        return 'Next';
      default:
        return 'Someday';
    }
  }
}

/// [task]'s backlog state, from its release token.
String backlogStateOf(Task task) {
  final labels =
      splitLabelTokens(task.label).map((l) => l.toLowerCase()).toSet();
  if (labels.contains(releaseNextToken)) return BacklogStates.active;
  if (labels.contains(releaseSoonToken)) return BacklogStates.next;
  return BacklogStates.someday;
}

/// Moves [task] into [state] by rewriting its release token, keeping every
/// other label (the same tokens `setWishReleaseGroup` writes).
void setBacklogState(Task task, String state) {
  final labels = splitLabelTokens(task.label)
      .where((l) => !releaseGroupTokens.contains(l.toLowerCase()))
      .toList();
  if (state == BacklogStates.active) labels.add(releaseNextToken);
  if (state == BacklogStates.next) labels.add(releaseSoonToken);
  task.label = joinLabelTokens(labels);
}

/// Suggestion keys for the dated groups, index-aligned with the home tabs
/// (`Config.tabs`: Today, Tomorrow, Day After Tomorrow, Next Week, Next
/// Month, Future).
const List<String> daySuggestionKeys = [
  'today',
  'tomorrow',
  'dayafter',
  'nextweek',
  'nextmonth',
  'future',
];

/// The home-tab index [suggestion] names, or null if it isn't a day key.
int? suggestedTabIndex(String? suggestion) {
  final v = (suggestion ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  if (v == 'dayaftertomorrow') return 2;
  final index = daySuggestionKeys.indexOf(v);
  return index < 0 ? null : index;
}

/// The backlog state [suggestion] names, or null if it isn't one.
String? suggestedState(String? suggestion) {
  final v = (suggestion ?? '').trim().toLowerCase();
  if (v == 'archive') return BacklogStates.someday;
  return BacklogStates.all.contains(v) ? v : null;
}

/// Everything the routine can put in a task description's marker lines.
class VoiceMarkers {
  final String? source;
  final String? group;
  final String? suggest;
  final String? project;
  final String? groceryCategory;
  final String? transcript;
  final String? obsidian;

  const VoiceMarkers({
    this.source,
    this.group,
    this.suggest,
    this.project,
    this.groceryCategory,
    this.transcript,
    this.obsidian,
  });

  bool get isEmpty =>
      source == null &&
      group == null &&
      suggest == null &&
      project == null &&
      groceryCategory == null &&
      transcript == null &&
      obsidian == null;
}

const List<String> _markerKeys = [
  'source',
  'group',
  'suggest',
  'project',
  'grocerycategory',
  'transcript',
  'obsidian',
];

/// A marker at the very start of the text: `[Key: value]`, optionally
/// followed on the same line by real description text (the original
/// `[Source:]` convention allowed that).
final RegExp _leadingMarker = RegExp(
  r'^\[(source|group|suggest|project|grocerycategory|transcript|obsidian):\s*([^\]\n]*)\][ \t]*\n?',
  caseSensitive: false,
);

/// A marker alone on its own line anywhere in the text — the routine
/// appends `[Obsidian: …]` at the end once it created the page.
final RegExp _lineMarker = RegExp(
  r'^[ \t]*\[(source|group|suggest|project|grocerycategory|transcript|obsidian):\s*([^\]\n]*)\][ \t]*$',
  caseSensitive: false,
  multiLine: true,
);

/// Splits [description] into the text a human should see and the markers it
/// carried. Leading markers (any number, any order) and full-line markers
/// anywhere are recognized and removed; a blank value counts as absent; the
/// first occurrence of a key wins.
(String, VoiceMarkers) parseVoiceMarkers(String description) {
  final values = <String, String>{};
  void put(String key, String value) {
    final v = value.trim();
    final k = key.toLowerCase();
    if (v.isEmpty || !_markerKeys.contains(k)) return;
    values.putIfAbsent(k, () => v);
  }

  var rest = description;
  while (true) {
    final match = _leadingMarker.firstMatch(rest);
    if (match == null) break;
    put(match.group(1)!, match.group(2)!);
    rest = rest.substring(match.end).trimLeft();
  }
  if (_lineMarker.hasMatch(rest)) {
    for (final match in _lineMarker.allMatches(rest)) {
      put(match.group(1)!, match.group(2)!);
    }
    rest = rest
        .replaceAll(_lineMarker, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
  return (
    rest,
    VoiceMarkers(
      source: values['source'],
      group: values['group'],
      suggest: values['suggest'],
      project: values['project'],
      groceryCategory: values['grocerycategory'],
      transcript: values['transcript'],
      obsidian: values['obsidian'],
    ),
  );
}
