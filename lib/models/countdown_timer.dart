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

  CountdownTimerItem({
    String? uid,
    required this.label,
    required this.target,
    this.notifyOnZero = false,
  }) : uid = uid ?? CountdownTimerItem.newUid();

  factory CountdownTimerItem.fromJson(Map<String, dynamic> json) {
    return CountdownTimerItem(
      uid: json['uid'] as String?,
      label: json['label'] as String? ?? '',
      target: DateTime.parse(json['target'] as String),
      notifyOnZero: json['notifyOnZero'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'label': label,
        'target': target.toIso8601String(),
        'notifyOnZero': notifyOnZero,
      };
}
