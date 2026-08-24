/// A user-configured tag filter for one view (Settings → Filtering rules).
///
/// Tasks whose [Task.label] carries any token in [excludeTags] are hidden;
/// when [includeTags] is non-empty, only tasks carrying at least one of
/// those tokens are shown. Matching is case-insensitive and token-based (see
/// `splitLabelTokens`). This sits on top of a view's own structural filter
/// (e.g. the wishlist still only ever shows [Task.isWish] items) — it is an
/// extra, optional layer the user configures per view.
class ViewFilterRules {
  /// View ids this feature covers today; keep these stable, they are the
  /// persisted map keys (`Config.viewFilterRules`).
  static const String home = 'home';
  static const String wishlist = 'wishlist';
  static const String projects = 'projects';
  static const String archived = 'archived';
  static const String bin = 'bin';

  static const List<String> viewIds = [
    home,
    wishlist,
    projects,
    archived,
    bin,
  ];

  static const Map<String, String> viewLabels = {
    home: 'Home',
    wishlist: 'Wishlist',
    projects: 'Projects',
    archived: 'Archived items',
    bin: 'Deleted bin',
  };

  static const Map<String, String> viewDescriptions = {
    home: 'The Today / Tomorrow / ... tabs on the home screen',
    wishlist: 'Tools → Wishlist',
    projects: 'Tools → Projects, including every project board',
    archived: 'Archived Items (the drawer entry)',
    bin: 'The real Deleted bin, opened from Archived Items',
  };

  List<String> excludeTags;
  List<String> includeTags;

  ViewFilterRules({List<String>? excludeTags, List<String>? includeTags})
      : excludeTags = excludeTags ?? <String>[],
        includeTags = includeTags ?? <String>[];

  bool get isEmpty => excludeTags.isEmpty && includeTags.isEmpty;

  factory ViewFilterRules.fromJson(Map<String, dynamic> json) =>
      ViewFilterRules(
        excludeTags: (json['excludeTags'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        includeTags: (json['includeTags'] as List?)
            ?.map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'excludeTags': excludeTags,
        'includeTags': includeTags,
      };
}
