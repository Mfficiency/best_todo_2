import 'package:uuid/uuid.dart';

import 'countdown_milestone.dart';

/// A single countdown timer counting toward (or up from) a target moment.
class CountdownTimerItem {
  static final Uuid _uuid = const Uuid();

  static String newUid() => _uuid.v4();

  String uid;
  String label;
  DateTime target;

  /// When true, a notification fires once when the timer reaches zero.
  bool notifyOnZero;

  /// Master switch for [milestones]. When false the configured milestones are
  /// kept but nothing fires.
  bool notifyRoundNumbers;

  /// Per-timer notification thresholds. Each entry fires when the timer passes
  /// that far before and/or after the target — see [CountdownMilestone].
  List<CountdownMilestone> milestones;

  /// When the timer was first created and last edited — used for sorting.
  DateTime createdAt;
  DateTime editedAt;

  CountdownTimerItem({
    String? uid,
    required this.label,
    required this.target,
    this.notifyOnZero = false,
    this.notifyRoundNumbers = false,
    List<CountdownMilestone>? milestones,
    DateTime? createdAt,
    DateTime? editedAt,
  })  : uid = uid ?? CountdownTimerItem.newUid(),
        milestones = milestones ?? defaultMilestones(),
        createdAt = createdAt ?? DateTime.now(),
        editedAt = editedAt ?? createdAt ?? DateTime.now();

  /// The milestones a new timer starts with: 10 of each large calendar unit,
  /// plus three round raw-count thresholds. Listed longest-first — note that
  /// 10,000,000 seconds (~115.7 days) outranks 10 weeks (70 days).
  static List<CountdownMilestone> defaultMilestones() => [
        CountdownMilestone(value: 10, unit: MilestoneUnit.years),
        CountdownMilestone(value: 10, unit: MilestoneUnit.months),
        CountdownMilestone(value: 10000000, unit: MilestoneUnit.seconds),
        CountdownMilestone(value: 10, unit: MilestoneUnit.weeks),
        CountdownMilestone(value: 100000, unit: MilestoneUnit.minutes),
        CountdownMilestone(value: 1000, unit: MilestoneUnit.hours),
        CountdownMilestone(value: 10, unit: MilestoneUnit.days),
      ];

  factory CountdownTimerItem.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String)
        : null;
    final edited = json['editedAt'] != null
        ? DateTime.tryParse(json['editedAt'] as String)
        : null;
    // Timers saved before milestones were configurable carry no list; give them
    // the defaults so an already-enabled bell keeps notifying.
    final rawMilestones = json['milestones'];
    final milestones = rawMilestones is List
        ? rawMilestones
            .whereType<Map>()
            .map((e) =>
                CountdownMilestone.fromJson(Map<String, dynamic>.from(e)))
            .where((m) => m.value > 0)
            .toList()
        : defaultMilestones();
    return CountdownTimerItem(
      uid: json['uid'] as String?,
      label: json['label'] as String? ?? '',
      target: DateTime.parse(json['target'] as String),
      notifyOnZero: json['notifyOnZero'] as bool? ?? false,
      notifyRoundNumbers: json['notifyRoundNumbers'] as bool? ?? false,
      milestones: milestones,
      createdAt: created,
      editedAt: edited,
    );
  }

  /// [milestones] ordered longest-first, the order they're shown and (for
  /// before-side milestones) the order they fire in.
  List<CountdownMilestone> get sortedMilestones {
    final sorted = [...milestones];
    sorted.sort((a, b) => b.approximateSeconds.compareTo(a.approximateSeconds));
    return sorted;
  }

  /// The milestone that came due in the half-open window `(previousNow, now]`,
  /// or null when none did.
  ///
  /// Each milestone contributes up to two instants (`target - value` before,
  /// `target + value` after); one is "due" when it lies in the window. When the
  /// window spans several — the app was backgrounded, or the clock jumped —
  /// only the most recent is reported, so reopening the app after a long gap
  /// produces one notification rather than a burst.
  MilestoneHit? dueMilestone({
    required DateTime previousNow,
    required DateTime now,
  }) {
    MilestoneHit? latest;
    void consider(DateTime? instant, CountdownMilestone m, bool isAfter) {
      if (instant == null) return;
      if (!instant.isAfter(previousNow)) return;
      if (instant.isAfter(now)) return;
      if (latest == null || instant.isAfter(latest!.instant)) {
        latest = MilestoneHit(milestone: m, isAfter: isAfter, instant: instant);
      }
    }

    for (final m in milestones) {
      if (m.value <= 0) continue;
      consider(m.beforeInstant(target), m, false);
      consider(m.afterInstant(target), m, true);
    }
    return latest;
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'label': label,
        'target': target.toIso8601String(),
        'notifyOnZero': notifyOnZero,
        'notifyRoundNumbers': notifyRoundNumbers,
        'milestones': milestones.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'editedAt': editedAt.toIso8601String(),
      };
}
