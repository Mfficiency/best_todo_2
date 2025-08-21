# Changelog

## [0.1.14] - 2025-08-21
- only show pending tasks due today or earlier on the home widget.

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
