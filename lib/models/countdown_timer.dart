import 'package:uuid/uuid.dart';

/// A single countdown timer counting toward (or up from) a target moment.
class CountdownTimerItem {
  static final Uuid _uuid = const Uuid();

  static String newUid() => _uuid.v4();

  String uid;
  String label;
  DateTime target;

  /// When true, a notification fires once when the timer reaches zero.
  bool notifyOnZero;

  /// When the timer was first created and last edited — used for sorting.
  DateTime createdAt;
  DateTime editedAt;

  CountdownTimerItem({
    String? uid,
    required this.label,
    required this.target,
    this.notifyOnZero = false,
    DateTime? createdAt,
    DateTime? editedAt,
  })  : uid = uid ?? CountdownTimerItem.newUid(),
        createdAt = createdAt ?? DateTime.now(),
        editedAt = editedAt ?? createdAt ?? DateTime.now();

  factory CountdownTimerItem.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String)
        : null;
    final edited = json['editedAt'] != null
        ? DateTime.tryParse(json['editedAt'] as String)
        : null;
    return CountdownTimerItem(
      uid: json['uid'] as String?,
      label: json['label'] as String? ?? '',
      target: DateTime.parse(json['target'] as String),
      notifyOnZero: json['notifyOnZero'] as bool? ?? false,
      createdAt: created,
      editedAt: edited,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'label': label,
        'target': target.toIso8601String(),
        'notifyOnZero': notifyOnZero,
        'createdAt': createdAt.toIso8601String(),
        'editedAt': editedAt.toIso8601String(),
      };
}
