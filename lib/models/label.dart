import 'package:uuid/uuid.dart';

/// A first-class label. Today every task still stores its labels as one
/// token string ([Task.label], split on commas/whitespace); this entity is
/// the structured side of that dual-write: one [Label] per distinct token,
/// carrying the metadata the string cannot (kind, colour). The token string
/// stays the canonical source on the task until a later migration step, so
/// nothing about how labels are typed or shown changes yet.
class Label {
  static final Uuid _uuid = const Uuid();

  static String newUid() => _uuid.v4();

  /// Kinds. Stored in JSON — keep them stable once shipped.
  /// A plain user tag.
  static const String kindTag = 'tag';

  /// One of the wishlist priorities (`priority-low/-medium/-high`).
  static const String kindPriority = 'priority';

  /// App-generated markers (e.g. the Todo.md import's `old`).
  static const String kindSystem = 'system';

  String id;

  /// The token as it appears inside [Task.label]. Unique per registry,
  /// case-preserving (matching is case-insensitive).
  String name;

  /// One of the `kind*` constants.
  String kind;

  /// Optional ARGB colour for future tag colouring; null = theme default.
  int? color;

  Label({
    String? id,
    required this.name,
    required this.kind,
    this.color,
  }) : id = id ?? Label.newUid();

  factory Label.fromJson(Map<String, dynamic> json) => Label(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '',
        kind: json['kind'] as String? ?? kindTag,
        color: json['color'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        if (color != null) 'color': color,
      };
}
