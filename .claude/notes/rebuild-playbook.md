# Rebuild playbook — BestToDo from zero

> The order in which to rebuild the app if the repo's code were lost, or the
> order in which to *understand* it if you're new. `SPEC.md` Part I holds the
> full detail per feature — this file supplies the build order, the dependency
> reasoning, and a verification gate per stage. Stages are ordered so every
> stage runs and is testable before the next begins.
>
> Before starting: `notes/environment.md` (setup) and `notes/principles.md`
> (the rules that must survive the rebuild). Keep `SPEC.md` §13 (invariants)
> open the whole time.

## Ground rules for a rebuild

- **Byte-compatible data first.** The JSON formats in SPEC §4.2 are the
  contract: a rebuilt app must read an old install's files. JSON keys equal
  field names; parsers default missing keys.
- **Test-first per stage.** The existing `test/` tree doubles as the executable
  half of the spec — port each stage's suite alongside the code
  (`test/README.md` maps suites to areas; conventions in `notes/testing.md`).
- **Preserve magic values.** Sentinel future date `DateTime(2300,1,1)`, alarm
  id scheme, notification channel ids (`alarm_notifications_v2`,
  `task_notifications`), fixed ids (`0x517D` SMS, `0x20000000/1` test alarms,
  `0x20000002` streak reminder), URI schemes (`besttodoalarm://`,
  `besttodotask://`), app group `group.homeScreenApp`, seed color `#005FDD`,
  applicationId `com.mfficiency.best_todo_2`.

## Stage 0 — Skeleton (SPEC §1–§2)

`flutter create` → rename to `best_todo_2`, set applicationId, Material 3
theme from seed `#005FDD` (light + dark), version scheme `x.y.z+build` in
pubspec. Add dependencies per the table in SPEC §2 (each has a stated reason —
don't add others). Pin Flutter 3.29.2 to match CI.
**Gate:** app boots to an empty page on Android + Chrome.

## Stage 1 — Core domain: Task, Config, Storage (SPEC §4.1–§4.2)

Order inside the stage: `Task` model (+ `DailyTaskStats`) → `task_utils`
(bucketing, sorting, 18:00 normalization) → `Config` (`settings.json`,
defensive `applyMap`) → `StorageService` (tasks, archive + real Deleted-bin
lists each cap 100, the bin also age-purged — SPEC §4.2g — day rollover,
`_ensureUniqueIds`) → `SafeFile` atomic writes + recovery →
export/import. This is the heart; everything else consumes it.
**Gate:** `flutter test test/core` — the whole silo, green.

## Stage 2 — Home UX (SPEC §4.3)

Tabs/buckets, `TaskTile` with swipe gestures + countdown auto-commit overlays,
add-task row, inline editing, done handling, deferred delete with undo,
recurrence, ordering + `applyDefaultDeadlineTimes` on save, drawer, schedule
view (+ active-day tracking), search, dice timer (controller singleton,
page-independent). Emulator/web fallback buttons for swipes.
**Gate:** `flutter test test/home` (and the home parts of core).

## Stage 3 — Notifications facade (SPEC §6)

Conditional-import facade: `_io` real, `_web` immediate-only, `_stub` no-op.
Two channels; quiet hours shift task notifications only. Needed now because
tools and alarms build on it.
**Gate:** compiles on all platforms; task notification fires on Android.

## Stage 4 — Android platform base (SPEC §9)

Manifest permissions (each has a documented reason), all receivers/services
(the missing `AlarmBroadcastReceiver` was a historic root cause), Gradle
config (minSdk 23, desugaring, glance pin, APK rename task), **committed debug
keystore**, **proguard-rules.pro** wired into release builds, `MainActivity`
lock-screen handling + `besttodo/alarm_ring` channel.
**Gate:** `flutter build apk --release` installs over a previous build and
alarms schedule in the *release* APK (this is exactly what R8 once broke).

## Stage 5 — Alarm clock subsystem (SPEC §5, notes/alarm-work-spec.md)

The reliability showpiece; port it faithfully, it encodes ~six real-device
failure modes: `Alarm` model + deterministic ids → `AlarmService`
(ValueNotifier singleton, `toggleInStorage` static path) → scheduling pipeline
(individual cancels, method ladder, OS read-back, watchdog +90 s, ack
registry) → `alarm_log.txt` + diagnostics ("alarm doctor", per-OEM hints) →
full-screen `AlarmRingPage` + melody playback (`AlarmSoundPlayer.kt`).
Background isolate rule (SPEC §3) applies to every `vm:entry-point`.
**Gate:** `flutter test test/alarms`; on hardware: test alarm rings with app
killed, screen locked; widget toggle with app closed schedules/cancels for
real; snooze survives an app open.

## Stage 6 — SMS daily report (SPEC §7)

Self-re-arming exact one-shot chain (never `periodic`), foreground-only
permission requests, re-arm-before-send, multipart sending with status
timeout, log with in-app viewer.
**Gate:** `flutter test test/sms`; on hardware: "Alarm fired" diag entry
appears with the app closed.

## Stage 7 — Home-screen widgets (SPEC §8)

`SimpleWidgetProvider.kt` (tasks; checkable rows behind
`Config.widgetCheckboxes`; `_mergeWidgetCompletions` on app resume) and
`AlarmsWidgetProvider.kt` (alarms; background toggle chain). Both go through
their Dart service payload builders. Kotlin files live under
`com/example/best_todo_2/` but declare package `com.mfficiency.best_todo_2` —
intentional, keep it.
**Gate:** widget checkbox toggle with app closed persists and survives the
next in-app save; `test/home/widget_checkboxes_test.dart`.

## Stage 8 — Tools (SPEC §10)

Independent of each other; order by value: Projects (+`ProjectService`),
Wishlist (a filtered view over the one task list, `isWish`), Countdown
(+milestones), Productivity Stats, Usage Data export, Chronize, Startup Times,
Changelog viewer (+heatmap), Test Results page (see stage 10).
**Gate:** `flutter test test/projects test/tools`.

## Stage 9 — Item-model layer & lifecycle features (SPEC §4.2b–§4.7, §4.5–4.6)

The 0.1.106–0.1.131 arc, in its original order (each step depends on the
previous): item-event journal → history seeding → structured labels →
schedule interval (schemaVersion 2) → item-linked reminders
(`ReminderSyncService`) → views-as-queries (`ItemViews`) → `ItemRepository`
facade → upgrade safety (SafeFile/PreUpdateBackup — if not done in stage 1) →
streak → simple mode & feature switches → dice-timer alarm delivery →
auto-backup → synced mode → in-app updates from GitHub releases
(`UpdateService` + About page + `tool/publish_apk.dart`).
**Gate:** `flutter test test/streaks test/sync test/update` + the core upgrade-safety
matrix (`test/core/upgrade_safety_test.dart` — it replays historical payloads
from the no-uid era forward).

## Stage 10 — Testing & automation infrastructure (notes/testing.md, notes/automation.md)

Last because it wraps everything: the test-report toolchain
(`generate_test_report.dart`, `sync_test_report.dart`, `pull_test_report.dart`,
`render_test_report_summary.dart`, `publish_test_report.sh` + the orphan
`ci-reports` branch), the in-app Test Results page + red dot, `tool/build.sh`
smoke gate, `bump_version.dart`, the three GitHub workflows with their loop
protections, screenshot integration tests, branch model
feature → dev → staging → main.
**Gate:** a push to dev runs tests, packages `assets/test_report.json`,
publishes to `ci-reports`, builds a versioned APK artifact, and updates the
screenshot changelog — with no workflow retrigger loops.

## What is deliberately NOT rebuilt from tests

Hardware-verified only (SPEC §12 end): Kotlin PendingIntent wiring, most
alarm/SMS runtime paths (use the alarm log + on-device verification pattern in
`environment.md`), stats/usage page rendering details.
