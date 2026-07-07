# BestToDo — Complete Rebuild Specification & History

> **Purpose of this document.** If the original authors, tooling, and AI sessions behind this
> app disappeared tomorrow, this file is what a human or AI needs to rebuild BestToDo from
> zero and to understand *why* it is built the way it is. Part I is the functional/technical
> specification (what to build). Part II is the complete development history (every step the
> project took and why). `CHANGELOG.md` remains the authoritative per-version record;
> `.claude/notes/alarm-work-spec.md` holds the deep-dive on the alarm reliability sessions.
>
> Accurate as of version **0.1.87+57** (2026-07-07), commit history through `094d681`.

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
lib/models/              task, daily_task_stats, alarm, countdown_timer, sms_*
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
9. SharedPreferences → `showIntro` (always skipped in dev builds).
10. `runApp(MyApp(showIntro))`; post-frame → `StartupTimeService.record()`.

**Background isolate rule (critical, learned the hard way):** every `@pragma('vm:entry-point')`
callback (`alarmWidgetBackgroundCallback`, `alarmWatchdogCallback`, `smsReportAlarmCallback`,
background notification-action handler) must first call
`WidgetsFlutterBinding.ensureInitialized()` **and** `DartPluginRegistrant.ensureInitialized()`.
A fresh background isolate has no plugin channels; without this, path_provider/notifications/
telephony silently no-op.

## 4. Core task system

### 4.1 Task model (`lib/models/task.dart`)

Uuid-v4 `uid`; JSON keys equal field names. Fields: `title`, `description`, `note`, `label`
(single string), `createdAt`, `completedAt`, `movedAt`, `rescheduledAt`, `dueDate`,
`deletedAt`, `autoDeleted` (swept at rollover vs manual delete), `isDone`,
`hasExplicitTime` (protects a deliberately chosen time from the 18:00 normalization),
`listRanking` (int?, omitted from JSON when null, renumbered 1-based per tab on every save),
recurrence: `isRecurring`, `recurrenceEndDate`, `recurrenceIntervalDays` (≥1; UI offers
1/2/7), `recurrenceParentUid` + `recurrenceInstanceKey` (`yyyy-MM-dd`) on generated children.
`fromJson` is tolerant: missing keys get defaults.

`DailyTaskStats` (per day, keyed `yyyy-MM-dd`): sets of task uids —
`openingTaskIds`, `movedFromOpeningTaskIds`, `completedFromOpeningTaskIds`,
`createdDuringDayTaskIds`, `completedFromCreatedTaskIds`. Powers the stats page and CSV
rollups.

### 4.2 Persistence (all in app documents dir, JSON, `flush: true`, errors swallowed)

| File | Content | Cap |
|---|---|---|
| `settings.json` | Config map | — |
| `tasks.json` | active tasks (incl. recurrence children) | — |
| `deleted_tasks.json` | deleted list | **100**, trimmed on save+load |
| `daily_task_stats.json` | one record per day | — |
| `last_opened.txt` | ISO timestamp for day-rollover detection | 1 value |
| `countdown_timers.json` | timers (null = first run, [] = emptied) | — |
| `startup_times.json` | plain ms ints | 100 |
| `startup_history.json` | `{at, ms}` per launch | 5000 |
| `alarms.json` | alarm list | — |
| `sms_report_config.json` / `sms_report_log.json` | SMS config / log | log 500 |
| `alarm_log.txt` | human-readable alarm pipeline log | ~400 KB → trim to 250 KB |

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

**Drawer:** Settings, Deleted Items, Your Stats, About, Changelog, App Logs, Startup Times,
Tools ▸ (Alarms, Countdown, Chronize, Usage Data).

**Home widget updates** after every save and at a self-rescheduling midnight timer: writes
the "due today or overdue" list text (or "Well done! No more tasks for today!"), a progress
percent, and a color (green all done / orange exactly 4 left / red ≥5 left).

**First-run seeds:** 3 today-tasks + 1 future task; dev builds additionally seed 20 future
tasks, 20 deleted tasks, and 14 days of stats (marker strings prevent re-seeding).

### 4.4 Settings (all persisted in `settings.json` via `Config`)

Appearance: dark mode, icon tabs, 24-hour time (default on), date format (6 choices,
default `dd.MM.yy`). Tasks: add-to-top, swipe-left-delete, default delay 0–10 s slider,
start tab, start in schedule view, Chronize hour wheel. Widget: progress line. Notifications:
enable (default **off**), quiet hours (default 22:00–07:00, stored as minutes-since-midnight;
applied to task notifications only, never alarms), default notification delay (dev 3 s /
prod 300 s). SMS report: see §7. Export/Import buttons. `Config.applyMap` is defensive
(clamps ranges, whitelists date formats). Dev mode = `!dart.vm.product`: skips intro, shows
the app-bar date stepper, seeds demo data.

## 5. Alarm subsystem (the reliability showpiece)

Two **independent** systems share nothing but the log: the user-facing alarm clock
(flutter_local_notifications) and the SMS report (android_alarm_manager_plus isolate).
Every mechanism below exists because a real failure was observed on Samsung/One UI
hardware — see Part II §"The reliability arc" and `.claude/notes/alarm-work-spec.md`.

### 5.1 Model & ids

`Alarm`: uid, name, description, hour/minute, optional one-off `date`, `isRepeating` +
`repeatDays` (Mon=1..Sun=7), `vibrate`, `color`, snooze (enabled, duration min, default 9),
`enabled`. (`volume`, `melody`, `snoozeMaxCount` are stored but **not implemented** — known
deferred work.) `nextOccurrence()` is the scheduling brain; a one-off *without* a date
re-arms for tomorrow after firing (no delivered-callback exists to auto-disable it).

Deterministic id scheme so every path can find an alarm's notifications:
`base = (uid.hashCode & 0x1FFFFFF) * 8`; `base+0` one-off/snooze slot, `base+1..7` weekday
slots, `base + 0x10000000` watchdog id; fixed test-alarm ids at `0x20000000/1`. All within
signed 32-bit; spaces cannot collide.

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
watchdog cover.

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
setting to change), configured alarms vs what the OS reports pending. "Test alarm (1 min)"
exercises the full ladder+watchdog with fixed test ids.

## 6. Notifications (platform split)

`notification_service.dart` facade with conditional imports: `_io` (Android/iOS — the real
implementation), `_web` (immediate `dart:html` notifications only; scheduling is a no-op),
`_stub` (everything no-op). Two Android channels: `task_notifications` (Importance.high)
and `alarm_notifications_v2` (see §5.2). Quiet hours shift only task notifications.

## 7. SMS daily report ("snitch text")

Social-accountability feature: a scheduled daily SMS with today's completed/uncompleted
counts and remaining list. Config (`sms_report_config.json`): enabled (default off), time
(default 22:00), message template with tokens `{hello}{nickname}{completed}{uncompleted}
{date}{list}`, recipients (nickname+phone), `subscriptionId` (-1 = default SIM; dual-SIM
support), optional completion-rate threshold (only send on days below X%).

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

**Sending:** per recipient, render template, auto-multipart when >160 ASCII / >70 unicode
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
- **Alarm widget** (`AlarmsWidgetProvider.kt`): up to 4 alarms (time/name/sub + ON/OFF),
  "+N more", empty state. URI scheme `besttodoalarm://` — `open` (header/+ → app),
  `edit?id=` (row → editor), and `toggle?id=` as a **background broadcast** that does not
  open the app: HomeWidgetBackgroundReceiver → Dart `alarmWidgetBackgroundCallback` →
  binding+registrant init → `AlarmService.toggleInStorage` → full awaited reschedule. This
  chain is what makes a widget toggle actually schedule/cancel the OS alarm with the app
  closed.

## 9. Android platform config

**Manifest permissions** (each exists for a reason): `POST_NOTIFICATIONS` (13+),
`SEND_SMS`, `RECEIVE_BOOT_COMPLETED` + `WAKE_LOCK`, `SCHEDULE_EXACT_ALARM` +
`USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `SET_ALARM`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (the main fix for OEM deep-sleep dropping alarms),
`FOREGROUND_SERVICE`, `VIBRATE`.

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
would demand compileSdk 37); NDK 28.2.13676358. **Signing:** `key.properties` if present,
otherwise a **committed fixed debug keystore** (`android/app/debug.keystore`, password
`android`) — deliberate, so every build (CI or local) is signed identically and updates
install in place instead of failing with a signature mismatch. A Gradle task renames the
release APK to `app-release_<patch>.apk`.

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
`CountdownTimerItem{uid,label,target,notifyOnZero,createdAt,editedAt}` in
`countdown_timers.json`. Inline always-present composer (auto-names "Timer N", default
target now+7d, minimizes on scroll), in-place edit, drag reorder (manual mode) or sort by
name/added/edited/deadline asc/desc, swipe-to-delete with undo, 1 s tick. Collapsed rows
show whole-unit breakdowns ("in 2mo 1w 3d 4h"); expanded shows the same duration as
decimals in every unit (years=days/365.25, months=days/30.4375, …). Past timers count up
(orange). Notify-on-zero fires a notification once (suppressed for already-past timers so
they never retro-fire; suppression is per-session).

### 10.3 Your Stats
Three sections: (a) GitHub-style 52-week × 7-day heatmap of **deleted-per-day** counts
(title says "Completed" — historical mislabel; buckets 0/1/2/3/4+ in blue shades, tap for
snackbar, auto-scrolls to newest); (b) 365 daily stacked bars from `DailyTaskStats` —
five segments: moved-from-start (red 0xFFD84343), completed-from-start (dark green
0x1B5E20), not-completed-from-start (dark grey), completed-from-created (light green),
not-completed-from-created (light grey); weekend tint/bold; unit height
`(180/total).clamp(3,16)`; (c) item-activity heatmap, last 31 days, 24h × 7 weekdays,
tabs Created/Completed/Moved/Deleted/Combined, primary-color lerp 0.18→0.92, with a peak
sentence ("Most items are completed on Monday between 09:00-10:00.").

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

### 10.5 The rest
**App Logs**: in-memory `LogService` (ValueNotifier, self-trims >24 h, NOT persisted).
**Startup Times**: summary card (typical/last/fastest/slowest, hero median), fl_chart line
chart of the last 30 launches (y-axis fits data, shaded band >1 s, date labels, tap
tooltips), and an auto-generated "What this means" section: median verdict, older-vs-newer
trend, share of slow starts, outlier callout, first-launch-of-day cold-start comparison;
uses timestamped history with legacy fallback. **Changelog**: renders CHANGELOG.md
(markdown, bundled asset). **About**: description, version, update link. **Intro**: 3
value screens (Speed / Minimal Interactions / Open Source), shown once (`intro_shown`),
replayable, skipped in dev.

## 11. Build, versioning, CI

- **Versioning:** `dart run tool/bump_version.dart <x.y.z+build> ["changelog entry"]`
  updates pubspec and prepends a dated CHANGELOG section (idempotent). Build number strictly
  increases per distributed build.
- **tool/build.sh:** smoke-test gate (`test/build_smoke_test.dart`) → `flutter build $@` →
  rename artifacts with the version (`app-release-<VERSION>.apk`, `web-<VERSION>`, …).
- **CI (GitHub Actions, Flutter 3.29.2, Java 17):**
  - `build-apk.yml` (push/PR main+dev, manual): builds release APK, uploads artifact
    `besttodo-<version>` (30-day retention), adds download link to the job summary.
  - `flutter_test.yml` (main/staging/dev): `flutter test --coverage`, parses results into a
    PASS/FAIL markdown report artifact, fails on test failure.
  - `screenshot_changelog.yml` (push to main/staging/dev): Windows runner drives an
    integration test capturing 4 screenshots (home, menu, settings, stats) into
    `docs/screenshots/home/<timestamp>-<sha>/` and prepends to `SCREENSHOT_CHANGELOG.md`.
    Loop protection: paths-ignore on its own outputs, skips actor `github-actions[bot]`,
    and its commit message carries `[skip-screenshot-changelog]`.
- **Branch model:** feature branches (historically `codex/*`, later `claude/*`) → `dev` →
  `staging` → `main`. Releases are built from dev after a version bump.

## 12. Testing

Unit/widget tests cover: usage-data CSV building (escaping, event derivation, rollups,
manifest), chronize mark-fade invariants + interaction smoke tests, startup-times page
(history/legacy/empty states, chart maxY not clipping outliers), countdown model, export/
import round-trip + legacy import, storage rollover, config persistence, alarm model +
storage round-trip, 18:00 deadline normalization, done-task ordering, reorder ranking,
dev date-advance sweep, home filtering, tile description editing, intro smoke. Integration
tests: screenshot walk-through + task-creation screenshots (Windows desktop, needs
Developer Mode for plugin symlinks). Not covered: ScheduleView, stats/usage page widget
rendering, most alarm/SMS runtime paths (verified on hardware + via alarm_log instead).

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
14. `melody`/`volume`/`snoozeMaxCount` are stored-but-unused; keep serializing them.
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

### Phase 7 — Insight tools (July 2026, v0.1.86 → 0.1.87, current)
**0.1.86 — Usage Data tool**: export the app's entire recorded history as detailed CSVs
(unified event timeline, daily/hourly rollups, task history with derived metrics, alarm
pipeline log, SMS log, app opens, timers + manifest); app opens now recorded with
timestamps (`startup_history.json`, cap 5000). Note: 0.1.85 was claimed twice in parallel
branches (release-build bump on dev vs the usage-data branch); resolved at merge by moving
the usage-data feature to 0.1.86. **0.1.87 — Startup Times facelift**: the bare clipped
line chart became summary stats + a data-scaled themed chart + an auto-generated
"What this means" analysis (typical verdict, trend, slow-start share, outliers, cold-start
pattern), with widget tests.

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
