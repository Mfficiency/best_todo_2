import 'dart:io';

import '../models/alarm.dart';
import '../models/countdown_timer.dart';
import '../models/daily_task_stats.dart';
import '../models/sms_report_log_entry.dart';
import '../models/task.dart';
import 'startup_time_service.dart';

/// One entry in the unified usage timeline: something that happened at a
/// known moment, no matter which subsystem recorded it (tasks, alarms, SMS
/// reports, app launches, countdown timers).
class UsageEvent {
  final DateTime at;

  /// Which subsystem produced the event: `task`, `alarm`, `sms`, `app`,
  /// `timer`.
  final String source;

  /// What happened, e.g. `created`, `completed`, `FIRE`, `report_sent`,
  /// `app_open`.
  final String type;

  final String itemId;
  final String itemTitle;
  final String detail;

  const UsageEvent({
    required this.at,
    required this.source,
    required this.type,
    this.itemId = '',
    this.itemTitle = '',
    this.detail = '',
  });
}

/// A named CSV table ready to be previewed or written to disk. [rows]
/// includes the header row.
class UsageCsvDataset {
  final String id;
  final String title;
  final String description;
  final List<List<Object?>> rows;
  final DateTime? earliest;
  final DateTime? latest;

  const UsageCsvDataset({
    required this.id,
    required this.title,
    required this.description,
    required this.rows,
    this.earliest,
    this.latest,
  });

  int get recordCount => rows.isEmpty ? 0 : rows.length - 1;

  String get fileName => '$id.csv';

  String toCsv() => UsageDataService.toCsv(rows);
}

/// Builds detailed, machine-readable CSV exports of everything the app has
/// ever recorded — the "Digital Wellbeing" style data dump for BestToDo.
///
/// All build methods are pure (data in, dataset out) so they can be unit
/// tested without touching the filesystem; only [writeDatasets] does IO.
class UsageDataService {
  UsageDataService._();

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  // ---------------------------------------------------------------------
  // CSV primitives (RFC 4180: comma separated, CRLF, quote-escaped)
  // ---------------------------------------------------------------------

  static String csvField(Object? value) {
    if (value == null) return '';
    String text;
    if (value is DateTime) {
      text = value.toIso8601String();
    } else if (value is double) {
      // Avoid noise like 3.3333333333: two decimals is plenty for durations
      // and rates while staying spreadsheet-friendly.
      text = value == value.roundToDouble()
          ? value.toStringAsFixed(1)
          : value.toStringAsFixed(2);
    } else {
      text = value.toString();
    }
    if (text.contains(',') ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }

  static String toCsv(List<List<Object?>> rows) {
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer.write(row.map(csvField).join(','));
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------
  // Small date helpers
  // ---------------------------------------------------------------------

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String dayKey(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)}';

  static String _timeOfDay(DateTime d) =>
      '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';

  static String _weekdayName(DateTime d) => _weekdays[d.weekday - 1];

  // ---------------------------------------------------------------------
  // Event derivation, one method per subsystem
  // ---------------------------------------------------------------------

  /// Every dated moment in a task's lifecycle, across active and deleted
  /// tasks. Deleted tasks are the app's long-term memory, so this reaches as
  /// far back as the app has data.
  static List<UsageEvent> taskEvents(
      List<Task> tasks, List<Task> deletedTasks) {
    final events = <UsageEvent>[];
    void addFor(Task task, bool isDeletedList) {
      void add(String type, DateTime? at, [String detail = '']) {
        if (at == null) return;
        events.add(UsageEvent(
          at: at,
          source: 'task',
          type: type,
          itemId: task.uid,
          itemTitle: task.title,
          detail: detail,
        ));
      }

      final due = task.dueDate?.toIso8601String() ?? '';
      add('created', task.createdAt,
          task.label.isEmpty ? '' : 'label=${task.label}');
      add('moved', task.movedAt, due.isEmpty ? '' : 'to_due_date=$due');
      add('rescheduled', task.rescheduledAt,
          due.isEmpty ? '' : 'to_due_date=$due');
      add('completed', task.completedAt);
      add('deleted', task.deletedAt,
          task.autoDeleted ? 'auto_deleted' : 'deleted_by_user');
      if (!isDeletedList &&
          task.deletedAt == null &&
          task.completedAt != null &&
          !task.isDone) {
        add('restored', task.completedAt);
      }
    }

    for (final t in tasks) {
      addFor(t, false);
    }
    for (final t in deletedTasks) {
      addFor(t, true);
    }
    return events;
  }

  static final RegExp _alarmLogLine = RegExp(
      r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.\d{3} '
      r'\[(OK|FAIL|WARN|INFO)\s*\] (\S+)\s*\| (.*)$');

  static final RegExp _alarmLogSection =
      RegExp(r'^═+ (.*) — (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\.\d{3} ═+$');

  /// Parses the persistent alarm pipeline log (`alarm_log.txt`) into events.
  /// Unparseable lines (the header, trim notices) are skipped.
  static List<UsageEvent> alarmLogEvents(String logText) {
    final events = <UsageEvent>[];
    for (final rawLine in logText.split('\n')) {
      final line = rawLine.trimRight();
      final entry = _alarmLogLine.firstMatch(line);
      if (entry != null) {
        final at = DateTime.tryParse(entry.group(1)!.replaceFirst(' ', 'T'));
        if (at == null) continue;
        events.add(UsageEvent(
          at: at,
          source: 'alarm',
          type: entry.group(3)!,
          itemTitle: entry.group(2)!,
          detail: entry.group(4)!,
        ));
        continue;
      }
      final section = _alarmLogSection.firstMatch(line);
      if (section != null) {
        final at =
            DateTime.tryParse(section.group(2)!.replaceFirst(' ', 'T'));
        if (at == null) continue;
        events.add(UsageEvent(
          at: at,
          source: 'alarm',
          type: 'SECTION',
          detail: section.group(1)!,
        ));
      }
    }
    return events;
  }

  static List<UsageEvent> smsEvents(List<SmsReportLogEntry> entries) {
    return entries
        .map((e) => UsageEvent(
              at: e.sentAt,
              source: 'sms',
              type: e.kind == SmsLogKind.diag
                  ? 'diagnostic'
                  : (e.success ? 'report_sent' : 'report_failed'),
              itemTitle: e.recipientNickname,
              detail: e.error ??
                  'completed=${e.completedCount} uncompleted=${e.uncompletedCount}',
            ))
        .toList();
  }

  static List<UsageEvent> appOpenEvents(List<StartupRecord> history) {
    return history
        .map((r) => UsageEvent(
              at: r.at,
              source: 'app',
              type: 'app_open',
              detail: 'startup_ms=${r.ms}',
            ))
        .toList();
  }

  static List<UsageEvent> timerEvents(List<CountdownTimerItem> timers) {
    final events = <UsageEvent>[];
    for (final t in timers) {
      events.add(UsageEvent(
        at: t.createdAt,
        source: 'timer',
        type: 'created',
        itemId: t.uid,
        itemTitle: t.label,
        detail: 'target=${t.target.toIso8601String()}',
      ));
      if (t.editedAt != t.createdAt) {
        events.add(UsageEvent(
          at: t.editedAt,
          source: 'timer',
          type: 'edited',
          itemId: t.uid,
          itemTitle: t.label,
          detail: 'target=${t.target.toIso8601String()}',
        ));
      }
    }
    return events;
  }

  // ---------------------------------------------------------------------
  // Datasets
  // ---------------------------------------------------------------------

  static UsageCsvDataset allEventsDataset(List<UsageEvent> events) {
    final sorted = [...events]..sort((a, b) => a.at.compareTo(b.at));
    final rows = <List<Object?>>[
      [
        'timestamp',
        'date',
        'time',
        'weekday',
        'hour',
        'source',
        'event_type',
        'item_id',
        'item_title',
        'detail',
      ],
      for (final e in sorted)
        [
          e.at,
          dayKey(e.at),
          _timeOfDay(e.at),
          _weekdayName(e.at),
          e.at.hour,
          e.source,
          e.type,
          e.itemId,
          e.itemTitle,
          e.detail,
        ],
    ];
    return UsageCsvDataset(
      id: 'all_events',
      title: 'Full event timeline',
      description:
          'Every recorded moment across all sources, one row per event.',
      rows: rows,
      earliest: sorted.isEmpty ? null : sorted.first.at,
      latest: sorted.isEmpty ? null : sorted.last.at,
    );
  }

  static UsageCsvDataset taskHistoryDataset(
      List<Task> tasks, List<Task> deletedTasks) {
    String status(Task t, bool deletedList) {
      if (deletedList || t.deletedAt != null) {
        return t.autoDeleted ? 'auto_deleted' : 'deleted';
      }
      return t.isDone ? 'done' : 'open';
    }

    DateTime? earliest;
    DateTime? latest;
    void track(DateTime? d) {
      if (d == null) return;
      if (earliest == null || d.isBefore(earliest!)) earliest = d;
      if (latest == null || d.isAfter(latest!)) latest = d;
    }

    List<Object?> row(Task t, bool deletedList) {
      for (final d in [t.createdAt, t.completedAt, t.deletedAt]) {
        track(d);
      }
      final hoursToComplete = (t.createdAt != null && t.completedAt != null)
          ? t.completedAt!.difference(t.createdAt!).inMinutes / 60.0
          : null;
      final completedOnTime = (t.completedAt != null && t.dueDate != null)
          ? !t.completedAt!.isAfter(t.dueDate!)
          : null;
      return [
        t.uid,
        t.title,
        t.description,
        t.note,
        t.label,
        status(t, deletedList),
        t.createdAt,
        t.dueDate,
        t.movedAt,
        t.rescheduledAt,
        t.completedAt,
        t.deletedAt,
        t.autoDeleted,
        t.isDone,
        t.hasExplicitTime,
        t.listRanking,
        t.isRecurring,
        t.recurrenceIntervalDays,
        t.recurrenceEndDate,
        t.recurrenceParentUid,
        hoursToComplete,
        completedOnTime,
      ];
    }

    final rows = <List<Object?>>[
      [
        'uid',
        'title',
        'description',
        'note',
        'label',
        'status',
        'created_at',
        'due_date',
        'moved_at',
        'rescheduled_at',
        'completed_at',
        'deleted_at',
        'auto_deleted',
        'is_done',
        'has_explicit_time',
        'list_ranking',
        'is_recurring',
        'recurrence_interval_days',
        'recurrence_end_date',
        'recurrence_parent_uid',
        'hours_to_complete',
        'completed_on_time',
      ],
      for (final t in tasks) row(t, false),
      for (final t in deletedTasks) row(t, true),
    ];
    return UsageCsvDataset(
      id: 'task_history',
      title: 'Task history',
      description:
          'One row per task ever stored (active and deleted), all fields plus derived metrics.',
      rows: rows,
      earliest: earliest,
      latest: latest,
    );
  }

  /// Digital-Wellbeing-style per-day summary combining every source.
  static UsageCsvDataset dailyUsageDataset(
    List<UsageEvent> events,
    Map<String, DailyTaskStats> dailyStatsByDay,
  ) {
    final byDay = <String, List<UsageEvent>>{};
    for (final e in events) {
      byDay.putIfAbsent(dayKey(e.at), () => <UsageEvent>[]).add(e);
    }
    final days = <String>{...byDay.keys, ...dailyStatsByDay.keys}.toList()
      ..sort();

    int count(List<UsageEvent> list, String source, [String? type]) => list
        .where((e) => e.source == source && (type == null || e.type == type))
        .length;

    final rows = <List<Object?>>[
      [
        'date',
        'weekday',
        'first_activity',
        'last_activity',
        'active_span_minutes',
        'app_opens',
        'total_events',
        'tasks_created',
        'tasks_completed',
        'tasks_moved',
        'tasks_rescheduled',
        'tasks_deleted',
        'tasks_restored',
        'open_tasks_at_day_start',
        'completed_from_day_start',
        'moved_from_day_start',
        'created_during_day',
        'completed_from_created',
        'day_start_completion_rate',
        'alarm_events',
        'alarm_fires',
        'sms_reports_sent',
        'sms_reports_failed',
        'timer_events',
      ],
    ];
    DateTime? earliest;
    DateTime? latest;
    for (final day in days) {
      final list = byDay[day] ?? const <UsageEvent>[];
      final sorted = [...list]..sort((a, b) => a.at.compareTo(b.at));
      final stats = dailyStatsByDay[day];
      final opening = stats?.openingTaskIds.length ?? 0;
      final completedFromOpening =
          stats?.completedFromOpeningTaskIds.length ?? 0;
      final dayDate = DateTime.tryParse(day);
      if (sorted.isNotEmpty) {
        earliest ??= sorted.first.at;
        latest = sorted.last.at;
      }
      rows.add([
        day,
        dayDate == null ? '' : _weekdayName(dayDate),
        sorted.isEmpty ? null : _timeOfDay(sorted.first.at),
        sorted.isEmpty ? null : _timeOfDay(sorted.last.at),
        sorted.isEmpty
            ? 0
            : sorted.last.at.difference(sorted.first.at).inMinutes,
        count(sorted, 'app', 'app_open'),
        sorted.length,
        count(sorted, 'task', 'created'),
        count(sorted, 'task', 'completed'),
        count(sorted, 'task', 'moved'),
        count(sorted, 'task', 'rescheduled'),
        count(sorted, 'task', 'deleted'),
        count(sorted, 'task', 'restored'),
        opening,
        completedFromOpening,
        stats?.movedFromOpeningTaskIds.length ?? 0,
        stats?.createdDuringDayTaskIds.length ?? 0,
        stats?.completedFromCreatedTaskIds.length ?? 0,
        opening == 0 ? null : completedFromOpening / opening,
        count(sorted, 'alarm'),
        count(sorted, 'alarm', 'FIRE'),
        count(sorted, 'sms', 'report_sent'),
        count(sorted, 'sms', 'report_failed'),
        count(sorted, 'timer'),
      ]);
    }
    return UsageCsvDataset(
      id: 'daily_usage',
      title: 'Daily usage summary',
      description:
          'Per-day rollup of activity across all sources — the Digital Wellbeing view.',
      rows: rows,
      earliest: earliest,
      latest: latest,
    );
  }

  /// Day × hour activity histogram; only hours with activity get a row.
  static UsageCsvDataset hourlyUsageDataset(List<UsageEvent> events) {
    final byBucket = <String, List<UsageEvent>>{};
    for (final e in events) {
      final bucket = '${dayKey(e.at)}T${_two(e.at.hour)}';
      byBucket.putIfAbsent(bucket, () => <UsageEvent>[]).add(e);
    }
    final buckets = byBucket.keys.toList()..sort();
    final rows = <List<Object?>>[
      [
        'date',
        'weekday',
        'hour',
        'total_events',
        'task_events',
        'alarm_events',
        'sms_events',
        'app_opens',
        'timer_events',
      ],
    ];
    DateTime? earliest;
    DateTime? latest;
    for (final bucket in buckets) {
      final list = byBucket[bucket]!;
      final first = list.first.at;
      for (final e in list) {
        if (earliest == null || e.at.isBefore(earliest)) earliest = e.at;
        if (latest == null || e.at.isAfter(latest)) latest = e.at;
      }
      rows.add([
        dayKey(first),
        _weekdayName(first),
        first.hour,
        list.length,
        list.where((e) => e.source == 'task').length,
        list.where((e) => e.source == 'alarm').length,
        list.where((e) => e.source == 'sms').length,
        list.where((e) => e.source == 'app').length,
        list.where((e) => e.source == 'timer').length,
      ]);
    }
    return UsageCsvDataset(
      id: 'hourly_usage',
      title: 'Hourly activity',
      description:
          'Activity counts per day and hour of day, split by source.',
      rows: rows,
      earliest: earliest,
      latest: latest,
    );
  }

  static UsageCsvDataset dailyTaskStatsDataset(
      Map<String, DailyTaskStats> dailyStatsByDay) {
    final days = dailyStatsByDay.keys.toList()..sort();
    final rows = <List<Object?>>[
      [
        'date',
        'opening_task_ids',
        'moved_from_opening_task_ids',
        'completed_from_opening_task_ids',
        'created_during_day_task_ids',
        'completed_from_created_task_ids',
      ],
      for (final day in days)
        [
          day,
          dailyStatsByDay[day]!.openingTaskIds.join(';'),
          dailyStatsByDay[day]!.movedFromOpeningTaskIds.join(';'),
          dailyStatsByDay[day]!.completedFromOpeningTaskIds.join(';'),
          dailyStatsByDay[day]!.createdDuringDayTaskIds.join(';'),
          dailyStatsByDay[day]!.completedFromCreatedTaskIds.join(';'),
        ],
    ];
    return UsageCsvDataset(
      id: 'daily_task_stats',
      title: 'Raw daily task stats',
      description:
          'The underlying per-day task ID sets the stats pages are built from.',
      rows: rows,
      earliest: days.isEmpty ? null : DateTime.tryParse(days.first),
      latest: days.isEmpty ? null : DateTime.tryParse(days.last),
    );
  }

  static UsageCsvDataset alarmLogDataset(String logText) {
    final events = alarmLogEvents(logText);
    final rows = <List<Object?>>[
      ['timestamp', 'level', 'stage', 'message'],
      for (final e in events)
        [
          e.at,
          e.type == 'SECTION' ? 'INFO' : e.itemTitle,
          e.type,
          e.detail,
        ],
    ];
    return UsageCsvDataset(
      id: 'alarm_pipeline_log',
      title: 'Alarm pipeline log',
      description:
          'Every step the alarm system took: scheduling, permissions, fires, snoozes.',
      rows: rows,
      earliest: events.isEmpty ? null : events.first.at,
      latest: events.isEmpty ? null : events.last.at,
    );
  }

  static UsageCsvDataset alarmsDataset(List<Alarm> alarms) {
    final rows = <List<Object?>>[
      [
        'uid',
        'name',
        'description',
        'time',
        'schedule',
        'enabled',
        'is_repeating',
        'repeat_days',
        'date',
        'melody',
        'volume',
        'vibrate',
        'snooze_enabled',
        'snooze_duration_minutes',
        'snooze_max_count',
      ],
      for (final a in alarms)
        [
          a.uid,
          a.name,
          a.description,
          a.timeLabel,
          a.scheduleLabel,
          a.enabled,
          a.isRepeating,
          a.repeatDays.join(';'),
          a.date,
          a.melody,
          a.volume,
          a.vibrate,
          a.snoozeEnabled,
          a.snoozeDurationMinutes,
          a.snoozeMaxCount,
        ],
    ];
    return UsageCsvDataset(
      id: 'alarms',
      title: 'Alarms (current setup)',
      description: 'Snapshot of every configured alarm and its settings.',
      rows: rows,
    );
  }

  static UsageCsvDataset smsLogDataset(List<SmsReportLogEntry> entries) {
    final sorted = [...entries]..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final rows = <List<Object?>>[
      [
        'timestamp',
        'kind',
        'success',
        'recipient_nickname',
        'recipient_phone',
        'completed_count',
        'uncompleted_count',
        'error',
        'message',
      ],
      for (final e in sorted)
        [
          e.sentAt,
          e.kind == SmsLogKind.diag ? 'diag' : 'send',
          e.success,
          e.recipientNickname,
          e.recipientPhone,
          e.completedCount,
          e.uncompletedCount,
          e.error,
          e.message,
        ],
    ];
    return UsageCsvDataset(
      id: 'sms_report_log',
      title: 'SMS report log',
      description: 'Every daily SMS report attempt with outcome and counts.',
      rows: rows,
      earliest: sorted.isEmpty ? null : sorted.first.sentAt,
      latest: sorted.isEmpty ? null : sorted.last.sentAt,
    );
  }

  static UsageCsvDataset appOpensDataset(List<StartupRecord> history) {
    final sorted = [...history]..sort((a, b) => a.at.compareTo(b.at));
    final rows = <List<Object?>>[
      ['timestamp', 'date', 'time', 'weekday', 'startup_ms'],
      for (final r in sorted)
        [r.at, dayKey(r.at), _timeOfDay(r.at), _weekdayName(r.at), r.ms],
    ];
    return UsageCsvDataset(
      id: 'app_opens',
      title: 'App opens',
      description:
          'Each app launch with its timestamp and startup duration (recorded from v0.1.85 on).',
      rows: rows,
      earliest: sorted.isEmpty ? null : sorted.first.at,
      latest: sorted.isEmpty ? null : sorted.last.at,
    );
  }

  static UsageCsvDataset startupTimesDataset(List<int> times) {
    final rows = <List<Object?>>[
      ['launch_index', 'startup_ms'],
      for (var i = 0; i < times.length; i++) [i + 1, times[i]],
    ];
    return UsageCsvDataset(
      id: 'startup_times',
      title: 'Startup durations (legacy)',
      description:
          'Startup durations of the last launches, recorded before timestamps were kept.',
      rows: rows,
    );
  }

  static UsageCsvDataset countdownTimersDataset(
      List<CountdownTimerItem> timers) {
    final rows = <List<Object?>>[
      ['uid', 'label', 'target', 'notify_on_zero', 'created_at', 'edited_at'],
      for (final t in timers)
        [t.uid, t.label, t.target, t.notifyOnZero, t.createdAt, t.editedAt],
    ];
    DateTime? earliest;
    for (final t in timers) {
      if (earliest == null || t.createdAt.isBefore(earliest)) {
        earliest = t.createdAt;
      }
    }
    return UsageCsvDataset(
      id: 'countdown_timers',
      title: 'Countdown timers',
      description: 'All countdown timers with creation and edit times.',
      rows: rows,
      earliest: earliest,
    );
  }

  /// Key/value manifest describing the export itself, written alongside the
  /// data files.
  static UsageCsvDataset exportInfoDataset(
    List<UsageCsvDataset> datasets, {
    required String appVersion,
    required DateTime exportedAt,
  }) {
    DateTime? earliest;
    DateTime? latest;
    var totalRecords = 0;
    for (final d in datasets) {
      totalRecords += d.recordCount;
      if (d.earliest != null &&
          (earliest == null || d.earliest!.isBefore(earliest))) {
        earliest = d.earliest;
      }
      if (d.latest != null && (latest == null || d.latest!.isAfter(latest))) {
        latest = d.latest;
      }
    }
    final rows = <List<Object?>>[
      ['key', 'value'],
      ['app', 'BestToDo'],
      ['app_version', appVersion],
      ['exported_at', exportedAt],
      ['datasets', datasets.length],
      ['total_records', totalRecords],
      ['earliest_data', earliest],
      ['latest_data', latest],
      for (final d in datasets)
        ['records_in_${d.id}', d.recordCount],
    ];
    return UsageCsvDataset(
      id: 'export_info',
      title: 'Export manifest',
      description: 'What this export contains and how far back it reaches.',
      rows: rows,
      earliest: earliest,
      latest: latest,
    );
  }

  /// Builds every dataset from the given in-memory data. Order matters: this
  /// is the order shown in the tool and written to disk.
  static List<UsageCsvDataset> buildAllDatasets({
    required List<Task> tasks,
    required List<Task> deletedTasks,
    required Map<String, DailyTaskStats> dailyStatsByDay,
    required String alarmLogText,
    required List<Alarm> alarms,
    required List<SmsReportLogEntry> smsEntries,
    required List<StartupRecord> startupHistory,
    required List<int> startupTimes,
    required List<CountdownTimerItem> countdownTimers,
  }) {
    final events = <UsageEvent>[
      ...taskEvents(tasks, deletedTasks),
      ...alarmLogEvents(alarmLogText),
      ...smsEvents(smsEntries),
      ...appOpenEvents(startupHistory),
      ...timerEvents(countdownTimers),
    ];
    return <UsageCsvDataset>[
      allEventsDataset(events),
      dailyUsageDataset(events, dailyStatsByDay),
      hourlyUsageDataset(events),
      taskHistoryDataset(tasks, deletedTasks),
      dailyTaskStatsDataset(dailyStatsByDay),
      alarmLogDataset(alarmLogText),
      alarmsDataset(alarms),
      smsLogDataset(smsEntries),
      appOpensDataset(startupHistory),
      startupTimesDataset(startupTimes),
      countdownTimersDataset(countdownTimers),
    ];
  }

  /// Writes [datasets] as CSV files into [directoryPath] (created if needed).
  /// Returns the written files.
  static Future<List<File>> writeDatasets(
      List<UsageCsvDataset> datasets, String directoryPath) async {
    final dir = Directory(directoryPath);
    await dir.create(recursive: true);
    final sep = Platform.pathSeparator;
    final base = directoryPath.endsWith(sep)
        ? directoryPath.substring(0, directoryPath.length - sep.length)
        : directoryPath;
    final files = <File>[];
    for (final dataset in datasets) {
      final file = File('$base$sep${dataset.fileName}');
      await file.writeAsString(dataset.toCsv(), flush: true);
      files.add(file);
    }
    return files;
  }
}
