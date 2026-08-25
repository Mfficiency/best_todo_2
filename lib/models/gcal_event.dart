/// One calendar event as displayed on the Weekly Hours Planner: a concrete
/// occurrence (a recurring event is expanded into one of these per instance).
class GCalEvent {
  final String uid;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  const GCalEvent({
    required this.uid,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
  });
}

/// One VEVENT as parsed from an imported .ics feed, kept in its raw
/// (unexpanded) form so a recurring event can be re-expanded for whatever
/// date range is being shown. Cached to disk so the app has something to
/// show before the next refresh completes.
class GCalRawEvent {
  final String uid;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? rrule;
  final List<DateTime> exdates;

  const GCalRawEvent({
    required this.uid,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.rrule,
    this.exdates = const [],
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'title': title,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'allDay': allDay,
        if (rrule != null) 'rrule': rrule,
        if (exdates.isNotEmpty)
          'exdates': [for (final d in exdates) d.toIso8601String()],
      };

  factory GCalRawEvent.fromJson(Map<String, dynamic> json) => GCalRawEvent(
        uid: json['uid'] as String? ?? '',
        title: json['title'] as String? ?? '',
        start: DateTime.parse(json['start'] as String),
        end: DateTime.parse(json['end'] as String),
        allDay: json['allDay'] as bool? ?? false,
        rrule: json['rrule'] as String?,
        exdates: [
          for (final d in (json['exdates'] as List? ?? const []))
            DateTime.parse(d as String),
        ],
      );
}
