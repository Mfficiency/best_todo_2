/// One race (or sprint) on the F1 Reminder calendar. [start] is in the
/// phone's local time — the dates were entered as the user's own clock time.
class F1Race {
  final String name;
  final DateTime start;

  const F1Race(this.name, this.start);

  /// Stable id used to remember which races already got their text.
  String get key => start.toIso8601String();
}

/// How long before lights-out the reminder text goes out.
const Duration kF1ReminderLead = Duration(hours: 4);

/// A reminder whose send time was missed (phone off, alarm deferred) is still
/// sent late — with an honest countdown — unless the race is closer than this.
const Duration kF1LateSendCutoff = Duration(minutes: 30);

/// The rest of the 2026 season, as local (CET/CEST) start times.
final List<F1Race> kF1Races = [
  F1Race('Singapore GP Sprint', DateTime(2026, 10, 10, 11, 0)),
  F1Race('Singapore GP', DateTime(2026, 10, 11, 14, 0)),
  F1Race('United States GP', DateTime(2026, 10, 25, 21, 0)),
  F1Race('Mexico City GP', DateTime(2026, 11, 1, 21, 0)),
  F1Race('Brazilian GP', DateTime(2026, 11, 8, 18, 0)),
  F1Race('Las Vegas GP', DateTime(2026, 11, 22, 5, 0)),
  F1Race('Qatar GP', DateTime(2026, 11, 29, 17, 0)),
  F1Race('Abu Dhabi GP', DateTime(2026, 12, 6, 14, 0)),
];

/// Template tokens (both templates):
///   {race}       -> race name, e.g. "Brazilian GP"
///   {time}       -> start time, e.g. "18:00"
///   {date}       -> start date, e.g. "Sunday 8 November"
///   {countdown}  -> time left until lights out, e.g. "4 hours"
const String kDefaultF1Template =
    '🏎️ Lights out in {countdown}! The {race} starts at {time}. '
    'Grab the snacks and get comfy — see you on the grid! 🏁';

const String kDefaultF1WelcomeTemplate =
    'Welcome to F1 race reminders! 🏎️ From now on you\'ll get a text '
    '4 hours before every race of the season. '
    'First up: the {race}, {date} at {time}.';

/// One sent (or failed) text, shown in the tool's "Recent texts" list.
class F1SendRecord {
  final DateTime at;
  final String message;
  final bool success;
  final String? error;

  const F1SendRecord({
    required this.at,
    required this.message,
    required this.success,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'message': message,
        'success': success,
        if (error != null) 'error': error,
      };

  factory F1SendRecord.fromJson(Map<String, dynamic> json) => F1SendRecord(
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime(2000),
        message: json['message'] as String? ?? '',
        success: json['success'] as bool? ?? false,
        error: json['error'] as String?,
      );
}

class F1ReminderConfig {
  bool enabled;
  String phoneNumber;
  String template;

  /// [F1Race.key]s whose reminder was already handled (sent, or attempted —
  /// a failed send is not retried, so a broken number can't spam retries).
  Set<String> handledRaces;

  /// Newest last, capped at [maxHistory].
  List<F1SendRecord> history;

  static const int maxHistory = 50;

  F1ReminderConfig({
    this.enabled = false,
    this.phoneNumber = '',
    this.template = kDefaultF1Template,
    Set<String>? handledRaces,
    List<F1SendRecord>? history,
  })  : handledRaces = handledRaces ?? <String>{},
        history = history ?? <F1SendRecord>[];

  void addHistory(F1SendRecord record) {
    history.add(record);
    if (history.length > maxHistory) {
      history.removeRange(0, history.length - maxHistory);
    }
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'phoneNumber': phoneNumber,
        'template': template,
        'handledRaces': handledRaces.toList(),
        'history': history.map((h) => h.toJson()).toList(),
      };

  factory F1ReminderConfig.fromJson(Map<String, dynamic> json) {
    final template = json['template'] as String?;
    return F1ReminderConfig(
      enabled: json['enabled'] as bool? ?? false,
      phoneNumber: json['phoneNumber'] as String? ?? '',
      template: (template == null || template.trim().isEmpty)
          ? kDefaultF1Template
          : template,
      handledRaces: {
        for (final k in (json['handledRaces'] as List? ?? const []))
          if (k is String) k,
      },
      history: [
        for (final h in (json['history'] as List? ?? const []))
          if (h is Map) F1SendRecord.fromJson(Map<String, dynamic>.from(h)),
      ],
    );
  }
}
