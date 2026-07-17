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

  /// When true, a notification fires each time the remaining time crosses a
  /// round number of seconds (one of [roundMilestones]).
  bool notifyRoundNumbers;

  /// When the timer was first created and last edited — used for sorting.
  DateTime createdAt;
  DateTime editedAt;

  CountdownTimerItem({
    String? uid,
    required this.label,
    required this.target,
    this.notifyOnZero = false,
    this.notifyRoundNumbers = false,
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
      notifyRoundNumbers: json['notifyRoundNumbers'] as bool? ?? false,
      createdAt: created,
      editedAt: edited,
    );
  }

  /// Second-count milestones the round-number bell notifies at, largest
  /// first: powers of ten from 1,000,000,000 down to 1,000 seconds
  /// (100,000 s ≈ 1.2 days). Applied to the remaining time while counting
  /// down and to the elapsed time while counting up; zero itself is the
  /// notify-on-zero bell's job.
  static const List<int> roundMilestones = [
    1000000000,
    100000000,
    10000000,
    1000000,
    100000,
    10000,
    1000,
  ];

  /// The milestone most recently crossed while the remaining time fell from
  /// [previousSeconds] to [currentSeconds], or null when none was crossed.
  /// A crossing means the remaining time was strictly above the milestone
  /// before and is at or below it now; when several were crossed at once
  /// (e.g. after the app was backgrounded) only the smallest — the most
  /// recent — is reported. A timer at or past zero reports nothing.
  static int? crossedRoundMilestone({
    required int previousSeconds,
    required int currentSeconds,
  }) {
    if (currentSeconds <= 0) return null;
    int? crossed;
    for (final milestone in roundMilestones) {
      if (previousSeconds > milestone && currentSeconds <= milestone) {
        crossed = milestone;
      }
    }
    return crossed;
  }

  /// Count-up counterpart of [crossedRoundMilestone]: the milestone most
  /// recently crossed while the elapsed time rose from [previousSeconds] to
  /// [currentSeconds], or null when none was crossed. A crossing means the
  /// elapsed time was strictly below the milestone before and is at or above
  /// it now; when several were crossed at once only the largest — the most
  /// recent — is reported.
  static int? crossedRoundMilestoneUp({
    required int previousSeconds,
    required int currentSeconds,
  }) {
    for (final milestone in roundMilestones) {
      if (previousSeconds < milestone && currentSeconds >= milestone) {
        return milestone;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'label': label,
        'target': target.toIso8601String(),
        'notifyOnZero': notifyOnZero,
        'notifyRoundNumbers': notifyRoundNumbers,
        'createdAt': createdAt.toIso8601String(),
        'editedAt': editedAt.toIso8601String(),
      };
}
