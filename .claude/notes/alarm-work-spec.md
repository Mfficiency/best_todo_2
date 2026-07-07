# Alarm & Reliability Work — Session Spec / History

> Agent-facing document. Purpose: track what the user asked, what was found,
> what was changed and WHY, so a future session can trace back decisions
> without re-deriving them. Update this file when the work continues.
>
> Repo: `Mfficiency/best_todo_2` (Flutter to-do app "BestToDo").
> Timeframe: 2026-06-30 → 2026-07-02. Versions 0.1.79+49 → 0.1.83+53.

---

## TL;DR — where we are and how we got here

The app has **two independent "alarm" systems**:

1. **Daily SMS report** ("snitch text") — `android_alarm_manager_plus` wakes a
   background isolate once a day and texts recipients a task summary.
   Files: `lib/services/sms_report_scheduler.dart`, `sms_report_service.dart`.
2. **Alarm clock tool + home-screen widget** — user-facing alarms scheduled as
   exact OS notifications via `flutter_local_notifications` (`zonedSchedule`,
   `exactAllowWhileIdle`). Files: `lib/models/alarm.dart`,
   `lib/services/alarm_*.dart`, `lib/ui/alarms_page.dart`, `alarm_edit_page.dart`,
   `android/.../AlarmsWidgetProvider.kt`, `lib/main.dart` (widget callback).

Both were broken for the app-not-running case, each in several independent
ways. All known issues are fixed as of **v0.1.83+53**, merged into `dev`
(commit `e15bb39`). Everything below is the trail.

---

## Question 1 (2026-06-30 / 07-01)

**User asked:** "look at the alarm branch and figure out why it is not ringing
the alarm. go deep with your research and don't stop until you found a
solution."

- Branch: `claude/alarm-not-ringing-ncfrr4` (fresh from main). "The alarm"
  turned out to be the **daily SMS report** — there was no alarm-clock feature
  in the app yet.
- **Root cause:** the app manifest declared the plugin's `AlarmService` and
  `RebootBroadcastReceiver` but was missing
  `dev.fluttercommunity.plus.androidalarmmanager.AlarmBroadcastReceiver`.
  Verified against plugin v4.0.4 sources: the plugin ships an EMPTY manifest
  (package only); `AlarmService.java` builds the PendingIntent with
  `new Intent(context, AlarmBroadcastReceiver.class)` — so the OS alarm fired
  but had no manifest-registered target and was never delivered to the app.
  The in-app "Send test now" button worked because it calls
  `runDailyReport()` directly, bypassing the alarm — that asymmetry was the
  key diagnostic clue.
- **Fix:** declared the receiver. Version 0.1.80+50, commit `2e2dbed`.

## Question 2 (2026-07-01)

**User sent:** screenshot of the stock Samsung/One UI **Clock** app's
"All permissions" page — "make sure it has these permissions so it can work
because it still doesn't do anything when it should alarm."

- Insight: the stock Clock is a system app and is auto-exempt from battery
  optimization. A normal app must REQUEST that exemption; on One UI,
  "Sleeping apps" deep-sleep otherwise silently drops alarms.
- **Fixes** (0.1.81+51, commit `1f40b55`):
  - Manifest: added `SET_ALARM`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`,
    `FOREGROUND_SERVICE`, `VIBRATE`.
  - `SmsReportScheduler.ensureBackgroundPermissions()` — runtime requests for
    exact-alarm, battery-optimization exemption, notifications; called from
    the "Enable daily SMS report" toggle in `settings_page.dart`.

## Question 3 (2026-07-02)

**User asked:** "merge with the dev branch, and double check everything works
like SMS and alarms even when the app is not running!"

- Merged `origin/dev` into the branch (dev brought no new content), then did a
  source-level audit of every plugin in the background chain. Found **two more
  real bugs**:
  1. `AndroidAlarmManager.periodic(exact: true)` maps to
     `AlarmManager.setRepeating` — **inexact since API 19**, and the plugin
     ignores `allowWhileIdle` for repeating alarms (verified in
     `AlarmService.java` v4.0.4). In Doze the daily alarm was deferred
     indefinitely. **Fix:** self-rechaining one-shot —
     `oneShotAt(exact, wakeup, allowWhileIdle)` →
     `setExactAndAllowWhileIdle`, which fires even in Doze. The callback
     re-arms tomorrow FIRST (crash-safe), `applyFromConfig()` at app launch
     restores a lost chain (force-stop clears alarms), `rescheduleOnReboot`
     covers reboots. `_nextFireTime` requires ≥1 min headroom so an
     early-delivered alarm can't double-fire the same day.
  2. `Permission.sms.request()` can never show a dialog in the background
     isolate (no Activity) — SMS permission MUST be granted in the foreground.
     Added to `ensureBackgroundPermissions()`.
  - Also: callback writes an "Alarm fired — running report in background"
    diag entry to the SMS report log so background fires are verifiable
    on-device (distinct from foreground "Send test now" entries).
- Verified OK: `Telephony.instance` in background isolates (identical to
  `backgroundInstance` in source; plugin registered via
  `DartPluginRegistrant`), path_provider, `@pragma('vm:entry-point')`,
  20 s send-status timeout.
- Tooling: **installed Flutter 3.29.2 (same as CI) into the session
  scratchpad** — `flutter analyze` (0 issues in touched files),
  `flutter test` (40/40 pass). No Android SDK in this environment; native
  packaging is covered by the CI `build-apk` workflow.
- Version 0.1.82+52, commit `d389362`; merged to dev as `5e5c506`.

## Question 4 (2026-07-02)

**User asked:** "Dude, where is my clock? and the widget and everything, fix
it. start from claude/alarms-tool-widget-... merge with dev, bump to 83 and
make sure all the things work all the time even in flight mode or whatever."

- The alarm-clock tool + widget existed on branch
  `claude/alarms-tool-widget-58gk4k` but **was never merged** — that's why it
  was "missing."
- Merged `dev` into it. Conflicts resolved: manifest permission block (union
  of both sides — kept `USE_FULL_SCREEN_INTENT` from the widget branch AND
  the battery/SET_ALARM/FOREGROUND_SERVICE set from dev), pubspec version
  (→ 0.1.83+53 as requested), CHANGELOG (widget branch had reused 0.1.80/81
  numbers; folded its entries under 0.1.83).
- **App-closed audit of the alarms tool found 4 bugs** (fixed in `a658757`):
  1. **Widget toggle no-op when app closed** (critical):
     `AlarmService.toggleInStorage` only called `rescheduleAll` when
     `instance._loaded` — never true in the widget's background isolate. An
     alarm enabled from the widget never rang; a disabled one still fired.
     Now always reschedules (and `_afterChange` awaits the reschedule so
     short-lived isolates don't die mid-work).
  2. **Background isolates missing plugin registration:**
     `alarmWidgetBackgroundCallback` (main.dart) and
     `_onBackgroundNotificationResponse` (notification_service_impl_io.dart)
     lacked `WidgetsFlutterBinding.ensureInitialized()` +
     `DartPluginRegistrant.ensureInitialized()` — storage/timezone/
     notification channels were dead there; Snooze with the app closed did
     nothing. Both entry points now initialize.
  3. **`cancelAll()` killed pending snoozes** on every app open / alarm edit.
     `scheduleAlarms` now cancels individually, preserving the snooze slot
     (`_baseId(uid) + 0`) for enabled alarms that don't schedule there
     themselves (repeating alarms use +1..+7; one-off whose time passed).
  4. **DST drift:** `_nextInstanceOfWeekday` stepped with
     `add(Duration(days: 1))`, which shifts the local hour across a DST
     change. Now rebuilds wall-clock `TZDateTime` per day-step.
  - Plus: `ensureAlarmPermissions()` also requests battery-optimization
    exemption (same Samsung lesson as Q2).
- Flight mode: alarm-clock alarms are OS-local notifications — no network
  involved, so flight mode is inherently fine. Reboot →
  `ScheduledNotificationBootReceiver` (also `MY_PACKAGE_REPLACED` for app
  updates).
- Verified: analyze clean (fixed the one warning in new code:
  `alarm_widget_service.dart` catchError), **48/48 tests pass** (incl. 8 new
  alarm tests from the branch). Merged to dev as `e15bb39`.

## Question 5 (2026-07-02)

**User asked:** create this document — a spec/history of questions and steps
"so you can track back later from where we came and why we are here."
→ This file.

---

## Question 6 (2026-07-07) — full-screen ring UI + release-build scheduling fix

**User asked:** "From dev, fix the alarm so that when it rings it's not just a
notification, it's a full screen thing like a Google or Samsung clock alarm."
Plus: merge back to dev and staging, bump version, update docs.

- Branch `claude/fullscreen-alarm-ui-56myqr` (rebased onto dev), version
  **0.1.88+58**.
- **Found on the way (critical):** the user's pasted alarm log (v0.1.85+55,
  Samsung SM-S911B / Android 16) showed EVERY schedule call rejected with
  `PlatformException(... Missing type parameter.)` — the classic R8-full-mode ×
  Gson bug: release builds had NO proguard keep rules, so R8 stripped the
  generic signatures flutter_local_notifications' Gson persistence needs.
  Release alarms only ever rang via the ~90 s-late watchdog. **Fix:** new
  `android/app/proguard-rules.pro` (keep `Signature`, `TypeToken` subclasses,
  gson + `com.dexterous.**`) wired into the release buildType in
  `build.gradle.kts`. Debug builds never showed the bug (no minification).
- **Full-screen ring UI** (`lib/ui/alarm_ring_page.dart`): dark
  gradient page themed with the alarm color, pulsing icon, live HH:mm clock,
  big Snooze pill (hidden when snooze disabled) + round Stop button; back
  blocked (PopScope). Sound still comes from the insistent notification;
  Stop/Snooze cancel it.
- **Plumbing:** notification payload now also carries `color`.
  `MainActivity.kt` (the real one under `com/example/best_todo_2/`) sets
  `setShowWhenLocked/setTurnScreenOn` when the launch intent is
  `SELECT_NOTIFICATION` with an alarm payload (uid marker), and hosts
  MethodChannel `besttodo/alarm_ring` (`canUseFullScreenIntent`,
  `clearLockScreenFlags` — called from the ring page's dispose so the todo
  list never stays over the keyguard). Cold start →
  `getAlarmLaunchPayload()` (launch details); warm →
  `onDidReceiveNotificationResponse` → `onAlarmRing` handler registered in
  `_MyAppState`, push guarded against double-open.
- **Ring-page actions:** Stop = `recordAck('ring_dismiss')` → cancel the
  alarm's ACTIVE notification ids (NB `plugin.cancel` also kills same-id
  pending schedules, e.g. auto-rearmed weekly repeats) → full reschedule from
  storage. Snooze = ack → cancel actives → reschedule → THEN schedule the
  snooze into base+0 (ordering so the reschedule can't clear it) → snooze
  watchdog. Shared helper `_scheduleSnoozeFromData` now backs both the
  notification action and the ring page.
- **Watchdog backup ring** now passes `uid` into `showAlarmNotification`,
  which posts under the alarm's own base id WITH payload → backup rings get
  the same full-screen treatment and are stoppable from the page.
- **Android 14+ FSI special access:** checked in `ensureAlarmPermissions`
  (opens the system toggle via `requestFullScreenIntentPermission()` when
  revoked) and in diagnostics (`_checkFullScreenIntent` — OK/FAIL/hint).
- **Tests:** `test/alarm_ring_page_test.dart` (render, snooze hidden,
  fallback name, Stop/Dismiss handlers + pop). NOTE: the ring page has an
  endless pulse animation — use fixed `pump()`s, `pumpAndSettle` never
  settles. `flutter analyze` clean for touched files; full suite green except
  `startup_times_page_test.dart` hangs (pre-existing on clean dev in this
  sandbox, unrelated).
- Docs: CHANGELOG 0.1.88, SPEC.md §5.2 "Full-screen ring UI" + §9
  (proguard + MainActivity), this file.

---

## Commit map (newest first)

| Commit | Branch | What |
|---|---|---|
| `e15bb39` | dev | Merge alarms tool + widget (0.1.83) into dev |
| `a658757` | alarms-tool-widget | 4 app-closed alarm fixes + battery exemption + analyzer fix |
| `51abdbe` | alarms-tool-widget | Merge dev in; conflicts resolved; bump 0.1.83+53 |
| `5e5c506` | dev | Merge SMS alarm fix branch into dev |
| `d389362` | alarm-not-ringing | periodic→one-shot chain, SMS perm in foreground, diag log (0.1.82+52) |
| `94719ac` | alarm-not-ringing | Merge dev in (no content) |
| `1f40b55` | alarm-not-ringing | Manifest perms + ensureBackgroundPermissions (0.1.81+51) |
| `2e2dbed` | alarm-not-ringing | Missing AlarmBroadcastReceiver fix (0.1.80+50) |

Branches pushed: `claude/alarm-not-ringing-ncfrr4`,
`claude/alarms-tool-widget-58gk4k`, `dev`. No PRs created (user never asked).

## Architecture cheat-sheet

- **SMS report chain:** `main()` → `SmsReportScheduler.applyFromConfig()` →
  `AndroidAlarmManager.oneShotAt` → OS fires →
  `AlarmBroadcastReceiver` → `AlarmService` (bg isolate) →
  `smsReportAlarmCallback` (re-arms first, then `runDailyReport()`).
  Diag/send log: SMS report log page (Settings → SMS report).
- **Alarm clock chain:** `AlarmService` (ValueNotifier, singleton) →
  `_afterChange` → storage save + widget sync +
  `NotificationService.scheduleAlarms` → `zonedSchedule` per alarm
  (`_baseId(uid) = (uid.hashCode & 0x1FFFFFF) * 8`; +0 one-off/snooze,
  +1..+7 weekday repeats, `matchDateTimeComponents: dayOfWeekAndTime`).
- **Widget:** `home_widget` package. Data pushed via
  `AlarmWidgetService.sync` (4 rows). Clicks: URI scheme `besttodoalarm://`
  hosts `toggle|edit|open`; background toggles land in
  `alarmWidgetBackgroundCallback` (main.dart), foreground in
  `_handleWidgetClick`. Kotlin: `AlarmsWidgetProvider.kt` — NOTE: file sits
  in folder `com/example/best_todo_2/` but declares package
  `com.mfficiency.best_todo_2` (matches applicationId; same for
  SimpleWidgetProvider — don't "fix" the folder mismatch blindly).

## Known limitations / potential follow-ups (deliberately NOT done)

- **Force-stop** (system settings) drops all OS alarms until next app launch —
  Android platform rule, affects both systems; unfixable app-side.
- One-off alarm **without a date** re-arms for tomorrow every time the app
  opens after it fired (`nextOccurrence` rolls to tomorrow). Stock alarm apps
  auto-disable after firing; there is no "notification delivered" callback in
  flutter_local_notifications to hook this. Product decision pending.
- Alarm `melody`/`volume` model fields are stored but **not used** for the
  notification sound (default channel sound plays; channel
  `alarm_notifications_v2` with `AudioAttributesUsage.alarm`).
- `snoozeMaxCount` is stored but not enforced.
- SMS report timezone: `_nextFireTime` uses device-local `DateTime.now()` —
  fine; alarm clock uses `flutter_timezone`, falls back to UTC if lookup
  fails (first-fire could then be off; recurring repeats are
  component-matched).
- Web/stub notification impls are no-ops for scheduling — alarms are
  Android/iOS only.

## Environment notes for future sessions

- Remote sandbox; Flutter is NOT preinstalled. This session downloaded
  Flutter 3.29.2 (CI's version) to the session scratchpad — redo when needed:
  download `flutter_linux_3.29.2-stable.tar.xz` from
  `storage.googleapis.com/flutter_infra_release`, `git config --global --add
  safe.directory <extracted path>`, add `flutter/bin` to PATH.
- No Android SDK → no local APK builds; CI workflow `build-apk.yml` builds on
  dev pushes (fixed keystore, versioned APK name).
- `pubspec.lock` is gitignored (`*.lock`).
- User's device: Samsung / One UI (from screenshot) — always consider
  "Sleeping apps" / battery optimization when alarms "don't work".
- Verification pattern the user responds to: set alarm/report a few minutes
  ahead, lock phone, check SMS report log ("Alarm fired" diag entry) or the
  ringing alarm.
