# BestToDo — Complete Rebuild Specification & History

> **Purpose of this document.** If the original authors, tooling, and AI sessions behind this
> app disappeared tomorrow, this file is what a human or AI needs to rebuild BestToDo from
> zero and to understand *why* it is built the way it is. Part I is the functional/technical
> specification (what to build). Part II is the complete development history (every step the
> project took and why). `CHANGELOG.md` remains the authoritative per-version record;
> `.claude/notes/alarm-work-spec.md` holds the deep-dive on the alarm reliability sessions.
>
> Accurate as of version **0.1.88+58** (2026-07-07), commit history through the 0.1.88
> full-screen alarm work.

---

# Part I — Rebuild specification

## Usage and digital wellbeing dashboard

Tools → Usage Data is both the raw-data export surface and an interactive
wellbeing dashboard. It combines BestToDo's existing task lifecycle, startup,
alarm, timer, and daily-stat records with optional Android system usage
sessions. Today, current-week, current-month, and current-year filters drive
the summary cards, hourly chart, app ranking, and productivity measures.

Android integration uses the `besttodo/digital_wellbeing` method channel and
`UsageStatsManager.queryEvents`. The user must deliberately grant Usage Access
in Android settings; without it the BestToDo dashboard and CSV exports still
work normally. Foreground/resumed and background/paused pairs become local
sessions with package label and Android app category. No usage data is sent to
a server and the feature never blocks another app.

Supportive insights call out late-night use and repeated sessions without
shaming language. Goals are disabled by default and persisted in shared
preferences (daily minutes, pickup limit, bedtime, and no-phone start hour).
The dashboard always retains the selectable detailed CSV export as an
expandable drill-down.

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

`main()` in `lib/main.dart`, strictly in this order:

1. `StartupTimeService.start()` — stopwatch for the <1s cold-start budget.
2. `WidgetsFlutterBinding.ensureInitialized()`.
3. `await Config.load()` — reads `settings.json` so theme/tabs are right before first frame.
4. `await NotificationService.initialize()` — plugin + notification channels.
5. Non-web: `await SmsReportScheduler.applyFromConfig()` — restore the daily SMS alarm chain.
6. `await AlarmService.instance.load()` — load persisted alarms.
7. `unawaited(NotificationService.runAlarmDiagnostics(trigger: 'app start'))` — deliberately
   NOT awaited; writing the diagnostics snapshot must never delay the first frame
   (this fixed a black-screen-at-open bug, v0.1.85 era).
8. Home-widget setup in try/catch: `HomeWidget.setAppGroupId` +
   `registerInteractivityCallback(alarmWidgetBackgroundCallback)`.
9. SharedPreferences → `showIntro` = `!intro_shown || !Config.modeChosen`
   (always skipped in dev builds); the mode question closes the intro, so an
   unanswered mode brings the whole welcome flow back rather than the chooser
   alone. `showStartupChoice` = `!startup_choice_made`, a separate one-time
   flag (0.1.242) decoupled from `intro_shown` so it survives being
   interrupted mid-onboarding; on an install where `intro_shown` was already
   true the very first time this flag is read, it backfills to "already
   answered" so nobody upgrading from an older build is asked it.
10. `runApp(MyApp(showIntro, showModePicker: !showIntro && !Config.modeChosen,
    showStartupChoice))`; post-frame → `StartupTimeService.record()`.
    `MyApp.home`: intro (slides + mode choice) → startup choice (fresh
    install only) → `_initialPage()`. The standalone `ModeSelectPage` is only
    for asking the mode question again (Settings → Mode & features, §4.6).

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
recurrence (rebuilt 0.2, see §4.3 "Recurrence" below for the full model):
`isRecurring`, `recurrenceFrequency`/`recurrenceInterval`/`recurrenceWeekdays`,
`recurrenceEndType`/`recurrenceEndDate`/`recurrenceOccurrenceCount`,
`recurrenceExceptionDates`, `recurrenceOverride`, `recurrenceParentUid` +
`recurrenceInstanceKey` (`yyyy-MM-dd`) on generated children; legacy `recurrenceIntervalDays`
kept for on-disk compat and migrated into the new fields on read.
Projects (0.1.89): `projectId` (String?, omitted from JSON when null) + `kanbanStatus`
(`'todo'`/`'ongoing'`/`'closed'`, constants on `Task`, defaults `'todo'`).
Wishlist (0.1.101): `isWish` (bool, default false) marks a task as a wishlist item
(see §10.6); wish tasks are undated and undated tasks bucket into the Future tab.
Food Diary (0.1.266): `isEatingHabit` (bool, default false) marks a task as a food
diary entry (see §10.6a); gated out of every other view by
`ItemViews.isVisibleInMainViews`.
Attachments (0.1.277): `attachments` (`List<Attachment>`, default `[]`, omitted from JSON
when empty) — see §4.1a.
`fromJson` is tolerant: missing keys get defaults.

### 4.1a Attachments (`lib/models/attachment.dart`, 0.1.277)

An `Attachment` is a note or file hung off a `Task`: uuid-v4 `uid`, `type` (`Attachment.
typeText`/`typeImage`/`typePdf`), `text` (inline content — used only by `typeText`),
`fileName` (original picked file name — used only by the file-backed types), `relativePath`
(the copy's path relative to the app documents dir — null for `typeText`), `createdAt`.
`toJson` omits empty `text`/`fileName` and null `relativePath`; `fromJson` defaults a missing
`type` to `typeText` so a stripped/legacy payload still parses.

`AttachmentStorageService` (`lib/services/attachment_storage_service.dart`, singleton
`.instance`) owns the on-disk side for image/PDF attachments — text attachments never touch
it. `importFile({taskUid, sourcePath, type})` copies the picked file's bytes into
`<docs>/attachments/<taskUid>/<attachmentUid>.<ext>` (never moves/deletes the source) and
returns the `Attachment`; `absolutePath(relativePath)` resolves a stored path back to an
absolute one for display; `deleteAttachmentFile(attachment)` removes one copy (no-op for
`typeText`); `deleteAttachmentsForTask(taskUid)` removes a task's whole attachments
subdirectory. `StorageService.loadBinTaskList`'s age-based retention purge (§4.2g) calls
`deleteAttachmentsForTask` for every task it expires out of the bin, so attachment files
don't outlive the task they belonged to.

UI: `AttachmentsField` (`lib/ui/attachments_field.dart`) is the editor, embedded in the
task tile's expanded editor (`lib/ui/task_tile.dart`, alongside the label picker) and, in
`readOnly: true` mode (view/open only, no add row or remove buttons, hidden entirely when
there are none), on `TaskDetailPage`. Adding an image/PDF uses `file_selector`'s `openFile`
(already a dependency, used elsewhere for import/export) with an extension-filtered
`XTypeGroup`; adding a note opens a plain multiline-text `AlertDialog`. Tapping a text
attachment reopens that dialog pre-filled (edit in place, not read-only mode); tapping an
image opens a full-screen `InteractiveViewer`; tapping a PDF (or any other file-backed type)
hands it to `share_plus`'s `SharePlus.instance.share(ShareParams(files: [...]))`, i.e. "open"
is implemented as the platform share sheet rather than an in-app viewer.

`TaskDetailPage`'s app bar carries an info icon (tooltip "Show all task metadata") that opens
an `AlertDialog` with two selectable-text sections: the hidden Todoist sync trailer — the same
text `TodoistMetadataCodec.build` would append to the description when pushing this task to
Todoist (uid, note, label, project, Kanban stage, createdAt, all normally invisible in the
regular view) — and a pretty-printed dump of `Task.toJson()` covering every field the model
persists (schema/internal timestamps, recurrence bookkeeping, `listRanking`, `kanbanStatus`,
raw `attachments`, etc.), so nothing about the task stays hidden from the user who asks.

Dev seed: `home_page._loadTasks` backfills a demo text attachment onto one starter task
(`Config.initialTasks[1]`, falling back to the first non-wish/non-food-diary task) whenever
`Config.isDev` and no task carries an attachment yet, so the "task expanded with an
attachment" state is visible on a fresh dev/laptop run without adding one by hand — every
other starter task stays attachment-free, showing the "without" state alongside it.

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
| `deleted_tasks.json` | archive (Archived Items — "deleted" but restorable, never age-purged) | **100**, trimmed on save+load |
| `deleted_bin.json` | the real Deleted bin — see §4.2g | **100**, trimmed on save+load; also age-purged past `Config.deletedItemsRetentionDays` |
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

Next to that JSON file, the same run writes a same-timestamped folder
`besttodo_backup_<yyyymmdd_hhmmss>/` — a Markdown mirror
(`MarkdownBackupService`, `lib/services/markdown_backup_service.dart`), export-only (Import
never reads it). One subfolder per item type — `Tasks/` (active, Archived Items and real
Deleted-bin tasks together, tagged with a `status: active|archived|binned` field since
they're the same kind of item and differ only in which list currently holds them),
`Projects/`, `Alarms/` (standalone alarms only; task-linked reminders are folded into their
task's note), `Countdown Timers/` — each holding one `.md` note per item (filename:
sanitized title + 8-char uid suffix). Every note, whatever the type, follows the same
layout so one Obsidian template/Dataview query covers the whole vault: YAML frontmatter
(Obsidian's Properties panel, collapsed by default — the note's "hidden" fields: `uid`,
`type`, `created`, `description` mirrored raw, `tags`, `reminders` — human-readable
anchor/offset/melody/volume/vibrate summaries pairing each linked alarm's schedule with its
notification settings — plus every other field the JSON backup carries: due date, project,
kanban status, wish/food-diary/recurring flags, recurrence detail, attachments summary,
etc.), then the visible body: `# Title`, the description paragraph, `## Notes`, `## Links`
(tags rendered as `[[wikilinks]]` for Obsidian's graph view), `## Edit History` (from
`ItemEventJournal`, one line per event with its source and field-level patch). Two more
folders describe the app rather than its items: `Views/` — one note per
`ViewFilterRules.viewIds` (Home, Wishlist, Waiting for Approval, Projects, Food Diary,
Alarms, Countdown, Archived items, Deleted bin), each showing its built-in structural rule,
its configured Settings → Filtering rules include/exclude tags (live from
`Config.viewFilterRules`/`ViewFilterRules.defaultsFor`), and its `ViewPresentation`
cosmetics, plus a Home-specific tab-bucketing table and a Projects-specific Kanban-column
table — and `Settings/Settings.md` (a JSON snapshot of `Config.toMap()`, with
`todoistApiToken` and `googleCalendarUrl` redacted — the JSON backup remains the only place
those secrets survive a restore). Markdown-vault failures are caught and logged separately
from the JSON write, so a Markdown bug can never fail the backup itself.

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
   `tasks.json`, `deleted_tasks.json`, `deleted_bin.json`, `daily_task_stats.json`,
   `countdown_timers.json` and `alarms.json`. A crash mid-save can no longer leave a
   half-written file.
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
`sortTasks`, optional extra predicate for search), `wishlist` (isWish), `foodDiary`
(isEatingHabit, §10.6a), `active` (deletedAt == null), `projectTasks`, `boardColumn`. The
home page's `_tasksForTab`, the Wishlist/Food Diary pages, the Projects page (counts +
top pane) and the Kanban board all delegate to it; the Future-tab sentinel date
(2300-01-01) lives here as `futureSentinelDate`. Membership flags on the task stay the
stored form (dual-write era) — this step moves the *reading* of them into one place.
`isVisibleInMainViews` (`isApproved(t) && !t.isEatingHabit`) is the combined gate every
selector except `foodDiary`/`waitingApproval` filters through — a food diary entry, like
an unapproved Todoist pull, is invisible everywhere but its own tool.

Every selector above, including `waitingApproval` (0.1.272), also takes an optional `rules`
(`ViewFilterRules?`, see §4.4 "Filtering rules"), checked via `ItemViews.passesFilterRules` —
an extra, user-configured tag layer on top of the view's own structural query. `applyFilterRules`
filters a plain list the same way (used for the Archived Items and Deleted bin pages, neither
of which is itself a selector — see §4.2g). A null or empty `rules` is a no-op, so every existing
call site that does not pass one is unaffected.

### 4.2e Waiting for Approval gate (0.1.256, token respelled 0.1.259)

Every task `TodoistSyncService._taskFromRemote` builds — first-launch import and the
"brand-new Todoist tasks" pull alike — is stamped with `waitingApprovalToken`
(`lib/utils/label_utils.dart`). `ItemViews.isApproved` makes that token the gate on
*every* other selector (home buckets, wishlist, active, project tasks, board columns), so
a task "created with the Todoist workflow" is invisible everywhere until a human decides
on it in Tools ▸ menu ▸ **Waiting for Approval** (`lib/ui/waiting_approval_page.dart`,
listed via `ItemViews.waitingApproval`, the one selector that shows *only* gated tasks).
Approve strips the token (`removeWaitingApprovalToken`) and the task drops into whatever
list it belongs to; Deny soft-deletes it straight into the real Deleted bin
(`deleted_bin.json`, recoverable from Deleted Items until it ages out — see §4.2g), never
into the archive, since a denial was never wanted in the first place.

**Schedule view bypassed the gate (fixed 0.1.261):** `HomePage._buildScheduleBody` built
the calendar/schedule view's list straight from the raw `_tasks`, not through
`ItemViews.homeBucket` like the tab list view — so a gated task with a due date (Todoist
due dates survive onto the stub) rendered under its date in Schedule view even while
correctly hidden from the tab view. Fixed by filtering `_tasks` through
`ItemViews.isApproved` before handing it to `ScheduleView`, same as every other surface.

**The home-screen widget bypassed it too, and kept a denied task (fixed 0.1.262):**
`TaskWidgetService.todayTasks` selected purely on `dueDate`, so a gated task due today sat
on the Android task widget — and denying it did not take it off, because the widget is only
pushed by `HomePage._saveTasks`, which the self-contained approval page never calls. Both
halves are fixed: `todayTasks` now drops `deletedAt != null` and `!ItemViews.isApproved`
rows (the widget mirrors the same views layer as every list), `WaitingApprovalPage._save`
pushes `TaskWidgetService.sync` after persisting, and `HomePage._reloadTasksFromStorage`
(the return path from the approval page, the wishlist and a Todoist pull) pushes as well.
`toggleInStorage` also re-syncs when the tapped uid is gone, so an already-stale row
clears itself instead of doing nothing.

**The token is `Waiting_for_approval`, one underscored word (0.1.259).** Label tokens
split on commas AND whitespace (`_tokenSeparator` = `[,\s]+`), so a Todoist label spelled
`Waiting for Approval` arrives as three unrelated tags — `Waiting`, `for`, `Approval` —
that gate nothing. The underscored spelling survives the split as a single tag on both
sides, and round-trips through Todoist's native `labels` array unchanged. Matching is
case-insensitive throughout, and `legacyWaitingApprovalTokens` keeps the pre-0.1.259
`waiting-for-approval` spelling recognized (still gates a task, still stripped on
approval) but never writes it again — so tasks pulled in before the rename don't get
stranded. Use `hasWaitingApprovalToken`/`removeWaitingApprovalToken` rather than
`labelHasToken`/`removeLabelToken` with the constant, or the legacy spelling is missed.

The token is local-only at import: the sync map's fingerprint baseline is computed *with*
it, so the initial pull pushes nothing back and the Todoist item's `labels` array stays
untouched. Approving changes `_localFingerprint`, so the next sync pushes the shortened
label array — the tag is removed on the Todoist side too, exactly once.

**Swipe approve/deny (0.1.272), matching `TaskTile`'s move/delete swipe exactly:** each
row in `WaitingApprovalPage` (`_PendingTaskTile`) carries the same gesture mechanics as
the home list and the Wishlist tile (drag with `AnimatedSlide`, 100 px/500 velocity
thresholds, directions honor `Config.swipeLeftDelete`, `GestureDetector` on Android/web).
The approve-side swipe opens a shortcut row of every `Config.tabs` label (Today/Tomorrow/
Day After Tomorrow/Next Week/Next Month/Future) with the `Config.delayDuration` countdown
bar; tapping one, or letting the countdown run out (default: Today), approves the task
(`removeWaitingApprovalToken`) AND schedules it — sets `dueDate` to that bucket's date
(same day math as `HomePageState._dueDateForTab`) plus `movedAt`/`rescheduledAt`. The
deny-side swipe opens a Deny button plus Fri/Sat/Sun/Mon weekday shortcuts (same set as
`TaskTile`'s delete-side weekday options): a weekday shortcut approves the task onto the
next occurrence of that day instead of denying it; Deny, or letting the countdown run out,
denies the task with the same home-style undo snackbar as everywhere else in the app —
only after the undo window expires does it move to the real Deleted bin (previously
`_deny` moved it there immediately, with no undo). Swiping back toward the other side
while options are open cancels, as on the home list. The original leading/trailing
Approve/Deny icon buttons are unchanged: they stay one-tap alternatives that lift the
approval gate (or deny) without touching `dueDate`.

### 4.2g Archived Items vs. the real Deleted bin (two-tier soft delete)

What used to be the single "Deleted Items" list is now **Archived Items**
(`lib/ui/archived_items_page.dart`, `deleted_tasks.json`, capped at 100 entries, never
purged by age): every normal delete — a swipe/menu delete anywhere in the app, Chronize's
delete, a wishlist delete, and the end-of-day sweep that clears finished tasks (both
`HomePage._changeDate`'s in-session rollover and `StorageService.loadTaskList`'s
across-launch rollover, both stamping `autoDeleted: true`) — lands here first, exactly as
"Deleted Items" always worked. Restorable from there indefinitely.

A second, real bin sits behind it: **the Deleted bin** (`lib/ui/deleted_bin_page.dart`,
`deleted_bin.json`, same 100-entry cap) is reachable from an Archived Items app-bar action
(`Icons.delete_forever`, tooltip "Deleted items (bin)"). An archived item's trailing icon
(`Icons.delete_outline`, "Move to bin" — `HomePage._moveArchivedToBin`) sends it on; from
there `Icons.delete_forever` ("Delete permanently") erases it for good, same undoable
snackbar pattern as before. Left alone, an item in the bin purges itself automatically
`Config.deletedItemsRetentionDays` days after it landed there (default 60, editable in
Settings → Tasks → "Deleted items retention") — `StorageService.loadBinTaskList` sweeps
expired entries and re-persists the trimmed list on every read, so the purge applies even
if the bin page is never opened.

**Denial skips the archive.** `WaitingApprovalPage._deny` was never "delete this task the
user actually wanted" — it inserts straight into `deleted_bin.json` via
`ItemRepository.loadBinItems`/`saveBinItems`, starting the retention clock immediately
rather than sitting in the archive indefinitely.

**Recurring instances and the archive/bin.** `HomePage._refreshRecurringForTask`
regenerates any date between a recurring parent's due date and its `recurrenceEndDate`
that is missing from `_tasks` — which, before this, included a date whose instance had
simply been archived, silently recreating it on the next refresh (app restart, or any edit
to the parent). The existing-dates lookup now also scans `_deletedTasks` and `_binTasks`
for that `recurrenceParentUid`, so an archived or binned occurrence's date stays skipped:
manually archiving one instance of a recurring task never regenerates it, and never
disturbs the rest of the series. Since goal credit (`StreakGoal`/`_recordGoalCompletion`)
only ever fires off an `isDone` toggle, an archived-but-incomplete instance was already
never counted toward a goal — archiving just had to stop fighting the regeneration.

`TodoistSyncService._runSyncBody`'s completed-vs-deleted reconciliation
(`deletedByUid`) reads both the archive and the bin, so a task whose Todoist mapping
predates it being moved on to the bin (denied, or sent there from Archived Items) is still
recognized correctly.

### 4.2c Structured labels (0.1.108)

`Label` (`lib/models/label.dart`: id, name, kind `tag`/`priority`/`system`, optional ARGB
color) + `LabelService` (`labels.json`, ValueNotifier singleton) form the structured half
of a label dual-write: `Task.label` (the token string, split on commas/whitespace —
helpers in `lib/utils/label_utils.dart`) stays canonical; every save auto-registers
unseen tokens fire-and-forget (`registerFromLabelStrings` from `saveTaskList`; write-free
when all tokens are known, nothing loads at startup). Kinds derive from the token:
`priority-low/-medium/-high` → priority, `old` (Todo.md import marker) → system, else
tag. Name matching is case-insensitive; `upsert` edits metadata (colour) by name.

**Label picker (0.1.255):** `LabelPickerField` (`lib/ui/label_picker.dart`) replaces the
raw comma-separated label text field everywhere a task's `label` is edited (task-tile
inline editor, wishlist add/edit dialog). Current tokens render as removable `InputChip`s;
an "Add label" chip opens a dialog with a search/create field over every known label
(`LabelService.instance.labels`, checkbox-toggled) — typing a name that isn't already a
label offers "Add "<name>"" to create and select it in one tap. Selection is staged in
the dialog and only committed (chips update, `onChanged` fires) on "Done"; "Cancel"
discards it.

### 4.2e Auto-tagging (0.1.229, grouped dictionary 0.1.249)

`AutoTagGroup` (`lib/models/auto_tag_group.dart`: tag, `keywords` list) + `AutoTagService`
(`auto_tag_rules.json`, ValueNotifier singleton, `lib/services/auto_tag_service.dart`) —
a user-editable tag → group-of-words dictionary, e.g. the `fitness` tag fires on any of
`gym`/`workout`/`exercise`/`cardio`/`yoga`/`jogging`/`running`/`training`/`stretch`. Seeded
with 12 starter groups (work, bike, fitness, health, shopping, finance, travel, home,
family, food, study, tech) on first run, same load-seeds-and-persists / write-on-save
shape as `ProjectService`; the starter word groups were curated from online thesaurus
results (thesaurus.com, Merriam-Webster, WordHippo, relatedwords.io — via `WebSearch`)
trimmed to common, everyday words. `withAutoTags(title, label)` is the one entry point:
when `Config.autoTagEnabled` (default **true**) is on, `tagsFor` whole-word
case-insensitively matches `title` against every group's keywords and every group with a
hit contributes its tag; matched tags are appended to `label` (deduped against tokens
already present via `label_utils`), a no-op otherwise. Called from the home page's
`_addTask`/`_addTaskFromChronize` and the Wishlist page's new-item flow — edits never
re-tag. `AutoTagGroup.fromJson` also accepts the original one-keyword-per-tag shape
(`keyword` singular) from before groups existed, and `AutoTagService._normalize` (run on
every load/save) merges any groups sharing a tag and dedupes their keywords, so old data
and hand-edited duplicates both collapse into one clean group per tag. Settings → Tasks
has the on/off switch ("Auto-tag new items") and an "Auto-tag rules" entry point
(`AutoTagRulesPage`) to add/rename/delete a tag and edit its whole word group (comma/space
separated) in one dialog. Deliberately dumb today (a fixed dictionary, no real NLP); the
plan is to later swap the matching in `tagsFor` for an on-device LLM without touching
callers, which only ever see the resulting tag list.

### 4.2h Change sources & global Undo (0.1.281)

**Source tracking.** Every `ItemEvent` now carries a `source` field — one of
`TaskChangeSource`'s constants (`lib/models/task_change_source.dart`): `user` (default,
omitted from JSON to keep old journal lines readable as-is), `sync` (stamped on every
`TodoistSyncService` write — push, the two pull saves, §4.2 Todoist sync above), `share`
(Android share-sheet tasks), `automation` (day-rollover archiving, recurring-task
generation, shipped-wish auto-completion, wishlist migration), `undo`/`redo` (the global
Undo/Redo below), and `system` (pre-journal history reconstructed by
`ItemHistorySeeder`/the dev-seed timelines, which predates source tracking).
`ItemEventJournal.diffSnapshots`/`recordDiff` and `StorageService.saveTaskList` take an
optional `source` parameter (threaded through `ItemRepository.saveItems`) that's stamped
on every event one save produces. The task-detail History section
(`describeItemEvent`, `lib/ui/task_detail_page.dart`) appends `· <Source>` to non-`user`
lines (e.g. "Created · Share"); a plain user action stays unadorned since that's the
overwhelming majority of history.

**Global Undo/Redo.** `TaskMutationService` (`lib/services/task_mutation_service.dart`,
singleton) is a bounded (30-entry) undo/redo stack sitting alongside every task-list
save, without owning persistence itself. The home page's three existing save
chokepoints — `_saveTasks()`/`_saveDeletedTasks()`/`_saveBinTasks()`, which every
mutation in the file already funnels through (active list, the Archived Items list, the
real Deleted bin — §4.2g) — call `noteActiveChange`/`noteDeletedChange`/`noteBinChange`
right alongside their existing `ItemRepository` call. All three notes coalesce into one
microtask-scheduled flush, so an archive-then-bin move (`_moveArchivedToBin`, which
calls `_saveDeletedTasks()` then `_saveBinTasks()` back to back, synchronously) becomes
exactly one undo entry: **bulk/paired changes undo as one action** because Dart's
microtask queue only drains after the current synchronous call stack finishes.
`noteBaseline` is called once per session, right after `_loadTasks()` reads the three
on-disk lists and before any seeding/migration mutates them, so the first save doesn't
get diffed against nothing and misread as "everything was just created". Each flush
that finds a real change pushes a three-way before/after snapshot (the same
`uid → task JSON` shape `StorageService` diffs into the journal) with an auto-generated
description (`TaskMutationService.describeChange`, tested directly): grouped per-task by
what happened across all three lists — created/completed/reopened/rescheduled/moved/
relabeled/archived/restored/deleted (archive → bin)/denied (straight to bin)/permanently
deleted (bin → gone)/edited — collapsing a same-kind batch into one phrase ("Completed 3
tasks") rather than one line per task. `undo()`/`redo()` persist the reverted/re-applied
lists straight through `ItemRepository` tagged `TaskChangeSource.undo`/`.redo` —
bypassing the note/flush path entirely, so applying an undo is never itself undoable,
and (since `StorageService` runs its own independent before/after diff on every
`saveTaskList` call) the per-task History timeline picks up an active-list revert as an
ordinary tagged event for free. The home app bar carries Undo/Redo icon buttons
(`ValueListenableBuilder` over `TaskMutationService.instance.revision`, disabled with
nothing to act on); tapping either applies the returned snapshot to `_tasks`/
`_deletedTasks`/`_binTasks` **in place** (`clear()` + `addAll()`, never reassigning the
list) since other open pages (Projects, Archived Items, the bin) hold those exact list
instances by reference, then shows a snackbar with the action's description. "Priority"
is not a separate concept in this app — it is a `label` edit (`priority-low/-medium/
-high` tokens, §4.2c) — so it is already covered by the mechanisms above without its own
event type. `WishlistPage` and `WaitingApprovalPage` (whose `_deny` writes the bin directly, see
§4.2g) each keep their own independently-loaded copy of the task list — not shared by
reference with the home page — and are deliberately left out of this undo stack: wiring
a second, independently-timed reader/writer into the same before/after baseline risks
misreading ordinary staleness between the two pages as a real edit.

### 4.2i Presentation filters / view configuration (0.2.5)

`ViewPresentation` (`lib/models/view_presentation.dart`) is the presentation counterpart to
`ViewFilterRules` (§4.4): where `ViewFilterRules` decides *which* items belong in a view
(data filter), `ViewPresentation` decides *how* the items a view already selected are shown
and edited (presentation filter) — the two-part split the item-model redesign calls for.
Keyed by the same view ids (`ViewPresentation.forView(viewId)`); every field defaults to
today's actual behavior, so a view that hasn't adopted it renders exactly as before. First
(and so far only) consumer: `TaskDetailPage` — shared by the Projects board, Archived Items
and the Deleted bin — takes an optional `viewId` that controls whether the item-linked
capability sections (`TaskReminderSection`, `TaskCountdownSection`) render; archived/deleted
items hide both, since offering to attach a *new* reminder or countdown to something already
over is never useful (an existing linked reminder is already gone by then via
`ReminderSyncService`). See `docs/architecture/presentation-layer-decision.md` for why this
step stopped at one real consumer instead of rewriting every view's tile widget onto a shared
config — `TaskTile` (Home) and the other bespoke tiles (Wishlist, Alarms, Countdown, Food
Diary, Waiting for Approval, Projects) are unchanged.

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
by default (`Config.addNewTasksToTop`, default true). Which *bucket* they land in is
`Config.defaultAddTabIndex` (0.1.233): `addToCurrentTab` (−1, the default) files them under
the open tab, an index 0–5 pins every quick-added task to that bucket, so an idea typed
while Today is open can go straight to Future. `_addTargetTabIndex()` resolves it (falling
back to the open tab for an out-of-range value) and the add row's label names the target
whenever it is not simply the list you are looking at — "Add task · Future" — because a
task silently appearing in another tab reads as a bug. The schedule view's active day still
wins over the pinned bucket (there the day is picked explicitly). A mic button
(`SpeechInputButton`, 0.1.288) sits beside the field: tap to start local
speech-to-text (`speech_to_text` plugin, wrapped by `SpeechRecognitionService`),
tap again to stop; the transcript is written straight into the field (appended
to whatever was already typed), stays fully editable, and never auto-submits —
the existing Add button/Enter key still does that.

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
archive after the undo-snackbar window (same 5 s default) so Undo can restore it
in-place. Restore from Archived Items always resets due date to today.

**Done:** checkbox sets `isDone` + `completedAt`, sinks to bottom with strikethrough;
swept to the archive at day rollover.

**Recurrence (rebuilt 0.2, `RecurrenceService`):** logic lives in
`lib/services/recurrence_service.dart` (unit-tested in `test/recurrence/`), not the UI layer.
A series is one master (`recurrenceParentUid == null`, `isRecurring`) plus generated child
occurrences (`recurrenceParentUid == master.uid`); the master's own due date is slot 0.
Rule fields on `Task`: `recurrenceFrequency` (`daily`/`weekly`/`monthly`/`yearly`),
`recurrenceInterval` (every N units), `recurrenceWeekdays` (weekly multi-day, 1=Mon..7=Sun),
`recurrenceEndType` (`never`/`date`/`count`) + `recurrenceEndDate`/`recurrenceOccurrenceCount`.
A `never`-ending series only materializes a rolling ~60-day window (regenerated as time
passes), not the whole future. `recurrenceExceptionDates` (slot `yyyy-MM-dd` keys) marks a
slot a "delete this event" removed — `planRefresh` never regenerates an excepted slot, so a
deleted occurrence stays deleted across reload/import (previously the #1 bug: deletion was
only ever applied to the live list, so the very next regeneration silently recreated it).
`planRefresh` also still cross-checks Archived Items and the Deleted bin (§4.2g) for a
matching slot as a compatibility fallback, so occurrences archived before this rebuild (with
no exception recorded) stay skipped too. `recurrenceOverride` (bool, on a child) marks an
individually edited/moved occurrence;
regeneration always preserves an override, even if the schedule later shrinks past its slot.
Legacy `recurrenceIntervalDays` records migrate on read (`daily`, that interval).

Google-Calendar-style **edit/delete scope** (`RecurrenceEditScope`, `recurrence_scope_dialog.dart`):
deleting a series member (deferred to `_requestDeleteTask` in `home_page.dart`) asks *this
event / this and following / all events* whenever more than one occurrence exists.
"This event" adds the slot to `recurrenceExceptionDates` (or, deleting the master itself,
promotes the next occurrence to take over as the new master —
`RecurrenceService.promoteNextOccurrenceAsMaster`). "This and following"/"all events" use
`RecurrenceService.truncateSeriesBefore` to end the old series and batch-delete the tail (full
undo restores every task removed, not just one — `_deleteTasksBatch`). Editing a child's own
due date (the "Pick due date" button) asks the same *this event/this and following* question;
"this event" moves just that occurrence and flags it an override (its slot stays reserved, so
it's never duplicated or lost); "this and following" (`RecurrenceService.reanchorSeriesFrom`)
splits the series there, turning that occurrence into a new master and shifting its
non-override tail siblings by the same delta so they keep matching the (unchanged) pattern.
Moving/rescheduling via a quick gesture (swipe, drag, dice postpone) keeps the occurrence in
its series as an override rather than detaching it. Regenerated after load, import, and any
master edit.

**Creating a recurring task:** the add-task row's Repeat button (`Icons.repeat`) opens a
Calendar-style quick sheet — Does not repeat / Daily / Weekly on `<today>` / Monthly / Yearly
(all default to no end) / Custom... (the full `RecurrenceEditor`, also used by the tile's
inline editor and the sheet's "Custom..." dialog) — and arms it for the next task created
from that row only.

**Inline editing:** tapping a tile expands it — title/description/note text fields (editing
a child field marks it an override) and a `LabelPickerField` (§4.2c, persists immediately on
each add/remove) for labels, due-date picker, recurring switch + `RecurrenceEditor`
(frequency/interval/weekday chips/never-date-count end) for a master, a Notify bell, collapse
button. Text fields persist on change/focus loss.

**Notify bell (delay sheet 0.1.233):** the bell asks *when* first — a modal sheet headed
`Notify me about "<title>"` offering In 5 minutes / In 20 minutes / In 1 hour
(`_notifyDelayOptions`) plus "Default delay", which keeps the old behaviour of
`Config.defaultNotificationDelaySeconds` and shows it as `In 05:00 — set in Settings`.
Picking one schedules a task notification (quiet hours still shift it, see §6) and
confirms with "Notification scheduled in 5 minutes"; dismissing the sheet schedules
nothing. The task's due date is never touched — this is a reminder, not a reschedule.
With notifications off the bell skips the sheet and shows "Enable notifications in
Settings first".

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

**Drawer:** Home, Settings, Archived Items (→ Deleted bin, §4.2g), About, Changelog, App Logs, Startup Times,
Tools ▸ (Food Diary, Alarms, Weekly Hours Planner, Projects, Wishlist, Chronize, Countdown,
Productivity Stats, Usage Data, Test Results — most-used first, Test Results pinned last).
**Home** (0.1.233) is `_goHome()`: pop every page stacked on
the home route, clear an active search, and return to the start tab
(`Config.startTabIndex`) and start view (`Config.startInScheduleView`, only when the
schedule-view feature is on) — so it always lands on the same familiar screen rather than
just closing the drawer.

**CI test report (0.1.96, moved to Tools + online in 0.1.99):** CI runs the tests and
serializes the run into `assets/test_report.json` via `tool/generate_test_report.dart`
(`--commit/--branch/--version`), which the APK bundles; the committed placeholder is
`{"available": false}` so local/dev builds carry no bundled data (asset registered in
pubspec). On push, `build-apk.yml` also commits that JSON to `docs/ci/test_report.json`
so the app can fetch the latest results over the network (`build-apk` push trigger
`paths-ignore`s `docs/ci/**` to avoid a self-triggering loop). `models/test_report.dart`
(tolerant fromJson; also owns `fromMachineJsonLines`, the `flutter test --machine` parser)
carries `appVersion` (`x.y.z+build` from pubspec at CI time). Since 0.1.129 the report
also carries `suites`: one `TestSuiteResult` per test file (path trimmed to the
repo-relative `test/…` / `integration_test/…` part, Windows backslashes normalized)
holding a `TestCaseResult` per executed test — name, result (`passed`/`failed`/`skipped`)
and `durationMs` (testDone − testStart machine timestamps; null when absent). Hidden
bookkeeping entries are excluded, tests whose suite was never named group under an empty
path, and per-suite/report durations sum only the known times (null when none). Reports
without a `suites` key parse to an empty list, so pre-0.1.129 JSON stays valid everywhere.
`TestReportService` (singleton; `load` = bundled asset + the acknowledgement marker,
`loadOnline` = `HttpClient` GET of the dev `docs/ci/test_report.json` with all failures
swallowed to an unavailable report, `loadForDisplay` = online-primary/bundled-fallback;
`setReportForTest`/`setOnlineReportForTest`/`refreshOnline`/`resetForTest`). The red
failure dot uses the **bundled** report (loaded offline at startup, so startup stays fast),
filtered through an acknowledgement marker (`hasUnseenFailures`): the Tools ▸ Test Results
entry — and, only when the "Red dot for failed tests" Appearance setting
(`Config.showFailureDotOnMenu`, default off) is on, the home app bar's custom hamburger
`leading` (default "Open navigation menu" tooltip, opens the drawer via `Scaffold.of`) —
carries a 9 px red dot (`Key('test-failure-dot')`). Opening the Test Results page calls
`markSeen(displayed)` (unawaited): it records the newest acknowledged run date plus
fingerprints (commit|date|counts) of the seen + bundled reports in
`test_report_seen.json`, so every dot disappears immediately and stays off across restarts
until a run newer than anything acknowledged fails. `TestResultsPage` (a Tools page,
`test_results` start-tool key) is a StatefulWidget with an app-bar refresh action: a
version card (running version vs tested version, match/mismatch note, online-vs-offline
source), a summary card (passed/failed/skipped/total plus "ran in 42.3 s" when durations
are known, commit + branch + run time), one ExpansionTile per failed test with its error +
stack trace, and — since 0.1.129 — an "All tests" section listing every suite as an
ExpansionTile (monospace path, per-suite counts + time, failing files sorted first) whose
children are one row per test: green check / red close / grey skip icon, name, and
`formatTestDuration` ("340 ms" under a second, "2.1 s" above). Reports without suite
detail show a "predates per-test details" note instead. `Config.resetVersionForTest()`
clears the memoized version future so widget tests reload it per async zone.

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
moving to the Tomorrow tab: a series member stays in its series as an override rather than
detaching), and **+1/+5/+10 min** (stops the
ring and restarts the countdown with that much time). With no open Today tasks (and no timer
already running) the dice shows a "No open tasks for today" snackbar instead.

**Cancel timer (0.1.127):** a muted-error `TextButton` in the action grid (beside Lock touch
while running/paused, beside Done at the ring), shown in the running, paused and ringing
phases (never on the untouched dial — there is nothing to cancel yet). It calls `DiceTimerController.clear()`, so the ticker, any melody/vibration and the
OS-scheduled ring all stop, then pops the page with a "Timer cancelled" snackbar. This is the
only exit that leaves the task untouched — Done and Postpone both answer for it, and plain
back-navigation deliberately keeps the countdown alive.

**Start timer from a task (0.1.132):** double-tapping a task tile opens a little
bottom-sheet menu — "Start timer" (subtitle shows the default duration), a divider, and
since 0.1.234 three snooze entries "Remind me in 5 / 10 / 20 minutes". The sheet is
`isScrollControlled` so five rows size to their content instead of overflowing the
default 9/16-height sheet on a short screen. The double tap is detected by hand inside the tile's `onTap` (two taps within
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
replaces the old one — the double tap is an explicit choice for that task. The reminder
entries go through `_TaskTileState._scheduleReminder` — the same helper the expanded
tile's Notify bell uses (§ notifications): `NotificationService.showTaskNotification`
with the picked delay, quiet-hours shifting included, a "Notification scheduled in 10
minutes" snackbar, and "Enable notifications in Settings first" when they are off. The
task's own due date is never touched.

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
default `dd.MM.yy`). Tasks: add-to-top, "New tasks go to" (`defaultAddTabIndex`, default
"Current tab", see §4.3), swipe-left-delete, default delay 0–10 s slider,
start tab (simple mode hides the tool-related entries, see §4.6), default start page
(`startTool`: the task list or any enabled tool — Alarms, Countdown,
Projects, Chronize, Usage Data, Productivity Stats, Weekly Hours Planner; the tool is pushed on top of the task
list after loading, so back lands on the tasks), start in schedule view, Chronize hour
wheel, "Auto-tag new items" (`autoTagEnabled`, default on) + an "Auto-tag rules" entry
point to edit the keyword dictionary (§4.2e). Widget: progress line, "Check off tasks on the widget" (`widgetCheckboxes`,
default **off**, see §8). Notifications:
enable (default **off**), quiet hours (default 22:00–07:00, stored as minutes-since-midnight;
applied to task notifications only, never alarms), default notification delay (dev 3 s /
prod 300 s). SMS report: see §7. Sync & export: synced-mode switch + sync-folder picker
+ Sync now tile (§4.7), Export/Import buttons. Todoist sync: enable switch + API token
field (§4.8). `Config.applyMap` is defensive
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
starts as **every** section index (0.1.157; it was `{1}` from 0.1.123), so Settings opens
as a short list of headings instead of a wall of switches. A right-aligned
`TextButton.icon` above the first card is the master toggle: "Collapse all"
(`unfold_less`) while any visible section is open, "Expand all" (`unfold_more`) once they
are all closed — on arrival it therefore reads "Expand all". Tests that reach a setting
must open its section first (tap `Expand <section>` or jump via its chip). `_jumpToSection` removes the target from
`_collapsedSections` first, so chips and search results never land on a closed title;
toggles re-run `_updateActiveSectionFromScroll` on the next frame because the list height
changed under the chip row.

**Filtering rules (0.1.235, extended to the archive/bin split 0.1.266, Waiting for Approval
added 0.1.272, synthetic state tags + Food Diary/Alarms/Countdown views + protected-tag
colouring added later):** a per-view tag filter, configured separately for each of Home,
Wishlist, Waiting for Approval, Projects, Food Diary, Alarms, Countdown, Archived Items and
the Deleted bin. `ViewFilterRules` (`lib/models/view_filter_rules.dart`: `excludeTags`,
`includeTags`, both `List<String>`) holds one view's configuration; `Config.viewFilterRules`
(`Map<String, ViewFilterRules>`, keyed by `ViewFilterRules.home/wishlist/approval/projects/
foodDiary/alarms/countdown/archived/bin`) persists all of them inside `settings.json`
alongside every other setting. A task carrying any `excludeTags` token is hidden from that
view; when `includeTags` is non-empty, only tasks carrying at least one of its tokens show.
This sits on top of each view's own structural rule (the wishlist still only ever shows
`isWish` tasks, and the Waiting for Approval queue only ever shows pending, non-deleted ones)
— see §4.2d. `ViewFilterRules.builtInRules` is a read-only string per view id (empty for
Archived Items/Deleted bin/Alarms/Countdown, which have no selector-level rule of their own)
summarizing that always-on structural business logic — Home's reads "Always excludes Waiting
for Approval, Archived, and Deleted items", for instance — shown in Settings directly under
each view's description, above its two editable chip rows, so the business logic a view lives
by is visible even though (being unconditional, not itself one of the `excludeTags`/
`includeTags` below it) it isn't something a chip edit can turn off. The Settings "Filtering
rules" section (index 2, right after Mode & features) lists all nine views with the built-in
line (if any) plus two chip editors each (add via text field + Enter/+, remove via the chip's
×); `SettingsPage._rulesFor` lazily creates an empty entry per view on first touch. Because a
Home rule can hide tasks mid-tab, drag-reorder on the home list is disabled whenever one is
active (`_homeFilterRulesActive`), exactly like it already is while a search query is active —
reordering a narrowed list would renumber only the visible subset and scramble the hidden
tasks' rank order; renumbering on save (`_saveTasks`, `applySearch: false`) always sees the
true unfiltered tab so ranks never drift. Countdown applies the same disable-reorder-while-
filtered rule to its own manual drag order (`_CountdownTimerPageState._onReorder`).

*Matching, including a task's synthetic state.* Matching (`ItemViews.passesTagRules`) is
case-insensitive against a *combined* token set: a task's real `Task.label` tokens
(`splitLabelTokens`) plus its synthetic state tags (`ItemViews.stateTags`) — Wish
(`isWish`), Fooddiary (`isEatingHabit`), Project (`projectId != null`), Waiting_for_approval
(`!isApproved`), and — supplied by the caller rather than derived from the task, since
neither is a field on `Task` itself, only which list currently holds it — Archived and
Deleted (`ItemViews.applyFilterRules`'s `archived`/`binned` flags, passed `true` at the
Archived Items and Deleted bin call sites in `home_page.dart`). This is what makes a rule
like "Home: hide Wish" actually do something even though no task's label literally contains
the word "Wish". `ItemViews.passesTagRules`/`applyTagRules` are the primitives underneath —
generalized over a raw tag string rather than a `Task`, so Alarms and Countdown (which have
their own `tags` field, not a `Task.label`) reuse the identical matching code.

*Protected/reserved tags (`lib/utils/label_utils.dart`, `lib/utils/label_style.dart`).* The
eight tokens a rule can reference — `Wish`, `Project`, `Archived`, `Deleted`, `Fooddiary`,
`Alarm`, `Countdown`, `Waiting_for_approval` (`protectedStateTokens`) — are reserved: typing
one by hand into a task's, alarm's, or timer's own tag field is a naming collision with
something the app already gives special meaning, so every chip renderer (`LabelPickerField`,
`TaskTile._tag`, the Alarms/Countdown tag pills) renders a matching token in one fixed accent
(`protectedTagColor`, deep-orange, with a border and a tooltip explaining why) instead of the
normal chip style — the tag equivalent of a file extension warning. `labelKindFor` classifies
every protected token as `Label.kindSystem`. Typing one does not, on its own, flip the
underlying flag (e.g. typing "Wish" onto a task does not set `isWish`) except
`Waiting_for_approval`, which — unchanged from before — is the one token that *is* the literal
mechanism (§4.2e).

*Food Diary, Alarms and Countdown as filterable views.* Food Diary
(`ItemViews.foodDiary(tasks, {rules})`) works exactly like Wishlist: an extra rules layer on
top of its `isEatingHabit` gate. Alarms and Countdown aren't task lists, so each gained its
own `tags` field (`Alarm.tags`, `CountdownTimerItem.tags` — free-form, same comma/whitespace
convention as `Task.label`, editable via a `LabelPickerField` in `AlarmEditPage` and the
`_DraftTimerComposer` used for both adding and inline-editing a timer) and each page filters
its own list with `ItemViews.applyTagRules(items, rules, (item) => item.tags)` before display,
rendering any tags as small pills under each row.

*Seeded defaults (`Config.viewFilterRulesSeedVersion`, `ViewFilterRules.defaultsFor`).* A
fresh install's Settings → Filtering rules starts pre-populated rather than empty, with the
literal Hide/Show matrix this feature was specified with — every view hides every other
view's reserved tag and shows only its own: Home has no tag of its own, so it hides all nine
(Wish, Project, Archived, Deleted, Fooddiary, Alarm, Countdown, Changelog, Waiting_for_
approval) and shows nothing; Wishlist/Food Diary/Alarms/Countdown hide the other eight and
show only their own tag; Waiting for Approval hides just Archived/Deleted/Changelog (its
built-in gate already excludes everything else) and shows Waiting_for_approval; Projects
hides everything except Wish (a wish can still be assigned to a project) and shows Project;
Archived and the Deleted bin only ever hide *each other*, since an item can legitimately be
both, e.g. an archived wish. This is a real, user-facing default, not a restatement of a
structural gate — e.g. Home now hides Wish/Project-tagged tasks by default even though
they'd otherwise show by due date. `Config.seedViewFilterRuleDefaultsIfNeeded` applies it:
called once from `Config.load`, it fills any view with *no* entry on a fresh install
(`viewFilterRulesSeedVersion == 0`), and — should `ViewFilterRules.defaultsFor`'s template
itself need correcting later, the way version 1's did (it shipped too conservative, leaving
Wish/Project out of several Hide lists to avoid disturbing other behavior) — a bump of
`Config._currentViewFilterRulesSeedVersion` re-syncs *every* view on an install still behind
that version, overwriting whatever the earlier template had seeded rather than only filling
gaps; it is a no-op once already at the current version. The one place a literal default
would break an existing feature outright: Projects' `includeTags: [Project]` would filter its
"All Tasks" pane (used to drag an *unassigned* task onto a project) down to only
already-assigned tasks. `ProjectsPage._assignPaneRules` compensates by dropping `includeTags`
(keeping `excludeTags`) for that one pane only — the project board itself
(`projectTasks`/`boardColumn`) still gets the full rule, though it's redundant there since a
board column already filters by exact `projectId`.

### 4.5 Streak (the flames, 0.1.115; three challenges 0.1.157; unlit-until-done
pulse 0.1.229; configurable goals 0.1.250)

Daily streak gamification with **three** flames (`StreakKind` in
`lib/models/streak_kind.dart`; the ids are persisted, so keep them stable):

| kind | id | day counts when | flame colours (cold → warm → hot) |
| --- | --- | --- | --- |
| Finish a task | `complete` | ≥1 non-wish task completed | orange → deep orange → red |
| Create (green) | `create` | a task matching its configured goal is completed | light green → green → teal |
| Plan (blue) | `plan` | a task matching its configured goal is completed | light blue → indigo → purple |

`complete` is fixed. The green (`create`) and blue (`plan`) slots are **user-configured
goals** since 0.1.250 (`StreakGoal` in `lib/models/streak_goal.dart`, persisted in
`Config.streakGoals` — a `Map<String, StreakGoal>` keyed by kind id): each goal picks a
`target` (`StreakGoalTarget.task` — one specific recurring task, matched by its own uid
**or** its generated instances' `recurrenceParentUid` — or `StreakGoalTarget.project` —
any task filed under a chosen project, matched by `projectId`) plus a `title` shown on
the flame instead of a fixed label (pre-filled from the task/project name when the goal
is set in the picker dialog, freely editable afterwards). `StreakGoal.matches(Task)`
implements the match. A slot with no entry in `Config.streakGoals` has **no built-in
default any more** — it just stays cold until configured (`streakFlameInfo` in
`lib/services/streak_flame_display.dart`, see below).

`StreakService` (ChangeNotifier singleton, `streak.json` via `SafeFile`) stores one
dayKey → **count** map per kind — `completionsByDay` (the original key, kept so old files
load unchanged), `createsByDay`, `planByDay` — plus, since 0.1.144, a parallel
`minutesByDay` map of dayKey → minute-of-day list (one entry per live completion; seeded
history has counts only) powering the time-of-day challenges. Counts, not booleans, so
toggle+untoggle on the same day cancels out exactly and per-day stats are possible.
`record(kind, when)` returns true on that kind's **first** event of the day (the
streak-kept moment); `recordCompletion` wraps it for `complete`, and `recordGoal(kind,
when)` is the equivalent for a configured `create`/`plan` goal — at most one event per
day (re-checking a task's matches on every toggle must not inflate the count).
`recordUncompletion(when, {kind})` (generalized in 0.1.250 — used to be `complete`-only)
decrements that kind's map, drops the **latest** recorded minute only for `complete` (the
other two never tracked times), and removes the day at zero. Every read API
(`currentStreak`, `isDayDone`, `longestStreak`, `bestDay`, `flameProgress`, …) takes an
optional `kind:` that defaults to `StreakKind.complete`, so older call sites and tests
keep their meaning. `enabledKinds` filters by `Config.streakKindEnabled` (all three on by
default; the switches live in Settings → Streak → "Active challenges" — this is
independent of whether a `create`/`plan` slot has a goal configured).
`StreakService.syncKnownTasks(tasks)` (called every `HomePage.build()`) tracks which task
uids currently exist so `isGoalMissing(kind)` can tell a task-targeted goal whose task was
deleted apart from one that simply has not fired today; a project-targeted goal is
checked directly against `ProjectService.instance.byId(goal.targetId)` by the display
layer instead (no service-to-service dependency needed for that case).

Wish items never count. Hooks in `home_page.dart`, all using `_currentDate` so the dev
date stepper works: `_recordStreakToggle` (tile checkbox + dice-timer "done") → completion
plus `_recordGoalCompletion`/`_recordGoalUncompletion`, which check the toggled task
against `Config.streakGoals['create']`/`['plan']` (`StreakGoal.matches`) and call
`recordGoal`/`recordUncompletion(kind: …)` on a match. The home-screen widget's checkbox
(`task_widget_service.dart`) mirrors the same goal-matching inline since it runs in a
background isolate without the home page's hooks. The old fixed "any task created" /
"a task moved or the day cleared" defaults (and their `_recordStreakCreation`/
`_recordStreakPlanning`/`_recordStreakDayCleared` hooks) were retired in 0.1.250 —
`_trackTaskCreated`/`_trackTaskMove` no longer touch the streak at all.

**Streak semantics:** consecutive active days ending today or later-graced; a day still
in progress never breaks the streak. Grace (`Config.streakGraceHours`, 24 default / 48):
24 = every calendar day needs ≥1 completion; 48 = a single missed day between active days
is forgiven (`_allowedGap` 0/1 applied both when anchoring from today and while walking
back). `longestStreak()` scans full history under the same rule; `longestStreakRange()`
returns the same run's exact first/last day as a record (earliest run wins ties). Flame
maxes out at **365 days** (`flameProgress` = streak/365 clamped to 1).

**Display layer (0.1.250):** `streakFlameInfo(kind)` in
`lib/services/streak_flame_display.dart` is the single place every flame's `short`
(chip/tooltip label), `title`, `description` and `callToAction` come from — `StreakPage`,
`StreakFlameButton` and the Settings "Active challenges" rows all call it instead of
reading `StreakKind`'s constants directly. `complete` always returns the fixed enum text.
For `create`/`plan` it returns one of three states: **unconfigured** (no
`Config.streakGoals` entry — `short`/title fall back to the kind's own short name, e.g.
"Create · no goal set", description invites setting one, `configured: false`);
**missing** (a goal is configured but `StreakService.isGoalMissing(kind)` — task target —
or `ProjectService.instance.byId(goal.targetId) == null` — project target — is true;
shows the goal's title with a "was deleted" description, `missing: true`); or **active**
(goal resolved fine — title/description/callToAction all built from `goal.title`, e.g.
"Complete 'Exercise' every day"). An unconfigured or missing slot never has anything
recorded against it, so its flame naturally renders cold (`flameColor` at progress 0 is
already grey) with no special-casing needed in the colour/size math.

**Goal picker (0.1.250):** `StreakGoalDialog` (`lib/ui/streak_goal_dialog.dart`, own
`StatefulWidget` owning its `TextEditingController` per the `_ProjectEditDialog`
convention) is opened from a "Set goal"/"Change" row under each of the `create`/`plan`
switches in Settings → Streak → "Active challenges". A `SegmentedButton` picks
`StreakGoalTarget.task` (a `DropdownButton` of recurring tasks — `isRecurring &&
recurrenceParentUid == null`, loaded via `StorageService().readTaskListRaw()` so it never
fights the home page's in-memory list/rollover) or `.project` (a dropdown of
`ProjectService.instance.list`); picking an option auto-fills the title field with its
name (only while the field still matches the last auto-fill, so a hand-typed title is
never clobbered) and the field stays freely editable. Save writes
`Config.streakGoals[kind.id]`, `Config.save()`s and calls
`StreakService.instance.settingsChanged()`; "Remove goal" clears that entry — both close
the dialog and the Settings page picks up the change via its own `setState`.

**UI:** `StreakFlameButton` (`lib/ui/streak_flame_button.dart`) in the home app bar
directly left of the dice (`ListenableBuilder` on the service; hidden when
`Config.showStreak` is false or every challenge is switched off). It **cycles** through
the active challenges every 2.4 s (`Timer.periodic` + `AnimatedSwitcher` fade/scale keyed
by kind), showing that kind's colour, `Badge` count and a `streakFlameInfo`-built tooltip
("Finish a task: 3-day streak" / "Create · no goal set" / "Exercise: 5-day streak"); the
icon grows 22→30 px with progress.
**Unlit until the day is done (0.1.229):** the flame burns in the kind's colour only when
`isDayDone(today, kind:)` — a streak still riding on yesterday (or on the grace day) shows
the *outlined* icon in `theme.disabledColor`, the `Badge` (still counting the streak at
risk) greys with it, and the tooltip gains "— still open today" (an unconfigured
`create`/`plan` slot short-circuits before any of this — `streakFlameInfo`'s `title` is
shown as-is with no streak/done state at all). That grey icon **pulses**: a 900 ms
repeat-reverse controller lerps it grey → white and scales it 1.0 → 1.12, so an unfinished
challenge keeps drawing the eye. Tapping opens `StreakPage` on the kind currently shown.
**All challenges done settles the flame (0.1.236; goal-aware since 0.1.250):** once every
*tracked* kind is done today (`complete`, plus `create`/`plan` only once a goal is
configured — an unconfigured slot is excluded so it can't block this forever — and more
than one tracked kind is on), the cycling collapses into a single **steady white flame
with a faint blue cast** (`StreakFlameButton.allDoneColor` = `0xFFE8F0FF`; red 700 until
0.1.252) badged with the **highest** of the streak counts, keyed `'all-done'` so the
switcher stops cross-fading. The badge's number switches to
`StreakFlameButton.allDoneBadgeTextColor` (`0xFF1B2A4A`) so it stays readable on the
near-white badge;
the tooltip becomes "All 3 challenges done today — 5-day streak" and tapping opens
`StreakPage` on the kind that owns that highest streak. A single tracked challenge keeps
its own colour (there is no cycle to collapse) — the cycle itself still hops through every
*enabled* kind, tracked or not, so an unconfigured slot's "no goal set" placeholder is
still shown in its turn. **Cycle and pulse are both disabled under the test bindings** (a
repeating timer/animation means `pumpAndSettle` never settles, and it also keeps
screenshot runs deterministic) — the check is `WidgetsBinding.instance.runtimeType`
containing "Test"; `StreakFlameButton.debugForceCycle` re-enables both for the tests that
cover them.

`StreakPage`: a `ChoiceChip` row (one mini flame per active challenge, "Finish 3") when
more than one is on, big flickering flame in the selected kind's colour (700 ms
repeat-reverse controller — **never `pumpAndSettle` this page in tests**, it never
settles; scale/sway/glow scale with progress), fun level names ("First spark" →
"MAXIMUM FIRE"), progress bar to a full year, a "Today" card listing every active
challenge via `streakFlameInfo` with a check mark, "Open", "Not set" (unconfigured) or an
error icon (goal missing) trailing (tap a row to select it), a stats card worded per kind
(streak start, longest ever, active days, total events, best day, average per active
day — `create`/`plan` use generic "the goal was met" wording since there is no fixed
challenge behind them any more), and a gear action → Settings. First completion of the
day plays a ~1.4 s
self-removing overlay celebration (`showStreakCelebration`: flame pop + sparks + "Streak
kept — N days!", `IgnorePointer`, gated by `Config.streakCompletionAnimation`) — tied only
to the `complete` flame, not to a goal completion.

**Streak calendar (0.1.144):** the "Longest streak ever" stat tile is tappable
("Tap to see it on the calendar") → `StreakCalendarPage`: header card naming the longest
streak's exact first/last day (`formatTimerDate`), year selector (defaults to the year
the longest streak started), legend, and all 12 months as compact Monday-first 7-column
grids in a responsive `Wrap` (2–4 columns by width). Day cells: filled in the kind's
`warm` colour = active day inside the longest streak, outlined = grace day the streak
survived, 35 %-alpha `cold` colour = active day outside it. Since 0.1.157 the page takes
a `kind` (default `complete`) and is opened for whichever flame the stats card belongs
to.

**Challenges (0.1.144):** `evaluateStreakChallenges(service)` in
`lib/services/streak_challenges.dart` recomputes **26** Duolingo-style challenges from
history on every build (nothing persisted, self-healing): First Spark (1st completion);
time-of-day via `minutesByDay` — Early Bird (<8:00), Dawn Patrol (<6:00), Night Owl
(≥22:00), Lunch Break Hero (12:00–14:00); best-day counts — Hat Trick 3 / High Five 5 /
Perfect Ten 10 / Task Tornado 20; streak lengths (max of longest & current) — Week of
Fire 7 / Fortnight Flame 14 / Monthly Blaze 30 / Quarter Inferno 90 / Half-Year Furnace
180 / Eternal Flame 365; calendar patterns — Weekend Warrior (Sat + next-day Sun),
Monday Hero, Fresh Start (1st of month), Full Month (every day of a calendar month),
Comeback Kid (new active day after ≥2 missed days); totals — Explorer 10 / Regular 50 /
Veteran 100 active days, Century Club 100 / Task Machine 500 / Task Legend 1000
completions. Rendered on `StreakPage` below the stats card: "Challenges" card with
"N / 26 earned" counter; earned tiles get an amber icon + check, unearned multi-step
ones a thin deep-orange progress bar and "x/y" trailing text. **Order (0.1.234):** still
open first (evaluation order within the group), then an amber "Earned" divider header
(only when both groups exist), then the earned ones — the card opens on what is left to
chase rather than on a wall of check marks.

**Seeding:** on first load without `streak.json` (`needsSeed`), only the `complete` kind
is backfilled from existing history — completions per day the **max** of daily-stats
counts and `completedAt` timestamps on live+deleted tasks (so nothing double-counts and
long-time users start warm). `create`/`plan` are user-configured goals with no fixed
app-wide meaning (0.1.250), so there is nothing generic to backfill for them — they start
cold and unconfigured for everyone, new install or not. (In dev builds the seeded demo
daily-stats produce a pre-lit `complete` flame; tests write an empty `streak.json` up
front to opt out.) Dev/demo builds then also run `seedDevStreak()`, which fills the last
`Config.devSeedStreakDays` (**50**) days back from today for `complete` only — max-merged,
so real counts survive. It runs only inside the `needsSeed` branch, so a dev install's
real streak is never papered over.

**Reminders (list since 0.1.157):** `Config.streakReminderEnabled` is the master switch
(default off) and `Config.streakReminders` holds up to `maxStreakReminders` (**24**)
`StreakReminder`s (`lib/models/streak_reminder.dart`: minutes-of-day, enabled, and a
`StreakAlertMode` — `notification` = silent channel, no sound or vibration, or `sound` =
task channel with sound + vibration). Settings written by an older version migrate their
single `streakReminderMinutes` into one list entry on load. `syncReminder()` cancels
every slot and re-arms one **one-shot** `zonedSchedule` per enabled reminder (ids
`kStreakReminderNotificationIdBase = 0x20000010` + slot, plus the legacy
`kStreakReminderNotificationId = 0x20000002` which is only ever cancelled;
`inexactAllowWhileIdle` — deliberately NOT the alarm ladder, no exact-alarm permission
needed) for today's time, or tomorrow when the time has passed or every *tracked* kind is
already met — an unconfigured `create`/`plan` slot is excluded from that check (0.1.250;
it has no challenge to meet, so it must not block the "everything done" shortcut). The
body names what is still open, skipping unconfigured slots and naming a configured goal
by its own title ("Still open today: finish a task, exercise. Keep your 5-day streak
alive.", `reminderBody`). Re-synced on every app start, recorded event and settings
change; cancelled when reminders are off, the streak is hidden, or no challenge is active.
Settings live in a searchable "Streak" Settings
section: show/hide, 24h/48h `SegmentedButton`, "Active challenges" (one switch per
`StreakKind`, plus a "Set goal"/"Change" row under `create`/`plan` opening
`StreakGoalDialog`), "Streak reminders" (master switch, one row per reminder with time picker,
alert-mode chips, on/off switch and delete, plus "Add reminder" — new entries default to
the last time + 1 h), celebration toggle.

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
`'features'`; unknown/missing keys count as enabled). Keys: the ten tool keys (equal to
`startToolOptions` minus `tasks`) plus `streak`, `dice_timer`, `schedule_view`, `search`,
`deleted_items`, `changelog`, `app_logs`, `startup_times`, `sms_report`.

**`Config.isFeatureEnabled(key)` is the single gate:** in simple mode it returns false for
everything except `Config.simpleModeFeatures` (`deleted_items`, `changelog`, `app_logs`,
`startup_times` since 0.1.121 — the app's own service pages are not "extra features", and
Archived Items is the undo of a delete, so simple mode only strips the home surface and
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

### 4.7 Synced mode — background folder sync on quit (0.1.130)

The offline/synced choice: `Config.syncEnabled` (default **off** = fully offline) +
`Config.syncFolderPath` (empty until picked), both in Settings → **Sync & export**
("Synced mode" switch; enabling it with no folder opens the `getDirectoryPath` picker
immediately; the "Sync folder" tile only shows while enabled; a "Sync now" tile below
it (0.1.148) runs a manual sync — `SyncService.syncNow(trigger: 'manual')` — with a
result snackbar, is disabled until a folder is chosen, and its subtitle shows the last
run from the sync history, "Last sync: <time> (N tasks)" or "Last sync failed: <time>",
live via the `entries` ValueNotifier). `SyncService`
(`lib/services/sync_service.dart`, singleton with `resetForTest`) writes the task list
to `<folder>/besttodo_tasks.json` (`{sync_version: 1, synced_at, app_version,
task_count, tasks[]}`) — **tasks only** for now.

Since 0.1.132 every sync also writes `<folder>/besttodo_tasks.md`, an Obsidian-friendly
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

Since 0.1.141 the repo also ships **Tier 2** of the Obsidian integration: an
Obsidian community plugin in the top-level `obsidian-plugin/` folder (TypeScript +
esbuild, own npm package and CI job `obsidian_plugin.yml` — not part of the Flutter
build). It renders `besttodo_tasks.json` as a custom `ItemView` (ribbon icon /
"Open task view" command): the six home buckets, checkbox + title + `📅` due
date (sentinel omitted) + `✅` completion date + `🔁` recurring marker, label chip and a
generic `📁 project` chip (the sync file carries no project names), open-first/ranking
order, plus an "as of …" line showing `synced_at` + app version. It re-reads on
Obsidian's file-change events (safe because the app's write is atomic), refuses unknown
`sync_version` values with a friendly notice, and parses tasks as tolerantly as
`Task.fromJson`. The contract lives in the pure module `obsidian-plugin/src/model.ts`
(mirrors `ItemViews.inHomeBucket`, `sortTasks`, `Task.fromJson`) and is pinned by jest
tests (`obsidian-plugin/test/model.test.ts`) mirroring `test/sync/sync_markdown_test
.dart`.

Since 0.1.235 the repo also ships **Tier 3**: two-way sync via a change journal, so
checking a task off (or back on) in Obsidian flows back to the phone. The plugin's
checkbox is no longer disabled — a tap appends a `complete`/`reopen` operation to
`besttodo_changes.json`, written next to the sync file (`BestToDoPlugin.appendChangeOp`,
`obsidian-plugin/src/main.ts`), instead of editing `besttodo_tasks.json`/`.md`
directly (the app overwrites both on every sync, so a direct edit would be clobbered).
The view updates optimistically and shows a "syncing…" chip on the task
(`BestToDoView.pending` in `obsidian-plugin/src/view.ts`) until a subsequent
file-change event confirms the app picked up the change.

On the app side, `SyncService.onLifecycleChanged` triggers `SyncImportService
.importPending()` (`lib/services/sync_import_service.dart`) on every **resume** —
the mirror of the quit-time sync trigger. It reads `besttodo_changes.json`, applies
ops by `uid` with last-writer-wins conflict rules (idempotent/monotonic
`complete`/`reopen` against `Task.completedAt`; date-field `edit`s arbitrated against
`Task.rescheduledAt`; `delete` as a `Task.deletedAt` tombstone, never a hard delete;
`create` idempotent by the `uid` it brings), truncates the journal to an empty
envelope (never deletes the file), and re-runs `SyncService.syncNow` so both sides
converge. Failures (malformed journal, unknown `journal_version`, folder gone) land as
red entries in the same App Logs "Sync" history as a regular sync
(`SyncService.recordEntry`), never as an exception — same fail-soft contract as the
rest of synced mode. The op vocabulary also carries `edit`/`create`/`delete` for a
future richer write surface; only the checkbox (`complete`/`reopen`) is wired up on the
plugin side today. Conflict rules and failure-mode rationale are recorded in
`.claude/notes/obsidian-integration.md`; tests: `test/sync/sync_import_service_test
.dart` (Dart) and the "change journal" describe block in `obsidian-plugin/test/model
.test.ts` (TypeScript).

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
The page has two tabs since 0.1.130: "Logs" (the live 24 h `LogService` list) and
"Sync" (green check "Synced N items in M ms" / red error "Sync failed: reason", with
timestamp · trigger subtitle).

**Red dot:** a failed sync sets `hasUnseenError` (persisted as `unseen_error`), which
puts a small red dot (Key `sync-error-dot`, same `_iconWithFailureDot` stack as the CI
test-failure dot but its own key) on the drawer's App Logs entry via a
`ValueListenableBuilder`. Opening App Logs calls `markErrorSeen()` (dot gone, entry
stays); a later successful sync also clears it.

Tests live in their own silo `test/sync/` (service round-trip/failures/lifecycle latch
+ Sync tab, drawer dot, settings switch).

### 4.8 Todoist sync — two-way sync with a Todoist account (0.1.237, API v1 since 0.1.238)

`Config.todoistSyncEnabled` (default **off**) + `Config.todoistApiToken` (plain text,
same as every other setting — the app has no secret-storage layer), both in Settings →
**Todoist sync**. `TodoistSyncService` (`lib/services/todoist_sync_service.dart`,
singleton with `resetForTest`) mirrors `SyncService`'s shape (lifecycle-triggered
background run via the same `onLifecycleChanged` latch, a manual "Sync now", a
`SyncLogEntry` history in `todoist_sync_log.json` — App Logs gained a third "Todoist" tab,
and its `hasUnseenError` ORs into the same drawer red dot as the folder sync) but writes
**both directions** against Todoist's unified API v1
(`https://api.todoist.com/api/v1`, `lib/services/todoist_api_client.dart`, `http` package,
injectable client for tests). Pulling down on the home page's task list
(`RefreshIndicator` around the tab/schedule body, `HomePage._pullToRefreshSync`) also runs
`syncNow(trigger: 'pull_to_refresh')` and reloads tasks from storage afterwards — a no-op
(no snackbar) when Todoist sync is off or unconfigured, same as any other trigger
otherwise; the same `SyncLogEntry` history and drawer dot apply. The old REST v2 (`rest/v2`)
and Sync v9 (`sync/v9`) endpoints Todoist previously offered are sunset and now return a
deprecation notice
instead of data — `tasks`/`projects` GET responses on v1 are also cursor-paginated
(`{"results": [...], "next_cursor": ...}` rather than a bare array), which
`TodoistApiClient._fetchAllPages` walks to completion.

**Scope:** recurring tasks (parents and generated instances) are excluded —
Todoist's own recurrence engine has no clean mapping onto this app's
generated-instance model, so those stay local-only. Everything else syncs,
including wishlist items: a task's `label` free-text round-trips as real
Todoist labels (auto-created on push), and `_targetProjectKey` routes it to a
Todoist project — its own Kanban project if it has one, else a dedicated
**Wishlist** project for `isWish` tasks, else a dedicated **Future** project
for any other unprojected task with no due date (the Future tab bucket,
including the schedule view's `Task.futureBucketMarker` sentinel date), else
Todoist's Inbox. Both dedicated projects are created on first push and cached
in `todoist_sync_state.json`'s project map like any other. Pulling a task back
out of either project restores the matching local state (`isWish: true`/
unassigned, or just unassigned).

**No live diff, so fingerprints:** the API has no per-task "updated at" and no
completed-task endpoint, so a run can't diff against a timestamp. `TodoistSyncMapEntry`
(`lib/models/todoist_sync_map_entry.dart`) persists, per synced task
(`todoist_sync_state.json`: task entries + the local-project→Todoist-project id map), a
fingerprint of each side's fields as of the last successful sync; a run recomputes both
current fingerprints and compares. **Conflict rule: local wins** — a task changed on both
sides pushes the local edit and overwrites the Todoist-side one. A task's disappearance
from Todoist's active-task list (the only "done" signal the API gives) is always treated
as a completion, never a delete, so the ambiguity never loses data.

**Fields with no Todoist equivalent** — `Task.note`, the project/Kanban assignment, `uid`
for relinking — round-trip through a trailer appended to Todoist's `description` field
(`lib/services/todoist_metadata_codec.dart`): the task's own description text, then a
`⸻ BestToDo sync — generated, do not edit below this line ⸻` separator, human-readable
`Project:`/`Label:`/`Note:` lines (visible if you open the task in Todoist), then one
`sync-data: {...}` JSON line, which is what parsing actually reads back. A description
with no such trailer is a plain Todoist-native task. `Task.label` is pushed into the
trailer's `Label:` summary line too (for readability in the Todoist app), but is **not**
read back from it — Todoist's native `labels` array is the only source of truth on pull,
so a label added/removed via Todoist's own label UI (which never touches the description)
is picked up. Label fingerprints (both push- and pull-side) compare the token *set*
case-insensitively, order-independent, so re-ordering labels on either side isn't treated
as a change.

**Sync info in the UI, not the description** (0.1.263): `TodoistSyncService.entryForLocalUid`
looks up a task's `TodoistSyncMapEntry` by `Task.uid`. `TaskTile`'s expanded edit view shows
an info icon (`Icons.info_outline`) as the Note field's `suffixIcon` when a mapping exists —
tapping it opens a dialog with the sync source ("Todoist"), the entry's `syncedAt` (local
time) and its `todoistId`. `Task.description` never carries any of this — it round-trips only
the free text on both sides, unlike the note/label/project/Kanban trailer above.

**Algorithm** (`TodoistSyncService._runSync`, six passes over one fetch of Todoist's
active tasks + projects): (0) every Kanban project already mapped in `_projectMap` has its
name reconciled against Todoist's, fingerprinted the same local-wins way as tasks (baseline
in `todoist_sync_state.json`'s `projectNameMap`, seeded rather than pushed the first time a
mapping is seen so a pre-existing mapping doesn't look like a rename); (1) a locally-vanished
synced task (completed-and-rolled-over or deleted) closes or deletes its Todoist
counterpart; (2) a still-open-locally task now marked done closes it; (3) every other open
local task creates (new), or pushes/pulls an edit by fingerprint diff (conflict → local
wins); (4) a Todoist task with no local mapping is pulled in as a new local task (an
embedded `uid` matching an existing local task relinks instead of duplicating — recovers
from a lost/reset state file); (5) a mapped task that silently vanished from Todoist's
active list is marked done locally. Projects are matched by name (case-insensitive) or
created on first push; an unmapped Todoist project on a pulled task leaves the local task
unassigned rather than importing the project. The Wishlist/Future dedicated projects are
exempt from name-sync (pass 0) — they're app infrastructure, not user projects. Due dates:
`hasExplicitTime` tasks are pushed via `due_datetime` (UTC); date-only tasks via `due_date`.
On pull, v1's `due.date` is a single field holding either a bare date or a full datetime
string — a `T` in it tells them apart; date-only tasks default to 18:00 (matching
`applyDefaultDeadlineTimes`).

Tests live in `test/sync/`: `todoist_metadata_codec_test.dart` (pure trailer round-trip),
`todoist_api_client_test.dart` (`http.testing.MockClient`), `todoist_sync_service_test.dart`
(a small in-memory fake Todoist backend routed through `MockClient`, covering push/pull/
conflict/completion/deletion/project-mapping/lifecycle-latch), plus the Settings section
and combined drawer-dot coverage in `sync_ui_test.dart`.

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

**Tags:** `Alarm.tags` (free-form, `Task.label`'s comma/whitespace convention, empty string
omitted from JSON) is editable via a `LabelPickerField` in `AlarmEditPage`, alongside name/
description, and filterable in Settings → Filtering rules → Alarms (`ItemViews.applyTagRules`,
see §4.4). Any tag rendered anywhere (this field, the Alarms list's tag pills, `TaskTile`'s
label chips) that names a reserved state — Wish/Project/Archived/Deleted/Fooddiary/Alarm/
Countdown/Waiting_for_approval — renders in one fixed protected colour as a naming-collision
warning (`protectedTagColor`, `lib/utils/label_style.dart`).

`AlarmService` is a singleton `ValueNotifier` store; every mutation persists →
syncs the widget → **awaits** `rescheduleAll` (so short-lived isolates don't die mid-work).
`toggleInStorage(uid)` is the static isolate-safe path used by widget toggles: load from
disk, flip, save, sync widget, and **always** reschedule (the old `_loaded`-guarded version
was why widget toggles silently did nothing with the app closed).

**Dev seed (0.1.270):** `load()` seeds three sample alarms (a repeating weekday "Wake up",
a one-off "Midday stretch", a disabled repeating-weekend "Wind down") when storage is
empty and `Config.isDev`, mirroring the seeds already used for tasks/wishlist/projects/
countdown timers — so the Alarms tool (and its screenshot) is never an empty state in
dev/demo builds. Goes through the same persist-and-reschedule path as any other mutation.

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

Four widgets via `home_widget` (app group `group.homeScreenApp`):

- **Task widget** (`SimpleWidgetProvider.kt`): today's open tasks as text + colored
  progress bar (green/orange/red per §4.3); tap opens the app. Updated after every save and
  at midnight. Deleted and not-yet-approved tasks never appear (§4.2e). The whole payload is built by `TaskWidgetService.sync(tasks)`
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
  widget. The title and every non-row area still open the app.
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
- **Food Diary widget** (`FoodDiaryWidgetProvider.kt`, 0.1.278): a "+" that opens the
  in-app "create entry" dialog directly (`besttodofood://add` → `FoodDiaryPage(autoAddEntry:
  true)`, which auto-opens `_editEntry()` on first frame, same pattern as the alarm widget's
  `edit?id=`); tapping anywhere else opens the Food Diary list (`besttodofood://open`). Both
  are foreground `HomeWidgetLaunchIntent`s, unlike the other two widgets' background
  toggles — logging food always needs the UI, so there is no background isolate path here.
  Turns the whole background red once a meal checkpoint (8:00/13:00/20:00 — breakfast/lunch/
  dinner) has passed today with nothing logged in that window (dueDate falling in
  `[checkpoint, nextCheckpoint)`, last window running to midnight). `FoodDiaryWidgetService`
  (`lib/services/food_diary_widget_service.dart`) pushes only "was anything logged in each
  window today" booleans plus the date they describe, synced from `FoodDiaryPage._save`,
  `home_page._updateHomeWidget` and `WaitingApprovalPage._save`; whether a checkpoint has
  *passed* is deliberately decided in Kotlin against the live clock (`food_diary_widget_
  info.xml` sets `updatePeriodMillis` = 30 min), so the color is right even when the widget
  redraws on its own schedule with the app never opened — a purely Flutter-computed flag
  would go stale the moment the clock crosses a checkpoint without a save happening.
- **Food Diary button widget** (`FoodDiaryButtonWidgetProvider.kt`): a companion to the
  Food Diary widget above, fixed at 1x1 (`minWidth`/`minHeight` = 40dp, `targetCellWidth`/
  `targetCellHeight` = 1, `resizeMode="none"`) and drawing nothing but a "+" that fills the
  cell. Tapping it is the same foreground `besttodofood://add` launch intent as the full
  widget's "+" — there is no room for status text at this size, so it carries no other tap
  target, pushes no data, and (`updatePeriodMillis="0"`) never redraws itself once placed.

**Widget Previews** (`lib/ui/widget_previews_page.dart`, dev-only — drawer entry gated on
`Config.isDev`, next to App Logs/Startup Times): the four widgets above are drawn by
`RemoteViews` on the Android home screen, entirely outside the Flutter tree, so they cannot
be captured by the desktop screenshot integration test (`integration_test/
home_page_screenshot_test.dart`, run with `-d windows`). This page mocks each one in Flutter
from the same data/logic the real widgets use — `TaskWidgetService.todayTasks`, the sorted
`AlarmService.instance.list`, `FoodDiaryWidgetService.computeHasEntry` plus the same
checkpoint-passed-against-the-live-clock check `FoodDiaryWidgetProvider.kt` does — so the
colors/text stay in sync with the Kotlin providers without duplicating their logic. The Food
Diary mock falls back to two in-memory (never saved) demo entries when no Food Diary tasks
exist yet, the same way `FoodDiaryPage` seeds its own copy on first open. The button-widget
mock is static (just the "+"), matching what the Kotlin provider actually draws.

## 9. Android platform config

**Manifest permissions** (each exists for a reason): `POST_NOTIFICATIONS` (13+),
`SEND_SMS`, `RECEIVE_BOOT_COMPLETED` + `WAKE_LOCK`, `SCHEDULE_EXACT_ALARM` +
`USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `SET_ALARM`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (the main fix for OEM deep-sleep dropping alarms),
`FOREGROUND_SERVICE`, `VIBRATE`, `REQUEST_INSTALL_PACKAGES` (in-app APK updates from the
About page; the user still confirms every install) and `INTERNET` (0.1.139 — debug builds
get it implicitly, so "Check for updates" worked in development and failed on every release
APK until it was declared in the main manifest). An `androidx.core.content.FileProvider`
(authority `${applicationId}.fileprovider`, paths `@xml/file_provider_paths`: cache + files
dirs) shares the downloaded update APK with the system installer as a `content://` URI.

**Receivers/services:** android_alarm_manager_plus `AlarmService` +
**`AlarmBroadcastReceiver`** (its absence was the original "SMS never sent" root cause —
the plugin ships an empty manifest and its PendingIntent targets this class) +
`RebootBroadcastReceiver`; flutter_local_notifications `ScheduledNotificationReceiver` +
`ScheduledNotificationBootReceiver` (BOOT/PACKAGE_REPLACED/quickboot) +
`ActionBroadcastReceiver` (snooze/dismiss); home_widget background receiver/service; the
four widget providers.

**Gradle (`build.gradle.kts`):** namespace/appId `com.mfficiency.best_todo_2`; minSdk
`max(26, flutter.minSdkVersion)` (androidx.work via home_widget needs 23; the
`health` plugin behind Tools → Fitness Activity needs 26, and Health Connect is
Android 8+ only — raised from 23 in 0.2.9+300); Java/Kotlin 11
with core-library desugaring; glance pinned to 1.1.1 (home_widget 0.8.1 pulls `1.+` which
would demand compileSdk 37); NDK 28.2.13676358. **Signing:** `key.properties` if present,
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

**Share-sheet task capture** (0.1.145; quick-add screen, images/PDFs, Today/Inbox
choice, redelivery dedup added later): BestToDo appears in Android's share sheet for
`text/plain`, `image/*` and `application/pdf` ACTION_SEND, plus `ACTION_SEND_MULTIPLE`
for `image/*` (Chrome, YouTube, Maps, Gmail, Photos, ...) and opens a very small
quick-add screen prefilled from whatever was shared, rather than silently creating a
task. `ShareActivity` — a translucent, non-Flutter trampoline (`excludeFromRecents`,
`noHistory`) — receives the share, merges `EXTRA_SUBJECT` + `EXTRA_TEXT` (browsers put
the page title in the subject; the subject is dropped when the text already contains
it), copies any `EXTRA_STREAM` file(s) into `cacheDir/shared_incoming/` (a `content://`
URI's read grant dies with this activity, so the file must be copied before it
finishes — a display name is looked up via `OpenableColumns.DISPLAY_NAME` when the
source provides one, else a generated name from the mime type's extension), and
forwards everything to `MainActivity` with `FLAG_ACTIVITY_NEW_TASK`. It is
deliberately not `MainActivity` itself: the share sheet starts its target inside the
*sharing* app's task, and a second MainActivity there would mean a second Flutter
engine. MainActivity queues the content (`pendingSharedContent`, one entry per share:
`{text, files: [{path, mimeType}, ...]}`) and pokes Dart over the `besttodo/share`
channel; delivery is always **pull-with-clear** (`takeSharedContent`), so a cold start
(queue filled before the engine ran, drained by `ShareIntentService.init`) and a warm
poke can never double-deliver.

On the Dart side, `SharedPayload`/`SharedFile` (`lib/models/shared_payload.dart`) parse
the channel map. `ShareIntentService` (`lib/services/share_intent_service.dart`) drops
an empty payload and a **redelivered duplicate** — a content signature (text + subject
+ file names) seen again within `dedupWindow` (5 s default) is dropped, so a fast
double-tap on the share target or an Android-level redelivery never queues twice — then
hands every remaining payload to the callback `main.dart` attached via
`setOnSharedPayload` (queued payloads drain into it the moment it attaches). `main.dart`
presents one `QuickAddSharePage` at a time (queuing the rest) via `appNavigatorKey`.

`QuickAddSharePage` (`lib/ui/quick_add_share_page.dart`) prefills title/description via
`ShareIntentService.buildDraftTask` — first non-empty line of the text (or the subject,
when there's no text) as the title (capped at 120 chars, full text kept in the
description when it carries more); a file-only share (no text/subject) titles itself
from the file — its display name when the source app provided one, a generic "Shared
photo"/"Shared PDF" for a camera/gallery-generated name (`IMG_...`, a UUID, ...), "(+N
more)" appended for multiple files. Both fields stay editable. Two buttons save
directly: **Save to Today** (due today) or **Save to Inbox** (undated — lands in the
Future tab like any other undated task, via `Task.futureBucketMarker`); any shared
image/PDF is imported into permanent attachment storage under the new task's uid via
`ShareIntentService.importAttachments` (reuses `AttachmentStorageService`; a type
`AttachmentsField` has no viewer for is skipped; the share's cache copy is deleted once
imported). Saving hands the built `Task` to `ShareIntentService.saveTask`, which routes
it exactly like every other share-derived write: while a home page is alive it is the
registered consumer and adds the task through its own in-memory list + `_saveTasks()`
(no second `tasks.json` writer, and ranking follows the same top/bottom setting as every
other add via `_tabIndexForDueDate`); without one it is persisted directly through
`ItemRepository`. Saving *or* discarding calls `returnToPreviousApp`
(`besttodo/share` → Android `moveTaskToBack(true)`), backgrounding the app to re-front
whatever app the share came from — the standard "quick capture" pattern, since this
activity was launched fresh by that app's share sheet; a bare back-gesture dismissal
(no button tapped) does the same from `dispose()`. Tests: `test/share/`.

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
`CountdownTimerItem{uid,label,target,notifyOnZero,notifyRoundNumbers,milestones,createdAt,editedAt,tags,itemUid}`
in `countdown_timers.json`. Inline always-present composer (auto-names "Timer N", default
target now+7d, minimizes on scroll), in-place edit, drag reorder (manual mode) or sort by
name/added/edited/deadline asc/desc, swipe-to-delete with undo, 1 s tick. Collapsed rows
show whole-unit breakdowns ("in 2mo 1w 3d 4h"); expanded shows the same duration as
decimals in every unit (years=days/365.25, months=days/30.4375, …). Past timers count up
(orange); the instant date picker ranges 1900 → now+100y (0.1.103) so past events
(birthdays) can be created directly. Notify-on-zero fires a notification once (suppressed for already-past timers so
they never retro-fire; suppression is per-session).

**Item-linked timers (0.2.5):** `itemUid` (nullable, mirroring `Alarm.itemUid`, §5.1) makes a
countdown attach to a task instead of standing alone — Task Details offers a one-tap "Add
countdown to due date" (`TaskCountdownSection`, next to the reminder section), and a linked
timer's card shows a small link icon (tooltip names the task). Unlike reminders, the link is
resolved *lazily*: `CountdownSyncService.resolveAgainstTasks` runs once when the Countdown
page loads (free when nothing is linked), not on every task save — milestone notifications
are foreground-only (this page's own ticker), so there is no background path that needs the
target kept correct between app opens. A linked timer's `target` follows the task's due date;
a timer whose task disappears is **unlinked**, not deleted — a countdown still means
something on its own once detached. See `docs/architecture/presentation-layer-decision.md`.

`tags` (free-form, `Task.label`'s comma/whitespace convention, empty string omitted from
JSON) is editable via a `LabelPickerField` in the composer, and filterable in Settings →
Filtering rules → Countdown (`ItemViews.applyTagRules`, see §4.4). Filtering narrows the
displayed list only — reorder is disabled while a Countdown filter rule is active, same
reasoning as Home (§4.4).

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
Four sections: (a) GitHub-style 52-week × 7-day heatmap of **deleted-per-day** counts
(title says "Completed" — historical mislabel; buckets 0/1/2/3/4+ in blue shades, tap for
snackbar, auto-scrolls to newest); (b) 365 daily stacked bars from `DailyTaskStats` —
five segments: moved-from-start (red 0xFFD84343), completed-from-start (dark green
0x1B5E20), not-completed-from-start (dark grey), completed-from-created (light green),
not-completed-from-created (light grey); weekend tint/bold; unit height
`(180/total).clamp(3,16)`; (c) item-activity heatmap, last 31 days, 24h × 7 weekdays,
tabs Created/Completed/Moved/Deleted/Combined, primary-color lerp 0.18→0.92, with a peak
sentence ("Most items are completed on Monday between 09:00-10:00."); (d) **Fun stats
(0.1.234)** — an all-time trivia list at the very bottom, computed on the fly from the
deduped `tasks` + `deletedItems` union (by uid) plus `dailyStatsByDay`, no new storage:
items completed, items ever created, completion rate, busiest day (count + date), days
with something done (with the average per day), golden hour (modal `completedAt` hour,
`_hourRangeLabel`), favourite weekday, planning hour (modal `createdAt` hour — when
things get written down), early-bird (<08:00) and night-owl (≥22:00 or <05:00) finishes,
weekend share, fastest finish / longest wait (min and max `completedAt − createdAt`,
negatives skipped, task title as subtitle), oldest open item (earliest `createdAt` among
live undone tasks), times postponed (Σ `movedFromOpeningTaskIds ∩ openingTaskIds` over
all days), most-postponed weekday (the same sum bucketed by the day key's weekday) and
open right now. Together these answer the backlog wish `wish-extra-productivity-stats`
(most productive day/time, when planning happens, which day gets postponed most), which
the shipped-wish registry ticks off in 0.1.234. Rows whose
input is missing are dropped; a completely empty history shows "Complete a few items and
the trivia shows up here." instead of a column of zeroes. Durations are deliberately
rough (`s` → `min` → `h` → `days` → `weeks`).

Since 0.1.239, any row backed by concrete items or days is **tappable** (a trailing
chevron marks it — `_funStatTile`'s `details` param, empty list = plain row, e.g. "Open
right now" and "Items ever created" stay non-interactive): tapping opens a
`DraggableScrollableSheet` (`_showStatDetails`) listing each item's title (or day, for
day-bucketed stats like busiest day / days with something done / times postponed / most
postponed on) against the weekday + date + time it happened
(`_weekdayDateTime`, e.g. "Mon, 2026-08-10 · 14:32"), newest first. Fastest finish /
longest wait / oldest open item show a two-row created→completed breakdown instead of a
list, since there is only ever one task behind them. All detail lists are recomputed on
tap from the same in-memory `tasks`/`deletedItems`/`dailyStatsByDay` the tile numbers
already come from — no new storage or state.

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
render as full, editable task tiles whose `TaskTile` subtitle shows a small "wish" tag
and the task's own labels as tags first, then (for a wish with a description) a
`DescriptionDisclosure` — a chevron toggle that expands the description on tap instead
of dumping it inline; tags read first since they're the more useful glance info. Label
tags are not wish-only: from 0.1.252 `TaskTile._buildSubtitle` renders every label token
on any task (plain, project-assigned or wish), so a task tagged `urgent` shows that tag
in the home list; the subtitle is still null when a task has no project, no wish flag
and no labels. The schedule view groups undated
tasks under "Someday". The home search matches them like any task. So: the item
overview (home) shows all items with all properties/tags; the Wishlist shows only wish
items and never anything date-related.

The page loads via `StorageService.loadTaskList()`, keeps the full list in memory,
mutates only the wish subset and always saves the whole list; HomePage reloads
`_tasks` from disk when returning from the Wishlist tool. Wishes are sorted open
items first, then by priority label (`priority-high` > `priority-medium` >
`priority-low` > none, stable within a group). Tiles look like home task tiles
(checkbox toggles done + `completedAt`; done wishes strike through, sort last, and are
archived by the normal new-day rollover); the subtitle shows label tags first, then a
`DescriptionDisclosure` chevron for the description — same order and widget as the
Food Diary tile and `TaskTile`'s own wish subtitle. Tap opens the add/edit dialog — field order
since 0.1.148: title, labels/tags with the quick-priority buttons right below (most
wishes are a title plus a priority), description last (a `_WishEditDialog`
StatefulWidget owning its controllers); edits mutate the task in place so uid/project/
recurrence fields survive. Per-item and export-all JSON export (`{export_version: 1,
exported_at, wishlist_items: [...]}`) remain.

**Copy to clipboard (0.1.236, moved behind the swipe panel 0.1.259):** "Copy" puts the
plain-text item on the clipboard via `_WishlistPageState.clipboardText` — title, then
description, then labels, each on its own line, empty parts skipped — and confirms with a
`Copied "<title>"` snackbar. Since 0.1.259 it lives only in the options-swipe panel; the
per-tile `Icons.copy_outlined` button is gone.

**Release grouping (0.1.254):** the wishlist is sectioned like the home page's due-date
tabs, top to bottom: **Newly implemented**, **Next release**, **Soon**, **Backlog**
(`WishReleaseGroup` in `wishlist_page.dart`). An empty non-"Next release" section is
skipped entirely; "Next release" always renders (even at 0) since it carries the
"Propose for next" button. Membership is decided purely by tags, via
`wishReleaseGroupOf(task, currentVersion)`:
- **Newly implemented** is automatic and not user-settable: it's the shipped-wish
  registry (`wishlist_shipped.dart`) restricted to the app's *own running version* —
  `shippedWishesByUid[task.uid]?.version == currentVersion` — so a backlog item that
  auto-completed this release shows here, and drops back to its tag-based group the
  moment the next version ships (`currentVersion` comes from `Config.version`, loaded
  async in `initState`; blank until then, which no registry version ever matches).
- **Next release** / **Soon** follow the `release-next` / `release-soon` label tokens
  (`releaseNextToken`/`releaseSoonToken`/`releaseGroupTokens` in `label_utils.dart`,
  ordinary `Label.kindTag` tokens — no new label kind). Anything left over, including
  a task whose shipped-version match has expired, is **Backlog**.
- `setWishReleaseGroup(task, group)` rewrites just the release tag (keeping every other
  label), mirroring `setWishPriority`; moving to Backlog or Newly-implemented just
  strips `release-next`/`release-soon`.

Every tile except a "Newly implemented" one carries a "Move to release group" icon
button (`Icons.drive_file_move_outline`, a `PopupMenuButton`) offering Next release /
Soon / Backlog with a checkmark on the current group — same shape as the sort menu.
Since 0.1.259 it is the tile's *only* trailing control (see Swipes below): the swipe
default only steps an item back one group, so an explicit picker has no swipe equivalent. Since `Task.label` is the same field the Todoist sync maps onto Todoist's
native labels (§ Sync), tagging an item `release-next` in Todoist (by hand, or via
"Propose for next" below) moves it here on the next sync, with no extra plumbing.

**"Propose for next" (0.1.254):** a `TextButton.icon` (`Icons.auto_awesome`) on the
"Next release" section header. There is no in-app model call — it copies
`proposeForNextPrompt(...)` to the clipboard: an instruction for Claude to review the
Todoist backlog, tag roughly 3 items `release-next` and a few more `release-soon`
(the "~3 items per release" target is a guideline in the prompt text, not an enforced
cap), plus a snapshot of every open, non-"Newly implemented" Backlog/Soon item
(`- <title> [<tags>]`) so Claude has titles and existing tags without cross-referencing
anything first. The user pastes the prompt into a Claude session with Todoist access;
BestToDo picks up the resulting tag changes on its next Todoist sync. Confirms with a
snackbar reminding the user to sync after pasting.

**Clickable URLs (0.1.148) and phone numbers (0.1.276):** http/https URLs and phone
numbers in descriptions are auto-linkified by `LinkifiedText`
(`lib/utils/linkified_text.dart`): a StatefulWidget that renders `Text.rich` with
underlined, primary-colored link spans (trailing sentence punctuation excluded), owns
and disposes the spans' `TapGestureRecognizer`s, and opens links via `url_launcher`
(`LaunchMode.externalApplication`; `onOpenLink` test hook). A link tap wins the gesture
arena over the tile's own `onTap`, so it never opens the edit dialog. Phone matching is
a shape regex (digits/spaces/dashes/dots/parens, optional leading `+`, 7-15 digits;
a bare run with no separators needs 9+ digits so short item counts/IDs don't qualify)
filtered to reject YYYY-MM-DD/MM-DD-YYYY-shaped text so due dates typed into a note
aren't mistaken for numbers; a match dials via a `tel:` Uri built from its digits and
any leading `+`. URL and phone matches share one pass so an accidental digit run inside
a matched URL never double-links. Used by the wish tile subtitle and by `TaskDetailPage`
(description and note).

**Swipes (0.1.101, redesigned 0.1.258, sole entry point 0.1.259, Delete +
8s sweep 0.1.261):** same gesture mechanics as `TaskTile` (drag with
AnimatedSlide, 100 px/500 velocity thresholds, directions honor
`Config.swipeLeftDelete`, GestureDetector on Android/web), but the two
swipe directions no longer prioritize/delete:

- **Options swipe** (right by default) opens a Share/Copy/Export/Delete shortcut
  row — each button is a `TextButton.icon` (icon beside its label) — with a
  `wishlistSweepDelay` (8s; deliberately longer than the app-wide
  `Config.delayDuration` 5s undo delay used elsewhere, since misreading one of
  four buttons costs more) countdown bar. "Share" calls `SharePlus.instance.share`
  (`share_plus`) with `clipboardText(item)`, summoning the OS share sheet; "Copy" puts
  `clipboardText(item)` on the clipboard; "Export" (0.1.259) writes the single-item JSON
  export; "Delete" (0.1.261) calls the same `_deleteItems` bulk-delete path with a
  single-item list, moving it to the archive with the usual undo snackbar
  (`Config.delayDuration`-timed, not the sweep delay). Letting the countdown run out
  applies the default: `regressWishReleaseGroup(task, currentVersion)` moves the
  item back one release step (nextRelease→soon, soon→backlog; no-op for Backlog and for
  the automatic Newly-implemented group). Swiping back toward the other side cancels, as
  on the home list.
- **Selection swipe** (left by default) starts multi-select instead of deleting: the app
  bar swaps to a "N selected" bar (close icon cancels, `Icons.content_copy` "Copy
  selected as prompt", `Icons.delete` "Delete selected"); tapping other tiles toggles
  them in and out of the selection (tile tap opens the edit dialog only outside selection
  mode). "Copy selected as prompt" puts `buildSelectedWishesPrompt(items)` — "Build the
  following items from my BestToDo wishlist:" plus each item's title/description/labels
  — on the clipboard for pasting into a Claude session, then exits selection mode.
  "Delete selected" moves every selected item to the archive in one shot
  (`_WishlistPageState._deleteItems`, a single undo snackbar covering all of them); when
  the undo window expires each task gets `deletedAt` and moves to `deleted_tasks.json`.
  Restoring a wish from Archived Items keeps `dueDate` null (other restores get today) so
  it lands back in the wishlist, not Today. Since 0.1.261 a single item can also be
  deleted straight from the options-swipe panel, reusing this same path.

**Trailing icons removed (0.1.259):** the per-tile Share / Copy / Export icon buttons and
the emulator/desktop fallback pair ("Wishlist swipe options" + "Select") are gone —
every one of those actions is reachable by swiping, so the icons were pure duplication
crowding the tile. Export joined the options panel as a third button so nothing was lost,
and `device_info_plus` emulator detection dropped out of `wishlist_page.dart` with the
fallback row. Only "Move to release group" survives as a trailing control. Consequence:
on desktop (where the GestureDetector is Android/web-only) per-item share/copy/export are
no longer reachable — acceptable, as Windows is a dev/screenshot target. Quick-priority
setting had already moved entirely into the add/edit dialog's priority buttons —
`wishPriorityRank`/`setWishPriority`/`bumpWishPriority` still back sorting and that
dialog, just no longer the swipe panel.

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

**Stable backlog uids + auto-completion (0.1.232):** every `LegacyTodoItem` now carries
a hand-assigned permanent id (`wish-<slug>`, e.g. `wish-calendar-view`) used verbatim as
the imported `Task.uid`, so a backlog entry is addressable from source. That makes the
shipped-wish registry possible (`lib/services/wishlist_shipped.dart`): a
`const List<ShippedWish>` of `(uid, version, note)` naming the backlog entries whose
feature has actually been built. `applyShippedWishes(tasks)` — called by `loadTaskList()`
after the wishlist migration, saving only when it changed something — ticks each matching
**wish** task done, stamps `completedAt`, appends the `autocompleted` tag to its labels
and `"Auto-completed in v<x.y.z>. <note>"` to its `note`. So the workflow for a wishlist
feature is *build it, then add one line to `shippedWishes`*; the app does the bookkeeping
on every install at next launch.

Rules that keep it safe:
- **Tag-guarded, so it runs exactly once per item.** An item already carrying
  `autocompleted` is skipped entirely — re-opening or un-ticking a wish by hand sticks,
  and the note is never appended twice. An item the user had already ticked off keeps
  its own `completedAt`.
- **Two kinds of registry id.** A `wish-<slug>` id is shared by every install (the
  backlog import assigns it). A raw uuid addresses a wish the *user* added themselves —
  those are minted per install, so the entry only ever matches on the device that
  created that idea, which is the point: it is that user's own wish. Uuids survive the
  wishlist JSON export/import, so the match also survives a reinstall from a backup.
  `wishlist_autocomplete_test.dart` pins both shapes down, because a typo in either is
  silent (the item simply never gets ticked off).
- **Existing installs are re-identified first.** `backfillLegacyWishUids(tasks)` maps
  0.1.100–0.1.231 imports (random uuids) onto their stable id by normalized title,
  restricted to items carrying the `old` import token so a user's same-titled item keeps
  its uid, and never taking a uid another item in the list already holds. It runs in
  `loadTaskList()` **before** `_journalBaseline` is snapshotted — re-identifying an item
  is bookkeeping, and a uid swap seen by the journal diff would read as delete + create —
  and again in `loadWishlist()` so an item still parked in the legacy file dedupes
  against its migrated twin by uid.
- `autocompleted` is classified `Label.kindSystem` by `labelKindFor` (like `old`).
- Auto-completed wishes are archived by the normal new-day rollover, exactly like
  manually ticked ones; the sweep runs before the shipped pass, so a freshly
  auto-completed wish stays visible for the rest of the day.

The 0.1.232 registry seeds twelve entries whose features shipped long before the
mechanism existed (calendar view ×2, Chronize, the Wishlist tab itself, Productivity
Stats, Startup Times, simple/advanced/pro mode ×3, the manual GitHub APK action, the
automatic test workflow, the screenshot integration tests).

### 10.6a Food Diary (0.1.266, phase 1)
Tools → Food Diary (`lib/ui/food_diary_page.dart`): a pre-filtered view over the ONE
task list, structurally identical to the Wishlist tool — flagged tasks
(`Task.isEatingHabit`) rather than a separate store. Unlike the wishlist, a food diary
entry is invisible everywhere except this tool and, once deleted, Archived Items/the
Deleted bin: `ItemViews.isVisibleInMainViews` (`isApproved(t) && !t.isEatingHabit`)
gates `homeBucket`, `wishlist`, `active`, `projectTasks`, `boardColumn`, the schedule
view's task list, the home-screen widget's `todayTasks`, and Todoist's `syncable`
filter — an eating-habit task carries no Todoist mapping and is never pushed or pulled.
`ItemViews.foodDiary(tasks)` (gated by `isApproved` alone, since the eating-habit check
would exclude every result) is the tool's own selector.

Phase 1 fields, deliberately small: title, description, a "time" (stored in the same
`dueDate`/`hasExplicitTime` fields every task uses — picked via `pickDateInstantly` +
`pickTimeOfDay`, so a past or future time is fine and never triggers day-rollover sweep
since rollover only sweeps `isDone` tasks and an entry's `isDone` never flips), and
free-form tags (e.g. "sugar", "lactose") through the same `LabelPickerField` every task
uses (the add/edit dialog puts the tags field right under the title, description at the
bottom, matching the wishlist dialog's field order — see 10.6). The Title field has the
same mic button (`SpeechInputButton`, 0.1.288, see §"Adding" above) as the home add-task
row, for speaking a food entry instead of typing it. Entries render
newest-time-first, no checkbox, no priority/release grouping/
export/share/multi-select (wishlist's extras) — add via FAB, tap to edit, swipe
(`Dismissible`) to delete. Deleting moves the entry straight to Archived Items
(`ItemRepository.loadDeletedItems`/`saveDeletedItems`) with an undo snackbar, exactly
like a wishlist delete — never the plain task list, never the real bin directly.

Registered like every other tool: `food_diary` key in `Config.startToolOptions`/
`featureKeys` (and their label/description arrays), a `_ToolEntry` in home_page's
drawer list, a `_buildToolPage` case, and `_openTool` reloading `_tasks` from storage
on return (the tool loads/saves the list on its own, like Wishlist).

A home-screen widget mirrors the tool (§8, "Food Diary widget") — its "+" opens this
same add dialog and its background goes red once a meal checkpoint has passed with
nothing logged.

**Dev seed (0.1.270):** when no `isEatingHabit` task exists yet and `Config.isDev`, the
page seeds three entries spread across the day (breakfast/lunch/dinner, each with its own
tags) so the tool is testable in Chrome and never shows the empty state in a screenshot.
Checking the eating-habit subset rather than `tasks.isEmpty` is the fix (0.1.270): the
dev/demo starter tasks seeded by `home_page._loadTasks` mean the overall list is never
actually empty by the time this page loads, so the original single-entry seed (a plain
`tasks.isEmpty` check) never fired in practice.

### 10.6b Weekly Hours Planner (0.1.272, vertical grid + Google Calendar overlay 0.1.274,
week navigation + actual over/undertime + sync-on-edit 0.1.280)
Tools → Weekly Hours Planner (`lib/models/weekly_hours_plan.dart`,
`lib/services/weekly_hours_service.dart`, `lib/ui/weekly_hours_planner_page.dart`): a
standalone, date-less Monday-to-Friday work-hours template — not tied to the task list or
any specific calendar week — with an optional Google Calendar overlay and a per-week actual
over/undertime entry, both resolved against whichever calendar week chevrons navigate to.

**Model:** `WorkBlock{startMinutes,endMinutes}` (minutes since midnight); `DayPlan{morning,
afternoon}` with `lunchMinutes` simply the gap between them and `workedMinutes` the sum of
both block durations; `WeeklyHoursPlan{days}` holds 5 `DayPlan`s (Monday index 0 .. Friday
index 4). `targetMinutesPerDay` is a fixed constant, 8:36 (516 min), so
`targetWeeklyMinutes` is 43:00 (the standard flexitime week this tool is built around).
`DayPlan.defaultPlan()` starts at 09:00, splits the 8:36 evenly (4:18 each side) around the
fixed 30-minute default lunch, ending 18:06.

**Flexitime carryover:** dragging a block's start/end away from the 8:36 default on any
Monday-Thursday day changes that day's `workedMinutes` without touching the 43:00 weekly
target. `WeeklyHoursPlan.carryoverBeforeFriday` sums `workedMinutes - targetMinutesPerDay`
over Monday-Thursday; `theoreticalFridayEndMinutes` is Friday's own start time + its lunch
gap + however many minutes Friday needs to work (`targetWeeklyMinutes` minus the
Monday-Thursday total) to bring the week back to 43:00 — independent of how Friday's own
two blocks are split, since only the total matters. The Weekly Hours Planner page renders
this as a dashed red line + time label under Friday's column (`_TheoreticalEndLine`,
`_HorizontalDashedLinePainter`), which is always computed (not gated on any "modified" flag)
so it simply coincides with Friday's own scheduled end when the week is exactly on target.

**UI (`weekly_hours_planner_page.dart`) — vertical week grid:** the five weekdays render as
columns side by side with time running top-to-bottom, sized (via a `LayoutBuilder` computing
`pxPerMinute = trackHeight / rangeMinutes`) to fill the space left under the summary card, so
the whole configured hour range (`Config.weeklyHoursStartHour`/`weeklyHoursEndHour`, Settings
→ Weekly Hours Planner, default 06:00-22:00) is visible without scrolling — replacing the
original one-row-per-weekday horizontal-timeline layout. A shared left gutter
(`_HourGutterPainter`) draws the hour labels; each day column (`_DayColumn`,
`_ColumnBackgroundPainter` for its faint hour gridlines) draws the morning block (primary
color) and afternoon block (secondary color) as `Positioned` bars (start/end time labels once
tall enough) plus 4 draggable handles (`_Handle.morningStart/morningEnd/afternoonStart/
afternoonEnd`, each keyed `handle-<Weekday>-<handleName>` for tests, now horizontal bars
dragged **vertically** — `onVerticalDragUpdate`, `deltaDy / pxPerMinute` for the minute delta)
that resize a block by dragging either of its own two edges, clamped to a 30-minute minimum
block length and to not cross the other block, snapped to 5-minute increments. Dragging
updates the in-memory plan on every frame (so Friday's dashed line and every day's duration
label react live) but only persists to disk once via `onDragEnd` when the drag finishes, to
avoid hammering the file on every pointer move — a drag-end also re-syncs the Google Calendar
overlay (`_persistAndSync`), not only the file write. A summary card at the top shows the
viewed week's planned-plus-actual vs. 43:00 target total with a +/- surplus/deficit chip; a
reset button (app bar) restores `WeeklyHoursPlan.defaultPlan()`.

**Week navigation (0.1.280):** chevrons above the summary card move `_viewedWeekStart`
(Monday-normalized, `WeeklyActual.mondayOf`) a week at a time; a "Back to this week" text
button appears whenever it isn't the current week and jumps straight back. The block template
itself (`_plan`) is never per-week — dragging edits the one reusable template regardless of
which week is being viewed — but the Google Calendar overlay's date range and the actual
over/undertime field (below) both follow `_viewedWeekStart`, which is what makes "moving
between weeks" meaningful for a date-less template: it changes what real-world context you're
comparing the template against, not the template itself.

**Actual over/undertime (0.1.280):** a field in the summary card
(`ValueKey('over-undertime-field')`, signed decimal hours, debounced 500 ms) records
`WeeklyActual{weekStart, overUndertimeMinutes}` for whichever week is being viewed — positive
means more was actually worked than the template planned, negative less. Typing updates the
displayed total (`planned + actualMinutes`) immediately via `setState`, independent of the
save debounce; after the debounce fires, `WeeklyHoursService.saveActual` persists it and the
page re-syncs the Google Calendar overlay, same as a block edit. Switching weeks reloads the
field from `WeeklyHoursService.actualFor(_viewedWeekStart)` (a zeroed, unpersisted record for
a week with nothing saved) and rewrites the controller text via `_formatSignedHours` (empty
for zero, `+`-prefixed for a surplus, unprefixed negative for a deficit).

**Google Calendar overlay:** Settings → Weekly Hours Planner has a "Calendar URL" field
(`Config.googleCalendarUrl`, shared with nothing else) — paste a public `.ics` feed (a Google
Calendar "Secret address in iCal format" URL, or any RFC 5545 feed) and Settings' Import
button fetches + caches it immediately, showing the event count/timestamp or an error inline.
`GoogleCalendarService` (`lib/services/google_calendar_service.dart`,
`lib/models/gcal_event.dart`) parses the feed into `GCalRawEvent`s (RFC 5545 line-unfolding;
`DTSTART`/`DTEND`/`DURATION`/`SUMMARY`/`UID`/`RRULE`/`EXDATE`; a `VALUE=DATE` or bare
8-digit `DTSTART` is all-day) and caches them to `google_calendar_cache.json` in the app
documents dir, so the planner has something to show offline before the next refresh.
`GoogleCalendarService.eventsInRange` expands `RRULE` on demand for whatever date range is
asked for — `FREQ=DAILY/WEEKLY/MONTHLY/YEARLY`, `INTERVAL`, `COUNT`, `UNTIL`, and (`WEEKLY`
only) `BYDAY`; `EXDATE` drops one occurrence (a date-only `EXDATE` excludes that whole day).
Network access goes through `HttpClient` (same pattern as `UpdateService._fetch`, with a
`fetchOverride` test hook). The plan itself stays date-less, so the Weekly Hours Planner page
resolves the overlay against `_viewedWeekStart` (defaults to the current calendar week, moved
by the chevrons above): `_viewedWeekStart` plus the column index gives each weekday column's
real date, and `eventsInRange` is called per day (`_gcalEventsForDay`, timed events only —
all-day events are not shown). The overlay refreshes (`_loadGoogleCalendar`) on page open, on
every block drag-end, and on every debounced actual-over/undertime edit — not only on the
Settings page's manual Import button — so it never falls behind while the planner is open.
Each event renders as a `_gcalBlock`: a `tertiaryContainer`-tinted, 55%-opacity `Positioned`
bar added to the column's `Stack` *before* the work blocks, so it paints underneath them —
visible in any gap where no work block covers that time, and simply covered where one does
(the honest reading: that time slot is occupied by a real work block).

**Persistence:** `WeeklyHoursService` (singleton, `ValueNotifier<WeeklyHoursPlan>`)
persists to `weekly_hours_plan.json` in the app documents directory, seeded with
`WeeklyHoursPlan.defaultPlan()` on first run — same load-once/seed-if-missing/swallow-errors
shape as `ProjectService`. A second `ValueNotifier<List<WeeklyActual>>` on the same singleton
persists to `weekly_hours_actuals.json` (own load flag `loadActuals`/`_actualsLoaded`, so the
plan and the actuals list load independently); `saveActual` upserts by `weekStart` and drops
the row entirely once it goes back to zero, so an untouched week never leaves a stale entry.

Registered like every other tool: `weekly_hours_planner` key in
`Config.startToolOptions`/`featureKeys` (and their label/description arrays, right after
`test_results` so the "first N keys match `startToolOptions`" comment stays accurate), a
`_ToolEntry` in home_page's drawer list (`Icons.calendar_view_week`), and a
`_buildToolPage` case. No `_openTool` reload-on-return wiring is needed — unlike
Wishlist/Food Diary this tool never touches `_tasks`. The Settings section (index 13,
"Weekly Hours Planner": start/end hour dropdowns + the Calendar URL field/Import button) sits
at the end of `_sectionTitles` to avoid renumbering the other twelve.

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

**Startup choice** (`startup_choice_page.dart`, 0.1.242; today-first import 0.1.243):
shown once, right after the intro/mode picker finish on a brand-new install (§3 step
9's `showStartupChoice`; never shown again after "Replay Introduction" — only the
intro's own two flags are cleared there). Two cards: **Start fresh** finishes
onboarding immediately with an empty list; **Import from Todoist** opens a dialog for
a Todoist API token (`TodoistSyncService.testConnection`), and on success saves it
(`Config.todoistApiToken`, `Config.todoistSyncEnabled = true`) and calls
`TodoistSyncService.startFirstLaunchImport()` — a pull-only, first-launch-shaped
variant of the regular two-way `syncNow()` (§4.8): it pulls just today's (and overdue)
tasks synchronously so the dialog can close and onboarding finish right away, and
returns a `finishInBackground()` closure — fired and forgotten — that pulls everything
else while the user is already on the home page exploring. `syncing` (the same
`ValueNotifier` the Settings page spinner uses) stays true until that finishes,
driving a slim "Importing the rest of your tasks from Todoist…" banner atop the home
page's tab view. A failed *first* connection (bad token) blocks with an inline error
and keeps the dialog open; once connected, a background-phase failure only shows up
in App Logs → Todoist — onboarding has already finished by then.

## 11. Build, versioning, CI

- **Versioning:** `dart run tool/bump_version.dart <x.y.z[+build]> ["changelog entry"]`
  updates pubspec and prepends a dated CHANGELOG section (idempotent). Build number strictly
  increases per distributed build; passing a bare `x.y.z` carries the current build number
  forward and increments it, so the `+build` suffix (= Android `versionCode`) can never be
  dropped by accident.
- **tool/build.sh:** smoke-test gate (`test/core/build_smoke_test.dart`) → times
  `flutter build $@` → on success, `dart run tool/append_build_time.dart --duration <secs>
  --target $1` → rename artifacts with the version (`best_todo_<VERSION>.apk`,
  `web-<VERSION>`, …) → `dart run tool/stage_local_release.dart` for an APK build →
  optionally `dart run tool/publish_apk.dart` when `PUBLISH_APK=1`. `tool/build.ps1` mirrors
  this with `[System.Diagnostics.Stopwatch]` for the timing.
- **Local build time & duration (0.1.240; duration + build_history.json added later):**
  `tool/append_build_time.dart` writes/updates a `- Local build: yyyy-mm-dd HH:MM` bullet
  inside the *newest* CHANGELOG.md section (`withBuildTimeNote`: replaces the existing line
  for that version on a repeat build instead of piling one up per build; inserted right
  after that section's other entries). When called with `--duration <secs> --target
  <name>` (both `build.sh` and `build.ps1` always pass these on a successful build) it also
  writes/updates a `- Build duration (<target>): <1h 02m|3m 05s|45s>` bullet in the same
  section, keyed by target so an `apk` and a `windows` build each keep their own line
  instead of overwriting each other (`withBuildDurationNote`), and appends
  `{version, target, durationSeconds, finishedAt, os}` to `build_history.json` at the repo
  root (`historyRecord`/`appendHistoryRecord`; JSON array, capped at the newest
  `maxHistoryEntries` = 1000, oldest dropped first) — committed (not gitignored) alongside
  `github_releases/` + CHANGELOG.md by `tool/build_all.sh`/`build.ps1`'s `all` sync step, so
  build durations are tracked across builds, versions and machines over time. Runs after
  `flutter build`, which already bundled CHANGELOG.md as an asset for *this* build — so a
  build only ever shows the previous build's timestamp/duration on the Changelog page,
  never its own; that's expected, not a bug. No-ops on the CHANGELOG.md note (prints,
  doesn't touch the file) when it has no `## [version] - date` heading yet; the
  `--duration`/`--target` args are optional so a bare call still only records the timestamp.
- **Kept builds in the repo (0.1.146):** `tool/stage_local_release.dart` copies the built
  APK to `github_releases/best_todo_<x.y.z+build>.apk` and deletes everything but the
  newest two (`--keep`, `--dir`, `--apk`, `--dry-run`; ordering by the numeric name
  components, non-APK files such as the folder README never touched). Committing that
  folder is what publishes a build: the app reads it over plain HTTPS, so the newest APK
  is the update and the one next to it is the rollback.
- **In-app updates (0.1.133):** `tool/publish_apk.dart` uploads a locally built release APK
  to a GitHub release — tag `v<x.y.z>-<build>` (git tags can't carry `+`), name
  `BestToDo <x.y.z>+<build>`, asset `BestToDo-<x.y.z>+<build>.apk`, body = the newest
  CHANGELOG section; token from `GITHUB_TOKEN`/`GH_TOKEN` or `gh auth token`; re-running
  for the same version reuses the release and replaces the asset. The app side
  (`lib/services/update_service.dart`, singleton `UpdateService.instance` with an
  injectable `fetchOverride` for tests) maps a tag back to `x.y.z+build` and compares
  numeric components (unparseable versions — 'unknown' in tests — compare as all-zero).
  The About page's "Check for updates" section then walks check → "Version x available" →
  download to the temp dir with a progress bar → hand to the installer over the
  `besttodo/update` channel (§9); a `needs-permission` reply keeps an "Install update"
  button up for the retry after granting. Web/desktop or a release without an APK asset
  falls back to opening the release page in the browser.
- **Update source + rollback (0.1.146):** `checkReleases()` reads the repo folder first —
  `contents/github_releases?ref=dev` (unauthenticated; `dev` is where every build lands
  first, and the API's `download_url` is already percent-encoded, which matters because
  the file names carry `+`). Versions come from the file names
  (`best_todo_0.1.143+115.apk`, also the `BestToDo-…` asset spelling), newest first, so
  the result is an `UpdateCheck` of `latest` + `previous`; when the folder is missing or
  holds no APK it falls back to `releases/latest` (single build, no rollback). The About
  page shows "Download & install" for `latest` and "Go back to <version>" for
  `UpdateCheck.rollback` — `previous` unless that is the running version — in both the
  update-available and up-to-date states. The rollback warns that Android blocks
  downgrades for non-debuggable builds, so the install may need an uninstall first.
- **Automatic update check (0.1.264, replaced by the background poll below in
  0.2.1):** `Config.autoUpdateCheckEnabled` (Settings → Updates) originally
  checked once per launch and, on finding a newer build, opened a confirm
  dialog that pushed `AboutPage` with its check pre-triggered — the user still
  had to tap "Download & install" there themselves.
- **Background auto-update prompt (0.2.1):** `Config.autoUpdateCheckEnabled`
  (Settings → Updates, **on by default**) now gates `AutoUpdateChecker`
  (`lib/services/auto_update_checker.dart`, singleton `.instance` like
  `UpdateService`), which polls `UpdateService.checkForUpdate()` on a
  `Timer.periodic` once a minute while the app is open. Started in
  `_MyAppState.initState` alongside the other Android-only wiring
  (`!kIsWeb && Platform.isAndroid` — which is false under `flutter test`'s
  host runner, so the suite never starts a real timer) and stopped in
  `dispose`; the setting itself is only read at launch, so flipping it in
  Settings takes effect on the next start. A release with no APK asset is
  skipped (nothing to auto-install); once a version is found it is reported at
  most once — a later tick finding the same build is a no-op
  (`_pendingUpdateVersion` in `main.dart`), onboarding screens (intro/mode
  picker/startup chooser) suppress the prompt entirely, and a declined version
  is not offered again until a newer one ships (`AutoUpdateChecker.dismiss`).
  The report opens `showUpdateAvailableDialog`
  (`lib/ui/auto_update_dialog.dart`) — "New version available. Do you want to
  download and install it?", Yes/No — via `appNavigatorKey`, the same pattern
  `_showAlarmRing` uses to reach the navigator from outside `build`. Yes opens
  `UpdateDownloadDialog`, which downloads and installs immediately with no
  further confirmation (Android's own install prompt is the only gate left)
  and shows a progress bar; No just dismisses it. The About page's "Download &
  install" already chained straight from download into install before this
  and is unchanged (the `AboutPage(autoCheckForUpdate: ...)` pre-trigger the
  old flow used is gone, since nothing navigates there automatically anymore).
- **CI (GitHub Actions, Flutter 3.29.2, Java 17):**
  - `build-apk.yml` (push/PR main+dev, manual; `contents: write`, push trigger
    `paths-ignore`s `docs/ci/**`): runs `flutter test --machine` **non-blocking** (a
    failing test run does not stop the build) and embeds the parsed results into the APK
    as `assets/test_report.json` via `dart run tool/generate_test_report.dart --input …
    --commit … --branch … --version …`. On push events it also commits that JSON to
    `docs/ci/test_report.json` (`[skip-screenshot-changelog]`) so the app can pull the
    latest results online. Then builds the release APK, uploads artifact
    `besttodo-<version>` (30-day retention), adds a download link to the job summary. The
    app surfaces the bundled report as a red dot on the drawer icon and shows the
    online-primary/bundled-fallback report on the Tools ▸ Test Results page (see §4.3).
  - `flutter_test.yml` (main/staging/dev): `flutter test --coverage`, parses results into a
    PASS/FAIL markdown report artifact, fails on test failure.
  - `screenshot_changelog.yml` (push to main/staging/dev): Windows runner drives an
    integration test capturing screenshots (home, menu, settings, stats; since 0.1.90 also
    search-active, projects page, project board, project edit dialog; since 0.1.275 also the
    Weekly Hours Planner grid) into `docs/screenshots/home/<timestamp>-<sha>/` and prepends
    to `SCREENSHOT_CHANGELOG.md`. The workflow copies every `build/e2e_screenshots/*.png`
    and the changelog tool emits one section per PNG found, so new captures need no CI
    edits. Each entry's header line reads `branch: <branch> v<pubspec version>` (since
    0.1.275, read straight from `pubspec.yaml` at the captured commit) alongside the
    timestamp and source sha. Loop protection: paths-ignore on its own outputs, skips actor
    `github-actions[bot]`, and its commit message carries `[skip-screenshot-changelog]`.
  - `build-windows-exe.yml` (`workflow_dispatch` + successful `Build APK`
    `workflow_run`, 0.1.250): Windows runner (same `windows-2022` pin as
    `screenshot_changelog.yml`, for the same VS-2022-CMake-generator reason)
    runs `flutter build windows --release`, zips the
    `build/windows/x64/runner/Release` folder as
    `BestToDo-<version>-portable-win64.zip` and uploads it as a build artifact
    (30-day retention). "Portable" = unzip and run `BestToDo.exe`, no installer,
    no admin rights; works on Windows 10 and 11 (x64). APK-triggered runs check
    out `github.event.workflow_run.head_sha`, so the EXE is built from the same
    commit as the APK that triggered it.
  - `delete-merged-branch.yml` (0.1.264, `pull_request: closed`; `contents: write`):
    once a PR into `dev` merges, deletes its head branch via `actions/github-script`
    (`git.deleteRef`), skipping `dev`/`staging`/`main` themselves and tolerating a branch
    already gone (422/404, e.g. deleted by a squash-merge UI option).
- **Branch model:** feature branches (historically `codex/*`, later `claude/*`) → `dev` →
  `staging` → `main`. Releases are built from dev after a version bump. A feature branch's
  PR into `dev` has its branch auto-deleted on merge (`delete-merged-branch.yml` above).

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
`tearDown` — the flags are global statics. Quick-add & reminders (0.1.233,
`test/home/home_default_add_bucket_test.dart`, `home_drawer_home_entry_test.dart`,
`task_tile_notify_delay_test.dart`): the default bucket (open tab by default, a pinned
Future bucket labelling the add row and persisting the 2300 sentinel), the drawer's Home
entry (search dropped, start tab restored) and the Notify bell's delay sheet (the four
options, dismissal scheduling nothing, the notifications-off path). Widget tests that
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

### 10.4.1 Weekly wellbeing analysis (0.2.9)
Usage Data defaults to a Monday–Sunday analysis. The header arrows and horizontal
swipe move through weeks (never beyond the current week). Phone sessions are
loaded for both the selected and preceding week so total screen time, session
count and each ranked app state their percentage change. A seven-bar daily chart
and the existing 24-hour chart label both axes and the summary states the
seven-calendar-day average. Historical weeks use their complete Monday–Sunday
window; Android Usage Access remains opt-in and all calculations stay local.

### 10.5 Fitness Activity (Tools → Fitness Activity)
Fitness Activity is a read-only Health Connect dashboard. After explicit consent
it reads the selected and preceding Monday–Sunday windows for steps, distance,
active calories, workouts, heart rate, resting heart rate, asleep time and
weight. It shows totals, a true seven-day step average, sleep average over days
with records, weekly changes, strongest day and actionable conclusions. The
step chart labels steps and weekdays; arrows browse weeks and pull-to-refresh
re-reads Health Connect. Missing permission/data is stated rather than treated
as zero evidence. Tapping the week range can jump to any historical week and
requests Android's separate history permission for records older than 30 days.
The dashboard and Settings shortcut open Health Connect's source settings so
Samsung Health can share phone, restored cloud, and Galaxy Watch records.
Health measurements are displayed without medical diagnosis.
