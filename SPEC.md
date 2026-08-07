# BestToDo — Complete Rebuild Specification & History

> **Purpose of this document.** If the original authors, tooling, and AI sessions behind this
> app disappeared tomorrow, this file is what a human or AI needs to rebuild BestToDo from
> zero and to understand *why* it is built the way it is. Part I is the functional/technical
> specification (what to build). Part II is the complete development history (every step the
> project took and why). `CHANGELOG.md` remains the authoritative per-version record; the
> operational deep dives (rebuild order, testing, CI/automation, environment, principles,
> the alarm reliability sessions) are indexed in `.claude/README.md`.
>
> Part I is accurate as of version **0.1.134+106** (2026-08-06). Part II's narrated
> history runs in detail through 0.1.91; every later version is covered feature-wise in
> Part I and per-version in `CHANGELOG.md`.

---

# Part I — Rebuild specification

## 1. What the app is

BestToDo is a **swipe-first, ultra-fast to-do app** built with Flutter, primarily targeting
Android. Tasks default to *today*; you move them forward in time with gestures. The design
philosophy (from README, unchanged since the start):

1. **Less than 1 second cold startup.**
2. **It must not be possible to do the same thing in fewer clicks/steps.**
3. **Open source.**

Everything else — widgets, alarms, SMS accountability reports, timelines, stats — grew around
that core. The app deliberately has **no backend, no accounts, no database**: all state is
plain JSON files in the app documents directory.

- App name: `besttodo`, display "BestToDo". Application id: `com.mfficiency.best_todo_2`.
- Primary/seed color: `#005FDD` (rgba(0, 95, 221, 1)), Material 3, light + dark themes via
  `ColorScheme.fromSeed` with primary forced to the seed.
- Version scheme: `x.y.z+build` in `pubspec.yaml` (`0.1.87+57` = versionName 0.1.87,
  versionCode 57).

## 2. Tech stack & repository layout

Flutter (Dart SDK >=3.0.0), tested against Flutter 3.29.2 in CI. Key directories:

```
lib/main.dart            app entry, widget background callback, MyApp/theme/start page
lib/config.dart          runtime + persisted configuration (settings.json)
lib/models/              task, daily_task_stats, alarm, countdown_timer, countdown_milestone, sms_*
lib/services/            storage, startup times, log, notifications (io/web/stub),
                         alarm pipeline (service/notification/watchdog/diagnostics/log/
                         storage/ids/widget), sms report (scheduler/service/config/log),
                         usage_data
lib/ui/                  all pages (home, settings, chronize, alarms, stats, usage data, …)
lib/utils/               task_utils (bucketing, sorting, 18:00 normalization), date_time_format
android/                 manifest, Kotlin widget providers, Gradle config, debug keystore
test/                    unit + widget tests; integration_test/ for screenshot E2E
tool/                    build.sh, bump_version.dart, icon scripts, screenshot changelog
.github/workflows/       build-apk, flutter_test, screenshot_changelog
```

Dependencies and why they exist:

| Package | Purpose |
|---|---|
| `path_provider` | app documents / downloads dirs (all JSON persistence, CSV export) |
| `shared_preferences` | small flags (intro_shown, watchdog/ack registries) |
| `uuid` | v4 ids for tasks, alarms, timers |
| `home_widget` | home-screen widgets (task list + alarm widget, background taps) |
| `flutter_local_notifications` | task notifications + the alarm-clock delivery path |
| `android_alarm_manager_plus` | background Dart isolates for SMS report + alarm watchdog |
| `another_telephony` | SMS sending (daily report) |
| `permission_handler` | runtime permissions (notifications, SMS, exact alarm, battery) |
| `timezone` + `flutter_timezone` | correct zoned alarm scheduling (DST-safe) |
| `device_info_plus` | emulator detection; OEM name for alarm diagnostics |
| `package_info_plus` | runtime version for About page / export manifests |
| `file_selector` | directory pickers for export/import |
| `fl_chart` | startup-times line chart |
| `flutter_markdown` | renders CHANGELOG.md in-app |
| `url_launcher` | About page links |
| `cupertino_icons` | iOS-style glyphs |

## 3. App startup sequence (order matters)

`main()` in `lib/main.dart`, strictly in this order. Guiding rule (0.1.136):
**nothing before `runApp` may block indefinitely** — until the first frame
renders, Android shows a black window, so any pre-frame `await` that hangs is
the intermittent black-screen-at-open bug (first hit v0.1.85 via awaited
diagnostics, hit again pre-0.1.136 via the plugin-init awaits).

1. `StartupTimeService.start()` — stopwatch for the <1s cold-start budget.
2. `WidgetsFlutterBinding.ensureInitialized()`.
3. `await Config.load()` — reads `settings.json` so theme/tabs are right before
   first frame. Wrapped in try/catch with a 5 s timeout: on failure the app
   opens with defaults instead of never opening.
4. SharedPreferences (also try/catch + 5 s timeout) → `showIntro` =
   `!intro_shown || !Config.modeChosen` (always skipped in dev builds; false if
   prefs fail); the mode question closes the intro, so an unanswered mode
   brings the whole welcome flow back rather than the chooser alone.
5. `runApp(MyApp(showIntro, showModePicker: !showIntro && !Config.modeChosen))`;
   post-frame → `StartupTimeService.record()`. `MyApp.home`: intro (slides +
   mode choice) → `_initialPage()`. The standalone `ModeSelectPage` is only
   for asking the mode question again (Settings → Mode & features, §4.6).
6. Post-first-frame, `_initServicesAfterFirstFrame()` (fire-and-forget, order
   preserved, each step in try/catch with a 20 s timeout so one wedged plugin
   can't stall the rest; failures land in LogService + `alarm_log.txt`):
   1. `NotificationService.initialize()` — plugin + notification channels
      (memoized: concurrent callers — e.g. `getAlarmLaunchPayload` in
      `MyApp.initState` — share one underlying init).
   2. Non-web: `SmsReportScheduler.applyFromConfig()` — restore the daily SMS
      alarm chain.
   3. `AlarmService.instance.load()` — load persisted alarms + reschedule
      (memoized so the alarms page's own `load()` can't double-reschedule).
   4. `unawaited(NotificationService.runAlarmDiagnostics(trigger: 'app start'))`.
   5. Home-widget setup: `HomeWidget.setAppGroupId` +
      `registerInteractivityCallback(alarmWidgetBackgroundCallback)`.
7. Also post-first-frame (deferred 1 s, fire-and-forget):
   `PermissionFlow.maybeRequestAfterUpdate()` — on the first open after an app
   update, asks for **every** runtime permission in one pass (§9); skipped
   while the mode picker has never been answered, because the picker's
   full-mode choice runs the same flow itself.

**Background isolate rule (critical, learned the hard way):** every `@pragma('vm:entry-point')`
callback (`alarmWidgetBackgroundCallback`, `alarmWatchdogCallback`, `smsReportAlarmCallback`,
background notification-action handler) must first call
`WidgetsFlutterBinding.ensureInitialized()` **and** `DartPluginRegistrant.ensureInitialized()`.
A fresh background isolate has no plugin channels; without this, path_provider/notifications/
telephony silently no-op.

## 4. Core task system

### 4.1 Task model (`lib/models/task.dart`)

Uuid-v4 `uid`; JSON keys equal field names. Fields: `title`, `description`, `note`, `label`
(single string), `createdAt`, `completedAt`, `movedAt`, `rescheduledAt`,
`startAt`/`endAt` (schema v2, 0.1.109 — the scheduled interval; deadline-style tasks have
`startAt == endAt`; `dueDate` is now a compat getter (= `endAt`) / setter (collapses the
interval to a deadline) and is still written to JSON as a mirror so downgrades/old imports
work; records carry `schemaVersion` (current 2), v1 records upgrade on read via
`fromJson`'s `dueDate` fallback; derived getters `allDay` (= `!hasExplicitTime`) and
`duration`),
`deletedAt`, `autoDeleted` (swept at rollover vs manual delete), `isDone`,
`hasExplicitTime` (protects a deliberately chosen time from the 18:00 normalization),
`listRanking` (int?, omitted from JSON when null, renumbered 1-based per tab on every save),
recurrence: `isRecurring`, `recurrenceEndDate`, `recurrenceIntervalDays` (≥1; UI offers
1/2/7), `recurrenceParentUid` + `recurrenceInstanceKey` (`yyyy-MM-dd`) on generated children.
Projects (0.1.89): `projectId` (String?, omitted from JSON when null) + `kanbanStatus`
(`'todo'`/`'ongoing'`/`'closed'`, constants on `Task`, defaults `'todo'`).
Wishlist (0.1.101): `isWish` (bool, default false) marks a task as a wishlist item
(see §10.6); wish tasks are undated and undated tasks bucket into the Future tab.
`fromJson` is tolerant: missing keys get defaults.

`DailyTaskStats` (per day, keyed `yyyy-MM-dd`): sets of task uids —
`openingTaskIds`, `movedFromOpeningTaskIds`, `completedFromOpeningTaskIds`,
`createdDuringDayTaskIds`, `completedFromCreatedTaskIds`. Powers the stats page and CSV
rollups.

### 4.2 Persistence (all in app documents dir, JSON, `flush: true`, errors swallowed)

| File | Content | Cap |
|---|---|---|
| `settings.json` | Config map | — |
| `tasks.json` | active tasks (incl. recurrence children and `isWish` wishlist items) | — |
| `wishlist.json` | legacy wishlist store; drained into `tasks.json` on load since 0.1.101 | — |
| `deleted_tasks.json` | deleted list | **100**, trimmed on save+load |
| `daily_task_stats.json` | one record per day | — |
| `last_opened.txt` | ISO timestamp for day-rollover detection | 1 value |
| `countdown_timers.json` | timers (null = first run, [] = emptied) | — |
| `startup_times.json` | plain ms ints | 100 |
| `startup_history.json` | `{at, ms}` per launch | 5000 |
| `alarms.json` | alarm list | — |
| `sms_report_config.json` / `sms_report_log.json` | SMS config / log | log 500 |
| `alarm_log.txt` | human-readable alarm pipeline log | ~400 KB → trim to 250 KB |
| `item_events.jsonl` | append-only item history journal (one JSON event per line) | ~1 MB → keep newest 4000 |
| `item_event_meta.json` | per-item last sequence number (`{uid: seq}`) | — |
| `sync_log.json` | `{unseen_error, entries[]}` background-sync history (§4.7) | 100 entries |

**Day rollover:** on load, if the calendar date changed since `last_opened.txt`, every
`isDone` task gets `completedAt`/`deletedAt` backfilled, moves to the top of the deleted
list, and is removed from active tasks. The dev date-stepper does the same on forward steps
(and marks them `autoDeleted: true`; the load-time sweep historically does not — a known
inconsistency: load-swept show "Deleted", dev-swept show "Auto-deleted").

**Invariant:** `_ensureUniqueIds` on every load/import reassigns empty/duplicate uids.

**Export/import:** three exports (Tasks / Settings / Everything) written to a user-picked
folder with timestamped names. Tasks bundle is `export_version: 2` with `tasks`,
`deleted_tasks`, `daily_stats`, derived `task_events`, `labels`, `projects`. Settings and
Everything use `export_version: 1` (two version namespaces — intentional). Import
auto-detects: bare JSON list = legacy tasks; map with `tasks_bundle` = everything; map with
only `settings` = settings; else tasks bundle.

**Automatic backup (0.1.130):** Settings → Backup schedules the Everything export
(`AutoBackupService`, `lib/services/auto_backup_service.dart`): frequency off/daily/weekly
(`Config.autoBackupFrequency`, default off) into a user-picked folder
(`Config.autoBackupDirectory`), checked after the home page loads and on every app resume
(`maybeRun`, cheap no-op when off). Daily = first check of each calendar day; weekly =
≥ 7 days since the last run. The last successful run is stored in `last_auto_backup.txt`
in the documents dir — deliberately *not* in settings.json, so importing an old settings
export cannot fake a recent backup. Backups read straight from disk
(`readTaskListRaw` etc., not the home page's in-memory list), are written as
`besttodo_backup_<yyyymmdd_hhmmss>.json` and restore through the regular Import button.
The Backup section also offers a "Back up now" tile and shows the last backup time.

### 4.2b Item history journal (0.1.106)

`ItemEventJournal` (`lib/services/item_event_journal.dart`) records every change to a
task as an immutable `ItemEvent` (`lib/models/item_event.dart`: eventId, itemId, per-item
`seq` = version number, at, type, field-level `patch` [{field, from, to}], `seeded` flag)
in append-only `item_events.jsonl`. `StorageService.saveTaskList` diffs the new list
against the last persisted snapshot (static baseline set on load/save; first contact only
snapshots, so test pre-saves stay silent) and enqueues the events on a fire-and-forget
write chain — **saves and startup are not slowed; the journal is never read at startup,
only on demand** (task-detail History section, export). Types: created / edited / labeled /
scheduled / statusChanged / projectChanged / wishChanged / recurrenceChanged / deleted /
restored. `listRanking` and the lifecycle timestamps are deliberately untracked (noise).
A reappearing uid whose seq index (`item_event_meta.json`) is non-zero logs `restored`,
not `created`. Self-compacts past ~1 MB to the newest 4000 events. Task exports carry the
journal as `item_events` next to the derived `task_events`.

**History seeding (0.1.107):** `ItemHistorySeeder.runOnce()` backfills the journal once
per install from pre-journal data — task lifecycle timestamps (created/moved/rescheduled/
completed/deleted + the restore heuristic), the deleted list, and `DailyTaskStats` id sets
(at day-noon, only for uids still present somewhere, never duplicating timestamp-covered
events). All seed events carry `seeded: true` ("(reconstructed)" in the timeline UI).
Guarded by `item_events_seed_v1.txt`; scheduled from `main.dart` 3 s after the first
frame so startup is untouched; `eventsForItem` sorts by `at` (then seq) because seeds are
appended after any live events but describe an older past.

### 4.2f Upgrade safety (0.1.113)

No update path may lose data. Three layers (`lib/services/safe_file.dart`,
`lib/services/pre_update_backup.dart`):

1. **Atomic saves with rotation** — `SafeFile.writeString` writes `<file>.tmp` (flushed),
   rotates the previous content to `<file>.bak`, then renames over. Applied to
   `tasks.json`, `deleted_tasks.json`, `daily_task_stats.json`, `countdown_timers.json`
   and `alarms.json`. A crash mid-save can no longer leave a half-written file.
   Writes to the same path are serialized on a per-path future chain (overlapping
   saves — e.g. delete + undo — would otherwise race on the shared `.tmp`; last
   caller wins, a failed write still surfaces to its own caller only).
2. **Corruption recovery** — loads go through `SafeFile.readWithRecovery`: an
   unparseable main file is quarantined as `<file>.corrupt-<timestamp>` (so a later save
   can never destroy the only copy — the pre-0.1.113 failure mode) and the `.bak` is
   used instead. `wishlist.json` is deliberately excluded (its migration contract is
   "unreadable file left untouched"); `loadCountdownTimers` keeps its null-vs-[] first-run
   semantics by also checking the `.bak` for existence.
3. **Pre-update snapshot** — `PreUpdateBackup.ensure()` runs before the first *write* of
   a session (static bool → flag file `pre_update_backup_v1.txt` → once per install):
   copies every data file (see `backedUpFiles`) verbatim into `pre_update_backup/`.
   Never on the startup path. The wishlist drain saves the merged list BEFORE emptying
   `wishlist.json` so the snapshot captures the original (re-merge on crash is deduped
   by uid). Logged to App Logs. `last_run_version.txt` records the running version
   (deferred from `main.dart`) for future version-specific migrations.

Covered by `test/core/upgrade_safety_test.dart` (payload matrix from the no-uid era
through projects/wishlist to schema v2, corruption drills, snapshot invariants) and
`test/alarms/alarm_storage_recovery_test.dart`.

### 4.2e Repository seam (0.1.112)

`ItemRepository` (`lib/services/item_repository.dart`, singleton) is the one interface
pages use for the item store: `loadItems`/`saveItems` (task list),
`loadDeletedItems`/`saveDeletedItems`, `loadDailyStats`/`saveDailyStats`,
`historyOf`/`allHistory` (journal). Today it delegates to `StorageService` +
`ItemEventJournal`; swapping the backend (SQLite, sync) happens inside this class only.
Backup/export tooling stays on `StorageService` directly (it deals in files). The
decision to stay on JSON files — and the concrete triggers for revisiting (sync, ~5k
items / ~2 MB, measured startup regression) — is recorded in
`docs/architecture/storage-decision.md`.

### 4.2d Views as queries (0.1.111)

`ItemViews` (`lib/services/item_views.dart`) is the shared query layer over the one task
list: pure static selectors `inHomeBucket`/`homeBucket` (date-only distance bucketing +
`sortTasks`, optional extra predicate for search), `wishlist` (isWish), `active`
(deletedAt == null), `projectTasks`, `boardColumn`. The home page's `_tasksForTab`, the
Wishlist page, the Projects page (counts + top pane) and the Kanban board all delegate to
it; the Future-tab sentinel date (2300-01-01) lives here as `futureSentinelDate`.
Membership flags on the task stay the stored form (dual-write era) — this step moves the
*reading* of them into one place.

### 4.2c Structured labels (0.1.108)

`Label` (`lib/models/label.dart`: id, name, kind `tag`/`priority`/`system`, optional ARGB
color) + `LabelService` (`labels.json`, ValueNotifier singleton) form the structured half
of a label dual-write: `Task.label` (the token string, split on commas/whitespace —
helpers in `lib/utils/label_utils.dart`) stays canonical; every save auto-registers
unseen tokens fire-and-forget (`registerFromLabelStrings` from `saveTaskList`; write-free
when all tokens are known, nothing loads at startup). Kinds derive from the token:
`priority-low/-medium/-high` → priority, `old` (Todo.md import marker) → system, else
tag. Name matching is case-insensitive; `upsert` edits metadata (colour) by name.

### 4.3 Home page UX

Six day buckets (`Config.tabs`): **Today, Tomorrow, Day After Tomorrow, Next Week, Next
Month, Future**. Bucketing by date-only diff from the current date: `<=0` Today (overdue
stays in Today), `1`, `2`, `3–29` Next Week, `>=30` Next Month, and Future = the sentinel
due date `DateTime(2300,1,1)` (not null — null due dates appear in no tab). Moving to a tab
sets due = today + `[0,1,2,7,30]` days, or the 2300 sentinel; note move offsets ≠ bucket
ranges (Next Week accepts diff 3–29 but moves land on +7).

**Ordering:** pending first, done last; within groups ascending `listRanking` (null last).
Every save renumbers rankings 1..n per tab and then runs **`applyDefaultDeadlineTimes`**:
per calendar day, tasks without `hasExplicitTime` get times 18:00, 18:01, 18:02… (ranking
order, clamped 23:59) so same-day tasks never share a time. Chronize sets
`hasExplicitTime = true` to opt out.

**Adding:** add-task row at the top of each list; new tasks go to the top (ranking min−1)
by default (`Config.addNewTasksToTop`, default true).

**Swipe gestures** (the heart of the app):
- Android/web: custom `GestureDetector` swipe in `TaskTile` (threshold 100 px or velocity
  500). iOS/desktop: plain `Dismissible` that moves to the next tab.
- Direction is configurable (`swipeLeftDelete`, default true): one direction opens **Move
  options** (a button per other tab), the other **Delete options** (Delete + next-Fri/Sat/
  Sun/Mon reschedule shortcuts).
- The options overlay auto-commits after a countdown (`defaultDelaySeconds`, default 5 s):
  move → next tab; delete → delete. Swiping back the opposite way shows an orange
  **Cancel** and aborts.
- Emulators/web show explicit swipe/delete icon buttons instead (detected via
  `device_info_plus`) because gestures are awkward there.

**Delete is deferred:** the task leaves the active list immediately, but only lands in the
deleted list after the undo-snackbar window (same 5 s default) so Undo can restore it
in-place. Restore from Deleted Items always resets due date to today.

**Done:** checkbox sets `isDone` + `completedAt`, sinks to bottom with strikethrough;
swept to Deleted at day rollover.

**Recurrence:** only parents generate; children are copies with
`recurrenceParentUid`/`recurrenceInstanceKey` per day-step until `recurrenceEndDate`.
Moving/rescheduling a child detaches it (clears parent linkage). Regenerated after load,
import, and any parent edit.

**Inline editing:** tapping a tile expands it — title/description/note/label fields,
due-date picker, recurring switch (+interval/end for parents), a Notify bell (schedules a
task notification after `defaultNotificationDelaySeconds`), collapse button. Edits persist
on change/focus loss.

**Schedule view:** app-bar toggle swaps the tabbed lists for one long day-grouped list
(`ScheduleView`); tabs become scroll anchors; overdue rolls up under Today; each day
section is a `ReorderableListView`; "Someday" holds the 2300-sentinel tasks.

**Schedule view active day (0.1.91):** each top-level list child is one whole day
section (header + rows) so scroll tracking can measure it: the bottom-most section whose
top edge sits at/above 12 px below the list top is the "active" day — its header is
highlighted (primaryContainer + 3 px primary left border, `ValueKey('active-day-header')`)
and `onActiveDateChanged` reports its date to the home page, which shows it in the
add-task label ("Add task · Aug 1") and uses it as the new task's `dueDate` (instead of
the current tab's bucket) while the schedule view is open. Empty "Next week"/"Next month"
range sections target today +7/+30; Someday targets the 2300 sentinel; when a range has
days its header is grouped into the first day's section. Bottom padding is
`max(32, viewport − 56)` so even the last section can reach the top and be targeted. A
small back-to-top FAB (tooltip "Back to top") appears past 300 px scroll and animates to
offset 0. Detection runs on depth-0 scroll notifications + a post-frame callback per
build; sections scrolled out of view are unmounted, which is fine because the section
spanning the top is always attached.

**Drawer:** Settings, Deleted Items, About, Changelog, App Logs, Startup Times,
Tools ▸ (Alarms, Countdown, Wishlist, Projects, Chronize, Productivity Stats,
Usage Data, Test Results).

**CI test report (0.1.96, moved to Tools + online in 0.1.99, branch-independent and
packaged in 0.1.128):** the app always shows the **newest** test run it knows of, no
matter which branch produced it or whether there is a network.

*Storage.* `models/test_report.dart` (tolerant fromJson; also owns
`fromMachineJsonLines`, the `flutter test --machine` parser, and `runUrl` = the CI run
link) carries `appVersion` (`x.y.z+build` from pubspec at run time) plus
`TestReport.newest(candidates)` — the single rule behind "latest": highest
`generatedAt` wins, unavailable reports never win, a dated run beats an undated one.
Since 0.1.129 the report also carries `suites`: one `TestSuiteResult` per test file
(path trimmed to the repo-relative `test/…` / `integration_test/…` part, Windows
backslashes normalized) holding a `TestCaseResult` per executed test — name, result
(`passed`/`failed`/`skipped`) and `durationMs` (testDone − testStart machine
timestamps; null when absent). Hidden bookkeeping entries are excluded, tests whose
suite was never named group under an empty path, and per-suite/report durations sum
only the known times (null when none). Reports without a `suites` key parse to an
empty list, so pre-0.1.129 JSON stays valid everywhere.
Three places hold a report:
- `assets/test_report.json` — **packaged into every build** (Android, Windows, web,
  debug or release) and committed, so a plain checkout of dev and
  `flutter run -d chrome` show real results with no network and no build step.
- `ci-reports` branch (orphan, no app code so it triggers no workflow):
  `latest.json` = newest run across all branches, `branches/<branch>.json` = newest per
  branch. Written by `tool/ci/publish_test_report.sh` (clone-or-create, newest-wins merge
  through the sync tool, 3 push attempts, never fails a build).
- `test_report_cache.json` in the app documents dir — the last report this install
  fetched, so a later offline launch is not stuck with what the build shipped.

*Tools.* `tool/generate_test_report.dart` (`--input machine.jsonl --commit/--branch/
--version/--run-url`) parses one run; `tool/sync_test_report.dart` decides what gets
packaged, taking the newest of the file already at `--output`, each `--candidate`,
`--candidate-machine` (a local `flutter test --machine` run, version read from pubspec)
and `latest.json` unless `--no-fetch` — an unreachable network or missing file just keeps
the existing report, so offline builds still package the last one they had.
`tool/render_test_report_summary.dart` renders the CI job summary from the same JSON, so
the summary and the app can never disagree.

*Runtime.* `TestReportService` (singleton): `load` = newest of bundled + cached (no
network, drives the red dot), `loadOnline` = `HttpClient` GET of `latest.json`
(`onlineReportUrl`, all failures swallowed to an unavailable report, writes the disk cache
on success, skipped on web), `loadForDisplay` = newest of online/cached/bundled with the
layer it came from (`TestReportSource`, `sourceLabel`: "Fetched just now from CI" / "Last
fetched results (offline)" / "Packaged with this build (offline)"); `setReportForTest`/
`setCachedReportForTest`/`setOnlineReportForTest`/`refreshOnline`/`resetForTest`. The red
failure dot uses the offline-best report loaded at startup, filtered through an
acknowledgement marker (`hasUnseenFailures`): the Tools ▸ Test Results entry — and, only
when the "Red dot for failed tests" Appearance setting (`Config.showFailureDotOnMenu`,
default off) is on, the home app bar's custom hamburger `leading` (default "Open
navigation menu" tooltip, opens the drawer via `Scaffold.of`) — carries a 9 px red dot
(`Key('test-failure-dot')`). Opening the Test Results page calls `markSeen(displayed)`
(unawaited): it records the newest acknowledged run date plus fingerprints
(commit|date|counts) of the seen + offline-best reports in `test_report_seen.json`, so
every dot disappears immediately and stays off across restarts until a run newer than
anything acknowledged fails. `TestResultsPage` (a Tools page, `test_results` start-tool
key) is a StatefulWidget with an app-bar refresh action: a version card (source label,
"Ran 3 hours ago on dev" via `formatReportAge`, running vs tested version with a
match/mismatch note, "Open CI run" when `runUrl` is set), a summary card
(passed/failed/skipped/total plus "ran in 42.3 s" when durations are known, commit +
branch + run time), one ExpansionTile per failed test with its error + stack trace,
and — since 0.1.129 — an "All tests" section listing every suite as an ExpansionTile
(monospace path, per-suite counts + time, failing files sorted first) whose children
are one row per test: green check / red close / grey skip icon, name, and
`formatTestDuration` ("340 ms" under a second, "2.1 s" above). Reports without suite
detail show a "predates per-test details" note instead.
`tool/render_test_report_summary.dart` mirrors the same detail as a per-suite
markdown table (✅/❌, counts, time) in the CI job summary. `Config.resetVersionForTest()` clears the
memoized version future so widget tests reload it per async zone. Page tests default every
layer to "no data" in `setUp`: the disk-cache read is real file I/O and would never
complete inside `testWidgets`' fake-async zone.

**Search (0.1.90):** the app-bar title is a live search field ("Search tasks"). A
non-empty query narrows every tab and the schedule view to tasks whose title,
description, note, label or assigned project name contains it (case-insensitive
substring); a clear (×) suffix button resets it. Index-based handlers (move/delete)
recompute the same filtered list so they act on the right task, but reorder is a no-op
while searching and `_saveTasks` renumbers `listRanking` from the UNfiltered tab
(`_tasksForTab(i, applySearch: false)`) — otherwise a save during search would scramble
hidden tasks' order.

**Dice timer (0.1.94):** a dice app-bar action (`Icons.casino`, immediately right of the
search field) picks a random open (not done) task from the Today tab — ignoring any active
search — and pushes `DiceTimerPage` (`lib/ui/dice_timer_page.dart`). The page shows the
rolled task above a rotary egg-timer dial (`DiceTimerDial`, one full turn = 60 min,
whole-minute snapping) opened pre-wound to a 20-minute default — turn back for less time, on
past 20 for more: winding uses raw pointer events (a `Listener`, NOT a pan recognizer — an
ancestor scrollable would win mostly-vertical drags in the gesture arena), with
`dialAngle`/`dialAngleDelta` keeping the rotation continuous across 12 o'clock. Releasing the
dial starts the countdown (a 1 s decrementing ticker, deliberately not wall-clock-anchored so
tests can fake-pump it) and shows the remaining time, the percentage of the started duration
still left (`DiceTimerController.percentLeft`, relative to `_total`), and the wall-clock end
time ("Ends at 14:32"). Grabbing the dial mid-countdown (or mid-ring) pauses/silences and
rounds up to whole minutes for rewinding. The page is sized to fit on one screen without
scrolling: the action buttons sit in a compact grid (two per row — only "Postpone to
tomorrow" keeps a full-width row, its label is too long to halve) and the dial diameter
adapts to the viewport (`maxHeight - 340`, clamped to 220–280 px) via a `LayoutBuilder`,
with a `SingleChildScrollView` kept only as a safety net for very short viewports.

The live timer lives in **`DiceTimerController`** — a singleton `ChangeNotifier` that owns the
ticker and state (task/phase/remaining/total/endAt), NOT the page's `State`. So leaving the
page (back button, other navigation) keeps the countdown running; the page is a thin view
that `configure()`s the controller in `initState` (a no-op that keeps a still-running same
task, so re-entering reattaches — `configure` must not `notifyListeners`, it runs during
build) and rebuilds off `addListener`. The app-bar dice icon shows a `Badge` and switches its
tooltip to "Return to the running task timer" while a timer `isActive` (running/paused/
ringing); tapping it then reopens the existing timer instead of re-rolling. **Done** (finish
early — marks the task done and clears the timer) and **Lock touch** are available from the
very start (even before a countdown begins); while **running** the page adds **Pause**
(freezes the time left → **paused** phase, whose center reads "Paused" and which offers
**Resume**/**Done**). **Lock touch** flips a page-local `_locked` flag that lays a full-screen
scrim (`AbsorbPointer` over the whole `Scaffold` + a `PopScope(canPop: !_locked)` to swallow
the system back) with only an **Unlock** button live — so a pocket bump or an incoming call
can't disturb the timer. At zero the controller runs the alert the settings ask for (see
below; best-effort, injectable via `DiceTimerController.onRingAlert` for tests) — this fires
even if the page was left, though a mid-ring page exit silences melody and vibration
(`DiceTimerController.stopAlert`) while keeping the expired state — and offers: **Done**
(marks the task done via the home page callback), **Postpone to tomorrow** (same semantics as
moving to the Tomorrow tab, including recurrence detach), and **+1/+5/+10 min** (stops the
ring and restarts the countdown with that much time). With no open Today tasks (and no timer
already running) the dice shows a "No open tasks for today" snackbar instead.

**Cancel timer (0.1.127):** a muted-error `TextButton` in the action grid (beside Lock touch
while running/paused, beside Done at the ring), shown in the running, paused and ringing
phases (never on the untouched dial — there is nothing to cancel yet). It calls `DiceTimerController.clear()`, so the ticker, any melody/vibration and the
OS-scheduled ring all stop, then pops the page with a "Timer cancelled" snackbar. This is the
only exit that leaves the task untouched — Done and Postpone both answer for it, and plain
back-navigation deliberately keeps the countdown alive.

**Start timer from a task (0.1.132):** double-tapping a task tile opens a little
bottom-sheet menu — for now a single "Start timer" entry (subtitle shows the default
duration). The double tap is detected by hand inside the tile's `onTap` (two taps within
`kDoubleTapTimeout`, the second one taking back the expansion toggle the first made) —
deliberately NOT via `InkWell.onDoubleTap`, whose recognizer holds the gesture arena for
the double-tap timeout on every tap in the tile, delaying the checkbox and expand-on-tap
by ~300 ms and deadlocking fake-async widget tests (the streak checkbox test caught
this). The menu only appears when `TaskTile.onStartTimer` is set (it is null in the
standalone-tile tests). Picking "Start timer" calls
`HomePage._startTaskTimer`, which — unlike a dice roll — `configure()`s
`DiceTimerController` for *that* task and immediately `releaseDial()`s, so
`DiceTimerPage` opens with the countdown already running at
`Config.diceTimerDefaultMinutes`; the dial still pauses/rewinds it like any dice timer,
and Done/Postpone/Cancel behave identically. The page header is parameterized for this
(`DiceTimerPage.caption`/`captionIcon`: "Timer for" + `Icons.timer_outlined` here,
"The dice picked" + `Icons.casino` by default). Double-tapping the task whose timer is
already live reopens the running countdown; starting a timer for a different task
replaces the old one — the double tap is an explicit choice for that task.

**Dice timer settings (0.1.120):** `Config.diceTimerAlertMode` picks what zero does —
`melody` (plays `Config.diceTimerMelody` at `Config.diceTimerVolume`, looping, like an
alarm), `vibrate` (repeating buzz only), `notification` (**the default**) or `silent`.
`Config.diceTimerAlsoVibrate` (off by default) adds the buzz to the melody/notification
modes, and `Config.diceTimerDefaultMinutes` (20) sets where the dial opens — so
`DiceTimerController.defaultDuration` is a getter now, not a const. `diceAlertPlan()` in
`dice_timer_page.dart` resolves those settings (plus `Config.enableNotifications`) into a
pure `DiceAlertPlan {melody, vibrate, notification}`, which both the ring and the UI read:
**a notification alert with notifications switched off degrades to complete silence**, never
to a sound nobody asked for, and a silent plan (`DiceAlertPlan.isSilent`) shows `0:00` +
"Time's up" in the dial instead of the loud red "Time's up!". Vibration goes through
`AlarmVibration` (`lib/services/alarm_vibration.dart`) — the `besttodo/alarm_audio` method
channel gained `vibrate` / `stopVibrate`, a `USAGE_ALARM` waveform repeating until stopped
(no-op off Android, like `AlarmSound`). The controls live in one shared widget,
`DiceTimerSettingsList` (`lib/ui/dice_timer_settings.dart`, writes through to `Config` and
saves on every change, melody Preview included), rendered both by the Settings page's "Dice
timer" section (index 6, hidden with the `dice_timer` feature) and by the bottom sheet behind
the timer page's app-bar gear ("Timer settings").

**Ringing like a real alarm (0.1.122):** away from the timer page zero is delivered through
the alarm pipeline, not by the in-page alert — full-screen `AlarmRingPage`, insistent, one
Stop button — so it works with the app backgrounded, killed or the phone locked. Three
delivery paths, picked by where the user is (`DiceTimerController._ring`):
1. **timer page on screen** (`_pageVisible && _appResumed`) → the in-page alert as above
   (dial + Done/Postpone/+min); no OS alarm is armed at all.
2. **app open, elsewhere** → `_ringFullScreen` presents `AlarmRingPage` through
   `DiceTimerController.presentFullScreenRing` (wired in `main.dart` to the same `_showAlarmRing`
   real alarms use), cancels the OS ring and starts the vibration itself.
3. **app away** → the OS-scheduled ring fires: `NotificationService.scheduleDiceTimerAlarm`
   puts one alarm on the normal ladder (`_zonedScheduleLayered` + `AlarmWatchdog.armDiceTimer`
   backup) under the fixed `kDiceTimerNotificationId` / `kDiceTimerUid` (`alarm_ids.dart`),
   with `_alarmDetails(silent: melody == null)` so the vibration-only and notification alerts
   stay quiet while still taking the screen.

Arming is driven by app lifecycle, not by a timer: `_DiceLifecycleWatcher` flips
`_appResumed`, and `_syncOsAlarm` applies the pure rule `diceOsAlarmAction(phase, appResumed,
alertSilent)` — **arm** while running with the app away, **cancel** when the app is back or
the countdown is paused/rewound/cleared, **leave** a ring that is already going (only Stop /
Done / Postpone / +min clear it). This is why there is no race between the two paths: only
one of them is ever armed. A silent alert (silent mode, or a notification alert with
notifications switched off) arms and presents nothing at all. Starting a countdown asks once
per app run for the alarm permissions (`_ensureRingPermissions`, Android only).

Both paths share one payload builder, `diceRingPayload` in `alarm_ids.dart`, so the alarm
screen is identical either way. The dice uid is a *standalone ring*: `_isStandaloneRing`
keeps `dismissAlarmFromRing` / `snoozeAlarmFromRing` from rescheduling alarm storage for it,
and stopping it cancels the dice watchdog. When the ring page closes, `main.dart`
(`_afterDiceRingStopped`) silences the in-app melody/vibration and calls
`openRunningDiceTimer` (`home_scaffold_key.dart`, set by `HomePage`) — which reopens the
timer page in its finished state, unless it is already on the stack or the timer is gone
(cold start after a kill: the alarm still rings, but there is no in-memory countdown left).

**Home widget updates** after every save and at a self-rescheduling midnight timer: writes
the "due today or overdue" list text (or "Well done! No more tasks for today!"), a progress
percent, and a color (green all done / orange exactly 4 left / red ≥5 left).

**First-run seeds:** 3 today-tasks + 1 future task; dev builds additionally seed 20 future
tasks, 20 deleted tasks, and 14 days of stats (marker strings prevent re-seeding). Dev
builds also spread 9 of the seeded future tasks across the three seed projects (one task
per Kanban column in each project) so the Projects tool opens populated — including on
desktop/web where storage may not persist; skipped as soon as any seeded task carries a
`projectId`, so manual (re)assignments survive reloads. "First run" means *no non-wish
task exists* (0.1.138): `loadItems()` merges the one-time Todo.md import into the task
list as wishes, so a plain `isEmpty` check saw a fresh install as an existing one and
skipped the starter tasks (and the dev range/history/reminder seeds) entirely. The starter
tasks are inserted ahead of the imported wishes.

### 4.4 Settings (all persisted in `settings.json` via `Config`)

Appearance: dark mode, minimalist mode (0.1.101, default off: swaps both themes for a
monochrome ink-on-paper `buildMinimalistTheme(brightness)` in `main.dart` — pure greys
only, transparent `surfaceTint`, no ink splashes, selected chips underlined via a
`WidgetStateTextStyle` label instead of a colour fill; the orange/red/green swipe
backdrops in `task_tile.dart`/`home_page.dart` turn neutral ink; combines with dark
mode), icon tabs, "Red dot for failed tests" (`showFailureDotOnMenu`, default **off**:
marks the home hamburger icon while the newest test run has unacknowledged failures,
see §4.3), 24-hour time (default on), date format (6 choices,
default `dd.MM.yy`). Tasks: add-to-top, swipe-left-delete, default delay 0–10 s slider,
start tab (simple mode hides the tool-related entries, see §4.6), default start page
(`startTool`: the task list or any enabled tool — Alarms, Countdown,
Projects, Chronize, Usage Data, Productivity Stats; the tool is pushed on top of the task
list after loading, so back lands on the tasks), start in schedule view, Chronize hour
wheel. Widget: progress line, "Check off tasks on the widget" (`widgetCheckboxes`,
default **off**, see §8). Notifications:
enable (default **off**), quiet hours (default 22:00–07:00, stored as minutes-since-midnight;
applied to task notifications only, never alarms), default notification delay (dev 3 s /
prod 300 s). SMS report: see §7. Sync & export: synced-mode switch + sync-folder picker
(§4.7), Export/Import buttons. `Config.applyMap` is defensive
(clamps ranges, whitelists date formats). Dev mode = `!dart.vm.product`: skips intro, shows
the app-bar date stepper, seeds demo data.

**Settings search (0.1.96, independent from the home task search):** a magnifier action in
the Settings app bar toggles search mode — the pinned section-chip header becomes an
autofocused text field ("Search settings", clear × suffix, close action in the app bar).
A static registry (`_SettingsSearchEntry`: title, section index, extra keywords) lists
every setting; a non-empty query replaces the sections with matching entries (case-
insensitive substring over title, keywords, or section name; section shown as subtitle).
Tapping a result closes search and `_jumpToSection`s to its section (deferred one frame so
the sections re-mount first). New settings must be added to the registry.

**`_jumpToSection` (chips + search results):** the sections are lazy `SliverList` children,
so an unbuilt one has no context and `ensureVisible` would no-op; the jump walks the scroll
one viewport at a time until the target's key has a context. Two rules learned the hard way
(0.1.118, when the tall Mode & features section pushed the later sections down): walk
**towards** the target (`index < _activeSectionIndex` ⇒ upwards, else downwards — a
down-only walk left every earlier section unreachable from the bottom of the page), and
treat only a hop that changes **neither offset nor `maxScrollExtent`** as the end
(`maxScrollExtent` is an estimate that grows as more children are laid out, so "reached the
bottom" fires long before the real bottom). Test note: every chip is built even when
off-screen, so `scrollUntilVisible`/`dragUntilVisible` skip their drag and run
`ensureVisible` on a chip inside the **pinned** header — which drags the settings list to
its very bottom. Tests must drag the chip row by rect instead (see `streak_ui_test.dart`).

**Collapsible sections (0.1.123):** every section card's title row is an `InkWell` with a
trailing chevron (`AnimatedRotation`, 0 → half turn, tooltip "Expand/Collapse &lt;section&gt;");
tapping it toggles the section, its body simply not being built while collapsed.
`_collapsedSections` (a `Set<int>` of section indexes, in-memory only — not persisted)
starts as `{1}`, so **Mode & features** is closed on every open (longest section, rarely
touched after setup). A right-aligned `TextButton.icon` above the first card is the master
toggle: "Collapse all" (`unfold_less`) while any visible section is open, "Expand all"
(`unfold_more`) once they are all closed. `_jumpToSection` removes the target from
`_collapsedSections` first, so chips and search results never land on a closed title;
toggles re-run `_updateActiveSectionFromScroll` on the next frame because the list height
changed under the chip row.

### 4.5 Streak (the flame, 0.1.115)

Daily-completion streak gamification. `StreakService` (ChangeNotifier singleton,
`streak.json` via `SafeFile`) stores one JSON map `completionsByDay` of dayKey →
completion **count** (counts, not booleans, so toggle+untoggle on the same day cancels
out exactly and per-day stats are possible). `recordCompletion(when)` returns true on the
day's **first** completion (the streak-kept moment); `recordUncompletion` decrements and
removes the day at zero. Wish items never count. Hooked into both completion paths in
`home_page.dart` (`_recordStreakToggle`: tile checkbox + dice-timer "done"), using
`_currentDate` so the dev date stepper works.

**Streak semantics:** consecutive active days ending today or later-graced; a day still
in progress never breaks the streak. Grace (`Config.streakGraceHours`, 24 default / 48):
24 = every calendar day needs ≥1 completion; 48 = a single missed day between active days
is forgiven (`_allowedGap` 0/1 applied both when anchoring from today and while walking
back). `longestStreak()` scans full history under the same rule. Flame maxes out at
**365 days** (`flameProgress` = streak/365 clamped to 1).

**UI:** flame `IconButton` in the home app bar directly left of the dice
(`ListenableBuilder` on the service; hidden when `Config.showStreak` false). Icon grows
22→30 px and colours grey → orange → deep orange → red with progress; a `Badge` shows the
day count. Tap → `StreakPage`: big flickering flame (700 ms repeat-reverse controller —
**never `pumpAndSettle` this page in tests**, it never settles; scale/sway/glow scale with
progress), fun level names ("First spark" → "MAXIMUM FIRE"), progress bar to a full year,
stats card (streak start, longest ever, active days, total completions, best day, average
per active day), gear action → Settings. First completion of the day plays a ~1.4 s
self-removing overlay celebration (`showStreakCelebration`: flame pop + sparks + "Streak
kept — N days!", `IgnorePointer`, gated by `Config.streakCompletionAnimation`).

**Seeding:** on first load without `streak.json` (`needsSeed`), backfilled from existing
history — per day the **max** of daily-stats completion counts and `completedAt`
timestamps on live+deleted tasks, so nothing double-counts and long-time users start warm.
(In dev builds the seeded demo daily-stats produce a pre-lit flame; tests write an empty
`streak.json` up front to opt out.) Dev/demo builds then also run `seedDevStreak()`, which
fills the last `Config.devSeedStreakDays` (**50**) days back from today with one completion
each — max-merged, so real counts survive — giving the Chrome demo, where nothing persists
between runs, a 50-day flame instead of the 14 days the stats seed covers. It runs only
inside the `needsSeed` branch, so a dev install's real streak is never papered over.

**Reminder:** optional daily nudge (`Config.streakReminderEnabled`, default off; time
`streakReminderMinutes`, default 22:00). `syncReminder()` re-arms a **one-shot**
`zonedSchedule` (fixed id `kStreakReminderNotificationId = 0x20000002`, task channel,
`inexactAllowWhileIdle` — deliberately NOT the alarm ladder, no exact-alarm permission
needed) for today's time if nothing is done yet, else tomorrow; re-synced on every app
start, completion, and settings change; cancelled when reminders are off or the streak is
hidden. Settings live in a searchable "Streak" Settings section (show/hide, 24h/48h
`SegmentedButton`, reminder toggle + time picker, celebration toggle).

### 4.6 Simple mode & feature switches (0.1.118)

Two ways to run the app, chosen on a first-run picker and changeable in Settings.

**Picker (`lib/ui/mode_select_page.dart`):** `ModeSelectView` is the chooser itself
(no `Scaffold`) — two cards ("Simple mode" / "Full mode", `Start simple` /
`Use everything`); picking one sets `Config.simpleMode` + `modeChosen` and saves
(`settings.json`, so it never reappears). It is the last page of the intro on a first
run (§10), and `ModeSelectPage` wraps it in a `Scaffold` for the ask-again path.
`MyApp.showModePicker` is a constructor flag (default false, and false whenever the
intro is showing) so screenshot/integration runs and tests never hit the picker;
`MyApp.restartModePicker()` clears `modeChosen` and pops back to the standalone page,
while `MyApp.restartIntro()` (About) replays the slides and the question together.

**Feature registry (`Config`):** `featureKeys` / `featureLabels` / `featureDescriptions`
(index-aligned) + `Map<String,bool> featureEnabled` (all true by default, persisted under
`'features'`; unknown/missing keys count as enabled). Keys: the eight tool keys (equal to
`startToolOptions` minus `tasks`) plus `streak`, `dice_timer`, `schedule_view`, `search`,
`deleted_items`, `changelog`, `app_logs`, `startup_times`, `sms_report`.

**`Config.isFeatureEnabled(key)` is the single gate:** in simple mode it returns false for
everything except `Config.simpleModeFeatures` (`deleted_items`, `changelog`, `app_logs`,
`startup_times` since 0.1.121 — the app's own service pages are not "extra features", and
the deleted list is the undo of a delete, so simple mode only strips the home surface and
the tools); in full mode it returns the per-feature switch. About has no feature key and is
always in the drawer. Call sites: `home_page.dart`
drawer entries and the Tools section (built from `_toolEntries`, hidden entirely when no
tool is enabled), the app-bar streak flame / dice / schedule toggle / search field (which
becomes a plain "BestToDo" title), `_buildToolPage` (returns null for a disabled tool, so
a stale `startTool` or deep link can't reach it) and `_recordStreakToggle`.
`_updateSettings` resets `_scheduleView`/`_searchQuery` when their feature disappears, so
switching modes can't strand the home page in a view with no way back.

**Settings section "Mode & features" (index 1):** the simple-mode switch, "Show the mode
picker again", and — full mode only — one `SwitchListTile` per feature. Sections owned by
a feature drop out of the chip row, the scroll list and the settings search when it is
off (`_isSectionVisible`: Streak → `streak`, SMS report → `sms_report`); single entries do
the same via `_isEntryVisible` (start-in-schedule-view, Chronize hour wheel, default start
page). Feature labels are searchable (`_featureSearchEntries`). Turning off the tool that
is the configured `startTool` resets it to `tasks` (`_dropUnavailableStartTool`), and the
start-page dropdown only offers enabled tools.

### 4.7 Synced mode — background folder sync on quit (0.1.131)

The offline/synced choice: `Config.syncEnabled` (default **off** = fully offline) +
`Config.syncFolderPath` (empty until picked), both in Settings → **Sync & export**
("Synced mode" switch; enabling it with no folder opens the `getDirectoryPath` picker
immediately; the "Sync folder" tile only shows while enabled). `SyncService`
(`lib/services/sync_service.dart`, singleton with `resetForTest`) writes the task list
to `<folder>/besttodo_tasks.json` (`{sync_version: 1, synced_at, app_version,
task_count, tasks[]}`) — **tasks only** for now.

Since 0.1.135 every sync also writes `<folder>/besttodo_tasks.md`, an Obsidian-friendly
Markdown companion (`SyncMarkdown.build` in `lib/services/sync_markdown.dart`, pure and
unit-tested): a header comment marking the file auto-generated, `# BestToDo tasks`, a
`Synced <yyyy-MM-dd HH:mm> · BestToDo <version> · N open / M total` line, then one `##`
section per home tab (Today/Tomorrow/Day After Tomorrow/Next Week/Next Month/Future) —
same bucketing and open-first/ranking sort as the tabs (`ItemViews.homeBucket`), deleted
tasks excluded, empty sections skipped. Lines follow the Obsidian Tasks plugin format:
`- [ ]`/`- [x]` + title (newlines flattened) + `📅 yyyy-MM-dd` due date (future-sentinel
dates omitted) + `✅ yyyy-MM-dd` completion date. Point the sync folder into an Obsidian
vault (directly or via Syncthing/Dropbox) and the list renders natively. One-way: the
file is atomically overwritten (`SafeFile`) on every sync; a failed Markdown write fails
the whole sync run (red history entry) like the JSON write.

Since 0.1.141 the repo also ships **Tier 2** of the Obsidian integration: a read-only
Obsidian community plugin in the top-level `obsidian-plugin/` folder (TypeScript +
esbuild, own npm package and CI job `obsidian_plugin.yml` — not part of the Flutter
build). It renders `besttodo_tasks.json` as a custom `ItemView` (ribbon icon /
"Open task view" command): the six home buckets, disabled checkbox + title + `📅` due
date (sentinel omitted) + `✅` completion date + `🔁` recurring marker, label chip and a
generic `📁 project` chip (the sync file carries no project names), open-first/ranking
order, plus an "as of …" line showing `synced_at` + app version. It re-reads on
Obsidian's file-change events (safe because the app's write is atomic), refuses unknown
`sync_version` values with a friendly notice, and parses tasks as tolerantly as
`Task.fromJson`. The contract lives in the pure module `obsidian-plugin/src/model.ts`
(mirrors `ItemViews.inHomeBucket`, `sortTasks`, `Task.fromJson`) and is pinned by jest
tests (`obsidian-plugin/test/model.test.ts`) mirroring `test/sync/sync_markdown_test
.dart`. Strictly a viewer — it never writes. Tier 3 (two-way via a change journal)
remains designed-only in `.claude/notes/obsidian-integration.md`.

**Trigger — quit, never startup:** `_MyAppState` is a `WidgetsBindingObserver` that
forwards every lifecycle state to `SyncService.onLifecycleChanged`. The first
hidden/paused/detached after a resume starts exactly one fire-and-forget sync
(`_syncedThisBackground` latch, reset on `resumed`; hidden→paused→detached arriving in
a row must not sync three times). Nothing runs at launch: the service is only touched
at startup by a lazy `ensureLoaded()` (memoized read of `sync_log.json`) from the home
page/App Logs, so first frame and load paths are untouched. The sync reads
`readTaskListRaw()` (state already on disk — every mutation saves), so it needs no page
state.

**Graceful failure:** the write is atomic (`SafeFile`, tmp+rename — a reader or crash
can never see a half-written file); every failure (no folder chosen, folder deleted,
write denied) is caught and becomes a red history entry, never an exception. Overlapping
runs are skipped (`_syncInFlight`).

**Sync history (App Logs → "Sync" tab):** every run is a `SyncLogEntry` (at,
durationMs, itemCount, success, message, trigger 'app quit'/'manual'), newest first,
capped 100, persisted in `sync_log.json` and mirrored as a one-liner into `LogService`.
The page has two tabs since 0.1.131: "Logs" (the live 24 h `LogService` list) and
"Sync" (green check "Synced N items in M ms" / red error "Sync failed: reason", with
timestamp · trigger subtitle).

**Red dot:** a failed sync sets `hasUnseenError` (persisted as `unseen_error`), which
puts a small red dot (Key `sync-error-dot`, same `_iconWithFailureDot` stack as the CI
test-failure dot but its own key) on the drawer's App Logs entry via a
`ValueListenableBuilder`. Opening App Logs calls `markErrorSeen()` (dot gone, entry
stays); a later successful sync also clears it.

Tests live in their own silo `test/sync/` (service round-trip/failures/lifecycle latch
+ Sync tab, drawer dot, settings switch).

## 5. Alarm subsystem (the reliability showpiece)

Two **independent** systems share nothing but the log: the user-facing alarm clock
(flutter_local_notifications) and the SMS report (android_alarm_manager_plus isolate).
Every mechanism below exists because a real failure was observed on Samsung/One UI
hardware — see Part II §"The reliability arc" and `.claude/notes/alarm-work-spec.md`.

### 5.1 Model & ids

`Alarm`: uid, name, description, hour/minute, optional one-off `date`, `isRepeating` +
`repeatDays` (Mon=1..Sun=7), `vibrate`, `overrideDnd` (default off), `color`, snooze
(enabled, duration min, default 9), `enabled`, `melody` + `volume` (0–1, fraction of the
device maximum). Melody/volume are played by the ring UI through the native
`besttodo/alarm_audio` channel (`AlarmSoundPlayer.kt`): synthesized melodies on the ALARM
stream, stream pinned to max during playback (previous level restored on stop) with the
alarm's volume applied as track gain — so loudness is independent of the phone's current
volume; `overrideDnd` additionally plays through Do Not Disturb. (`snoozeMaxCount` is
stored but **not implemented** — known deferred work.) `nextOccurrence()` is the
scheduling brain; a one-off *without* a date re-arms for tomorrow after firing (no
delivered-callback exists to auto-disable it).

Deterministic id scheme so every path can find an alarm's notifications:
`base = (uid.hashCode & 0x1FFFFFF) * 8`; `base+0` one-off/snooze slot, `base+1..7` weekday
slots, `base + 0x10000000` watchdog id; fixed test-alarm ids at `0x20000000/1`. All within
signed 32-bit; spaces cannot collide.

**Item-linked reminders (0.1.110):** `Alarm` additionally carries `itemUid?` +
`triggerAnchor` (`start`/`end`) + `triggerOffsetMinutes` (negative = before; serialized
only when linked, so standalone alarm JSON is byte-identical to before). A linked alarm
is an ordinary one-off whose `date`/`hour`/`minute` are rewritten from its task by
`ReminderSyncService` (fire-and-forget from `saveTaskList`; free when no linked alarm is
in memory): reschedule → follows (and re-enables), complete/undated → disabled (never
deleted, so reopening revives it), task gone → removed, rename → name follows. Created
via the one-tap "Remind me 15 min before due" on the task-detail page (hidden for
undated tasks). **The scheduling pipeline below the model is untouched.**

`AlarmService` is a singleton `ValueNotifier` store; every mutation persists →
syncs the widget → **awaits** `rescheduleAll` (so short-lived isolates don't die mid-work).
`toggleInStorage(uid)` is the static isolate-safe path used by widget toggles: load from
disk, flip, save, sync widget, and **always** reschedule (the old `_loaded`-guarded version
was why widget toggles silently did nothing with the app closed).

### 5.2 Scheduling pipeline (per reschedule run)

1. Log a `RESCHEDULE (trigger)` banner.
2. **Individual cancel, never `cancelAll()`** — compute which `base+0` slots must be
   preserved (pending snoozes live there) and cancel only stale ids. `cancelAll` on every
   app-open used to kill pending snoozes.
3. Schedule each enabled alarm: repeating → one zoned schedule per weekday with
   `matchDateTimeComponents: dayOfWeekAndTime`; one-off → `nextOccurrence()`.
4. **Method ladder** per schedule, strongest first, first success wins, every attempt
   logged: `alarmClock` (setAlarmClock — immune to Doze) → `exactAllowWhileIdle` →
   `inexactAllowWhileIdle` (last resort). All with absolute-time interpretation.
5. **OS read-back verification**: `pendingNotificationRequests()` diffed against expected
   ids — "we called schedule()" ≠ "the OS kept it".
6. **Arm the watchdog** (Android): an independent `android_alarm_manager_plus` one-shot at
   `fireAt + 90 s` per enabled alarm (exact, wakeup, allowWhileIdle, rescheduleOnReboot),
   registry in SharedPreferences (`alarm_watchdogs_v1`).

**Watchdog fire logic:** no registry entry → alarm was edited meanwhile, done. Else check
(a) user ack (`recordAck` from every tap/snooze/dismiss, valid if after fireAt−5 min) and
(b) `getActiveNotifications()` for the alarm's ids. Either → DELIVERED, log OK. Neither →
primary path silently dropped: log FAIL with likely cause and **ring now** via
`showAlarmNotification` (~90 s late but it rings). Then re-arm for the next occurrence.

**Notification presentation:** channel `alarm_notifications_v2` (v2 = channel migration;
Android channel settings are immutable), Importance.max, `audioAttributesUsage: alarm`
(alarm volume stream), `fullScreenIntent`, `ongoing`, insistent flag (`additionalFlags:
[4]`) so it loops until acted on. Actions: Snooze (if enabled) + Dismiss. Snooze schedules
`now + snoozeMinutes` into the `base+0` slot through the same ladder and gets its own
watchdog cover. When the ring UI starts the alarm's own melody it hands the notification
over to the sound-less channel `alarm_notifications_silent_v1` (same actions/vibration, no
channel sound) so the default sound and the melody don't stack; if melody playback can't
start, the loud channel keeps ringing as the reliability baseline.

**Full-screen ring UI (0.1.88):** a ringing alarm presents `AlarmRingPage`
(`lib/ui/alarm_ring_page.dart`) — a clock-app-style full-screen page (live clock, alarm
name/description, pulsing icon, big Snooze / round Stop button, dark gradient themed with
the alarm's `color`; back is blocked, the alarm must be answered). Delivery paths into it:
(a) the notification's full-screen intent fires while the device is locked/screen-off —
`MainActivity` detects the `SELECT_NOTIFICATION` intent whose `payload` extra contains an
alarm `uid` and sets `setShowWhenLocked/setTurnScreenOn` (cleared again via the
`besttodo/alarm_ring` MethodChannel when the page closes, so the rest of the app never
sits over the keyguard); cold start then reads `getNotificationAppLaunchDetails()`
(`getAlarmLaunchPayload`), a warm app gets the response via `onDidReceiveNotificationResponse`
→ the `onAlarmRing` handler registered by `_MyAppState`, which pushes the page (guarded
against double-push). (b) tapping the ringing notification — same wiring. The sound keeps
coming from the insistent notification while the page shows. Page **Stop**: `recordAck` →
cancel the alarm's active notifications (`plugin.cancel` also kills same-id pending
schedules, e.g. the auto-rearmed next weekly fire) → full reschedule from storage.
**Snooze**: ack → cancel actives → reschedule → snooze scheduled last (so the reschedule
can't clear the `base+0` slot) → snooze watchdog. The watchdog backup ring passes the
alarm `uid` into `showAlarmNotification`, which then posts under the alarm's own `base`
id with the full payload — so the backup ring gets the identical full-screen treatment.
The Android 14+ "full screen intents" special access is checked in `ensureAlarmPermissions`
(opens the system toggle when revoked) and in diagnostics via
`NotificationManager.canUseFullScreenIntent` over the `besttodo/alarm_ring` channel.

**Reboot/update:** boot receivers (`BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, quickboot) for
both plugins + `rescheduleOnReboot` + full reschedule on every app launch. Force-stop
drops all OS alarms until next launch — platform rule, documented, unfixable.

**DST:** next-occurrence stepping rebuilds wall-clock `TZDateTime` per day instead of
`add(Duration(days:1))` (which shifts the local hour across DST transitions).

### 5.3 The alarm log & diagnostics

`alarm_log.txt`: `YYYY-MM-DD HH:mm:ss.mmm [OK|FAIL|WARN|INFO] STAGE | message`, stages
ENV/PERM/SCHEDULE/VERIFY/BACKUP/FIRE/ACTION, section banners, self-trimming, write-chained
per isolate, mirrored to `debugPrint` for logcat. Viewable/copyable in-app (Alarms → log
icon) with FAIL/WARN/OK colorization.

Startup diagnostics ("alarm doctor", also on-demand): device/OEM/SDK, notification +
channel state, exact-alarm permission, battery-optimization exemption, per-OEM power-saver
hints (samsung/xiaomi/huawei/honor/oppo/vivo/oneplus/meizu/asus each get the specific
setting to change), full-screen-intent access (Android 14+ can revoke it → the alarm
degrades to a banner while locked; logged with the settings path), configured alarms vs
what the OS reports pending. "Test alarm (1 min)" exercises the full ladder+watchdog with
fixed test ids.

## 6. Notifications (platform split)

`notification_service.dart` facade with conditional imports: `_io` (Android/iOS — the real
implementation), `_web` (immediate `dart:html` notifications only; scheduling is a no-op),
`_stub` (everything no-op). Two Android channels: `task_notifications` (Importance.high)
and `alarm_notifications_v2` (see §5.2). Quiet hours shift only task notifications —
neither alarms nor the streak reminder (§4.5), which rides the task channel at an
explicit user-chosen time.

## 7. SMS daily report ("snitch text")

Social-accountability feature: a scheduled daily SMS with today's completed/uncompleted
counts and remaining list. Config (`sms_report_config.json`): enabled (default off), time
(default 22:00), message template with tokens `{hello}{nickname}{completed}{uncompleted}
{date}{list}`, recipients (nickname+phone+`enabled`), `subscriptionId` (-1 = default SIM;
dual-SIM support), optional completion-rate threshold (only send on days below X%).

**Recipient pause switch (0.1.117):** each recipient carries `enabled` (default true;
missing key in older payloads reads as true). Settings shows a `Switch` per row next to
edit/delete — off dims the row, appends "• disabled" to the number, and keeps the contact
so it never has to be re-typed; editing a paused recipient preserves the flag.
`SmsReportConfig.activeRecipients` is the send list, so the daily report and "Send test
now" both skip paused contacts; an all-disabled list logs "Skipped — all N recipient(s)
disabled" and the send diag reports "Sent x/y (N disabled)".

**Scheduling:** exact **one-shot self-re-arming chain** (`oneShotAt` →
`setExactAndAllowWhileIdle`, fixed id `0x517D`), NOT `periodic` (maps to `setRepeating`:
inexact since API 19, deferred indefinitely in Doze — this was a real bug). The callback
(background isolate; binding+registrant first) logs "Alarm fired" (proves background
delivery), **re-arms tomorrow before running the report** (crash-safe chain), then sends.
`applyFromConfig()` on every launch restores a force-stopped chain; ≥1 min headroom
prevents same-day double-fire.

**Permissions strategy:** requested in the **foreground** when the user enables the report
(SMS, exact alarm, ignore-battery-optimizations, notifications) — a background isolate has
no Activity and cannot show a permission dialog, so the send would be silently skipped.

**Sending:** per enabled recipient, render template, auto-multipart when >160 ASCII / >70 unicode
chars (carriers silently drop over-length single parts), send via `another_telephony` with
a 20 s status-listener timeout. Everything logged to `sms_report_log.json` (500 entries,
send + diag kinds) with an in-app viewer and export. "Send test now" calls the report
directly — the fact that test-send worked while the alarm never fired was the diagnostic
clue for the missing-receiver bug.

## 8. Home-screen widgets (Android)

Two widgets via `home_widget` (app group `group.homeScreenApp`):

- **Task widget** (`SimpleWidgetProvider.kt`): today's open tasks as text + colored
  progress bar (green/orange/red per §4.3); tap opens the app. Updated after every save and
  at midnight.
  **Opening the app (0.1.128):** every tap that is not a checkbox — the progress line (all
  three coloured bars carry their own handler; they sit above the text and are not part of
  it), the root container, the summary text, a task row/title, the empty state and
  "+N more" — launches `besttodotask://open` via `HomeWidgetLaunchIntent`. `main.dart`'s
  `_handleWidgetClick` branches **on the scheme first** (both widgets use the hosts
  `toggle`/`open`) and calls `_openTasks()`: it pops everything above the root route and
  sets `_openedFromTaskWidget`, which makes `_initialPage()` return `HomePage` regardless
  of `Config.startPage`. So the widget always lands on the task list, warm or cold, instead
  of resuming on whatever subpage the app was left on. (RemoteViews only deliver single
  clicks — there is no double-tap on a home-screen widget.)
  **Warm re-front (0.1.142):** `MainActivity` must keep the *default* task affinity —
  never `android:taskAffinity=""`. With an empty affinity Android could not match the
  widget's PendingIntent (which implicitly carries `FLAG_ACTIVITY_NEW_TASK`) to the app's
  existing task while the app sat in the background, so it started a second MainActivity
  in a new task that never got past the launch window: the widget opened a black screen
  only a force-close fixed. With the default affinity plus `launchMode="singleTop"` a
  warm tap re-fronts the running task via `onNewIntent` → `HomeWidget.widgetClicked`.
  `MainActivity.onCreate` additionally finishes a duplicate non-task-root instance
  created by a widget launch, revealing the live one underneath.
  **Black screen on warm re-front (0.1.143):** the 0.1.142 task fix alone did not cure
  the widget tap turning a backgrounded app into a permanent black window. Flutter 3.29
  made Impeller the default Android renderer, and on some devices/GPU drivers it comes
  back from a destroyed surface black and unresponsive (flutter/flutter#164717,
  #180054) — exactly the widget-tap-from-background path. The manifest therefore opts
  out (`io.flutter.embedding.android.EnableImpeller` = `false`, back to Skia); re-test
  before removing on a newer Flutter. Belt-and-braces, `_MyAppState`'s lifecycle
  observer calls `scheduleForcedFrame()` on `resumed` so a recreated surface always
  gets a frame even if the engine's own request goes missing, and every widget tap
  logs a `[widget]` breadcrumb to the App Logs page.
  The whole payload is built by `TaskWidgetService.sync(tasks)`
  (`lib/services/task_widget_service.dart`) — `home_page._updateHomeWidget` and the
  background isolate both go through it, so both looks always agree.
  **Checkable rows (0.1.125, `Config.widgetCheckboxes`, default off):** with the setting on
  the provider hides the text blob and draws up to `maxRows` = 5 rows
  (`widget_task_{i}_id/title/done` + `widget_task_count`/`widget_task_overflow`), each a
  vector checkbox (`widget_check_box[_checked].xml`) plus the title; done rows go grey.
  Rows are today's + overdue tasks, **open first** (so a busy day still shows what is left)
  and completed after them (so a mis-tap can be undone). The checkbox fires
  `besttodotask://toggle?id=` as a background broadcast → `alarmWidgetBackgroundCallback` →
  `Config.load()` (the isolate has no settings) → `TaskWidgetService.toggleInStorage`:
  flips `isDone`/`completedAt` in `tasks.json`, records the streak (guarded — the reminder
  re-sync needs the notification plugin, which may be unavailable there) and re-syncs the
  widget. The row (title + the space around it) and every non-row area open the task list
  as above.
  Because that isolate writes the file behind the app's back, `_HomePageState` is a
  `WidgetsBindingObserver`: on `resumed` it runs `_mergeWidgetCompletions`, which reloads
  storage and copies **only** the done state of changed uids into the in-memory list (plus
  the daily stats, which live only in the page) — without it the next in-app save would
  silently undo the widget's completion.
- **Alarm widget** (`AlarmsWidgetProvider.kt`): up to 4 alarms (time/name/sub + ON/OFF),
  "+N more", empty state. URI scheme `besttodoalarm://` — `open` (root container +
  header/+ + empty state + "+N more" → alarms list; since 0.1.90 the container-level
  intent makes ANY tap on the widget that lacks a more specific action open straight to
  the alarms page), `edit?id=` (whole row incl. its container → editor), and `toggle?id=`
  as a **background broadcast** that does not open the app: HomeWidgetBackgroundReceiver → Dart `alarmWidgetBackgroundCallback` →
  binding+registrant init → `AlarmService.toggleInStorage` → full awaited reschedule. This
  chain is what makes a widget toggle actually schedule/cancel the OS alarm with the app
  closed.

## 9. Android platform config

**Manifest permissions** (each exists for a reason): `INTERNET` (update check +
APK download from GitHub releases — it must live in the **main** manifest; debug/profile
get it implicitly from their own manifests, so its absence only breaks release builds,
as every network call then fails with "Failed host lookup"), `POST_NOTIFICATIONS` (13+),
`SEND_SMS`, `RECEIVE_BOOT_COMPLETED` + `WAKE_LOCK`, `SCHEDULE_EXACT_ALARM` +
`USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `SET_ALARM`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (the main fix for OEM deep-sleep dropping alarms),
`FOREGROUND_SERVICE`, `VIBRATE`, `REQUEST_INSTALL_PACKAGES` (in-app APK updates from the
About page; the user still confirms every install).

**Up-front permission flow** (`lib/services/permission_flow.dart`): every runtime
permission is asked in one pass — notifications, exact alarms, the battery-optimization
exemption and full-screen intent (via `NotificationService.ensureAlarmPermissions`, each
logged to `alarm_log.txt`), then SMS — at the two moments the user expects the question:
picking the **full experience** ("Use everything" on the mode picker, or turning simple
mode off in Settings) and the **first open after an app update** (startup step 7, §3).
A marker file `permissions_prompted_version.txt` holding the last handled
`version+build` makes the after-update ask one-time per version; picking simple mode
writes the marker without asking. At most one run per app session; individual features
still re-check lazily as before (alarms/dice pages, enabling the SMS report).

An `androidx.core.content.FileProvider`
(authority `${applicationId}.fileprovider`, paths `@xml/file_provider_paths`: cache + files
dirs) shares the downloaded update APK with the system installer as a `content://` URI.

**Receivers/services:** android_alarm_manager_plus `AlarmService` +
**`AlarmBroadcastReceiver`** (its absence was the original "SMS never sent" root cause —
the plugin ships an empty manifest and its PendingIntent targets this class) +
`RebootBroadcastReceiver`; flutter_local_notifications `ScheduledNotificationReceiver` +
`ScheduledNotificationBootReceiver` (BOOT/PACKAGE_REPLACED/quickboot) +
`ActionBroadcastReceiver` (snooze/dismiss); home_widget background receiver/service; the
two widget providers.

**Gradle (`build.gradle.kts`):** namespace/appId `com.mfficiency.best_todo_2`; minSdk
`max(23, flutter.minSdkVersion)` (androidx.work via home_widget needs 23); Java/Kotlin 11
with core-library desugaring; glance pinned to 1.1.1 (home_widget 0.8.1 pulls `1.+` which
would demand compileSdk 37); NDK 28.2.13676358. The root `android/build.gradle.kts`
forces every plugin subproject to Java/Kotlin JVM target 11 (afterEvaluate +
configureEach): home_widget 0.8.1 still compiles Kotlin at 1.8 while the androidx
bytecode it inlines is built with JVM 11, which broke every release APK build from
2026-07-28 until this override. **Signing:** `key.properties` if present,
otherwise a **committed fixed debug keystore** (`android/app/debug.keystore`, password
`android`) — deliberate, so every build (CI or local) is signed identically and updates
install in place instead of failing with a signature mismatch. A Gradle task renames the
release APK to `best_todo_<version>+<build>.apk` (e.g. `best_todo_0.1.117+87.apk`),
alongside the untouched `app-release.apk` CI uploads. The pubspec version must keep its
`+build` suffix — without it `flutter.versionCode` falls back to `1` and the APK is
rejected as a downgrade on any device holding an earlier build.

**ProGuard/R8 (`android/app/proguard-rules.pro`, wired in the release build type):** keep
rules for Gson generic signatures/`TypeToken` and `com.dexterous.flutterlocalnotifications.**`.
Without them R8 full mode strips the generic type info Gson needs, and **every** schedule
call in a release build throws `RuntimeException: Missing type parameter.` — the 0.1.85–87
releases could not hand a single alarm to the OS (only the watchdog backup rang, ~90 s
late). Do not remove.

**MainActivity** (`com/example/best_todo_2/MainActivity.kt`) is no longer a bare
`FlutterActivity`: it sets show-when-locked/turn-screen-on when launched by an alarm's
full-screen intent and hosts the `besttodo/alarm_ring` MethodChannel
(`canUseFullScreenIntent`, `clearLockScreenFlags`) — see §5.2 "Full-screen ring UI" — plus
the `besttodo/update` channel: `installApk(path)` hands a downloaded APK to the package
installer via the FileProvider (ACTION_VIEW, `application/vnd.android.package-archive`);
when the one-time "install unknown apps" toggle is missing (O+,
`canRequestPackageInstalls()` false) it opens that settings screen and returns
`"needs-permission"` so the Dart side tells the user to grant it and retry.

**Quirk — do not "fix":** Kotlin files sit under `com/example/best_todo_2/` but declare
`package com.mfficiency.best_todo_2` (matches applicationId). It works; blind refactors
here have broken builds before.

## 10. Secondary tools

### 10.1 Chronize (experimental continuous timeline)
Vertical infinite timeline on a continuous time axis (`_pixelsPerMinute` zoom 0.03–12.0,
default 0.9; `_topMinute` from a `_base` = start of today). Eight mark levels (1d, 12h, 6h,
2h, 1h, 30m, 10m, 5m); each fades in/out by pixel spacing (`markLevelOpacity`: ramp 22→52
px; day level always visible); finer intervals divide coarser so marks align. Left gutter
56 px with day labels ("D Mon", primary bold) and "HH:mm"; grid lines across the body;
error-colored now-line + dot recomputed every build. Pinch/pan with anchor-minute
preservation; mouse wheel support; fling → `FrictionSimulation(0.135, …)` in pixel space;
shared 300 ms easeOut glide for Today (centers now), zoom buttons (×1.6, compounding),
wheel settles, and nav taps. Right side: infinite Cupertino wheels (optional hour, day,
month; item 0 = `_base`; 120 ms settle debounce; suppress-counters to ignore programmatic
moves). Tasks render as chips at their due time, cascading downward on overlap (height 22,
gap 2); done = strikethrough on surfaceContainerHighest. When no dated event is on screen,
two centered pills point at the nearest past (arrow above) / future (arrow below) events
with coarse distances ("3 hours"); tap to glide there. Tap empty timeline → create dialog
(5-min rounded time); tap chip → edit dialog (sets `hasExplicitTime`).

### 10.2 Countdown timers (Tools → Countdown)
`CountdownTimerItem{uid,label,target,notifyOnZero,notifyRoundNumbers,milestones,createdAt,editedAt}`
in `countdown_timers.json`. Inline always-present composer (auto-names "Timer N", default
target now+7d, minimizes on scroll), in-place edit, drag reorder (manual mode) or sort by
name/added/edited/deadline asc/desc, swipe-to-delete with undo, 1 s tick. Collapsed rows
show whole-unit breakdowns ("in 2mo 1w 3d 4h"); expanded shows the same duration as
decimals in every unit (years=days/365.25, months=days/30.4375, …). Past timers count up
(orange); the instant date picker ranges 1900 → now+100y (0.1.103) so past events
(birthdays) can be created directly. Notify-on-zero fires a notification once (suppressed for already-past timers so
they never retro-fire; suppression is per-session).

**Milestone notifications** (# icon → `showCountdownMilestonesDialog`, per-timer, 0.1.105;
replaced the fixed power-of-ten-seconds ladder of 0.1.103). `notifyRoundNumbers` is now the
master switch for `List<CountdownMilestone>`
(`lib/models/countdown_milestone.dart`): `{value:int, unit:MilestoneUnit, direction:
MilestoneDirection}` where unit ∈ seconds|minutes|hours|days|weeks|months|years and
direction ∈ before|after|both. Any count of any unit, any number of entries.

A milestone is *not* compared as a span of remaining seconds — it resolves to **absolute
instants** relative to the target: `target − value` (before side) and `target + value`
(after side), via `CountdownMilestone.shift`. Seconds→weeks add a fixed `Duration`;
months/years walk the calendar with day-of-month clamping (`addMonths`: 31 Mar − 1 month →
28/29 Feb), so "10 months before" lands on the same day-of-month. This is what makes the two
directions symmetric and calendar units correct.

`CountdownTimerItem.dueMilestone({previousNow, now})` returns the `MilestoneHit`
(milestone + `isAfter` + instant) whose instant lies in the half-open window
`(previousNow, now]`, or null. The page keeps last-checked wall-clock per timer
(`_milestoneSeen`, per-session); the first observation only baselines (no retro-fire on
load/edit/dialog-save), and a window spanning several milestones (backgrounded app) reports
only the **most recent** so reopening yields one notification, not a burst. Message reads
"<name> — 10 days to go" / "… since".

Defaults (`CountdownTimerItem.defaultMilestones()`, both directions, declared longest-first):
10 years, 10 months, 10,000,000 s, 10 weeks, 100,000 min, 1,000 h, 10 days — note
10,000,000 s (~115.7 d) outranks 10 weeks (70 d). Timers saved before 0.1.105 carry no
`milestones` key and inherit the defaults on load. The dialog owns one
`TextEditingController` per row and disposes them itself (never dispose from the caller after
`showDialog`); on save it drops non-positive rows, collapses duplicate number+unit pairs, and
re-sorts by `approximateSeconds` descending (months/years use average lengths — display
ordering only, never placement).

### 10.3 Productivity Stats (formerly "Your Stats"; lives under Tools since 0.1.91)
Three sections: (a) GitHub-style 52-week × 7-day heatmap of **deleted-per-day** counts
(title says "Completed" — historical mislabel; buckets 0/1/2/3/4+ in blue shades, tap for
snackbar, auto-scrolls to newest); (b) 365 daily stacked bars from `DailyTaskStats` —
five segments: moved-from-start (red 0xFFD84343), completed-from-start (dark green
0x1B5E20), not-completed-from-start (dark grey), completed-from-created (light green),
not-completed-from-created (light grey); weekend tint/bold; unit height
`(180/total).clamp(3,16)`; (c) item-activity heatmap, last 31 days, 24h × 7 weekdays,
tabs Created/Completed/Moved/Deleted/Combined, primary-color lerp 0.18→0.92, with a peak
sentence ("Most items are completed on Monday between 09:00-10:00.").

The item-activity cell shading is **outlier-resistant** (`_ActivityScale`, 0.1.124): the
ramp saturates at the Tukey upper fence of the non-empty cells
(`cap = clamp(max(q3+1, q3 + 1.5·IQR), 1, maxCount)`) and counts are compressed
logarithmically inside it (`log(1+count)/log(1+cap)`, `cap == 1` → full intensity).
Normalising against the raw maximum instead made one huge slot (bulk import, marathon
session) flatten every other slot into the same faint shade. A legend under each tab shows
geometric swatch stops (0, 1, `cap^⅓`, `cap^⅔`, `cap`, the top one labelled `cap+` when it
saturates) plus a caption naming the cap and the raw busiest slot.

### 10.4 Usage Data (Tools → Usage Data)
Digital-Wellbeing-style CSV dump of everything ever recorded, as far back as device data
goes. Loads all sources fault-tolerantly, shows summary (earliest day, total records) + a
per-dataset include/exclude checklist, exports RFC-4180 CSVs into
`besttodo_usage_<timestamp>/` in a picked folder plus an `export_info.csv` manifest.
Datasets (see `usage_data_service.dart` for exact columns): all_events (unified timeline
across task/alarm/sms/app/timer sources), daily_usage (first/last activity, active span,
opens, task counts, day-start completion rate), hourly_usage, task_history (with derived
hours_to_complete / completed_on_time), daily_task_stats (raw id sets), alarm_pipeline_log
(parsed alarm_log.txt), alarms snapshot, sms_report_log, app_opens (timestamped since
0.1.85), startup_times (legacy), countdown_timers.

### 10.5 Projects (Kanban, 0.1.89–0.1.90)
Tools → Projects (`lib/ui/projects_page.dart`; moved from a top-level drawer entry into
the Tools group in 0.1.90). Split view: top pane (flex 3) lists all non-deleted tasks;
bottom pane (flex 2) shows the projects. **Projects persist** via `ProjectService`
(singleton, `ValueNotifier<List<Project>>`, `projects.json` in app documents dir, seeded
with `Project.placeholders` "Project 1–3" on first run; corrupt/missing file keeps the
in-memory seeds). `Project = {id, name, description}` (immutable, `copyWith`); ids are
stable — tasks reference `projectId`, so renames propagate everywhere. Drag a
task onto a project card to assign it (sets `task.projectId`, resets `kanbanStatus` to
todo, snackbar confirms; assignment persists via the task's own JSON through `onChanged`
→ `_saveTasks`). Cards show name, one-line description (if any) and live task count.
Drag sources are `AdaptiveDraggable` (`lib/ui/adaptive_draggable.dart`): long-press-drag
on touch platforms (Android/iOS incl. mobile web, so drags don't fight list scrolling),
immediate mouse drag on desktop and desktop web (e.g. Chrome on a laptop; decided via
`defaultTargetPlatform`, which reflects the underlying OS on web). The hint text above
the task pane adapts to the input mode.

**Tags on task tiles (0.1.90):** an assigned task shows two small
`secondaryContainer`-tinted pills under its title on every home tile — the project name
and the stage ("Project 1", "To-Do"); rendered via `ValueListenableBuilder` on
`ProjectService.projects` so renames update live; stage names via
`ProjectService.stageLabel`. Unknown project ids fall back to the raw id.
`ProjectService.load()` runs in HomePage initState so names resolve without opening the
tool.

**Board** (`ProjectBoardPage`): three equal-width Kanban columns — To-Do (blue
0xFF90CAF9), Ongoing (orange 0xFFFFCC80), Closed (green 0xFFA5D6A7) — each a `DragTarget`
with count in the header; drag cards between columns (same `AdaptiveDraggable`
long-press-on-touch / immediate-on-mouse behavior) to change `kanbanStatus`,
tap a card for `TaskDetailPage`, the × on a card unassigns it (clears `projectId`, resets
stage). **Edit (0.1.90):** pencil action in the app bar opens a name+description dialog;
Save upserts through `ProjectService` (empty name keeps the old one, description may be
cleared); the app-bar title and a hint-colored description line under it update in place.
Original board written pre-0.1.58, merged at 0.1.89; still uses deprecated
`onWillAccept`/`onAccept` and some hardcoded `Colors.black45`-style hints.

### 10.6 Wishlist (0.1.94–0.1.95, Todo.md import 0.1.100, unified into the task list 0.1.101)
Tools → Wishlist (`lib/ui/wishlist_page.dart`): a pre-filtered view over the ONE task
list — exactly like opening a project — showing only tasks flagged `Task.isWish`
(JSON key `isWish`, default false). Wish tasks live in `tasks.json` alongside
everything else; they are undated (`dueDate == null`), which alone buckets them into
the Future tab (`_tasksForTab` sends null-due tasks to the future bucket), where they
render as full, editable task tiles whose `TaskTile` subtitle shows the description, a
small "wish" tag and the task's own labels as tags. The schedule view groups undated
tasks under "Someday". The home search matches them like any task. So: the item
overview (home) shows all items with all properties/tags; the Wishlist shows only wish
items and never anything date-related.

The page loads via `StorageService.loadTaskList()`, keeps the full list in memory,
mutates only the wish subset and always saves the whole list; HomePage reloads
`_tasks` from disk when returning from the Wishlist tool. Wishes are sorted open
items first, then by priority label (`priority-high` > `priority-medium` >
`priority-low` > none, stable within a group). Tiles look like home task tiles
(checkbox toggles done + `completedAt`; done wishes strike through, sort last, and are
archived by the normal new-day rollover). Tap opens the add/edit dialog (title,
description, labels/tags with quick priority buttons — a `_WishEditDialog`
StatefulWidget owning its controllers); edits mutate the task in place so uid/project/
recurrence fields survive. Per-item and export-all JSON export (`{export_version: 1,
exported_at, wishlist_items: [...]}`) remain.

**Swipes (0.1.101):** same gesture mechanics as `TaskTile` (drag with AnimatedSlide,
100 px/500 velocity thresholds, directions honor `Config.swipeLeftDelete`, GestureDetector
on Android/web, emulator/desktop fallback buttons: swipe icon = prioritize, trash =
delete), but the options swipe changes PRIORITY instead of rescheduling: it opens a
high/medium/low shortcut row with the `Config.delayDuration` countdown bar; letting it
run out raises the priority one step (none→low→medium→high, capped; helpers
`wishPriorityRank`/`setWishPriority`/`bumpWishPriority` rewrite the priority label in
`Task.label`, keeping other labels). Swiping back toward the delete side cancels, as on
the home list. The delete swipe removes the item immediately and shows the home-style
undo snackbar; when the undo window expires the task gets `deletedAt` and moves to
`deleted_tasks.json`. Restoring a wish from Deleted Items keeps `dueDate` null (other
restores get today) so it lands back in the wishlist, not Today.

**Legacy `wishlist.json` migration (0.1.101):** `loadTaskList()` calls
`_migrateWishlistIntoTasks`: any items still in `wishlist.json` (a pre-0.1.101 store)
are flagged `isWish`, stripped of any due date, appended to the task list (dedup by
uid), persisted, and the legacy file is emptied so nothing merges twice. An unreadable
`wishlist.json` makes `loadWishlist()` return an empty list, so the migration is a
no-op and the corrupt file is left untouched. The migration also runs when
`tasks.json` doesn't exist yet.

**One-time Todo.md import (0.1.100):** `lib/services/wishlist_migration.dart` bakes in
the still-open ideas from the repo's historical `Todo.md` ("After MVP → TODO" + "Later"
sections, verbatim; 63 items, DONE sections excluded).
`StorageService.loadWishlist()` merges them once into the wishlist, each labelled
`old`, deduplicating against existing items by normalized title (lowercased,
whitespace-collapsed) and never modifying or removing existing entries. The run is
guarded by a `wishlist_todo_import_v1.txt` flag file so later deletions of imported
items stick, and the import is skipped entirely (no flag, no write) when an existing
`wishlist.json` fails to parse, so a corrupt-but-recoverable file is never overwritten.
Since 0.1.101 this import feeds the task list via the wishlist migration above (fresh
installs get the backlog as wish tasks on first `loadTaskList`).

### 10.7 The rest
**App Logs**: in-memory `LogService` (ValueNotifier, self-trims >24 h, NOT persisted).
**Startup Times**: summary card (typical/last/fastest/slowest, hero median), fl_chart line
chart of the last 30 launches (y-axis fits data, shaded band >1 s, date labels, tap
tooltips), and an auto-generated "What this means" section: median verdict, older-vs-newer
trend, share of slow starts, outlier callout, first-launch-of-day cold-start comparison;
uses timestamped history with legacy fallback. **Changelog**: renders CHANGELOG.md
(markdown, bundled asset); an app-bar button toggles an update heatmap — the file is
parsed into releases (`parseChangelogReleases`: `## [version] - yyyy-mm-dd` headings +
their bullets, wrapped lines joined, undated headings skipped) and drawn as a
GitHub-style week grid (green shade = releases that day, Mon/Wed/Fri labels, month label
above the week where the month changes — with the year appended on the first column and
at every year switch, e.g. "Jan 2026", drawn in an `OverflowBox` so it can run past its
12 px column — horizontally scrolled to the newest week). Tapping a day selects it and lists that day's
versions and their entries below; opens on the newest release day. **About**: description,
version, update link, "Replay Introduction" (clears `intro_shown` *and*
`Config.modeChosen`, so the slides and the mode question both run again).
**Intro** (`intro_page.dart`): 3 value screens (Privacy First / Open Source & Fast /
Minimal Interactions) followed by the simple/full mode chooser (`ModeSelectView`) as
its last page — the dots count 4, the last page has no Next button so the mode
question cannot be skipped, and picking a mode is what ends the intro. Shown once
(`intro_shown` + `Config.modeChosen`), replayable from About, skipped in dev.

## 11. Build, versioning, CI

- **Versioning:** `dart run tool/bump_version.dart <x.y.z[+build]> ["changelog entry"]`
  updates pubspec and prepends a dated CHANGELOG section (idempotent). Build number strictly
  increases per distributed build; passing a bare `x.y.z` carries the current build number
  forward and increments it, so the `+build` suffix (= Android `versionCode`) can never be
  dropped by accident.
- **tool/build.sh:** smoke-test gate (`test/core/build_smoke_test.dart`) → `flutter build $@` →
  rename artifacts with the version (`best_todo_<VERSION>.apk`, `web-<VERSION>`, …) →
  optionally `dart run tool/publish_apk.dart` when `PUBLISH_APK=1`.
- **In-app updates (0.1.133):** `tool/publish_apk.dart` uploads a locally built release APK
  to a GitHub release — tag `v<x.y.z>-<build>` (git tags can't carry `+`), name
  `BestToDo <x.y.z>+<build>`, asset `BestToDo-<x.y.z>+<build>.apk`, body = the newest
  CHANGELOG section; token from `GITHUB_TOKEN`/`GH_TOKEN` or `gh auth token`; re-running
  for the same version reuses the release and replaces the asset. The app side
  (`lib/services/update_service.dart`, singleton `UpdateService.instance` with an
  injectable `fetchOverride` for tests) hits the public
  `repos/Mfficiency/best_todo_2/releases/latest` API unauthenticated, maps the tag back to
  `x.y.z+build`, and compares numeric components (unparseable versions — 'unknown' in
  tests — compare as all-zero). The About page's "Check for updates" section then walks
  check → "Version x available" → download to the temp dir with a progress bar → hand to
  the installer over the `besttodo/update` channel (§9); a `needs-permission` reply keeps
  an "Install update" button up for the retry after granting. Web/desktop or a release
  without an APK asset falls back to opening the release page in the browser.
- **CI (GitHub Actions, Flutter 3.29.2, Java 17):**
  - `build-apk.yml` (push/PR main+staging+dev, manual; `contents: write`, push trigger
    `paths-ignore`s `assets/test_report.json` + `docs/ci/**`): runs `flutter test --machine`
    **non-blocking** (a failing test run does not stop the build) into
    `build/ci/test_report.json`, then `dart run tool/sync_test_report.dart --candidate …`
    packages the newest run known — this build's own, or a newer one another branch already
    published — into `assets/test_report.json`, so an APK cut from **any** branch carries
    the latest results with no network on the device. On push it shares the run through
    `tool/ci/publish_test_report.sh`. Then builds the release APK, uploads artifact
    `besttodo-<version>` (30-day retention), adds a download link to the job summary
    (see §4.3).
  - `flutter_test.yml` (main/staging/dev, same `paths-ignore`; `contents: write`): one
    `flutter test --machine --coverage` run feeds everything — `generate_test_report.dart`
    for the JSON, `render_test_report_summary.dart` for the PASS/FAIL job summary +
    artifact (report JSON and machine stream uploaded with it), `sync_test_report.dart` to
    package the newest run, `publish_test_report.sh` to publish it to `ci-reports`. On
    **dev only** it commits the packaged `assets/test_report.json` (plus a
    `docs/ci/test_report.json` copy for app versions before 0.1.128 that still fetch it)
    with `[skip-screenshot-changelog]`, rebase-retried 3×. dev is the single writer so
    dev → staging → main merges carry the report along instead of conflicting on it. Fails
    the job on test failure.
  - `screenshot_changelog.yml` (push to main/staging/dev): Windows runner drives an
    integration test capturing screenshots (home, menu, settings, stats; since 0.1.90 also
    search-active, projects page, project board, project edit dialog) into
    `docs/screenshots/home/<timestamp>-<sha>/` and prepends to `SCREENSHOT_CHANGELOG.md`.
    The workflow copies every `build/e2e_screenshots/*.png` and the changelog tool emits
    one section per PNG found, so new captures need no CI edits. Loop protection:
    paths-ignore on its own outputs, skips actor `github-actions[bot]`, and its commit
    message carries `[skip-screenshot-changelog]`.
- **Branch model:** feature branches (historically `codex/*`, later `claude/*`) → `dev` →
  `staging` → `main`. Releases are built from dev after a version bump.

## 12. Testing

Tests are organized into siloed suites under `test/` so a change only needs the
suites it can affect (see `test/README.md` for the file→suite map): `core/`
(task model, storage/config persistence, tab bucketing, ordering/reorder,
deadline normalization, app-boot + build-gate smoke tests — always run),
`alarms/` (alarm model/storage, editor, ring page), `projects/` (model,
service, projects page, board, tile tags), `home/` (search, drawer, tile
description editing), `update/` (in-app update check + About page update
section + publish-tool helpers), `tools/` (export/import + analytics, usage data,
startup-times page, countdown model, chronize). Plain `flutter test` still
runs the full suite and is what CI uses; `tool/build.sh` gates builds on
`test/core/build_smoke_test.dart`.

Unit/widget tests cover: usage-data CSV building (escaping, event derivation, rollups,
manifest), chronize mark-fade invariants + interaction smoke tests, startup-times page
(history/legacy/empty states, chart maxY not clipping outliers), countdown model, export/
import round-trip + legacy import, storage rollover, config persistence, alarm model +
storage round-trip, 18:00 deadline normalization, done-task ordering, reorder ranking,
dev date-advance sweep, home filtering, tile description editing, intro smoke. Projects &
search (0.1.90): project model + `ProjectService` persistence (seed/rename/reload/corrupt
file), projects page (drag-assign incl. desktop mouse drag, renamed-projects-from-disk,
platform-dependent hint), board page (column grouping, drag between columns incl. desktop
mouse drag, unassign, edit dialog save/cancel/empty-name), dev project seed (spread across
projects/columns, no reshuffle of existing assignments), task-tile
project/stage tags (incl. live rename + unknown-id fallback), home search (title/
description/label/project-name matching, case-insensitivity, clear button, empty state),
drawer placement of Projects under Tools, alarm-editor top save action, schedule-view
active-day tracking (highlight follows scroll, back-to-top arrow, add-to-highlighted-day
end to end). CI test report & settings search (0.1.96): `TestReport` tolerant fromJson /
toJson round-trip and the `--machine` output parser (hidden/skipped handling, error
capture, garbage tolerance), Test Results page states (failures + expandable errors, all
green, no bundled report), home red dot on the hamburger (opt-in setting) + drawer entry
navigation (its absence when green/unavailable/by default on the hamburger, and its
clearing once Test Results is opened), settings search (toggle, title + keyword matching,
section subtitle, no-match message, jump-to-section, close restoring chips). Simple mode &
features (0.1.118, `test/home/simple_mode_test.dart` + `settings_features_test.dart`):
home page in simple mode (no dice/flame/schedule/search, drawer down to Settings + Deleted
Items + About + Changelog + App Logs + Startup Times, no Tools section),
per-feature hiding of drawer tools and app-bar actions, the mode
picker storing and persisting its choice, `isFeatureEnabled` semantics + `features`
round-trip, and the Settings side (feature switches searchable, feature-owned sections
disappearing, the simple-mode switch persisting). Both suites restore `Config` in
`tearDown` — the flags are global statics. Widget tests that
touch persistence use a `_FakePathProvider` + temp dir. Caveat: real file I/O awaited
inside `testWidgets` hangs until the 10-min per-test timeout (the fake-async zone never
services dart:io completions — locally and on CI) — such tests wrap I/O in
`tester.runAsync` and pump real-event-loop slices in rounds; see CLAUDE.md for the exact
patterns. The unmitigated pattern kept `flutter_test.yml` red from 0.1.87 until 0.1.90. Integration tests: screenshot
walk-through + task-creation screenshots (Windows desktop, needs Developer Mode for
plugin symlinks). Not covered: stats/usage page widget rendering, the
Kotlin widget PendingIntent wiring (verified on hardware), most alarm/SMS runtime paths
(verified on hardware + via alarm_log instead).

## 13. Invariants & quirks a rebuilder must preserve

1. Background isolates must init binding + DartPluginRegistrant before any plugin call.
2. Never `cancelAll()` notifications on reschedule — preserve snooze slots.
3. The 18:00 normalization runs on every save; `hasExplicitTime` is the only escape hatch.
4. Future bucket = magic `DateTime(2300,1,1)`; null due date appears nowhere.
5. Deleted list caps at 100 everywhere it's touched.
6. Delete/undo is deferred commit; killing the app mid-window loses the task silently.
7. uid uniqueness is enforced (reassigned) on every load/import.
8. Widget toggles must go through `toggleInStorage` + awaited reschedule.
9. DST: never `add(Duration(days:1))` for next-occurrence math on wall-clock times.
10. SMS/alarm one-shots re-arm themselves; re-arm BEFORE running the payload.
11. Permissions that need dialogs are requested in the foreground only.
12. Alarm channel changes require a new channel id (hence `_v2`).
13. Kotlin folder/package mismatch is intentional; keep the committed debug keystore.
14. `snoozeMaxCount` is stored-but-unused; keep serializing it. (`melody`/`volume` are
    implemented since 0.1.91 via the native `besttodo/alarm_audio` channel.)
15. Stats heatmap counts deletions but is titled "Completed" — fix knowingly or keep.

---

# Part II — Development history (every step, explained)

428 commits, 87 released versions, June 2025 → July 2026. Sources: `CHANGELOG.md`
(authoritative per-version bullets), git log, `.claude/notes/alarm-work-spec.md`. The
project was built largely through AI-assisted sessions (OpenAI Codex branches `codex/*`
early on, Claude sessions `claude/*` later) merged by the maintainer (mfficiency), flowing
feature branch → dev → staging → main.

### Phase 1 — Bootstrap (June 2025, v0.1.0 → 0.1.3)
Flutter skeleton generated, renamed to `best_todo_2`, README with the three fundamentals
(<1 s startup, fewest clicks, open source). The swipe concept landed immediately: Today/
Tomorrow pages, swipe/drag to move tasks forward, then Day After Tomorrow and Next Week.
The swipe-options-with-countdown pattern (reveal choices for a delay, then auto-commit)
appeared in v0.1.1 with a 2 s delay — later made configurable and defaulted to 5 s.
Expandable task editing, settings (configurable swipe direction), drawer navigation,
undoable delete with a Deleted Items page, dev-mode date navigation, and task persistence
(v0.1.2 — plain JSON, not the Hive/Isar the README once envisioned) all arrived in this
first burst. Automatic version bumping began (v0.1.3).

### Phase 2 — Android era: the widget saga (August 2025, v0.1.4 → 0.1.41)
Focus shifted to making it a real Android app. SDK/NDK config fixed, swipe UI cleaned up
(0.1.4–0.1.5). The **home-screen widget** went through visible trial and error: first a
widget showing just the app version (0.1.6), clickable to open the app (0.1.7), then
showing today's tasks (0.1.8), multiple rounds of color/readability fixes — including a
comically documented green-background-red-text experiment — a black-background temp fix
(0.1.15), file-path fixes, filtering out done tasks (0.1.13) and tomorrow's tasks
(0.1.14–0.1.15), and ordering aligned with the app (0.1.37-era). An App Logs page was
added to debug the widget from the phone (in-memory, 24 h retention). Startup-time logging
with an in-app graph landed (0.1.40) to police the <1 s budget. Theme standardized on
#005FDD (0.1.18). Tabs grew Next Month (0.1.21) and icons (0.1.22–0.1.23). Settings began
persisting (0.1.24), intro screens introduced the app's values (0.1.26), import/export
arrived with directory pickers (0.1.27–0.1.31; a storage-permission attempt was reverted
in "0.1.36 — this is actually 0.1.33, but i fucked up the versioning"). Crucially for
everything later: **tasks got uuid uids and listRanking** (0.1.37), done-tasks-to-bottom
and the deleted-list-on-rollover model (0.1.38), swipe animations (0.1.20, 0.1.39).

### Phase 3 — Revival and analytics (February 2026, v0.1.42 → 0.1.56)
After a five-month gap, a fix-and-features burst: deleted-items restore repaired
(0.1.42–0.1.46, including permanent delete), the versioning/bump script cleaned up
(0.1.45), and the **Your Stats** page born (0.1.47): GitHub-style completion heatmap,
then more stats below it (0.1.52–0.1.54). First notification support (0.1.48), widget
progress line (0.1.50), navigation-bar-safe layout + auto APK naming (0.1.49).
**Recurring tasks** (0.1.55) and quality-of-life settings: new-task position, startup tab,
quiet hours, future tab (0.1.55–0.1.56). Dev mode learned to skip intro and seed data.

### Phase 4 — Automation and the SMS report (May 2026, v0.1.57 → 0.1.69)
CI matured: automated screenshot changelog on every push with loop protection (0.1.57),
APK build workflow (May 11). Export was overhauled and moved into settings (0.1.58).
Swipe both ways + swipe-cancel with the orange background (0.1.59–0.1.60). Then the
**daily SMS report** ("snitch text", social accountability): initial module with schedule,
recipients, template (0.1.61); then a hardening series driven by real-device failures —
permission narrowing + persistent diagnostic log (0.1.62), waiting for the native
SENT/DELIVERED callback with a 20 s timeout instead of trusting the API return (0.1.63),
dual-SIM subscription id + log export (0.1.64), auto-multipart because carriers silently
drop over-length messages (0.1.65), completion-rate threshold (0.1.66). Also: auto-deleted
label in Deleted Items (0.1.67) and the **schedule view** — Google-Calendar-style single
list with tabs as scroll anchors (0.1.68–0.1.69).

### Phase 5 — Tools: Countdown and Chronize (June 2026, v0.1.70 → 0.1.79)
The Tools menu appeared with the **Countdown** tool, iterated rapidly in one stretch:
multiple timers counting down then up, inline composer with auto-names, instant pickers
(tap-a-day closes, analog clock dial), drag reorder + sort modes, minimizing form,
3-decimal breakdowns, Monday-first tinted date picker, backup/restore integration
(0.1.70–0.1.71). Build/CI fixes: pinned Flutter 3.29.2, minSdk 23, and the **fixed debug
keystore** decision so every build installs over the last (0.1.72). Then **Chronize**, the
experimental continuous timeline, over seven versions: initial tool + the 18:00 default
deadline time (0.1.73), scroll wheels + infinite timeline (0.1.74), continuous zoom with
fading granularity marks + optional hour wheel (0.1.75–0.1.76), task chips with cascade +
now-line (0.1.76), navigator cards to nearest off-screen events (0.1.77), center-on-now
Today + momentum + tap-to-create/edit with `hasExplicitTime` (0.1.78), subtler distance
pills (0.1.79).

### Phase 6 — The reliability arc (June 30 – July 6 2026, v0.1.80 → 0.1.85)
The defining engineering saga, fully documented in `.claude/notes/alarm-work-spec.md`.
Four rounds of "it works when the app is open but not when it's closed":

- **0.1.80 — the missing receiver.** The daily SMS report never fired in the background.
  Root cause: the manifest lacked `AlarmBroadcastReceiver` — the plugin's PendingIntent
  target. The OS fired; nothing received it. Diagnostic clue: "Send test now" worked
  (bypasses the alarm). Fix: declare the receiver.
- **0.1.81 — OEM power savers.** Samsung "Sleeping apps"/Doze silently dropped alarms.
  The stock Clock is exempt as a system app; a normal app must request
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. Enabling the report now prompts for exact-alarm
  + battery exemption; manifest gained SET_ALARM/FOREGROUND_SERVICE/VIBRATE.
- **0.1.82 — Doze defers repeating alarms.** `periodic(exact:true)` maps to Android's
  `setRepeating` — inexact since API 19, ignores allowWhileIdle, deferred indefinitely in
  deep sleep. Replaced with the exact one-shot self-re-arming chain
  (`setExactAndAllowWhileIdle`, re-arm on fire + on every launch + on reboot). SMS
  permission moved to foreground request (background isolates can't show dialogs).
  Every background fire now logs "Alarm fired" as proof of delivery.
- **0.1.83 — the Alarms tool + widget.** Full alarm clock (per-alarm settings, repeat
  days, snooze, colors), home-screen alarm widget, exact OS scheduling surviving reboot
  and flight mode, absolute-time fix for timezone drift. Its own app-closed bug set:
  widget toggles that only changed stored state (never scheduling), snooze dead in the
  notification-action isolate (missing plugin registration), pending snoozes killed by
  `cancelAll` on app open, and DST drift from day-adding — all fixed, all now invariants
  (§13). The session ended by writing the work-spec notes file so future sessions could
  trace the reasoning.
- **0.1.84 — foolproof delivery.** Belt-and-suspenders: the method ladder (setAlarmClock →
  setExactAndAllowWhileIdle → inexact, every attempt logged), OS read-back verification,
  the independent 90 s watchdog that re-rings if the primary path was silently dropped,
  ack tracking so it never double-rings, the persistent human-readable `alarm_log.txt`
  with startup diagnostics + per-OEM hints, test-alarm and run-diagnostics buttons, and
  the insistent (looping) alarm sound.
- **0.1.85 — release build** (no functional changes) plus, same day, a fix making app
  startup non-blocking on plugin init (black-screen-at-open) — which is why the alarm
  diagnostics snapshot is fire-and-forget in `main()`.

### Phase 7 — Insight tools (July 2026, v0.1.86 → 0.1.91, current)
**0.1.86 — Usage Data tool**: export the app's entire recorded history as detailed CSVs
(unified event timeline, daily/hourly rollups, task history with derived metrics, alarm
pipeline log, SMS log, app opens, timers + manifest); app opens now recorded with
timestamps (`startup_history.json`, cap 5000). Note: 0.1.85 was claimed twice in parallel
branches (release-build bump on dev vs the usage-data branch); resolved at merge by moving
the usage-data feature to 0.1.86. **0.1.87 — Startup Times facelift**: the bare clipped
line chart became summary stats + a data-scaled themed chart + an auto-generated
"What this means" analysis (typical verdict, trend, slow-start share, outliers, cold-start
pattern), with widget tests. **0.1.88 — full-screen alarm ring UI + release scheduling
fix**: `AlarmRingPage` (§5.2) and the R8/ProGuard keep rules that un-broke scheduling in
release builds. **0.1.89 — Projects tool (§10.5)**: written back in June on a parallel
branch (claimed 0.1.57), cherry-picked into dev during a branch cleanup; also added a Save
action to the top app bar of the alarm editor. Second time a parallel branch's version
claim had to be re-resolved at merge (after 0.1.85). **0.1.90 — Projects grow up +
search**: Projects moved under Tools; projects persist (`ProjectService`,
`projects.json`) with an edit dialog for name/description on the board; assigned tasks
show project + stage tags on every home tile; the app-bar search placeholder became a
working live filter (title/description/note/label/project name, all tabs + schedule
view, reorder disabled and ranking renumbering kept unfiltered while searching); any tap
on the alarms home-screen widget now opens the alarms page (container-level
PendingIntent); screenshot CI generalized to archive every captured PNG. First feature
batch to ship with per-feature widget tests, CLAUDE.md (AI working guide) and expanded
screenshot coverage in the same commit. **0.1.91 — schedule view active day**: the day
section scrolled to the top of the schedule list is highlighted and becomes the target
of the add-task row (label shows "Add task · <day>", new tasks get that day's due date);
back-to-top arrow; generous bottom padding so the last sections can reach the top (§ Home
page, "Schedule view active day").

### Recurring themes (read this before adding features)
1. **Everything background on Android will silently fail at least once.** Manifest
   receivers, plugin registration, permissions, OEM power savers, Doze semantics — each
   bit them separately. The response evolved from "fix the bug" to "build verification and
   logging into the pipeline itself" (read-back, watchdog, alarm log).
2. **Iterate in public, in small versions.** 87 versions in ~13 months; most features
   shipped rough and were refined over 3–7 consecutive patch versions (widget, countdown,
   Chronize, SMS, alarms).
3. **Logs are features.** App Logs, SMS report log, alarm log, startup times, usage-data
   export — every debugging pain became a permanent in-app observability tool.
4. **Speed is a spec.** Startup is measured on every launch and charted in-app; the <1 s
   budget drove the non-blocking startup fix and the fire-and-forget diagnostics.
