import 'track.dart';

/// A [Track] field a [RuleCondition] can test.
enum RuleField { title, artist, album, genre, year }

/// How a [RuleCondition] compares its [RuleField] against
/// [RuleCondition.values].
///
/// This is where a rule playlist's AND/OR/NOT actually live: NOT is
/// per-condition ([notEquals]/[notContains]/[notInList] — "excluding
/// Artist C"), OR is a single [inList] condition's value list ("Artist A
/// or Artist B"), and AND is [PlaylistRuleSet.combinator]'s
/// [RuleCombinator.all] across conditions ("genre X and released last
/// year"). [greaterOrEqual]/[lessOrEqual] only apply to [RuleField.year].
enum RuleOperator {
  equals,
  notEquals,
  contains,
  notContains,
  inList,
  notInList,
  greaterOrEqual,
  lessOrEqual,
}

/// Whether a [PlaylistRuleSet]'s conditions must all match (AND) or any one
/// of them is enough (OR).
enum RuleCombinator { all, any }

/// One leaf condition of a rule playlist, e.g. `genre is "Rock"` or
/// `artist is one of ["Queen", "ABBA"]`.
class RuleCondition {
  final RuleField field;
  final RuleOperator operator;

  /// The comparison value(s). A single-value operator ([equals],
  /// [notEquals], [contains], [notContains], [greaterOrEqual],
  /// [lessOrEqual]) only reads [values.first]; [inList]/[notInList] read
  /// the whole list.
  final List<String> values;

  const RuleCondition({
    required this.field,
    required this.operator,
    this.values = const [],
  });

  bool matches(Track track) {
    if (field == RuleField.year) return _matchesYear(track.year);
    return _matchesText(_textValue(track));
  }

  bool _matchesYear(int? year) {
    final targets = values.map(int.tryParse).whereType<int>().toList();
    switch (operator) {
      case RuleOperator.equals:
        return year != null && targets.isNotEmpty && year == targets.first;
      case RuleOperator.notEquals:
        return targets.isEmpty || year == null || year != targets.first;
      case RuleOperator.greaterOrEqual:
        return year != null && targets.isNotEmpty && year >= targets.first;
      case RuleOperator.lessOrEqual:
        return year != null && targets.isNotEmpty && year <= targets.first;
      case RuleOperator.inList:
        return year != null && targets.contains(year);
      case RuleOperator.notInList:
        return targets.isEmpty || year == null || !targets.contains(year);
      case RuleOperator.contains:
      case RuleOperator.notContains:
        return false; // not meaningful for a numeric field
    }
  }

  bool _matchesText(String fieldValue) {
    final value = fieldValue.toLowerCase();
    bool eq(String v) => value == v.trim().toLowerCase();
    bool has(String v) =>
        v.trim().isNotEmpty && value.contains(v.trim().toLowerCase());
    switch (operator) {
      case RuleOperator.equals:
        return values.isNotEmpty && eq(values.first);
      case RuleOperator.notEquals:
        return values.isEmpty || !eq(values.first);
      case RuleOperator.contains:
        return values.isNotEmpty && has(values.first);
      case RuleOperator.notContains:
        return values.isEmpty || !has(values.first);
      case RuleOperator.inList:
        return values.any(eq);
      case RuleOperator.notInList:
        return values.isEmpty || values.every((v) => !eq(v));
      case RuleOperator.greaterOrEqual:
      case RuleOperator.lessOrEqual:
        return false; // numeric-only, not meaningful for a text field
    }
  }

  String _textValue(Track track) {
    switch (field) {
      case RuleField.title:
        return track.title;
      case RuleField.artist:
        return track.artist;
      case RuleField.album:
        return track.album;
      case RuleField.genre:
        return track.genre;
      case RuleField.year:
        return track.year?.toString() ?? '';
    }
  }

  Map<String, dynamic> toJson() => {
        'field': field.name,
        'operator': operator.name,
        'values': values,
      };

  factory RuleCondition.fromJson(Map<String, dynamic> json) {
    final rawValues = json['values'];
    return RuleCondition(
      field: RuleField.values.firstWhere(
        (f) => f.name == json['field'],
        orElse: () => RuleField.title,
      ),
      operator: RuleOperator.values.firstWhere(
        (o) => o.name == json['operator'],
        orElse: () => RuleOperator.equals,
      ),
      values:
          rawValues is List ? rawValues.whereType<String>().toList() : const [],
    );
  }
}

/// A manually built set of rules ("smart playlist" in the iTunes/Plex
/// sense): every matching [Track] in the library is included, recomputed
/// live rather than stored as a fixed track list.
class PlaylistRuleSet {
  final RuleCombinator combinator;
  final List<RuleCondition> conditions;

  const PlaylistRuleSet({
    this.combinator = RuleCombinator.all,
    this.conditions = const [],
  });

  /// A rule set with no conditions matches nothing — an empty rule playlist
  /// should look empty, not include the whole library.
  bool matches(Track track) {
    if (conditions.isEmpty) return false;
    return combinator == RuleCombinator.all
        ? conditions.every((c) => c.matches(track))
        : conditions.any((c) => c.matches(track));
  }

  Map<String, dynamic> toJson() => {
        'combinator': combinator.name,
        'conditions': conditions.map((c) => c.toJson()).toList(),
      };

  factory PlaylistRuleSet.fromJson(Map<String, dynamic> json) {
    final rawConditions = json['conditions'];
    return PlaylistRuleSet(
      combinator: RuleCombinator.values.firstWhere(
        (c) => c.name == json['combinator'],
        orElse: () => RuleCombinator.all,
      ),
      conditions: rawConditions is List
          ? rawConditions
              .whereType<Map>()
              .map((e) => RuleCondition.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}
