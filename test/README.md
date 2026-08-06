# Test suites

The test suite is split into siloed sub-suites so you only run what a change
can affect. **`test/core/` must always pass** — run it for every change. The
other suites are per-feature silos: run the ones whose area you touched.
`flutter test` (no path) still runs everything and is what CI uses.

## Suites

| Suite | Command | Covers |
|---|---|---|
| `test/core/` | `flutter test test/core` | Task model + JSON round-trip, `StorageService` persistence/rollover, item-history journal (`ItemEventJournal` diff + persistence), upgrade safety (`SafeFile` atomic writes/recovery, `PreUpdateBackup` snapshot, historical payload matrix), automatic backups (`AutoBackupService` schedule + payload), config persistence, tab bucketing/filtering (`date_utils`), done-task ordering, reorder ranking, deadline normalization, app-boot smoke test, build-gate smoke test |
| `test/alarms/` | `flutter test test/alarms` | Alarm model, `AlarmStorageService` round-trip + corruption recovery/backup, alarm editor (top save), alarm ring page, item-linked reminders (`ReminderSyncService` + task-detail reminder section) |
| `test/projects/` | `flutter test test/projects` | Project model, `ProjectService` (seed/rename/reload/corrupt file), Projects page drag-assign, Kanban board page, task-tile project/stage tags |
| `test/home/` | `flutter test test/home` | Home page UI: search behaviors, drawer layout (Projects under Tools), task-tile description editing, test-failure red dot on the hamburger/drawer, settings search, dice random-task timer, its alert settings and its full-screen alarm ring (`dice_timer_alarm_test.dart`), wishlist items on the Future tab, simple/full mode + the feature switches (`simple_mode_test.dart`, `settings_features_test.dart`), collapsible settings sections (`settings_collapse_test.dart`), home-screen widget payload + checkbox toggles (`widget_checkboxes_test.dart`) |
| `test/streaks/` | `flutter test test/streaks` | Daily completion streak: `StreakService` (grace periods, persistence, history seeding, fun stats), home-page flame icon + badge, celebration overlay, `StreakPage`, Streak settings section + search entries |
| `test/sms/` | `flutter test test/sms` | SMS daily report: `SmsRecipient`/`SmsReportConfig` JSON round-trip, per-recipient enable flag + `activeRecipients` filtering, Settings recipient rows (pause switch, edit keeps the flag) |
| `test/tools/` | `flutter test test/tools` | Auxiliary tools: export/import + analytics CSVs, usage-data service, startup-times page, countdown timer model + milestone notifications (model & dialog), timer date picker (`lib/utils/date_time_format.dart`), chronize page, CI test report model/parser (`TestReport.newest`), report layering service, `sync_test_report` packaging tool + Test Results page, wishlist Todo.md import migration, wishlist page (filtered view, priority/delete swipes), changelog parser + update heatmap (toggle, day selection), Productivity Stats item-activity heatmap colour scale (`stats_activity_heatmap_test.dart`) |

## Which suites to run

Pick suites by what you touched, always including core:

- `lib/models/task.dart`, `lib/services/storage_service.dart`, `lib/utils/`,
  `lib/config.dart`, `lib/main.dart` → **core** (plus any suite whose UI
  consumes what you changed — when in doubt, run everything)
- `lib/models/alarm.dart`, `lib/services/alarm_*`, `lib/ui/alarm*` → core + **alarms**
- `lib/models/project.dart`, `lib/services/project_service.dart`,
  `lib/ui/projects_page.dart`, `lib/ui/project_board_page.dart` → core + **projects**
- `lib/ui/home_page.dart`, `lib/ui/task_tile.dart`, `lib/ui/settings_page.dart`,
  `lib/ui/dice_timer_page.dart`
  → core + **home** (+ **projects** for `task_tile.dart`, which renders project tags;
  + **streaks** for `home_page.dart`/`settings_page.dart`, which host the flame and
  its settings section)
- `lib/services/streak_service.dart`, `lib/ui/streak_page.dart`,
  `lib/ui/streak_celebration.dart` → core + **streaks**
- `lib/models/sms_*`, `lib/services/sms_report_*`, the SMS section of
  `lib/ui/settings_page.dart` → core + **sms** (+ **home**/**streaks**, which also
  pump the settings page)
- `lib/services/usage_data_service.dart`, `lib/services/startup_time_service.dart`,
  export/import, `lib/ui/startup_times_page.dart`, `lib/ui/chronize_page.dart`,
  `lib/ui/changelog_page.dart`,
  `lib/models/countdown_timer.dart`, `lib/models/test_report.dart`,
  `lib/services/test_report_service.dart`, `lib/ui/test_results_page.dart`,
  `lib/services/wishlist_migration.dart`, `lib/ui/wishlist_page.dart`,
  `lib/ui/your_stats_page.dart`,
  `tool/generate_test_report.dart`, `tool/sync_test_report.dart` → core + **tools**

Multiple suites can be passed in one invocation:
`flutter test test/core test/alarms`.

Cross-cutting changes (theme, navigation, dependency upgrades, anything in
`pubspec.yaml`) → run the full suite: `flutter test`.

## Adding tests

Put new tests in the suite matching the feature area; create a new
`test/<area>/` directory when a new feature area doesn't fit an existing silo.
Keep core limited to functionality the whole app depends on (task model,
persistence, bucketing) plus app-boot/build smoke tests. Test conventions
(fake path provider, `ProjectService.instance.resetForTest()`, etc.) are in
`CLAUDE.md`.
