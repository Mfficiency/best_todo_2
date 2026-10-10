/// How a streak reminder announces itself. The keys are persisted, so keep
/// them stable.
enum StreakAlertMode {
  /// A plain notification on a silent channel — no sound, no vibration.
  notification('notification', 'Silent notification'),

  /// Sound and vibration, like a task notification.
  sound('sound', 'Sound & vibration');

  const StreakAlertMode(this.id, this.label);

  final String id;
  final String label;

  static StreakAlertMode fromId(String? id) =>
      StreakAlertMode.values.firstWhere((mode) => mode.id == id,
          orElse: () => StreakAlertMode.notification);
}

/// One "keep your streak alive" reminder: a time of day, an alert mode and an
/// on/off switch. The user can have as many as [maxStreakReminders] of them.
class StreakReminder {
  /// Time of day in minutes since midnight (0..1439).
  int minutes;

  /// Off keeps the entry in the list without scheduling it.
  bool enabled;

  StreakAlertMode mode;

  StreakReminder({
    required this.minutes,
    this.enabled = true,
    this.mode = StreakAlertMode.notification,
  });

  Map<String, dynamic> toJson() => {
        'minutes': minutes,
        'enabled': enabled,
        'mode': mode.id,
      };

  factory StreakReminder.fromJson(Map<String, dynamic> json) => StreakReminder(
        minutes: ((json['minutes'] as num?)?.round() ?? 0).clamp(0, 1439),
        enabled: json['enabled'] as bool? ?? true,
        mode: StreakAlertMode.fromId(json['mode'] as String?),
      );

  StreakReminder copy() =>
      StreakReminder(minutes: minutes, enabled: enabled, mode: mode);
}

/// Upper bound on the reminder list: every reminder occupies one fixed
/// notification id slot (see `alarm_ids.dart`).
const int maxStreakReminders = 24;
