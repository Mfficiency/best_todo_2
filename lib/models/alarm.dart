import 'package:uuid/uuid.dart';

import '../utils/label_utils.dart';

/// Available built-in melodies an alarm can play. The strings are stored in
/// JSON, so keep them stable once shipped.
const List<String> kAlarmMelodies = [
  'Classic',
  'Chimes',
  'Radar',
  'Beacon',
  'Bells',
  'Digital',
  'Marimba',
];

/// A small palette of colours an alarm can be tagged with. Stored as ARGB
/// integers so they round-trip cleanly through JSON.
const List<int> kAlarmColors = [
  0xFF005FDD, // primary blue
  0xFFE53935, // red
  0xFFFB8C00, // orange
  0xFF43A047, // green
  0xFF8E24AA, // purple
  0xFF00897B, // teal
  0xFFFDD835, // yellow
  0xFF6D4C41, // brown
];

/// Required tag carried by every alarm so Settings -> Filtering rules can
/// match alarms through the stored tag string.
const String kAlarmRequiredTag = 'alarm';

/// A single alarm with all of its configuration.
class Alarm {
  static final Uuid _uuid = const Uuid();

  static String newUid() => _uuid.v4();

  static String ensureAlarmTag(String tags) =>
      addLabelToken(tags, kAlarmRequiredTag);

  String uid;

  /// Human readable name shown in the list and the widget.
  String name;

  /// Optional longer description.
  String description;

  /// Playback volume in the 0.0 - 1.0 range.
  double volume;

  /// Name of the melody to play, see [kAlarmMelodies].
  String melody;

  /// Whether the device should vibrate when the alarm fires.
  bool vibrate;

  /// When true the alarm rings at [volume] even while the phone is in
  /// Do Not Disturb / silent mode or the alarm stream is turned down.
  bool overrideDnd;

  /// Hour of day (0-23) the alarm fires.
  int hour;

  /// Minute of the hour (0-59) the alarm fires.
  int minute;

  /// Specific date for a one-off alarm. Ignored when [isRepeating] is true.
  DateTime? date;

  /// Whether the alarm repeats on the days in [repeatDays].
  bool isRepeating;

  /// Weekdays the alarm repeats on, using [DateTime.monday] (1) .. (7).
  List<int> repeatDays;

  /// ARGB colour used to tag the alarm.
  int color;

  /// Whether the alarm can be snoozed.
  bool snoozeEnabled;

  /// Snooze length in minutes.
  int snoozeDurationMinutes;

  /// Maximum number of times the alarm can be snoozed.
  int snoozeMaxCount;

  /// Whether the alarm is currently active (the on/off toggle).
  bool enabled;

  /// Uid of the task this alarm is a reminder for, or null for a standalone
  /// clock alarm (every alarm that existed before 0.1.110). Linked alarms are
  /// kept in sync by `ReminderSyncService`: their [date]/[hour]/[minute] are
  /// rewritten from the task's schedule whenever the task list is saved, so
  /// the scheduling pipeline below this model stays completely unchanged.
  String? itemUid;

  /// Which end of the task's interval the reminder anchors to.
  static const String anchorStart = 'start';
  static const String anchorEnd = 'end';

  /// Only meaningful when [itemUid] is set: [anchorStart] or [anchorEnd].
  String triggerAnchor;

  /// Only meaningful when [itemUid] is set: minutes relative to the anchor
  /// (negative = before, e.g. -15 for "15 minutes before").
  int triggerOffsetMinutes;

  /// Tags (comma/whitespace-separated, same convention as [Task.label]).
  /// Every alarm carries [kAlarmRequiredTag] plus any user categorization
  /// (e.g. "work", "medication") so Settings -> Filtering rules can match
  /// the Alarms view's own reserved tag through the stored tag string.
  String tags;

  Alarm({
    String? uid,
    required this.name,
    this.description = '',
    this.volume = 0.8,
    this.melody = 'Classic',
    this.vibrate = true,
    this.overrideDnd = false,
    this.hour = 8,
    this.minute = 0,
    this.date,
    this.isRepeating = false,
    List<int>? repeatDays,
    this.color = 0xFF005FDD,
    this.snoozeEnabled = true,
    this.snoozeDurationMinutes = 9,
    this.snoozeMaxCount = 3,
    this.enabled = true,
    this.itemUid,
    this.triggerAnchor = anchorEnd,
    this.triggerOffsetMinutes = 0,
    String tags = kAlarmRequiredTag,
  })  : uid = uid ?? Alarm.newUid(),
        repeatDays = repeatDays ?? <int>[],
        tags = ensureAlarmTag(tags);

  /// Two digit `HH:mm` representation of the alarm time.
  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Short human readable summary of when the alarm fires.
  String get scheduleLabel {
    if (isRepeating) {
      if (repeatDays.isEmpty) return 'Repeats';
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final sorted = [...repeatDays]..sort();
      if (sorted.length == 7) return 'Every day';
      if (sorted.length == 5 &&
          sorted.every((d) => d >= DateTime.monday && d <= DateTime.friday)) {
        return 'Weekdays';
      }
      if (sorted.length == 2 &&
          sorted.contains(DateTime.saturday) &&
          sorted.contains(DateTime.sunday)) {
        return 'Weekends';
      }
      return sorted.map((d) => names[d - 1]).join(', ');
    }
    if (date != null) {
      final d = date!;
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    return 'Once';
  }

  /// The next time this alarm should fire from [from], or null when it has no
  /// future occurrence (a one-off alarm whose date/time has passed).
  DateTime? nextOccurrence([DateTime? from]) {
    final now = from ?? DateTime.now();
    if (isRepeating) {
      if (repeatDays.isEmpty) return null;
      for (var i = 0; i < 8; i++) {
        final day = DateTime(now.year, now.month, now.day + i, hour, minute);
        if (repeatDays.contains(day.weekday) && day.isAfter(now)) {
          return day;
        }
      }
      return null;
    }
    if (date != null) {
      final fire = DateTime(date!.year, date!.month, date!.day, hour, minute);
      return fire.isAfter(now) ? fire : null;
    }
    // One-off with no explicit date: today if still ahead, otherwise tomorrow.
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    if (today.isAfter(now)) return today;
    return today.add(const Duration(days: 1));
  }

  factory Alarm.fromJson(Map<String, dynamic> json) {
    return Alarm(
      uid: json['uid'] as String?,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      volume: (json['volume'] as num?)?.toDouble() ?? 0.8,
      melody: json['melody'] as String? ?? 'Classic',
      vibrate: json['vibrate'] as bool? ?? true,
      overrideDnd: json['overrideDnd'] as bool? ?? false,
      hour: json['hour'] as int? ?? 8,
      minute: json['minute'] as int? ?? 0,
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String)
          : null,
      isRepeating: json['isRepeating'] as bool? ?? false,
      repeatDays: (json['repeatDays'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          <int>[],
      color: json['color'] as int? ?? 0xFF005FDD,
      snoozeEnabled: json['snoozeEnabled'] as bool? ?? true,
      snoozeDurationMinutes: json['snoozeDurationMinutes'] as int? ?? 9,
      snoozeMaxCount: json['snoozeMaxCount'] as int? ?? 3,
      enabled: json['enabled'] as bool? ?? true,
      itemUid: json['itemUid'] as String?,
      triggerAnchor: json['triggerAnchor'] as String? ?? anchorEnd,
      triggerOffsetMinutes: json['triggerOffsetMinutes'] as int? ?? 0,
      tags: json['tags'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'description': description,
        'volume': volume,
        'melody': melody,
        'vibrate': vibrate,
        'overrideDnd': overrideDnd,
        'hour': hour,
        'minute': minute,
        'date': date?.toIso8601String(),
        'isRepeating': isRepeating,
        'repeatDays': repeatDays,
        'color': color,
        'snoozeEnabled': snoozeEnabled,
        'snoozeDurationMinutes': snoozeDurationMinutes,
        'snoozeMaxCount': snoozeMaxCount,
        'enabled': enabled,
        // Reminder link: omitted for standalone alarms.
        if (itemUid != null) 'itemUid': itemUid,
        if (itemUid != null) 'triggerAnchor': triggerAnchor,
        if (itemUid != null) 'triggerOffsetMinutes': triggerOffsetMinutes,
        'tags': ensureAlarmTag(tags),
      };

  Alarm copy() => Alarm.fromJson(toJson());
}
