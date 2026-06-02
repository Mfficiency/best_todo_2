# Changelog

## [0.1.71] - 2026-06-02
- countdown: timers are now included in the app's full export/import (backup & restore)
- countdown: the date picker only closes when you tap a day — selecting a year or changing month keeps it open
- countdown: the date/time selectors drop their icons on narrow screens to avoid crowding

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
