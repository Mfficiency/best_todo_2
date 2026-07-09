# Changelog

## [0.1.97] - 2026-07-09
- New dice button in the app bar (right of the search field): rolls one of today's open tasks at random and opens a rotary egg-timer for it — the dial opens pre-wound to 20 minutes, so turn it back for less time, and the countdown starts the moment you let go, showing the time left, the percentage of time remaining, and the wall-clock end time
- Dice timer keeps running when you leave the page: the dice button shows a dot and returns you to the running timer instead of rolling a new one
- Dice timer: Done is available from the moment it opens (finish the task without starting a countdown), and while it counts down you can finish early with Done, Pause and later Resume, or Lock touch — a full-screen lock that ignores every tap (and the back button) until you press Unlock, so a pocket bump or an incoming call can't disturb the timer
- Dice timer: at zero an alarm rings and the task can be confirmed Done, postponed to tomorrow, or given extra time (+1 / +5 / +10 min); grabbing the dial mid-countdown pauses and rewinds it

## [0.1.96] - 2026-07-09
- release builds now embed the CI test results: if a test failed on GitHub while the APK still built, the menu (hamburger) icon shows a red dot and a new Test Results page in the menu lists the current build's failing tests
- Settings: search your settings — a magnifier in the Settings title bar filters all settings by name or keyword and jumps to the matching section (separate from the task search on the home screen)

## [0.1.95] - 2026-07-08
- wishlist export for all or individual items, plus quick low/medium/high priority labels

## [0.1.94] - 2026-07-08
- new Wishlist tool for title/description/label wish items, available from Tools and as a default start page

## [0.1.93] - 2026-07-08
- Stats renamed to Productivity Stats and moved into the Tools section of the menu
- Settings: choose the default start page — the task list or any tool (Alarms, Countdown, Projects, Chronize, Usage Data, Productivity Stats); the chosen tool opens on launch, back returns to the task list
- alarms: per-alarm volume is now real — every alarm rings its melody at its own volume as a fraction of the device maximum, independent of the phone's current media/ringer/alarm volume (the alarm stream is pinned to max during the ring and restored afterwards)
- alarms: new "Override Do Not Disturb" switch per alarm — when on, the alarm always plays at its configured volume, even while the phone is silenced or in Do Not Disturb
- alarms: Preview button next to the melody picker — plays the selected melody at the configured alarm volume (live-updates while changing melody or volume) so sound and loudness can be checked before saving
- alarms: while the full-screen ring page plays the alarm's own melody, the notification moves to a silent channel (actions and vibration stay) so the default alarm sound no longer plays on top; if melody playback cannot start, the notification sound keeps ringing as before

## [0.1.92] - 2026-07-08
- tests: the test suite is split into siloed per-area suites (`test/core`, `test/alarms`, `test/projects`, `test/home`, `test/tools`) so a change only needs to run the suites it can affect; core (task model, persistence, bucketing, smoke tests) is always run, `flutter test` still runs everything and CI is unchanged — see `test/README.md` for the file→suite map

## [0.1.91] - 2026-07-08
- schedule view: the day scrolled to the top of the list is now highlighted as the active day
- schedule view: new tasks typed into the add-task field land on the highlighted day (e.g. scroll to Aug 1, type, hit + — the task is due Aug 1); the field's label shows the target day ("Add task · Aug 1")
- schedule view: a back-to-top arrow appears while scrolled down and jumps back to today
- schedule view: the list can now scroll far enough that even the last section (Someday) can reach the top and be targeted

## [0.1.90] - 2026-07-07
- projects: name and description are editable (pencil icon on the project board) and persist across restarts (`projects.json`); renames update everywhere a project is shown
- projects: moved into the Tools menu (Tools → Projects)
- projects: tasks assigned to a project show the project name and Kanban stage as small tags on the task tile itself (e.g. "Project 1", "To-Do"), updating live when the task moves between columns or the project is renamed
- search: the search field in the top bar works — typing filters every tab and the schedule view by title, description, note, label and project name (case-insensitive), with a clear (×) button; reordering is disabled while a search is active so hidden tasks keep their order
- alarms widget: tapping anywhere on the widget now opens the alarms page directly (background, header and empty state included); tapping a row opens that alarm's editor and the ON/OFF toggle still works without opening the app
- tests: per-feature widget/unit tests for all of the above (project persistence, drag-assign, board columns, edit dialog, tile tags, search behaviors, drawer placement, alarm-editor top save)
- docs: added CLAUDE.md (AI working guide); SPEC.md updated for all new behavior
- screenshots: the CI screenshot walk-through now also captures search-in-action, the Projects page, the Kanban board and the project edit dialog, and archives every captured page automatically

## [0.1.89] - 2026-07-07
- new Projects tool
- drag tasks onto projects to assign them
- per-project Kanban board (To-Do / Ongoing / Closed)
- alarms: Save action in the top app bar of the alarm editor (in addition to the button at the end of the form)

## [0.1.88] - 2026-07-07
- alarms: full-screen alarm screen — a ringing alarm now opens a clock-app-style full-screen page (live clock, alarm name, big Snooze / Stop buttons, themed with the alarm's color) instead of only a notification banner. It shows over the lock screen with the screen turned on (via the notification's full-screen intent) and also opens when the ringing notification is tapped; Stop/Snooze on it keep the OS schedules, the snooze slot and the delivery watchdog consistent
- alarms: FIXED release builds silently failing to schedule anything — R8/ProGuard stripped Gson's generic type info inside flutter_local_notifications, so every schedule call died with "Missing type parameter." (all three ladder methods REJECTED in the alarm log) and only the ~90 s-late watchdog backup ever rang; added keep rules (`android/app/proguard-rules.pro`) so the primary exact-alarm path works in release builds again
- alarms: the watchdog backup ring now carries the alarm payload too, so it also opens the full-screen alarm screen and can be stopped from it
- alarms: permission flow and diagnostics now check the Android 14+ "full screen intents" special access — revoked access is reported in the alarm log with the exact settings path, and the permission flow opens the system toggle
- alarms: stopping/snoozing on the ring screen is acknowledged to the delivery watchdog (no double-ring) and logged as ACTION lines in the alarm log

## [0.1.87] - 2026-07-07
- startup times page facelift: summary card (typical/last/fastest/slowest launch, human-readable ms/s), themed chart that scales to the data instead of clipping launches over 1.5 s, date labels and tap-for-details tooltips, shaded band marking starts over 1 s
- startup times: a "What this means" section below the chart explains what is measured and draws conclusions from the data — typical-startup verdict, faster/slower trend, share of slow starts, outlier spikes, and whether the first launch of the day is a slower cold start
- startup times: uses the timestamped launch history (up to 5000 launches) when available, falling back to the legacy duration list

## [0.1.86] - 2026-07-07
- usage data tool (Tools → Usage Data): export everything the app has ever recorded as detailed CSV files — a Digital-Wellbeing-style data dump reaching as far back as the data on the device goes. Datasets: a unified event timeline across all sources (every task created/moved/rescheduled/completed/deleted/restored, alarm pipeline steps, SMS report attempts, app opens, countdown timers), per-day usage summary (first/last activity, active span, app opens, task counts, start-of-day completion rate), per-hour activity histogram, full task history with derived metrics (hours to complete, completed on time), raw daily task stats, parsed alarm pipeline log, alarm setup snapshot, SMS report log, app opens, legacy startup durations, countdown timers, plus an export manifest stating how far back the data reaches
- usage data: each dataset can be included/excluded before export; files are written as `.csv` (RFC 4180) into a timestamped `besttodo_usage_<timestamp>` folder in a directory you pick
- app opens are now recorded with a timestamp on every launch (`startup_history.json`, capped at 5000 entries) so future usage exports show opens per day — previously only the duration of the last 100 startups was kept

## [0.1.85] - 2026-07-06
- release build (no functional changes since 0.1.84)

## [0.1.84] - 2026-07-06
- alarms: foolproof delivery — every alarm is now scheduled through an escalation ladder (setAlarmClock → setExactAndAllowWhileIdle → inexact last resort; each attempt logged) and additionally guarded by an independent watchdog that wakes ~90 s after the fire time, checks whether the alarm actually rang (notification on screen or already tapped/snoozed/dismissed) and rings it itself if the primary path was silently dropped
- alarms: persistent human-readable log file (`alarm_log.txt`, viewable in-app via Alarms → log icon) records every step with [OK]/[FAIL]/[WARN] and a fix hint: permission checks and requests, each scheduling method tried, OS read-back verification of pending schedules, watchdog arming, delivery verdicts, and user actions (tap/snooze/dismiss) — when an alarm doesn't ring, the file says which step failed and why
- alarms: startup diagnostics snapshot logged on every launch — device/OEM, Android version, notification + alarm-channel state, exact-alarm permission, battery-optimization exemption, per-OEM power-saver hints (Samsung sleeping apps, Xiaomi autostart, …), configured alarms vs. what the OS reports as scheduled
- alarms: "Test alarm (1 min)" and "Run diagnostics" buttons on the log page exercise the full pipeline on demand
- alarms: alarm sound/vibration now loops until the notification is acted on (insistent flag) instead of playing once
- alarms: snooze fires are also covered by the watchdog and logged

## [0.1.83] - 2026-07-02
- alarms tool: full alarm clock with per-alarm settings (Tools → Alarms)
- home-screen alarms widget with toggle and edit
- exact alarm scheduling that fires when the app is closed and after reboot — alarms are scheduled with the OS, so they also ring in flight mode / offline
- alarm snooze and dismiss actions
- scheduled notifications interpret times as absolute (fixed timezone drift)
- alarms: toggling an alarm from the home-screen widget while the app is closed now actually schedules/cancels the OS alarm (before, the toggle only changed the stored state, so an alarm enabled from the widget never rang and a disabled one still fired)
- alarms: snooze now works when the app is closed (the notification-action isolate couldn't reach the platform plugins), and a pending snooze is no longer silently cancelled when the app is opened or another alarm is edited
- alarms: the alarm permission prompt also asks for battery-optimization exemption so OEM power savers (Samsung "Sleeping apps") can't delay or drop alarms
- alarms: repeating alarms scheduled across a DST change no longer fire an hour off

## [0.1.82] - 2026-07-02
- sms report: the daily alarm now fires reliably while the app is closed — switched from a repeating alarm (which Android treats as inexact and defers indefinitely in Doze/deep sleep) to an exact one-shot alarm (`setExactAndAllowWhileIdle`) that re-arms itself for the next day each time it fires; the chain is also restored on every app launch and survives reboots
- sms report: enabling the report now also asks for SMS permission up front — the background isolate has no UI, so the permission dialog can never be shown when the alarm fires
- sms report: every background alarm fire writes an "Alarm fired" entry to the SMS report log, so you can verify firing even when the send is skipped

## [0.1.81] - 2026-07-01
- sms report: the daily alarm now requests the permissions it needs to actually fire in the background — exact-alarm scheduling and, crucially, exemption from battery optimization / Doze (Samsung "Sleeping apps" and similar OEM power savers silently drop background alarms unless the app is whitelisted). Enabling the report now prompts for these. Also declared the matching manifest permissions (SET_ALARM, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, FOREGROUND_SERVICE, VIBRATE)

## [0.1.80] - 2026-06-30
- sms report: fixed the scheduled daily report never firing — the Android manifest was missing the `AlarmBroadcastReceiver` that AndroidAlarmManager's alarm targets, so the alarm fired in the OS but was never delivered to the app and the background callback never ran (the in-app "Send test now" button still worked because it bypasses the alarm)

## [0.1.79] - 2026-06-05
- chronize: the off-screen event hints are subtler — a small lowercase distance pill (e.g. "3 hours") with the direction arrow moved outside the pill (above for earlier, below for later), so the hint is one line tall and the wording no longer says "earlier"/"in"

## [0.1.78] - 2026-06-05
- chronize: the "Today" button now centers the view on the current time instead of pinning it to the top
- chronize: flinging the timeline keeps gliding and slows to a stop (momentum scrolling) instead of halting on release
- chronize: tap an empty spot on the timeline to create a task with that exact deadline (date + time); tap a task to edit its title, deadline and done state, or delete it
- tasks: a deadline time set on the Chronize timeline is preserved and no longer overwritten by the default 18:00 normalization

## [0.1.77] - 2026-06-05
- chronize: when no event is in view, two centered cards point to the nearest past (↑) and future (↓) events, showing how far away each is; tap a card to jump there. They hide as soon as an event scrolls into view

## [0.1.76] - 2026-06-05
- chronize: the left timeline now zooms on a continuous axis — time marks fade in and spread apart as you zoom in (2h → 1h → 30m → 10m → 5m) and fade away when zooming out, with the day marks always visible
- chronize: tasks are placed on the timeline by their time, cascading when they would overlap, and a live "now" line tracks the clock

## [0.1.75] - 2026-06-04
- chronize: the left timeline is now zoomable — pinch (or the zoom buttons) from 5-minute marks all the way out to a multi-day overview
- chronize: a "Today" button jumps the timeline and wheels back to now
- chronize: the hour wheel is now optional via a setting (Settings → Tasks → "Chronize: show hour wheel"), off by default so the timeline has more room
- chronize: day/month wheels spin more smoothly (the timeline glide + refresh are deferred until the wheel settles)

## [0.1.74] - 2026-06-04
- chronize: the three navigators are now iOS-style scroll wheels (hour / day / month) instead of sliders
- chronize: wheels scroll infinitely; the day wheel shows real calendar dates and the wheels carry over (hour past midnight bumps the day, day past month-end bumps the month)
- chronize: the calendar on the left is an infinite, smoothly-scrolling 24h timeline with per-day date markers, kept in sync with the wheels both ways
- chronize: changing the month fakes a smooth glide on the timeline instead of snapping

## [0.1.73] - 2026-06-04
- chronize calendar tool (experimental)
- default task deadline time 18:00

## [0.1.72] - 2026-06-03
- ci: fix the Build APK workflow (upgrade deprecated upload-artifact/setup-java actions, pin Flutter 3.29.2, add manual + dev-branch triggers, surface the APK download link)
- ci: include the app version in the built APK filename (besttodo-<version>.apk)
- android: raise minSdk to 23 for androidx.work compatibility
- android: sign every build with a committed fixed debug keystore so updates install in place instead of failing with a signature mismatch

## [0.1.71] - 2026-06-02
- countdown: timers are now included in the app's full export/import (backup & restore)
- countdown: the date picker only closes when you tap a day — selecting a year or changing month keeps it open
- countdown: the date/time selectors drop their icons on narrow screens to avoid crowding
- countdown: the date picker grid now starts the week on Monday, with the Saturday/Sunday columns tinted grey

## [0.1.70] - 2026-06-02
- Tools menu with a Countdown tool: multiple timers that count down and keep counting up after reaching zero, with per-timer edit, zero-notification toggle, and swipe-to-delete with undo
- countdown: always-present inline "New timer" draft at the top — pre-filled name (Timer 1, Timer 2, …) and a date one week out, with separate date and time selectors and an Add button
- countdown: editing a timer uses the same inline form as adding (edit in place, Save/Cancel)
- countdown: long-press a timer to drag it to a new spot (manual order, saved)
- countdown: sort controls — Name, Added, Edited, Deadline (each ascending/descending) plus Manual to return to your drag order
- countdown: the Add-timer form minimizes as you scroll down the list
- countdown: quick pickers, no OK step — the date picker closes when you tap a day; the time picker is an analog clock dial that closes once you set the minute (with a "Minutes" button to jump to minutes when the hour is already right)
- countdown: expanded breakdown shows 3 decimals
- countdown: dev demo timers now also appear on web (Chrome), where local persistence is unavailable
- settings: "24-hour time" toggle (defaults to 24-hour)
- settings: "Date format" choice (defaults to dd.mm.yy)

## [0.1.69] - 2026-05-26
- settings: "Start in schedule view" toggle (Tasks section) — launches the app directly into the calendar / schedule view
- schedule view: long-press to reorder tasks within a day section, matching the list view's drag behavior
- schedule view: Next week / Next month / Future tabs always scroll to a permanent range header, so the buttons work like Tomorrow even when those ranges are empty

## [0.1.68] - 2026-05-24
- schedule view: app bar toggle between the existing tab list and a Google-Calendar-style schedule — one long scrollable list grouped by day, with tabs acting as quick-scroll anchors
- dev seed: 20 future-dated tasks spread from tomorrow through ~2 months out so the schedule view and the next-week / next-month tabs always have data

## [0.1.67] - 2026-05-24
- Deleted Items: distinguish auto-deleted (done tasks swept on day change) from manually deleted with an "Auto-deleted:" label

## [0.1.66] - 2026-05-17
- SMS report: completion-rate threshold — send only on days you fall below a configurable %, for social accountability
- SMS report: compact, human-readable diagnostic logging (one summary line per run instead of eight)

## [0.1.65] - 2026-05-17
- SMS report: auto-enable multipart when message exceeds single-SMS length (160 ASCII / 70 unicode chars) — previously long messages were silently dropped by the carrier

## [0.1.64] - 2026-05-17
- SMS report: configurable SIM subscription id for dual-SIM devices (default -1 = system default)
- SMS report: export history button on the log page (writes JSON to a chosen folder)
- SMS report: log subscription id used per run

## [0.1.63] - 2026-05-17
- SMS report: wait for native SENT/DELIVERED callback (with 20s timeout) instead of trusting `sendSms` return — surfaces silent platform failures
- SMS report: pre-flight check of `isSmsCapable` and `simState`, logged to history

## [0.1.62] - 2026-05-17
- SMS report: only request SMS permission (no longer asks for phone access)
- SMS report: SMS settings now inline in Settings as their own tab/section
- SMS report: persistent diagnostic log of every run (start, config, permission, summary, per-send errors) to make failures debuggable

## [0.1.61] - 2026-05-17
- daily SMS report module: sends a scheduled text with today's completed/uncompleted task counts and the remaining list
- configurable send time, recipient list (nickname + phone), and message template
- dedicated SMS history page with per-message status and errors

## [0.1.60] - 2026-05-16
- cancel a pending swipe action by swiping the opposite direction
- show orange "Cancel" background while swiping back

## [0.1.59] - 2026-05-10
- swipe both ways

## [0.1.58] - 2026-05-03
- export optimisation
- exporting tasks and settings now possible
- exporting and importing now moved to settings

## [0.1.57] - 2026-05-03
- added time of day heatmap to stats
- automate screenshot changelog updates on push to `dev`, `staging`, and `main`
- prevent screenshot workflow self-trigger loops
- capture and archive four screenshots per push (home, menu open, settings, your stats)
- group screenshots in one folder per push and prepend grouped entries to `SCREENSHOT_CHANGELOG.md`
## [0.1.56] - 2026-02-27
- extra default task future
- skipping default screens in dev mode
- update settings menu
- add setting to choose startup tab
- add notification quiet hours setting

## [0.1.55] - 2026-02-26
- recurring tasks
- new task at top or bottom
- automated ui test
- future tab

## [0.1.54] - 2026-02-17
- update date on stats page

## [0.1.53] - 2026-02-17
- working tests, 
- update empty message, 
- tooltip on heatmap, 
- remove date selector if not dev

## [0.1.52] - 2026-02-15
- new stats added below heatmap

## [0.1.51] - 2026-02-15
- update bar location
- populate historic data for graph in dev mode
- update colors

## [0.1.50] - 2026-02-15
- widget progress line

## [0.1.49] - 2026-02-15
- take into account navigation bar
- auto apk naming

## [0.1.48] - 2026-02-15
- send notifiction

## [0.1.47] - 2026-02-15
- stats page
- heatmap like github with amount of closed items related to shade of blue
- also just return

## [0.1.46] - 2026-02-15
- able to permanently delete the deleted items

## [0.1.45] - 2026-02-15
- automatic versioning

## [0.1.44] - 2026-02-15
- update filename

## [0.1.43] - 2026-02-15
- delete message fading away

## [0.1.42] - 2026-02-15
- bringing back deleted items

## [0.1.41] - 2025-08-27
- changed menu items
- added padding to startup time graph
- fixed inconsistent primary color in menu and checkbox

## [0.1.40] - 2025-08-27
- update icons to V2
- added text "no tasks for today" when there are no tasks for today.
- text of tabs is now on two lines to make it more readable.
- log startup duration and display graph of last 100 startups
- show startup time graph scaled 0–3s with a red zone above 1s
- added short text in About page.
- widget will update at midnight to show tasks for the new day.

## [0.1.39] - 2025-08-27
- added animation for sliding actions
- fixed a bug where tasks would glitch when editing them.

## [0.1.38] - 2025-08-27
- fixed order update in widget
- move done tasks to the end of their list when marking them as done.
- not permanently deleting tasks when deleting them on a new day, but moving them to a deleted list. 

## [0.1.37] - 2025-08-27
- added uid to tasks for better identification.
- added list number to tasks for ordering within a list.

## [0.1.36] - 2025-08-25
- this is actually 0.1.33, but i fucked up the versioning
- undid the storage permission, this was not working.

## [0.1.32] - 2025-08-22
- request storage permission before exporting tasks on Android

## [0.1.31] - 2025-08-22
- allow selecting a folder when exporting tasks in sandboxed macOS builds.

## [0.1.30] - 2025-08-22
- add update button on about page to check for new versions.

## [0.1.29] - 2025-08-22
- allow choosing export location, defaulting to Downloads folder.

## [0.1.28] - 2025-08-22
- fixed a bug where the widget would not update

## [0.1.27] - 2025-08-22
- leave more space at the bottom of the intro screen for devices with gesture navigation.
- added import and export buttons for tasks in the settings page.
- updated logo

## [0.1.26] - 2025-08-22
- Added introduction screens highlighting core values: Speed, Minimal Interactions, Open Source.

## [0.1.25] - 2025-08-22
- save task description and notes automatically when editing.
- still have the bug where the title changes when you edit stuff

## [0.1.24] - 2025-08-22
- Persist settings across app restarts.

## [0.1.23] - 2025-08-21
- Added icons for unselected tabs.
- added settings to toggle icon tabs.

## [0.1.22] - 2025-08-21
- widen the tabs.
- added icons in background ready to be used in next version

## [0.1.21] - 2025-08-21
- Added Next Month tab to organize tasks beyond a week ahead.

## [0.1.20] - 2025-08-21
- Added animated feedback for swipe gestures.

## [0.1.19] - 2025-08-21
- make delay for swipe button configurable in settings.

## [0.1.18] - 2025-08-21
- updated app theme to use base hue #005FDD
- aligned web manifest colors with new theme

## [0.1.17] - 2025-08-21
- delete button only visible in dev mode.

## [0.1.16] - 2025-08-21

- completed tasks now move to the end of their list when checked.
- delete button added to task tile when in dev mode.
- delete all completed tasks when a new day starts.

## [0.1.15] - 2025-08-21
- ensure tasks due tomorrow are excluded from today's list.
- made background black in widget as a temporary fix.

## [0.1.14] - 2025-08-21
- only show pending tasks due today or earlier on the home widget.
- update padding in widget layout to improve appearance on various devices.

## [0.1.13] - 2025-08-21
- dont show tasks that are done in the widget.

## [0.1.12] - 2025-08-21
- Removed old version widget and associated Android resources.
- widget works and shows tasks due today.

## [0.1.11] - 2025-08-17
- changed saving location

## [0.1.10] - 2025-08-17
- (fix) Widget now displays all tasks due today

## [0.1.9] - 2025-08-17
- updated widget color to be better visible on all devices

## [0.1.8] - 2025-08-15
- Widget now displays tasks due today instead of app version.

## [0.1.7] - 2025-08-15
- Updated the widget so when you click on it, it opens the app.
- showing the correct logo and icons

## [0.1.6] - 2025-08-15
- a working version where the widget shows the version number

## [0.1.5] - 2025-08-15
- cleanup main branch with android folder attached

## [0.1.4] - 2025-08-15
- cleanup of the ui when doing the swipe gesture
- update sdk and dependencies

## [0.1.3] - 2025-06-23
- restored tasks go to today by default.
- automatic update version number

## [0.1.2] - 2025-06-23
- ensure tasks persist across app restarts.

## [0.1.1] - 2025-06-23
- Added default example tasks on startup.
- Introduced two pages (Today and Tomorrow) with swipe/drag to move tasks to the next page.
- Added changelog file.
- Added Day After Tomorrow and Next Week pages.
- Swipe button now reveals options for 2 seconds to move a task to Tomorrow,
  Day After Tomorrow, or Next Week (defaulting to Tomorrow if none selected).
- Fixed swipe button logic so tasks move only after the 2-second delay if no
  option is tapped.
- Fixed headline text style in the task detail page.
- Added expandable task editing with description, notes and labels.
- Added settings page with configurable swipe direction.
- Added drawer navigation with About, Settings and Deleted Items pages.
- Added undoable delete with snackbar and Deleted Items restore list.
- Added task detail view when tapping items in Deleted list.
- Added dev mode date navigation and automatic cleanup of completed tasks.
- Reschedule options now appear when swiping tasks and the swipe button is hidden on Android.
- Swipe gestures now move tasks to the next list by default and wrap from Next Week back to Today.
