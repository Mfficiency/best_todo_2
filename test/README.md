# Test suites

The test suite is split into siloed sub-suites so you only run what a change
can affect. **`test/core/` must always pass** — run it for every change. The
other suites are per-feature silos: run the ones whose area you touched.
`flutter test` (no path) still runs everything and is what CI uses.

## Suites

| Suite | Command | Covers |
|---|---|---|
| `test/core/` | `flutter test test/core` | Task model + JSON round-trip, `StorageService` persistence/rollover, item-history journal (`ItemEventJournal` diff + persistence), upgrade safety (`SafeFile` atomic writes/recovery, `PreUpdateBackup` snapshot, historical payload matrix), config persistence, tab bucketing/filtering (`date_utils`), done-task ordering, reorder ranking, deadline normalization, per-view `ViewFilterRules`/`ItemViews.passesFilterRules` filtering (including the Waiting for Approval view and every view's `builtInRules` text) + `Config.viewFilterRules` round-trip (`view_filter_rules_test.dart`), `ItemViews.waitingApproval`'s extra `rules` layer on top of the pending/non-deleted gate, app-boot smoke test, build-gate smoke test, `Attachment` model JSON round-trip + `Task.attachments` round-trip (`attachment_model_test.dart`, `task_model_test.dart`), `AttachmentStorageService` file copy/delete/task-purge (`attachment_storage_service_test.dart`), the deleted-bin retention purge deleting an expired task's attachment files (`storage_service_test.dart`) |
| `test/alarms/` | `flutter test test/alarms` | Alarm model, `AlarmStorageService` round-trip + corruption recovery/backup, alarm editor (top save), alarm ring page, item-linked reminders (`ReminderSyncService` + task-detail reminder section) |
| `test/projects/` | `flutter test test/projects` | Project model, `ProjectService` (seed/rename/reload/corrupt file), Projects page drag-assign, Kanban board page, task-tile project/stage tags, the Projects filtering-rules tag exclusion on the top pane and board (`project_filter_rules_test.dart`) |
| `test/home/` | `flutter test test/home` | Home page UI: search behaviors, drawer layout (Projects under Tools), task-tile description editing, task-tile attachments editor: add/edit/remove a text note and its wiring into `Task.attachments` (`attachments_field_test.dart`), test-failure red dot on the hamburger/drawer, settings search, dice random-task timer, its alert settings and its full-screen alarm ring (`dice_timer_alarm_test.dart`), wishlist items on the Future tab, simple/full mode + the feature switches (`simple_mode_test.dart`, `settings_features_test.dart`), collapsible settings sections (`settings_collapse_test.dart`), home-screen widget payload + checkbox toggles (`widget_checkboxes_test.dart`), double-tap "Start timer" menu (`task_double_tap_timer_test.dart`), first-launch starter-task seeding next to a Todo.md import (`home_first_launch_seed_test.dart`), `LinkifiedText` URL spans (`linkified_text_test.dart`), the default bucket for quick-added tasks (`home_default_add_bucket_test.dart`), the drawer's Home entry (`home_drawer_home_entry_test.dart`), the Notify bell's 5/20/60-minute delay sheet (`task_tile_notify_delay_test.dart`), the fresh-start/import-from-Todoist onboarding chooser (`startup_choice_page_test.dart`), the dev-only Widget Previews drawer entry mocking the four Android home-screen widgets (`widget_previews_page_test.dart`), auto-tagging (`AutoTagService` keyword matching/persistence in `auto_tag_service_test.dart`, the Settings switch + rules page in `auto_tag_settings_test.dart`, new tasks tagged on creation in `auto_tag_home_test.dart`), the Home view's Filtering rules (hides a tag from the tab list, disables reorder while active), the Settings "Filtering rules" section's add/remove-tag chip editor and the Waiting for Approval view row + its built-in-rule text (`home_filter_rules_test.dart`) |
| `test/streaks/` | `flutter test test/streaks` | Daily streaks: `StreakService` (grace periods, persistence, history seeding, fun stats), the fixed `complete` challenge plus the user-configured `create`/`plan` goals (`StreakGoal` matching, `Config.streakGoals` persistence, `isGoalMissing`) and their per-kind streaks, reminder list + migration (`streak_kinds_test.dart`), the cycling home-page flame + badge (unlit-until-done pulse, all-tracked-done red collapse), celebration overlay, `StreakPage`, `StreakGoalDialog`, Streak settings section + search entries |
| `test/sms/` | `flutter test test/sms` | SMS daily report: `SmsRecipient`/`SmsReportConfig` JSON round-trip, per-recipient enable flag + `activeRecipients` filtering, Settings recipient rows (pause switch, edit keeps the flag) |
| `test/sync/` | `flutter test test/sync` | Synced mode (background folder sync on quit): `SyncService` write/failure/persistence round-trips, the once-per-background lifecycle latch, the Obsidian-friendly Markdown companion (`SyncMarkdown` bucketing/format), App Logs "Sync" tab entries + unseen-error acknowledgement, sync-error red dot on the drawer's App Logs entry, Settings "Synced mode" switch + folder tile + "Sync now" manual run. Todoist sync: `TodoistMetadataCodec` trailer round-trip, `TodoistApiClient` request/response handling (`http.testing.MockClient`), `TodoistSyncService` push/pull/conflict/completion/deletion/project-mapping/lifecycle-latch against a small in-memory fake Todoist backend, Settings "Todoist sync" section (switch, token field, Sync now) + its App Logs "Todoist" tab + combined drawer dot. Waiting for Approval page (`waiting_approval_page_test.dart`): filtered pending view, plain Approve/Deny buttons, and the approve/deny swipe (day/weekday quick-select shortcuts, undo window before the bin) |
| `test/update/` | `flutter test test/update` | In-app updates: `UpdateService` version parsing/comparison and the `github_releases/` folder listing (newest + rollback), the About page's check → download → install flow and its "Go back to ..." button, `tool/publish_apk.dart` release naming, `tool/stage_local_release.dart` keep-the-newest-two staging |
| `test/share/` | `flutter test test/share` | Share-sheet task creation: `SharedPayload` parsing off the platform channel, `ShareIntentService.buildDraftTask` (title/description split, truncation, file-only shares), content-signature dedup of a redelivered share, payload-callback routing/queueing, `saveTask`'s home-page-consumer vs. direct-to-storage fallback, `importAttachments` (image/PDF copied into permanent storage, cache copy cleared), the platform-channel pull and `returnToPreviousApp`, and `QuickAddSharePage` (prefill, Save to Today/Inbox, Discard) |
| `test/history/` | `flutter test test/history` | `TaskMutationService`: note/flush coalescing (a paired active+archive/bin change becomes one undo entry), undo/redo (single and sequential), redo-stack invalidation on a new mutation, the bounded (30-entry) stack, and `describeChange`'s auto-generated wording |
| `test/tools/` | `flutter test test/tools` | Auxiliary tools: export/import + analytics CSVs, usage-data service, startup-times page, countdown timer model + milestone notifications (model & dialog), timer date picker (`lib/utils/date_time_format.dart`), chronize page, CI test report model/parser + Test Results page, wishlist Todo.md import migration, stable backlog uids + shipped-wish auto-completion (`wishlist_autocomplete_test.dart`), wishlist page (filtered view, priority/delete swipes), the Wishlist view's Filtering rules tag restriction (`wishlist_filter_rules_test.dart`), the Waiting for Approval view's Filtering rules tag restriction on top of the pending gate (`waiting_approval_filter_rules_test.dart`), changelog parser + update heatmap (toggle, day selection), Productivity Stats item-activity heatmap colour scale (`stats_activity_heatmap_test.dart`), failure-dot acknowledgement (`test_report_service_test.dart`), Weekly Hours Planner (`WeeklyHoursPlan` model + Friday flexitime carryover, `WeeklyHoursService` persistence, the vertical week grid's drag-to-resize block handles + reset button + Google Calendar overlay, `weekly_hours_planner_test.dart`) and its Google Calendar .ics import/RRULE expansion (`google_calendar_service_test.dart`) |

## Which suites to run

Pick suites by what you touched, always including core:

- `lib/models/task.dart`, `lib/services/storage_service.dart`, `lib/utils/`,
  `lib/config.dart`, `lib/main.dart` → **core** (plus any suite whose UI
  consumes what you changed — when in doubt, run everything)
- `lib/models/attachment.dart`, `lib/services/attachment_storage_service.dart`
  → core (+ **home**, whose `attachments_field_test.dart` and
  `task_tile.dart`/`task_detail_page.dart` also exercise them)
- `lib/ui/attachments_field.dart` → core + **home** (embedded in
  `task_tile.dart`'s expanded editor and `task_detail_page.dart`)
- `lib/models/view_filter_rules.dart`, `lib/services/item_views.dart`,
  `lib/ui/waiting_approval_page.dart` → core (+ **home**, **projects** and
  **tools**, whose Home/Settings, Projects/board and Wishlist/Waiting for
  Approval pages all read the configured rules through it)
- `lib/models/alarm.dart`, `lib/services/alarm_*`, `lib/ui/alarm*` → core + **alarms**
- `lib/models/project.dart`, `lib/services/project_service.dart`,
  `lib/ui/projects_page.dart`, `lib/ui/project_board_page.dart` → core + **projects**
- `lib/ui/home_page.dart`, `lib/ui/task_tile.dart`, `lib/ui/settings_page.dart`,
  `lib/ui/dice_timer_page.dart`
  → core + **home** (+ **projects** for `task_tile.dart`, which renders project tags;
  + **streaks** for `home_page.dart`/`settings_page.dart`, which host the flame and
  its settings section)
- `lib/services/task_mutation_service.dart`, `lib/models/task_change_source.dart` → core +
  **history** (+ **home**, whose `_saveTasks`/`_saveDeletedTasks` are what feed it)
- `lib/services/streak_service.dart`, `lib/models/streak_kind.dart`,
  `lib/models/streak_goal.dart`, `lib/models/streak_reminder.dart`,
  `lib/services/streak_flame_display.dart`, `lib/ui/streak_page.dart`,
  `lib/ui/streak_flame_button.dart`, `lib/ui/streak_goal_dialog.dart`,
  `lib/ui/streak_calendar_page.dart`,
  `lib/ui/streak_celebration.dart` → core + **streaks**
- `lib/models/sms_*`, `lib/services/sms_report_*`, the SMS section of
  `lib/ui/settings_page.dart` → core + **sms** (+ **home**/**streaks**, which also
  pump the settings page)
- `lib/services/sync_service.dart`, `lib/services/sync_markdown.dart`,
  `lib/services/todoist_sync_service.dart`, `lib/services/todoist_api_client.dart`,
  `lib/services/todoist_metadata_codec.dart`, `lib/models/sync_log_entry.dart`,
  `lib/models/todoist_sync_map_entry.dart`, `lib/ui/waiting_approval_page.dart`,
  `lib/ui/app_logs_page.dart`, the Sync & export / Todoist sync sections of
  `lib/ui/settings_page.dart` → core + **sync** (+ **home**, which also pumps the
  settings page and drawer)
- `lib/services/share_intent_service.dart`, `lib/models/shared_payload.dart`,
  `lib/ui/quick_add_share_page.dart`, `ShareActivity.kt`, the share wiring in
  `MainActivity.kt` → core + **share** (+ **home**, which registers the
  consumer that claims a quick-add-built task while the home page is alive)
- `lib/services/usage_data_service.dart`, `lib/services/startup_time_service.dart`,
  export/import, `lib/ui/startup_times_page.dart`, `lib/ui/chronize_page.dart`,
  `lib/ui/changelog_page.dart`,
  `lib/models/countdown_timer.dart`, `lib/models/test_report.dart`,
  `lib/services/test_report_service.dart`, `lib/ui/test_results_page.dart`,
  `lib/services/wishlist_migration.dart`, `lib/services/wishlist_shipped.dart`,
  `lib/ui/wishlist_page.dart`,
  `lib/ui/your_stats_page.dart`,
  `tool/generate_test_report.dart`,
  `lib/models/weekly_hours_plan.dart`, `lib/services/weekly_hours_service.dart`,
  `lib/ui/weekly_hours_planner_page.dart`, `lib/models/gcal_event.dart`,
  `lib/services/google_calendar_service.dart` → core + **tools** (+ **home**
  for the Settings section that configures the calendar URL and hour range)
- `lib/models/auto_tag_group.dart`, `lib/services/auto_tag_service.dart`,
  `lib/ui/auto_tag_rules_page.dart` → core + **home** (+ **tools**, since
  `wishlist_page.dart` also calls into it)
- `lib/services/update_service.dart`, `lib/ui/about_page.dart`,
  `tool/publish_apk.dart`, `tool/stage_local_release.dart` → core + **update**
- `lib/utils/linkified_text.dart`, `lib/ui/task_detail_page.dart` → core +
  **home** + **tools** (the wishlist page renders the same links)
- `lib/ui/widget_previews_page.dart` → core + **home** (+ **alarms**, whose
  `AlarmService` dev seed it reads; + **tools**, whose `FoodDiaryWidgetService`
  logic it mirrors)

Multiple suites can be passed in one invocation:
`flutter test test/core test/alarms`.

Cross-cutting changes (theme, navigation, dependency upgrades, anything in
`pubspec.yaml`) → run the full suite: `flutter test`.

## Adding tests

Put new tests in the suite matching the feature area; create a new
`test/<area>/` directory when a new feature area doesn't fit an existing silo.
Keep core limited to functionality the whole app depends on (task model,
persistence, bucketing) plus app-boot/build smoke tests. Test conventions
(fake path provider, `ProjectService.instance.resetForTest()`, etc.) are in
`CLAUDE.md`.
