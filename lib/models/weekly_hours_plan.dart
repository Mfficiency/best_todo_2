/// One work session within a day, expressed in minutes since midnight.
class WorkBlock {
  final int startMinutes;
  final int endMinutes;

  const WorkBlock({required this.startMinutes, required this.endMinutes});

  int get durationMinutes => endMinutes - startMinutes;

  WorkBlock copyWith({int? startMinutes, int? endMinutes}) => WorkBlock(
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
      );

  factory WorkBlock.fromJson(Map<String, dynamic> json) => WorkBlock(
        startMinutes: (json['start'] as num?)?.round() ?? 0,
        endMinutes: (json['end'] as num?)?.round() ?? 0,
      );

  Map<String, dynamic> toJson() => {'start': startMinutes, 'end': endMinutes};
}

/// One weekday's plan: a morning block and an afternoon block, with lunch
/// simply being whatever gap sits between them.
class DayPlan {
  final WorkBlock morning;
  final WorkBlock afternoon;

  const DayPlan({required this.morning, required this.afternoon});

  int get lunchMinutes => afternoon.startMinutes - morning.endMinutes;

  int get workedMinutes => morning.durationMinutes + afternoon.durationMinutes;

  DayPlan copyWith({WorkBlock? morning, WorkBlock? afternoon}) => DayPlan(
        morning: morning ?? this.morning,
        afternoon: afternoon ?? this.afternoon,
      );

  factory DayPlan.fromJson(Map<String, dynamic> json) => DayPlan(
        morning: WorkBlock.fromJson(
            Map<String, dynamic>.from(json['morning'] as Map? ?? {})),
        afternoon: WorkBlock.fromJson(
            Map<String, dynamic>.from(json['afternoon'] as Map? ?? {})),
      );

  Map<String, dynamic> toJson() => {
        'morning': morning.toJson(),
        'afternoon': afternoon.toJson(),
      };

  /// The default 8:36 day: a 9:00 start, an even split around a 30-minute
  /// lunch break, ending at 18:06 (9:00 + 8:36 worked + 0:30 lunch).
  static DayPlan defaultPlan() {
    const dayStart = 9 * 60;
    final half = WeeklyHoursPlan.targetMinutesPerDay ~/ 2;
    return DayPlan(
      morning: WorkBlock(startMinutes: dayStart, endMinutes: dayStart + half),
      afternoon: WorkBlock(
        startMinutes: dayStart + half + WeeklyHoursPlan.lunchMinutes,
        endMinutes: dayStart +
            WeeklyHoursPlan.targetMinutesPerDay +
            WeeklyHoursPlan.lunchMinutes,
      ),
    );
  }
}

/// A Monday-to-Friday plan of two work blocks per day, used by the Weekly
/// Hours Planner tool. Each day nominally works [targetMinutesPerDay]
/// (8 hours 36 minutes) split around a half-hour lunch break, for a
/// 43-hour working week — the standard flexitime target this tool is built
/// around. Dragging a block's start or end on any day away from that default
/// creates a surplus or deficit that [theoreticalFridayEndMinutes] carries
/// forward onto Friday, so the week still totals 43 hours.
class WeeklyHoursPlan {
  static const int targetMinutesPerDay = 8 * 60 + 36;
  static const int lunchMinutes = 30;
  static const List<String> weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
  ];

  /// Monday (index 0) through Friday (index 4).
  final List<DayPlan> days;

  const WeeklyHoursPlan({required this.days});

  static WeeklyHoursPlan defaultPlan() => WeeklyHoursPlan(
        days: List.generate(weekdayNames.length, (_) => DayPlan.defaultPlan()),
      );

  factory WeeklyHoursPlan.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    final parsed = <DayPlan>[];
    if (rawDays is List) {
      for (final entry in rawDays) {
        if (entry is Map) {
          parsed.add(DayPlan.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }
    while (parsed.length < weekdayNames.length) {
      parsed.add(DayPlan.defaultPlan());
    }
    return WeeklyHoursPlan(days: parsed.take(weekdayNames.length).toList());
  }

  Map<String, dynamic> toJson() =>
      {'days': days.map((d) => d.toJson()).toList()};

  WeeklyHoursPlan withDay(int index, DayPlan day) {
    final next = [...days];
    next[index] = day;
    return WeeklyHoursPlan(days: next);
  }

  int get targetWeeklyMinutes => targetMinutesPerDay * days.length;

  int get plannedWeeklyMinutes =>
      days.fold<int>(0, (sum, d) => sum + d.workedMinutes);

  /// Total surplus (positive) or deficit (negative) minutes worked on
  /// Monday-Thursday relative to the 8:36 default, which Friday must absorb
  /// to keep the week at [targetWeeklyMinutes].
  int get carryoverBeforeFriday {
    var sum = 0;
    for (var i = 0; i < days.length - 1; i++) {
      sum += days[i].workedMinutes - targetMinutesPerDay;
    }
    return sum;
  }

  /// The Friday clock-out time (minutes since midnight) needed to make the
  /// whole week hit [targetWeeklyMinutes], holding Friday's own start time
  /// and lunch gap fixed and only accounting for the total minutes worked.
  int get theoreticalFridayEndMinutes {
    final friday = days.last;
    final neededFridayMinutes = targetWeeklyMinutes -
        days
            .take(days.length - 1)
            .fold<int>(0, (sum, d) => sum + d.workedMinutes);
    return friday.morning.startMinutes +
        friday.lunchMinutes +
        neededFridayMinutes;
  }
}

/// A manual, per-calendar-week record of actual over/undertime, on top of
/// the block-edited [WeeklyHoursPlan] template (which stays a single
/// reusable "typical week" — it has no date of its own). Keyed by the Monday
/// of the week it applies to, so the Weekly Hours Planner's week navigation
/// can show/edit a different value for each week you look at.
class WeeklyActual {
  /// Monday of the week this record is for, normalized to midnight.
  final DateTime weekStart;

  /// Signed minutes: positive means more was actually worked than the
  /// template planned, negative means less.
  final int overUndertimeMinutes;

  WeeklyActual({required DateTime weekStart, this.overUndertimeMinutes = 0})
      : weekStart = mondayOf(weekStart);

  /// Normalizes any date to the Monday of its week, at midnight.
  static DateTime mondayOf(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  /// Stable per-week key used to persist and look up records, `yyyy-MM-dd`
  /// of the Monday.
  String get weekKey => '${weekStart.year.toString().padLeft(4, '0')}-'
      '${weekStart.month.toString().padLeft(2, '0')}-'
      '${weekStart.day.toString().padLeft(2, '0')}';

  WeeklyActual copyWith({int? overUndertimeMinutes}) => WeeklyActual(
        weekStart: weekStart,
        overUndertimeMinutes:
            overUndertimeMinutes ?? this.overUndertimeMinutes,
      );

  factory WeeklyActual.fromJson(Map<String, dynamic> json) => WeeklyActual(
        weekStart: DateTime.tryParse(json['weekStart'] as String? ?? '') ??
            DateTime.now(),
        overUndertimeMinutes:
            (json['overUndertimeMinutes'] as num?)?.round() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'weekStart': weekStart.toIso8601String(),
        'overUndertimeMinutes': overUndertimeMinutes,
      };
}
