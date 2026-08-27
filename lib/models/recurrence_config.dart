import 'task.dart';

/// A recurrence rule detached from any particular [Task] — used by the
/// "Repeat" picker at creation time (before a task exists to hang the rule
/// off of) and shared by the inline editor for an existing series. Applying
/// it (via [applyTo]) writes the same fields [Task] itself persists, so a
/// config built here and one read back off a master always compare equal in
/// meaning.
class RecurrenceConfig {
  static const frequencies = ['daily', 'weekly', 'monthly', 'yearly'];
  static const endTypes = ['never', 'date', 'count'];

  String frequency;
  int interval;

  /// Weekly only, 1=Monday..7=Sunday. Empty means "just the anchor's
  /// weekday".
  List<int> weekdays;

  String endType;
  DateTime? endDate;
  int? occurrenceCount;

  RecurrenceConfig({
    this.frequency = 'daily',
    this.interval = 1,
    List<int>? weekdays,
    this.endType = 'never',
    this.endDate,
    this.occurrenceCount,
  }) : weekdays = weekdays ?? [];

  factory RecurrenceConfig.fromTask(Task task) => RecurrenceConfig(
        frequency: task.recurrenceFrequency,
        interval: task.recurrenceInterval,
        weekdays: List.of(task.recurrenceWeekdays),
        endType: task.recurrenceEndType,
        endDate: task.recurrenceEndDate,
        occurrenceCount: task.recurrenceOccurrenceCount,
      );

  RecurrenceConfig copyWith({
    String? frequency,
    int? interval,
    List<int>? weekdays,
    String? endType,
    DateTime? endDate,
    bool clearEndDate = false,
    int? occurrenceCount,
    bool clearOccurrenceCount = false,
  }) {
    return RecurrenceConfig(
      frequency: frequency ?? this.frequency,
      interval: interval ?? this.interval,
      weekdays: weekdays ?? List.of(this.weekdays),
      endType: endType ?? this.endType,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      occurrenceCount: clearOccurrenceCount
          ? null
          : (occurrenceCount ?? this.occurrenceCount),
    );
  }

  void applyTo(Task task) {
    task.recurrenceFrequency = frequency;
    task.recurrenceInterval = interval < 1 ? 1 : interval;
    task.recurrenceWeekdays = List.of(weekdays);
    task.recurrenceEndType = endType;
    task.recurrenceEndDate = endType == 'date' ? endDate : null;
    task.recurrenceOccurrenceCount =
        endType == 'count' ? occurrenceCount : null;
  }
}
