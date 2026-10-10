/// Units a countdown milestone can be expressed in. Seconds through weeks are
/// fixed-length; months and years are calendar-based (so "10 months before"
/// lands on the same day-of-month, not 304.375 days out).
enum MilestoneUnit { seconds, minutes, hours, days, weeks, months, years }

/// Which side(s) of the target a milestone fires on: while counting down to it
/// ([before]), while counting up from it ([after]), or both.
enum MilestoneDirection { before, after, both }

/// One user-configured notification threshold on a countdown timer, e.g.
/// "10 days, both sides" or "1,000,000 seconds, before only".
///
/// A milestone doesn't describe a span of remaining time so much as a pair of
/// *instants* relative to the timer's target — `target - value` on the before
/// side and `target + value` on the after side. Resolving to instants (rather
/// than comparing second counts) is what lets months and years follow the
/// calendar and makes the two directions symmetric.
class CountdownMilestone {
  int value;
  MilestoneUnit unit;
  MilestoneDirection direction;

  CountdownMilestone({
    required this.value,
    required this.unit,
    this.direction = MilestoneDirection.both,
  });

  bool get firesBefore => direction != MilestoneDirection.after;
  bool get firesAfter => direction != MilestoneDirection.before;

  /// The instant this milestone fires at while counting down to [target], or
  /// null when it is an after-only milestone.
  DateTime? beforeInstant(DateTime target) =>
      firesBefore ? shift(target, unit, -value) : null;

  /// The instant this milestone fires at while counting up from [target], or
  /// null when it is a before-only milestone.
  DateTime? afterInstant(DateTime target) =>
      firesAfter ? shift(target, unit, value) : null;

  /// [from] moved by [amount] of [unit] (negative moves back). Seconds through
  /// weeks add a fixed [Duration]; months and years walk the calendar, clamping
  /// the day into the target month (31 Jan − 1 month → 31 Dec, 31 Mar − 1 month
  /// → 28/29 Feb).
  static DateTime shift(DateTime from, MilestoneUnit unit, int amount) {
    switch (unit) {
      case MilestoneUnit.seconds:
        return from.add(Duration(seconds: amount));
      case MilestoneUnit.minutes:
        return from.add(Duration(minutes: amount));
      case MilestoneUnit.hours:
        return from.add(Duration(hours: amount));
      case MilestoneUnit.days:
        return from.add(Duration(days: amount));
      case MilestoneUnit.weeks:
        return from.add(Duration(days: amount * 7));
      case MilestoneUnit.months:
        return addMonths(from, amount);
      case MilestoneUnit.years:
        return addMonths(from, amount * 12);
    }
  }

  /// [d] moved by [months] calendar months, clamping the day-of-month to the
  /// last valid day of the resulting month.
  static DateTime addMonths(DateTime d, int months) {
    final total = d.year * 12 + (d.month - 1) + months;
    final year = (total / 12).floor();
    final month = total - year * 12 + 1;
    // Day 0 of the following month is the last day of this one.
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = d.day > lastDay ? lastDay : d.day;
    return DateTime(year, month, day, d.hour, d.minute, d.second);
  }

  /// Approximate length in seconds, used only to order milestones for display.
  /// Months/years use average lengths — exact placement always goes through
  /// [shift] against a real target.
  int get approximateSeconds {
    switch (unit) {
      case MilestoneUnit.seconds:
        return value;
      case MilestoneUnit.minutes:
        return value * 60;
      case MilestoneUnit.hours:
        return value * 3600;
      case MilestoneUnit.days:
        return value * 86400;
      case MilestoneUnit.weeks:
        return value * 604800;
      case MilestoneUnit.months:
        return (value * 2629800.0).round();
      case MilestoneUnit.years:
        return (value * 31557600.0).round();
    }
  }

  static String unitName(MilestoneUnit unit, {required bool plural}) {
    final singular = switch (unit) {
      MilestoneUnit.seconds => 'second',
      MilestoneUnit.minutes => 'minute',
      MilestoneUnit.hours => 'hour',
      MilestoneUnit.days => 'day',
      MilestoneUnit.weeks => 'week',
      MilestoneUnit.months => 'month',
      MilestoneUnit.years => 'year',
    };
    return plural ? '${singular}s' : singular;
  }

  /// e.g. "10 days", "1 hour", "10,000,000 seconds".
  String get label =>
      '${formatThousands(value)} ${unitName(unit, plural: value != 1)}';

  /// Short direction tag for the milestone list, e.g. "before & after".
  String get directionLabel => switch (direction) {
        MilestoneDirection.before => 'before',
        MilestoneDirection.after => 'after',
        MilestoneDirection.both => 'before & after',
      };

  /// Groups digits with commas: 10000000 → "10,000,000".
  static String formatThousands(int n) {
    final s = n.abs().toString();
    final b = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  CountdownMilestone copy() =>
      CountdownMilestone(value: value, unit: unit, direction: direction);

  /// Two milestones are duplicates when they'd fire at the same instants.
  bool sameAs(CountdownMilestone other) =>
      value == other.value && unit == other.unit;

  factory CountdownMilestone.fromJson(Map<String, dynamic> json) {
    return CountdownMilestone(
      value: (json['value'] as num?)?.toInt() ?? 0,
      unit: _unitFrom(json['unit'] as String?),
      direction: _directionFrom(json['direction'] as String?),
    );
  }

  static MilestoneUnit _unitFrom(String? name) => MilestoneUnit.values
      .firstWhere((u) => u.name == name, orElse: () => MilestoneUnit.seconds);

  static MilestoneDirection _directionFrom(String? name) =>
      MilestoneDirection.values.firstWhere(
        (d) => d.name == name,
        orElse: () => MilestoneDirection.both,
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'unit': unit.name,
        'direction': direction.name,
      };
}

/// A milestone that came due: which milestone, which side of the target it
/// fired on, and the exact instant it fired at.
class MilestoneHit {
  final CountdownMilestone milestone;
  final bool isAfter;
  final DateTime instant;

  const MilestoneHit({
    required this.milestone,
    required this.isAfter,
    required this.instant,
  });

  /// Notification body, e.g. "10 days to go" / "10 days since".
  String get message =>
      '${milestone.label} ${isAfter ? 'since' : 'to go'}';
}
