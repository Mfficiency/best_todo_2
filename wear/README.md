# BestToDo Watch (Wear OS companion)

A small Wear OS app for BestToDo, made for the Samsung Galaxy Watch6 Classic
(Wear OS 4+ / One UI Watch, round 480x480, rotating bezel). Kotlin + Jetpack
Compose for Wear OS, in its own Gradle build: `android/` and `flutter build apk`
never see this folder.

It is a companion (`com.google.android.wearable.standalone` = false): every
list comes from BestToDo on the paired phone, through the Wearable Data Layer.

## What it does

- **Today**: today's tasks (and overdue ones), exactly the list of the phone's
  "Due Tasks" home-screen widget (`TaskWidgetService.todayTasks`): open first,
  then the done ones. Same gates as the widget and the Today tab: no deleted
  or waiting-for-approval tasks, no Food Diary/Research items, **no `mlr`
  (Worklist-only) tasks**, and the Home filtering rules apply.
- **Complete a task**: tap a task, then tap it again within 4 s ("Tap again:
  done"; there is no undo on the watch, so one brush of the screen doesn't
  finish a task). It shows as done right away ("Done · sent", or "Done ·
  waiting for phone" while the phone can't be reached; it is sent again on
  the next refresh).
- **Tomorrow**: the Tomorrow tab's tasks (same gates), also completable.
- **Alarms** (chip with the next ring time → its own screen): the alarm
  widget's alarms, read-only, soonest first, switched-off ones last.
- **Status line** at the top: "Phone connected", "Phone not reachable · saved
  14:32", "Update BestToDo on your phone" (a phone is connected but its
  BestToDo doesn't have the watch sync yet) or "Looking for your phone…".
  The last lists are kept on the watch, so it shows them offline. A list from
  an earlier day says so in its header ("Today (saved Mon 21:10)").
- **Refresh** chip at the end of each list.

Deliberately not in v1: creating or editing tasks, un-completing, toggling or
editing alarms, tiles/complications, notifications. Up to 40 tasks per list
are shown (`+N more on the phone` for the rest).

Bezel: the lists scroll with the rotating bezel (Wear Compose's
ScalingLazyColumn does this by itself). Swipe right to go back from Alarms.

## Sync design

| Direction | What | Where |
|---|---|---|
| phone → watch | DataItem `/todo/today`: `{"v":1,"day":"yyyy-MM-dd","today":[{"id","title","done"}],"todayMore","tomorrow":[…],"tomorrowMore"}` | `WearSyncService.tasksPayload` |
| phone → watch | DataItem `/todo/alarms`: `{"v":1,"alarms":[{"id","time","name","sub","on","next"}]}` (`next` = epoch ms or null) | `WearSyncService.alarmsPayload` |
| watch → phone | Message `/todo/command/complete`, the task's uid (UTF-8) | `PhoneLink.sendComplete` |

Each DataItem carries `json` and `at` (publish time, ms) and is sent urgent.
Capabilities: the phone advertises `todo_phone`
(`android/app/src/main/res/values/wear.xml`), the watch `todo_wear`
(`wear/app/src/main/res/values/wear.xml`). The watch sends commands to the
reachable `todo_phone` node.

**Phone side** (kept tiny):

- Publishing rides on the two widget syncs: `TaskWidgetService.sync` and
  `AlarmWidgetService.sync` end with `WearSyncService.publishTasks/
  publishAlarms`, which send the JSON over the `besttodo/wear` method channel
  (`MainActivity.kt`) to `WearSync.publish` (`putDataItem`). So the watch is
  updated whenever the widget is: after every save, on start/resume, at
  midnight. An unchanged list is not re-sent. Android only; errors swallowed
  (no Play services = nothing happens).
- Commands never touch `tasks.json` from Kotlin. `WearCommandService.kt` (a
  `WearableListenerService`, `MESSAGE_RECEIVED`, path prefix `/todo/`)
  appends `{"action":"complete","id","at"}` to a queue in its own
  SharedPreferences file (`best_todo_wear`), then:
  - app running (the `besttodo/wear` channel is attached): pokes Dart
    (`wearCommandsPending`). The home page drains the queue (`takeCommands`)
    and completes each still-open task through its own path (in-memory list,
    daily stats, streak, `_saveTasks` → history/undo, Todoist, widget), whose
    widget sync republishes to the watch;
  - app not running: fires the home-screen widget's own background path,
    `besttodotask://complete?id=` → `alarmWidgetBackgroundCallback` →
    `TaskWidgetService.completeInStorage` (like the widget checkbox, but
    complete-only, so a stale watch can't un-complete a task). The queued
    copy is applied when the app next starts and finds the task done
    already (no-op, idempotent).
  The home page also drains the queue on start and on every resume.
  Why a queue + the widget path instead of writing storage directly: the
  app keeps the task list in memory and saves it whole, so a second writer
  while it runs would be overwritten (or overwrite it). The widget's
  background isolate is already the app's accepted "write while closed" path
  (with the merge-on-resume the home page does for it); everything else goes
  through the running app.

**Watch side**: reads the items on start (`getDataItems`), listens with
`DataClient.addListener` only while the activity is started, caches the last
JSON of each path in SharedPreferences (`wear_cache`), and keeps the "done"
taps the phone hasn't confirmed (`Pending`): a tap is settled once a
`/todo/today` item newer than the tap arrives (then the phone's list is the
truth); undelivered taps are resent; taps older than 24 h are dropped.
Pure logic (payload parsing, pending taps, labels) is in `core/`, without
Android imports, unit-tested on the JVM.

Battery: no services, alarms, wakelocks or background work on the watch. The
Data Layer listener and a connection check every 30 s run only while the app
is on screen (`repeatOnLifecycle(STARTED)`). Black background, R8 + resource
shrinking on release.

## Build

Needs the Android SDK (the phone build's `android/local.properties` `sdk.dir`
works: copy that line to `wear/local.properties`) and JDK 17+ (Android
Studio's `jbr` is fine).

```bash
./gradlew -p wear assembleDebug        # wear/app/build/outputs/apk/debug/app-debug.apk
./gradlew -p wear assembleRelease      # wear/app/build/outputs/apk/release/app-release.apk
./gradlew -p wear test                 # unit tests of core/
```
(On Windows: `wear\gradlew.bat -p wear …`, from the repo root.)

- `applicationId` = the phone's `com.mfficiency.best_todo_2` (the Data Layer
  only pairs apps with the same id **and** the same signing key); `namespace`
  and Kotlin package `com.mfficiency.best_todo_2.wear`.
- versionCode = `-PbuildNumber` or env `BUILD_NUMBER` (else 1); versionName =
  `-PversionName` or the `x.y.z` of `pubspec.yaml`.
- Signing: `android/key.properties` (the phone's upload key; `storeFile`
  relative to `android/app`, like the phone). Without it: the phone's
  committed `android/app/debug.keystore`. `REQUIRE_RELEASE_KEY=1` fails the
  build instead.
- AGP 8.9.1 / Kotlin 2.1.0 / Gradle 8.12, the same as the phone build.

**The phone and the watch must carry the same signature** for sync: install
both from laptop builds (release key), or both from local builds without
`key.properties` (debug key). A mix shows "Update BestToDo on your phone"
or "Phone not reachable" and nothing syncs.

### Releases

`tool\build.ps1 release` (the laptop builder) builds the watch after the phone
APK and, with `PUBLISH=1`, after the phone release is published:

- `wear\gradlew.bat -p wear assembleRelease -PbuildNumber=<BUILD_NUMBER>
  -PversionName=<x.y.z> --no-daemon` with `REQUIRE_RELEASE_KEY=1`
  (`wear\local.properties` from `android\local.properties`; `JAVA_HOME` =
  Android Studio's `jbr` when unset);
- APK → `build\wear\BestToDo-Watch-<x.y.z>-<build>[-dev|-staging].apk` (not
  committed, not in `github_releases/`);
- `PUBLISH=1`: a separate GitHub release `wear-v<x.y.z>-<build>[-dev|-staging]`
  (`gh release create`, prerelease for dev/staging, never "Latest", same
  commit), its notes link the phone release.
- Prints `WEAR_BUILD_RESULT …`. A failure is only a warning: the phone
  release, its exit code and its `LAPTOP_BUILD_RESULT` line are unchanged.
  `WEAR=0` skips the watch.

The phone's updater only takes `v<digit>…` tags (`matchesTagPrefix`, prefix
`v`) and the same-code release lookup only matches `^v\d…`, so `wear-…`
releases are never offered to phones and never stop a phone build.

## Install on the Galaxy Watch6 Classic (wireless ADB)

1. Watch: Settings › About watch › Software information › tap **Software
   version** 5 times (Developer options on).
2. Settings › Developer options: **ADB debugging** on, **Wireless debugging**
   on (watch and computer on the same Wi-Fi).
3. Wireless debugging › **Pair new device**: note the IP, pairing port and
   code, then `adb pair <ip>:<pair-port> <code>`.
4. `adb connect <ip>:<port>` (the port shown on the Wireless debugging screen,
   not the pairing port).
5. `adb -s <ip>:<port> install -r BestToDo-Watch-<version>.apk`

Get the APK from the `wear-v…` GitHub release (Mfficiency/best_todo_2
releases) or `build\wear\` on the laptop. The phone needs a BestToDo with the
watch sync (0.2.116 or later) from the same kind of build (see signature
above).

## Test

- Unit tests: `./gradlew -p wear test` (Payloads, Pending, Labels in `core/`).
  The phone side: `flutter test test/home/wear_sync_test.dart` (payloads,
  the gates incl. `mlr`, the command queue, complete-only background path,
  channel publish/dedupe).
- Emulator: Android Studio › Device Manager › Wear OS **Large Round**, paired
  with a phone emulator through the Wear OS app's pairing assistant.
- Manual checklist:
  - [ ] Phone app open: the watch shows today's list, tomorrow's and the
        next alarm; "Phone connected".
  - [ ] Complete a task on the watch (two taps): it is done on the phone
        within seconds, streak/stats count it; the watch keeps it done.
  - [ ] Phone app closed (swiped away): complete a task on the watch; open
        the phone app: the task is done, nothing completed twice.
  - [ ] Complete / add / move a task on the phone: the watch list follows.
  - [ ] An `mlr` task, a Food Diary entry, a task waiting for approval:
        never on the watch.
  - [ ] Phone Bluetooth off / airplane mode: "Phone not reachable · saved
        hh:mm", the cached list still shows; a completion says "waiting for
        phone" and is delivered after reconnecting + Refresh.
  - [ ] Bezel scrolls both lists; swipe back from Alarms.
  - [ ] Screen off for a while: no battery drain from the app (no
        background work).
