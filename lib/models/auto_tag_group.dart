/// One auto-tagging group: when any word in [keywords] appears as a whole
/// word in a new item's title (case-insensitive), [tag] is appended to its
/// label. Grouping several related words under one tag is what makes the
/// matching "smart" without any real NLP — e.g. "gym"/"workout"/"cardio" all
/// point at the same "fitness" tag. User editable from Settings > Tasks >
/// Auto-tag rules.
class AutoTagGroup {
  String tag;
  List<String> keywords;

  AutoTagGroup({required this.tag, required this.keywords});

  /// Tolerant of both the current shape (`keywords`, a list) and the
  /// original one-keyword-per-tag shape (`keyword`, a single string) that
  /// shipped before groups existed, so a file saved by that earlier version
  /// still loads.
  factory AutoTagGroup.fromJson(Map<String, dynamic> json) {
    final tag = (json['tag'] as String? ?? '').trim();
    final keywordsField = json['keywords'];
    if (keywordsField is List) {
      return AutoTagGroup(
        tag: tag,
        keywords: keywordsField.whereType<String>().toList(),
      );
    }
    final legacyKeyword = json['keyword'] as String?;
    return AutoTagGroup(
      tag: tag,
      keywords: legacyKeyword == null || legacyKeyword.isEmpty
          ? <String>[]
          : <String>[legacyKeyword],
    );
  }

  Map<String, dynamic> toJson() => {
        'tag': tag,
        'keywords': keywords,
      };
}
