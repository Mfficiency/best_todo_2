# Changelog

## [0.1.2] - Unreleased
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
