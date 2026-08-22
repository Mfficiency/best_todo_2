/// One auto-tagging rule: when [keyword] appears as a whole word in a new
/// item's title (case-insensitive), [tag] is appended to its label. User
/// editable from Settings > Tasks > Auto-tag rules.
class AutoTagRule {
  String keyword;
  String tag;

  AutoTagRule({required this.keyword, required this.tag});

  factory AutoTagRule.fromJson(Map<String, dynamic> json) => AutoTagRule(
        keyword: json['keyword'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'keyword': keyword,
        'tag': tag,
      };
}
