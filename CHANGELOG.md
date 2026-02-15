# Changelog

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

