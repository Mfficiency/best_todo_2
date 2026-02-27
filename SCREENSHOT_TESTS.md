# Screenshot Test Catalog

Use this file to document all screenshot and visual integration tests.

- [Screenshot Test Catalog](#screenshot-test-catalog)
  - [Overview](#overview)
  - [Test Template](#test-template)
  - [Task Tests](#task-tests)
    - [Create Task Flow](#create-task-flow)
    - [Modify Task Flow](#modify-task-flow)
    - [Open Task Flow](#open-task-flow)
    - [Close Task Flow](#close-task-flow)
    - [Move Task Flow](#move-task-flow)
    - [Delete Task Flow](#delete-task-flow)
    - [Add Description Flow](#add-description-flow)
    - [Add Note Flow](#add-note-flow)
    - [Add Label Flow](#add-label-flow)
    - [Pick Due Date Flow](#pick-due-date-flow)
    - [Set Notification Flow](#set-notification-flow)
  - [Settings Tests](#settings-tests)
    - [Settings - Dark Mode](#settings---dark-mode)
    - [Settings - Use Tab Icons](#settings---use-tab-icons)
    - [Settings - Add New Tasks At Top](#settings---add-new-tasks-at-top)
    - [Settings - Swipe Left To Delete](#settings---swipe-left-to-delete)
    - [Settings - Default Delay Slider](#settings---default-delay-slider)
    - [Settings - Start Page](#settings---start-page)
    - [Settings - Widget Progress Line](#settings---widget-progress-line)
    - [Settings - Enable Notifications](#settings---enable-notifications)
    - [Settings - Quiet Hours Toggle](#settings---quiet-hours-toggle)
    - [Settings - Quiet Hours Start](#settings---quiet-hours-start)
    - [Settings - Quiet Hours End](#settings---quiet-hours-end)
    - [Settings - Default Notification Delay](#settings---default-notification-delay)


## Overview

| Test | Status | File |
| --- | --- | --- |
| Create Task Flow | Implemented | `integration_test/create_task_screenshot_test.dart` |
| Modify Task Flow | Planned | `integration_test/modify_task_screenshot_test.dart` |
| Open Task Flow | Planned | `integration_test/open_task_screenshot_test.dart` |
| Close Task Flow | Planned | `integration_test/close_task_screenshot_test.dart` |
| Move Task Flow | Planned | `integration_test/move_task_screenshot_test.dart` |
| Delete Task Flow | Planned | `integration_test/delete_task_screenshot_test.dart` |
| Add Description Flow | Planned | `integration_test/add_description_screenshot_test.dart` |
| Add Note Flow | Planned | `integration_test/add_note_screenshot_test.dart` |
| Add Label Flow | Planned | `integration_test/add_label_screenshot_test.dart` |
| Pick Due Date Flow | Planned | `integration_test/pick_due_date_screenshot_test.dart` |
| Set Notification Flow | Planned | `integration_test/set_notification_screenshot_test.dart` |
| Settings - Dark Mode | Planned | `integration_test/settings_dark_mode_screenshot_test.dart` |
| Settings - Use Tab Icons | Planned | `integration_test/settings_use_tab_icons_screenshot_test.dart` |
| Settings - Add New Tasks At Top | Planned | `integration_test/settings_add_new_tasks_top_screenshot_test.dart` |
| Settings - Swipe Left To Delete | Planned | `integration_test/settings_swipe_left_delete_screenshot_test.dart` |
| Settings - Default Delay Slider | Planned | `integration_test/settings_default_delay_screenshot_test.dart` |
| Settings - Start Page | Planned | `integration_test/settings_start_page_screenshot_test.dart` |
| Settings - Widget Progress Line | Planned | `integration_test/settings_widget_progress_line_screenshot_test.dart` |
| Settings - Enable Notifications | Planned | `integration_test/settings_enable_notifications_screenshot_test.dart` |
| Settings - Quiet Hours Toggle | Planned | `integration_test/settings_quiet_hours_toggle_screenshot_test.dart` |
| Settings - Quiet Hours Start | Planned | `integration_test/settings_quiet_hours_start_screenshot_test.dart` |
| Settings - Quiet Hours End | Planned | `integration_test/settings_quiet_hours_end_screenshot_test.dart` |
| Settings - Default Notification Delay | Planned | `integration_test/settings_default_notification_delay_screenshot_test.dart` |

## Test Template

Copy this block for each test:

```md
### Test Name
- File:
- Purpose:
- Scenario:
- Preconditions:
- Steps:
- Expected Screenshots:
- Output Path:
- Run Command:
- Notes:
```

## Task Tests

### Create Task Flow
- File: `integration_test/create_task_screenshot_test.dart`
- Purpose: Verify task creation flow and capture screenshots after key steps.
- Scenario: Open app, create a task, and record visual checkpoints.
- Preconditions: Windows Developer Mode enabled (symlink support for Flutter desktop integration tests).
- Steps:
  1. Launch app on home page.
  2. Add one new task.
  3. Capture screenshots after each step.
- Expected Screenshots: Home page, add-task interaction, task-created result.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/create_task_screenshot_test.dart -d windows`
- Notes: Compares screenshots against historical golden references in `integration_test/goldens/create_task/`. To create/update goldens, run with `--dart-define=UPDATE_CREATE_TASK_GOLDENS=true`. To force a deterministic failure and verify the test can fail, run with `--dart-define=FORCE_CREATE_TASK_SCREENSHOT_FAILURE=true`. The test also keeps the latest 5 sessions in `build/e2e_screenshots/sessions_index.json`.

### Modify Task Flow
- File: `integration_test/modify_task_screenshot_test.dart`
- Purpose: Verify editing an existing task and capture visual checkpoints.
- Scenario: Create/select a task, update values, and validate updated UI state.
- Preconditions: Windows Developer Mode enabled.
- Steps:
  1. Launch app and ensure at least one task exists.
  2. Open task edit mode.
  3. Change task description and/or note.
  4. Save changes.
  5. Capture screenshots after open, edit, and save.
- Expected Screenshots: Task before edit, edit form state, updated task tile/detail.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/modify_task_screenshot_test.dart -d windows`
- Notes: Planned.

### Open Task Flow
- File: `integration_test/open_task_screenshot_test.dart`
- Purpose: Verify opening task details from the list.
- Scenario: Tap a task tile to open detail page and capture view state.
- Preconditions: Windows Developer Mode enabled; at least one task exists.
- Steps:
  1. Launch app with existing task.
  2. Tap task tile.
  3. Capture screenshots before and after open.
- Expected Screenshots: Task list state, opened task detail page.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/open_task_screenshot_test.dart -d windows`
- Notes: Planned.

### Close Task Flow
- File: `integration_test/close_task_screenshot_test.dart`
- Purpose: Verify closing a task detail page back to list.
- Scenario: Open task detail and return to list while capturing checkpoints.
- Preconditions: Windows Developer Mode enabled; at least one task exists.
- Steps:
  1. Launch app and open a task.
  2. Close detail page (back button/gesture).
  3. Capture screenshots before close and after return.
- Expected Screenshots: Open detail page, list view after close.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/close_task_screenshot_test.dart -d windows`
- Notes: Planned.

### Move Task Flow
- File: `integration_test/move_task_screenshot_test.dart`
- Purpose: Verify moving/rescheduling a task between date buckets.
- Scenario: Move one task using swipe/action and validate destination list.
- Preconditions: Windows Developer Mode enabled; at least one movable task exists.
- Steps:
  1. Launch app with task in source list.
  2. Move task to another date/list (swipe or action button).
  3. Navigate to destination list if needed.
  4. Capture screenshots before move, during action, and after move.
- Expected Screenshots: Source list state, move action state, destination list with task.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/move_task_screenshot_test.dart -d windows`
- Notes: Planned.

### Delete Task Flow
- File: `integration_test/delete_task_screenshot_test.dart`
- Purpose: Verify deleting a task and resulting list state.
- Scenario: Delete a selected task and confirm it is removed.
- Preconditions: Windows Developer Mode enabled; at least one task exists.
- Steps:
  1. Launch app with at least one task.
  2. Trigger delete action (swipe/menu).
  3. Confirm deletion if prompted.
  4. Capture screenshots before delete, confirmation, and final list state.
- Expected Screenshots: Pre-delete list, delete confirmation, post-delete list.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/delete_task_screenshot_test.dart -d windows`
- Notes: Planned.

### Add Description Flow
- File: `integration_test/add_description_screenshot_test.dart`
- Purpose: Verify adding or updating a task description.
- Scenario: Open task input/detail, enter description text, and save.
- Preconditions: Windows Developer Mode enabled; app launched.
- Steps:
  1. Open add-task or edit-task screen.
  2. Enter description text.
  3. Save task.
  4. Capture screenshots before input, during input, and after save.
- Expected Screenshots: Empty/input-ready state, typed description field, saved task with description shown.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/add_description_screenshot_test.dart -d windows`
- Notes: Planned.

### Add Note Flow
- File: `integration_test/add_note_screenshot_test.dart`
- Purpose: Verify adding a note to a task.
- Scenario: Open note field for a task, enter note text, and save.
- Preconditions: Windows Developer Mode enabled; at least one target task available.
- Steps:
  1. Open task detail page.
  2. Focus note field.
  3. Enter note text.
  4. Save changes.
  5. Capture screenshots before note, during note entry, and after save.
- Expected Screenshots: Task detail without note, note entry state, task detail with saved note.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/add_note_screenshot_test.dart -d windows`
- Notes: Planned.

### Add Label Flow
- File: `integration_test/add_label_screenshot_test.dart`
- Purpose: Verify assigning a label to a task.
- Scenario: Open label picker/input, choose or create a label, and save.
- Preconditions: Windows Developer Mode enabled; label feature available.
- Steps:
  1. Open task detail or create-task screen.
  2. Open labels control.
  3. Select or create a label.
  4. Save changes.
  5. Capture screenshots before label selection, picker state, and saved result.
- Expected Screenshots: Task without label, label picker/input, task showing assigned label.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/add_label_screenshot_test.dart -d windows`
- Notes: Planned.

### Pick Due Date Flow
- File: `integration_test/pick_due_date_screenshot_test.dart`
- Purpose: Verify setting a due date on a task.
- Scenario: Open date picker, choose a due date, and confirm task update.
- Preconditions: Windows Developer Mode enabled; at least one task exists or can be created.
- Steps:
  1. Open task detail/edit screen.
  2. Open due date picker.
  3. Select a date.
  4. Save/confirm.
  5. Capture screenshots before picker, picker open, and updated due date.
- Expected Screenshots: Pre-date state, date picker UI, task with selected due date.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/pick_due_date_screenshot_test.dart -d windows`
- Notes: Planned.

### Set Notification Flow
- File: `integration_test/set_notification_screenshot_test.dart`
- Purpose: Verify configuring a notification/reminder for a task.
- Scenario: Open notification settings for a task, set reminder, and save.
- Preconditions: Windows Developer Mode enabled; notifications enabled in app.
- Steps:
  1. Open task detail/edit screen.
  2. Open notification/reminder control.
  3. Set reminder date/time or relative reminder.
  4. Save changes.
  5. Capture screenshots before setting, picker/control state, and saved reminder state.
- Expected Screenshots: Task without reminder, reminder picker/configuration UI, task showing reminder set.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/set_notification_screenshot_test.dart -d windows`
- Notes: Planned.

## Settings Tests

### Settings - Dark Mode
- File: `integration_test/settings_dark_mode_screenshot_test.dart`
- Purpose: Verify dark mode toggle and visual theme switch.
- Scenario: Open Settings > Appearance, toggle Dark mode on and off.
- Preconditions: Windows Developer Mode enabled.
- Steps:
  1. Open Settings and capture initial light/dark state.
  2. Toggle `Dark mode`.
  3. Navigate back to home screen and capture theme result.
  4. Re-open settings and toggle back.
- Expected Screenshots: Settings before toggle, settings after toggle, home screen in changed theme.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_dark_mode_screenshot_test.dart -d windows`
- Notes: Planned.

### Settings - Use Tab Icons
- File: `integration_test/settings_use_tab_icons_screenshot_test.dart`
- Purpose: Verify tab bar switches between text labels and icons.
- Scenario: Toggle `Use tab icons` and compare home tab visuals.
- Preconditions: Windows Developer Mode enabled.
- Steps:
  1. Open Settings > Appearance.
  2. Capture `Use tab icons` off/on state.
  3. Toggle setting.
  4. Return to home screen and capture tab bar.
- Expected Screenshots: Setting row state, home tabs with text, home tabs with icons.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_use_tab_icons_screenshot_test.dart -d windows`
- Notes: Planned.

### Settings - Add New Tasks At Top
- File: `integration_test/settings_add_new_tasks_top_screenshot_test.dart`
- Purpose: Verify insertion position behavior for newly created tasks.
- Scenario: Toggle `Add new tasks at top` and create task to confirm position.
- Preconditions: Windows Developer Mode enabled; list has at least one existing task.
- Steps:
  1. Open Settings > Tasks and set `Add new tasks at top` on.
  2. Create a task and capture list order.
  3. Set the toggle off.
  4. Create another task and capture list order.
- Expected Screenshots: Setting state on/off, new task at top, new task at bottom.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_add_new_tasks_top_screenshot_test.dart -d windows`
- Notes: Planned.

### Settings - Swipe Left To Delete
- File: `integration_test/settings_swipe_left_delete_screenshot_test.dart`
- Purpose: Verify swipe direction behavior for delete/move actions.
- Scenario: Toggle `Swipe left to delete` and validate swipe outcome.
- Preconditions: Windows Developer Mode enabled; at least one task exists.
- Steps:
  1. Enable `Swipe left to delete`.
  2. Swipe left on a task and capture result.
  3. Disable the setting.
  4. Swipe left on another task and capture result.
- Expected Screenshots: Toggle state, swipe-left delete behavior, swipe-left move behavior.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_swipe_left_delete_screenshot_test.dart -d windows`
- Notes: Planned.

### Settings - Default Delay Slider
- File: `integration_test/settings_default_delay_screenshot_test.dart`
- Purpose: Verify default delay slider value updates and persistence.
- Scenario: Adjust `Default delay` slider and confirm displayed seconds value.
- Preconditions: Windows Developer Mode enabled.
- Steps:
  1. Open Settings > Tasks and capture current slider label.
  2. Move slider to a new value (for example `2.5s`).
  3. Capture updated label.
  4. Re-open settings and capture persisted value.
- Expected Screenshots: Initial slider value, updated slider value, persisted value after reopen.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_default_delay_screenshot_test.dart -d windows`
- Notes: Planned.

### Settings - Start Page
- File: `integration_test/settings_start_page_screenshot_test.dart`
- Purpose: Verify app launches on selected default tab.
- Scenario: Change `Start page` dropdown, restart app flow, and confirm landing tab.
- Preconditions: Windows Developer Mode enabled.
- Steps:
  1. Open Settings > Tasks.
  2. Set `Start page` to a non-default tab.
  3. Capture dropdown state.
  4. Relaunch app session and capture first visible tab.
- Expected Screenshots: Dropdown before/after change, app startup on selected tab.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_start_page_screenshot_test.dart -d windows`
- Notes: Planned.

### Settings - Widget Progress Line
- File: `integration_test/settings_widget_progress_line_screenshot_test.dart`
- Purpose: Verify widget progress line toggle in settings and resulting state.
- Scenario: Toggle `Widget progress line` in Settings > Widget.
- Preconditions: Windows Developer Mode enabled.
- Steps:
  1. Open Settings > Widget.
  2. Capture initial toggle state.
  3. Toggle setting and capture changed state.
- Expected Screenshots: Toggle off/on states in settings.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_widget_progress_line_screenshot_test.dart -d windows`
- Notes: Planned. If widget UI capture is available later, add widget-before/widget-after shots.

### Settings - Enable Notifications
- File: `integration_test/settings_enable_notifications_screenshot_test.dart`
- Purpose: Verify notifications master switch behavior.
- Scenario: Toggle `Enable notifications` in Settings > Notifications.
- Preconditions: Windows Developer Mode enabled.
- Steps:
  1. Open Settings > Notifications.
  2. Capture notifications switch initial state.
  3. Toggle setting and capture updated state.
- Expected Screenshots: Notifications disabled/enabled states in settings.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_enable_notifications_screenshot_test.dart -d windows`
- Notes: Planned.

### Settings - Quiet Hours Toggle
- File: `integration_test/settings_quiet_hours_toggle_screenshot_test.dart`
- Purpose: Verify quiet-hours toggle reveals/hides schedule controls.
- Scenario: Toggle `Quiet hours` and check visibility of start/end rows.
- Preconditions: Windows Developer Mode enabled.
- Steps:
  1. Open Settings > Notifications.
  2. Capture with quiet hours off (no start/end rows).
  3. Toggle `Quiet hours` on and capture again.
  4. Toggle off and capture final state.
- Expected Screenshots: Quiet hours off state, quiet hours on with start/end controls visible.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_quiet_hours_toggle_screenshot_test.dart -d windows`
- Notes: Planned.

### Settings - Quiet Hours Start
- File: `integration_test/settings_quiet_hours_start_screenshot_test.dart`
- Purpose: Verify selecting quiet-hours start time.
- Scenario: Open `Quiet hours start` time picker and save a new time.
- Preconditions: Windows Developer Mode enabled; quiet hours enabled.
- Steps:
  1. Enable `Quiet hours`.
  2. Tap `Quiet hours start`.
  3. Select a new time and confirm.
  4. Capture updated start time row.
- Expected Screenshots: Time picker open, selected start time persisted on row.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_quiet_hours_start_screenshot_test.dart -d windows`
- Notes: Planned.

### Settings - Quiet Hours End
- File: `integration_test/settings_quiet_hours_end_screenshot_test.dart`
- Purpose: Verify selecting quiet-hours end time.
- Scenario: Open `Quiet hours end` time picker and save a new time.
- Preconditions: Windows Developer Mode enabled; quiet hours enabled.
- Steps:
  1. Enable `Quiet hours`.
  2. Tap `Quiet hours end`.
  3. Select a new time and confirm.
  4. Capture updated end time row.
- Expected Screenshots: Time picker open, selected end time persisted on row.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_quiet_hours_end_screenshot_test.dart -d windows`
- Notes: Planned.

### Settings - Default Notification Delay
- File: `integration_test/settings_default_notification_delay_screenshot_test.dart`
- Purpose: Verify editing `Default notification delay` (MM:SS) with valid input.
- Scenario: Open delay dialog, enter value, and confirm updated label.
- Preconditions: Windows Developer Mode enabled.
- Steps:
  1. Open Settings > Notifications.
  2. Tap `Default notification delay`.
  3. Enter a valid value (for example `00:45`) and save.
  4. Capture updated subtitle.
- Expected Screenshots: Delay dialog open, value entered, settings row showing new MM:SS.
- Output Path: `build/e2e_screenshots/`
- Run Command: `flutter test integration_test/settings_default_notification_delay_screenshot_test.dart -d windows`
- Notes: Planned. Add a separate negative test later for invalid format error (`Use format MM:SS`).
