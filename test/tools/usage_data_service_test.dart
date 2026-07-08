import 'package:besttodo/models/daily_task_stats.dart';
import 'package:besttodo/models/sms_report_log_entry.dart';
import 'package:besttodo/models/task.dart';
import 'package:besttodo/services/startup_time_service.dart';
import 'package:besttodo/services/usage_data_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CSV formatting', () {
    test('plain fields pass through unquoted', () {
      expect(UsageDataService.csvField('hello'), 'hello');
      expect(UsageDataService.csvField(42), '42');
      expect(UsageDataService.csvField(null), '');
      expect(UsageDataService.csvField(true), 'true');
    });

    test('fields with commas, quotes and newlines are quoted and escaped',
        () {
      expect(UsageDataService.csvField('a,b'), '"a,b"');
      expect(UsageDataService.csvField('say "hi"'), '"say ""hi"""');
      expect(UsageDataService.csvField('line1\nline2'), '"line1\nline2"');
    });

    test('DateTime fields are ISO 8601', () {
      expect(
        UsageDataService.csvField(DateTime(2026, 7, 6, 8, 30)),
        '2026-07-06T08:30:00.000',
      );
    });

    test('rows are joined with CRLF', () {
      final csv = UsageDataService.toCsv([
        ['a', 'b'],
        [1, 'x,y'],
      ]);
      expect(csv, 'a,b\r\n1,"x,y"\r\n');
    });
  });

  group('task events', () {
    test('derives one event per dated lifecycle field', () {
      final task = Task(
        title: 'Write report',
        label: 'work',
        createdAt: DateTime(2026, 7, 1, 9),
        movedAt: DateTime(2026, 7, 2, 10),
        rescheduledAt: DateTime(2026, 7, 3, 11),
        completedAt: DateTime(2026, 7, 4, 12),
        dueDate: DateTime(2026, 7, 5, 18),
        isDone: true,
      );
      final events = UsageDataService.taskEvents([task], []);
      expect(events.map((e) => e.type).toSet(),
          {'created', 'moved', 'rescheduled', 'completed'});
      final created = events.singleWhere((e) => e.type == 'created');
      expect(created.detail, 'label=work');
      expect(created.itemTitle, 'Write report');
    });

    test('deleted tasks contribute deletion events with auto flag', () {
      final deleted = Task(
        title: 'Old',
        createdAt: DateTime(2025, 1, 1),
        deletedAt: DateTime(2025, 1, 2),
        autoDeleted: true,
      );
      final events = UsageDataService.taskEvents([], [deleted]);
      final deletion = events.singleWhere((e) => e.type == 'deleted');
      expect(deletion.detail, 'auto_deleted');
    });

    test('restored heuristic only applies to active undone tasks', () {
      final restored = Task(
        title: 'Back again',
        completedAt: DateTime(2026, 6, 1),
        isDone: false,
      );
      final events = UsageDataService.taskEvents([restored], []);
      expect(events.where((e) => e.type == 'restored').length, 1);
      // Same shape in the deleted list must not produce a restored event.
      final events2 = UsageDataService.taskEvents([], [restored]);
      expect(events2.where((e) => e.type == 'restored'), isEmpty);
    });
  });

  group('alarm log parsing', () {
    const sample = '''
BestToDo ALARM LOG — how to read this file
  [OK]   step worked        [FAIL] step failed (message says why + fix)

════════ diagnostics — app start — 2026-07-05 07:59:00.000 ════════
2026-07-05 08:00:00.123 [OK  ] SCHEDULE| alarm 42 handed to OS
2026-07-05 08:01:02.456 [FAIL] FIRE    | alarm 42 did not ring, watchdog took over
garbage line that matches nothing
''';

    test('parses entry lines with level, stage and message', () {
      final events = UsageDataService.alarmLogEvents(sample);
      final scheduled = events.singleWhere((e) => e.type == 'SCHEDULE');
      expect(scheduled.at, DateTime(2026, 7, 5, 8, 0, 0));
      expect(scheduled.itemTitle, 'OK');
      expect(scheduled.detail, 'alarm 42 handed to OS');
      final fire = events.singleWhere((e) => e.type == 'FIRE');
      expect(fire.itemTitle, 'FAIL');
    });

    test('parses section banners and skips unparseable lines', () {
      final events = UsageDataService.alarmLogEvents(sample);
      final section = events.singleWhere((e) => e.type == 'SECTION');
      expect(section.at, DateTime(2026, 7, 5, 7, 59, 0));
      expect(section.detail, 'diagnostics — app start');
      expect(events.length, 3);
    });
  });

  group('daily usage rollup', () {
    test('combines events and daily stats per day', () {
      final events = [
        UsageEvent(source: 'app', type: 'app_open', at: _jul6Morning),
        UsageEvent(source: 'task', type: 'created', at: _jul6Noon),
        UsageEvent(source: 'task', type: 'completed', at: _jul6Evening),
        UsageEvent(source: 'sms', type: 'report_sent', at: _jul6Evening),
        UsageEvent(source: 'task', type: 'created', at: _jul7),
      ];
      final stats = {
        '2026-07-06': DailyTaskStats(
          dayKey: '2026-07-06',
          openingTaskIds: {'a', 'b', 'c', 'd'},
          completedFromOpeningTaskIds: {'a'},
        ),
        // A day with stats but no events must still get a row.
        '2026-07-01': DailyTaskStats(
          dayKey: '2026-07-01',
          openingTaskIds: {'x'},
        ),
      };
      final dataset = UsageDataService.dailyUsageDataset(events, stats);
      expect(dataset.recordCount, 3);

      final header = dataset.rows.first.cast<String>();
      Map<String, Object?> rowFor(String day) {
        final row = dataset.rows.skip(1).firstWhere((r) => r.first == day);
        return Map.fromIterables(header, row);
      }

      final jul6 = rowFor('2026-07-06');
      expect(jul6['weekday'], 'Monday');
      expect(jul6['app_opens'], 1);
      expect(jul6['total_events'], 4);
      expect(jul6['tasks_created'], 1);
      expect(jul6['tasks_completed'], 1);
      expect(jul6['sms_reports_sent'], 1);
      expect(jul6['open_tasks_at_day_start'], 4);
      expect(jul6['completed_from_day_start'], 1);
      expect(jul6['day_start_completion_rate'], 0.25);
      expect(jul6['first_activity'], '08:00:00');
      expect(jul6['last_activity'], '20:00:00');
      expect(jul6['active_span_minutes'], 12 * 60);

      final jul1 = rowFor('2026-07-01');
      expect(jul1['total_events'], 0);
      expect(jul1['open_tasks_at_day_start'], 1);

      // Days are sorted ascending.
      expect(dataset.rows[1].first, '2026-07-01');
    });
  });

  group('hourly usage rollup', () {
    test('buckets events by day and hour, split per source', () {
      final events = [
        UsageEvent(source: 'task', type: 'created', at: _jul6Morning),
        UsageEvent(
            source: 'alarm', type: 'FIRE', at: DateTime(2026, 7, 6, 8, 45)),
        UsageEvent(source: 'task', type: 'completed', at: _jul6Noon),
      ];
      final dataset = UsageDataService.hourlyUsageDataset(events);
      expect(dataset.recordCount, 2);
      final eight = dataset.rows[1];
      expect(eight[0], '2026-07-06');
      expect(eight[2], 8); // hour
      expect(eight[3], 2); // total
      expect(eight[4], 1); // task
      expect(eight[5], 1); // alarm
    });
  });

  group('task history dataset', () {
    test('one row per task with status and derived metrics', () {
      final done = Task(
        title: 'Done on time',
        createdAt: DateTime(2026, 7, 1, 8),
        completedAt: DateTime(2026, 7, 1, 11),
        dueDate: DateTime(2026, 7, 1, 18),
        isDone: true,
      );
      final open = Task(title: 'Still open');
      final deleted = Task(
        title: 'Gone',
        deletedAt: DateTime(2026, 7, 2),
        autoDeleted: true,
      );
      final dataset =
          UsageDataService.taskHistoryDataset([done, open], [deleted]);
      expect(dataset.recordCount, 3);

      final header = dataset.rows.first.cast<String>();
      final statusIndex = header.indexOf('status');
      final hoursIndex = header.indexOf('hours_to_complete');
      final onTimeIndex = header.indexOf('completed_on_time');

      expect(dataset.rows[1][statusIndex], 'done');
      expect(dataset.rows[1][hoursIndex], 3.0);
      expect(dataset.rows[1][onTimeIndex], true);
      expect(dataset.rows[2][statusIndex], 'open');
      expect(dataset.rows[3][statusIndex], 'auto_deleted');
      expect(dataset.earliest, DateTime(2026, 7, 1, 8));
      expect(dataset.latest, DateTime(2026, 7, 2));
    });
  });

  group('full export bundle', () {
    test('buildAllDatasets returns every dataset with unique file names', () {
      final datasets = UsageDataService.buildAllDatasets(
        tasks: [Task(title: 'One', createdAt: DateTime(2026, 7, 1))],
        deletedTasks: [],
        dailyStatsByDay: {},
        alarmLogText: '',
        alarms: [],
        smsEntries: [
          SmsReportLogEntry(
            sentAt: DateTime(2026, 7, 5, 20),
            message: 'report',
            success: true,
            completedCount: 3,
            uncompletedCount: 1,
          ),
        ],
        startupHistory: [
          StartupRecord(at: DateTime(2026, 7, 6, 8), ms: 350),
        ],
        startupTimes: [350, 410],
        countdownTimers: [],
      );
      final ids = datasets.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(
        ids,
        containsAll([
          'all_events',
          'daily_usage',
          'hourly_usage',
          'task_history',
          'daily_task_stats',
          'alarm_pipeline_log',
          'alarms',
          'sms_report_log',
          'app_opens',
          'startup_times',
          'countdown_timers',
        ]),
      );

      final allEvents = datasets.singleWhere((d) => d.id == 'all_events');
      // task created + sms sent + app open
      expect(allEvents.recordCount, 3);
      // Timeline is sorted ascending, so it reaches back to the oldest event.
      expect(allEvents.earliest, DateTime(2026, 7, 1));
      expect(allEvents.latest, DateTime(2026, 7, 6, 8));
    });

    test('export info manifest aggregates counts and date range', () {
      final datasets = UsageDataService.buildAllDatasets(
        tasks: [Task(title: 'One', createdAt: DateTime(2025, 12, 24))],
        deletedTasks: [],
        dailyStatsByDay: {},
        alarmLogText: '',
        alarms: [],
        smsEntries: [],
        startupHistory: [],
        startupTimes: [],
        countdownTimers: [],
      );
      final info = UsageDataService.exportInfoDataset(
        datasets,
        appVersion: '0.1.85+55',
        exportedAt: DateTime(2026, 7, 6, 9),
      );
      final rows = {
        for (final row in info.rows.skip(1)) row[0]: row[1],
      };
      expect(rows['app_version'], '0.1.85+55');
      expect(rows['earliest_data'], DateTime(2025, 12, 24));
      expect(rows['datasets'], datasets.length);
    });
  });
}

final DateTime _jul6Morning = DateTime(2026, 7, 6, 8);
final DateTime _jul6Noon = DateTime(2026, 7, 6, 12);
final DateTime _jul6Evening = DateTime(2026, 7, 6, 20);
final DateTime _jul7 = DateTime(2026, 7, 7, 9);
