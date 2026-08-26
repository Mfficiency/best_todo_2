# Changelog

## [0.1.286] - 2026-08-26
- Food Diary: each entry now has a copy-to-now button that re-logs the same meal at the current time, so recurring meals take one tap instead of retyping them
- Local build: 2026-08-26 11:45

## [0.1.285] - 2026-08-26
- Wellbeing dashboard: the hourly chart's time axis now shows only the 0:00 / 6:00 / 12:00 / 18:00 marks instead of a crowded row of overlapping hour labels
- Food Diary now groups entries by day and collapses past days into expandable sections, so today and undated entries stay visible at the top instead of scrolling past weeks of history
- Local build: 2026-08-26 07:23

## [0.1.284] - 2026-08-25
- Turn Usage Data into an interactive, optional digital wellbeing dashboard with period views, phone sessions, hourly patterns, app rankings, BestTodo productivity measures, supportive insights, and gentle goals.
- Add opt-in Android Usage Access collection so screen time stays private and is combined with the existing detailed Usage Data exports.
- Local build: 2026-08-26 07:06

## [0.1.283] - 2026-08-25
- Task History and global Undo: every task change (create, edit, reschedule, priority/label, project, complete, archive, delete) now records who or what made it — you, sync (the Todoist integration), Android Share, or the app's own automation — visible in each task's History timeline; a new Undo/Redo pair in the app bar can step back (and forward) through recent actions, one tap per action, with bulk/paired changes like archiving or deleting undoing as a single step

## [0.1.282] - 2026-08-25
- Added a second, 1x1 Food Diary home-screen widget that is nothing but the "+" button, for pinning to the smallest widget slot next to the full Food Diary widget
- Local build: 2026-08-25 20:46

## [0.1.281] - 2026-08-25
- Android share sheet: BestToDo now appears when sharing text, links, images or PDFs from other apps (Chrome, YouTube, Maps, Gmail, Photos, ...) and opens a small quick-add screen prefilled from the shared content, with one tap to save to Today or the Inbox, attachments preserved, and a return to the app you shared from
- Local build: 2026-08-25 20:25

## [0.1.280] - 2026-08-25
- Weekly Hours Planner: navigate between weeks with chevrons, record each week's actual over/undertime (folds into the weekly total shown), and the Google Calendar overlay now re-syncs automatically after every edit (block drag or over/undertime entry), not only when the page opens or you tap Import in Settings

## [0.1.279] - 2026-08-25
- Added a dev-only "Widget Previews" drawer entry that mocks the Task/Alarms/Food Diary home-screen widgets in-app, so the screenshot changelog can show them off even though the real widgets are drawn by Android outside the Flutter app
- Dev/laptop runs now seed a demo text attachment onto a starter task, and the screenshot changelog captures a task expanded on the main screen both with and without an attachment

## [0.1.278] - 2026-08-25
- Food Diary got a home-screen widget: tap the + to log a meal straight from your home screen, without opening the app — same "create entry" dialog you get inside Food Diary
- The widget turns red once a meal checkpoint (8:00, 13:00, 20:00 — after breakfast/lunch/dinner) passes with nothing logged in that window, so a missed meal log actually gets your attention

## [0.1.277] - 2026-08-25
- Tasks can now carry attachments: add a text note, an image, or a PDF from the expanded task editor. Images open full-screen; PDFs open via the share sheet. Attachments are removable and are cleaned up automatically when a deleted task ages out of the bin.

## [0.1.276] - 2026-08-25
- Phone numbers in task descriptions and notes are now clickable too, same as URLs — tap one to open the dialer

## [0.1.275] - 2026-08-25
- Settings → Filtering rules gained a Waiting for Approval view (with its own tag rules, like every other view) and a read-only built-in-rule line under each view explaining the business logic it already enforces unconditionally — e.g. Home always excludes Waiting for Approval, Archived, and Deleted items
- The screenshot changelog job now also captures the Weekly Hours Planner grid alongside the rest of the tool pages
- Every screenshot changelog entry now shows the app version next to the branch it was captured from (e.g. `branch: dev v0.1.275+275`), not just the branch name

## [0.1.274] - 2026-08-25
- Weekly Hours Planner is now a vertical week grid: the five weekdays sit side by side as columns with time running top-to-bottom, sized to fill the screen so the whole hour range is visible without scrolling (replacing the old one-row-per-weekday horizontal timeline). Drag a block's edge up or down to resize it, same as before
- Settings → Weekly Hours Planner: set the grid's default start/end hour, and paste a Google Calendar (or any .ics feed) URL to import — this week's events show translucent, underneath your work blocks, right on the planner
- Weekly Hours Planner's Google Calendar card ("coming in a future update") is gone now that it's built

## [0.1.273] - 2026-08-25
- Waiting for Approval now has the same swipe gestures as the main list: swipe one way to approve a pending item onto today, with quick shortcuts for Tomorrow/Day After Tomorrow/Next Week/Next Month/Future; swipe the other way to deny it, with Fri/Sat/Sun/Mon shortcuts to approve it onto a specific day instead. Denying now gets an undo window before the item moves to the bin, matching every other delete swipe in the app.
- Local build: 2026-08-25 06:49

## [0.1.272] - 2026-08-25
- Add Weekly Hours Planner tool: a Monday-to-Friday 8:36-a-day plan split into two draggable work blocks around a half-hour lunch break, with a dotted Friday line showing the theoretical clock-out time needed to keep the week at 43 hours
- Local build: 2026-08-25 06:30

## [0.1.271] - 2026-08-25
- Fixed a launch failure that could leave the app on a blank screen: a startup step that fails (for example saving data on a platform without file storage) no longer stops the app from opening.
- Local build: 2026-08-25 06:14

## [0.1.270] - 2026-08-24
- Dev/demo builds: the Alarms tool now seeds three sample alarms (a repeating weekday "Wake up", a one-off "Midday stretch", and a disabled repeating-weekend "Wind down") instead of opening empty. Fix: the Food Diary dev seed never actually fired, because it checked whether the whole task list was empty instead of whether any food-diary entry existed — the dev starter tasks always made that list non-empty. It now seeds three sample entries spread across the day whenever no food-diary entry exists yet, so every tool's screenshot shows populated demo data.

## [0.1.269] - 2026-08-24
- Screenshot Changelog entries now timestamp in Swiss local time (`yyyy.mm.dd HH:mm:ss`) instead of raw UTC ISO-8601
- Local build: 2026-08-24 18:37

## [0.1.268] - 2026-08-24
- Reordered the Settings sections: Appearance, Mode & features, Filtering rules, Notifications, Tasks, Streak, Dice timer, SMS report, Widget, Updates, Todoist sync, Sync & export, Backup

## [0.1.267] - 2026-08-24
- Settings gained per-view Filtering rules: hide or restrict Home, Wishlist, Projects, Archived Items and the Deleted bin by tag, configured separately for each view

## [0.1.266] - 2026-08-24
- New Food Diary tool (Tools drawer): log what you eat — title, description, time and free-form tags (e.g. "sugar", "lactose") — kept entirely separate from your task lists. Entries never show on the home tabs, schedule view, projects or Todoist sync; deleting one sends it to Archived Items like everything else.

## [0.1.265] - 2026-08-24
- Deleted tasks are now Archived Items — restorable indefinitely, exactly like before. A new real Deleted bin sits behind it (open it from the Archived Items app bar): items sent there purge for good after a configurable retention window (Settings → Tasks → "Deleted items retention", default 60 days). Denying a task in Waiting for Approval now goes straight to the bin instead of the archive. Fix: manually archiving one occurrence of a recurring task could reappear on the next app restart; it now stays gone without disturbing the rest of the series or counting toward any goals.

## [0.1.264] - 2026-08-24
- New setting, Settings → Updates → "Automatically check for updates" (off by default): looks up the newest build every time the app opens and, if one is available, asks before doing anything — confirming opens the About page's update section with the check already run. A manual check on the About page still always works regardless of this setting.
- A feature branch's pull request into `dev` now has its branch deleted automatically once merged, via a new CI workflow.
- Local build: 2026-08-24 07:10

## [0.1.263] - 2026-08-24
- A task synced with Todoist now shows a small info icon next to its Note field (when expanded) with the sync source, last synced date and Todoist task id — the description field stays exactly what you typed, free of any sync metadata.
- Local build: 2026-08-24 06:24

## [0.1.262] - 2026-08-23
- Fix: a task denied in the Waiting for Approval view could stay on the Android home-screen widget. The widget list now skips deleted and not-yet-approved tasks (so pending Todoist imports never show there either), denying or approving one redraws the widget right away, and reloading the task list from storage refreshes it too.
- Local build: 2026-08-24 05:50

## [0.1.261] - 2026-08-23
- Wishlist swipe options: the countdown before the default action (moving an item back one release step) is now 8 seconds instead of the app-wide 5, each Share/Copy/Export button now shows its icon next to its label, and a Delete button was added so a single wish can be deleted straight from the swipe panel.
- Fix: tasks still waiting for Todoist approval could leak into the home page's schedule (calendar) view, which built its list straight from the raw task list instead of going through the same filter as the tab list view.
- Local build: 2026-08-23 21:09

## [0.1.260] - 2026-08-23
- The Waiting for Approval tag is now a single tag, "Waiting_for_approval", instead of one tag per word — tasks pulled from Todoist are gated properly again, and approving a task strips the tag on the Todoist side too. Tasks still carrying the old "waiting-for-approval" spelling stay gated and get cleaned up on approval.
- Local build: 2026-08-23 19:09

## [0.1.259] - 2026-08-23
- Wishlist tiles are decluttered: the per-item share, copy, export, swipe and select icons are gone — those actions now live behind the swipe gestures (swipe right for Share/Copy/Export, swipe left to select). Only the release-group picker stays on the tile.
- Local build: 2026-08-23 18:51

## [0.1.258] - 2026-08-23
- Wishlist swipe actions redesigned: swipe right for Share/Copy shortcuts (default: move the item back one release step), swipe left to multi-select items and copy them as a "build these" prompt for Claude, or bulk-delete them.
- Local build: 2026-08-23 18:33

## [0.1.257] - 2026-08-23
- Fix: the Windows exe kept showing the old default icon after rebuilding — the app icon .ico was already correct, but Ninja had no way to know Runner.rc depended on it, so incremental Windows builds never re-embedded a changed icon. A clean/first Windows build after this fix picks it up.
- Local build: 2026-08-23 17:29

## [0.1.256] - 2026-08-23
- Tasks pulled in from Todoist now arrive tagged "Waiting for Approval" and stay out of every list (Today, projects, wishlist) until reviewed in the new Waiting for Approval view (menu, under About) — approve to release it into its normal spot, or deny to delete it.

## [0.1.255] - 2026-08-23
- Editing a task or wishlist item's labels is now a ClickUp/Sheets-style picker instead of a raw text field: current labels show as removable chips, and an "Add label" chip opens a searchable list of every label you've used, checkbox-toggled, with typing a new name offering to create and add it on the spot

## [0.1.254] - 2026-08-23
- Build all release artifacts
- Wishlist items now group into release sections (Newly implemented, Next release, Soon, Backlog) decided by tags; move an item between groups with its new "Move to release group" menu, and use "Propose for next" above Next release to copy a prompt for Claude to tag ~3 Todoist backlog items for the next release.

## [0.1.253] - 2026-08-23
- The streak flame now turns white with a slight blue hue (was red) once every challenge is done for the day; its streak badge number switches to dark blue so it stays readable

## [0.1.252] - 2026-08-23
- Labels now show as tags on every task in the home list, not just wishlist items — a task tagged "urgent" or "priority-high" shows that tag under its title wherever it appears

## [0.1.251] - 2026-08-22
- Fix: tapping a schedule-view section tab that's scrolled far offscreen now actually scrolls to it (was a silent no-op)

## [0.1.250] - 2026-08-22
- The green and blue flames are now configurable goals instead of a fixed "create a task"/"plan ahead" rule: pick a recurring task or a project in Settings → Streak, and that flame lights the day a matching task is completed
- Each configurable flame gets its own title (pre-filled from the task/project name, editable) and shows a "no goal set" state until you choose one, or a "goal missing" prompt if its task/project is later deleted
- The orange "finish a task" flame is unchanged; the old fixed create/plan behaviour is retired in favour of goals you set yourself

## [0.1.249] - 2026-08-22
- Windows portable EXE builds now run automatically after a successful GitHub APK build, checking out the same commit that produced the APK; the manual "Build Windows Portable Exe" action is still available for one-off rebuilds.
- Auto-tagging got smarter: instead of one keyword per tag, each tag now has a whole group of words that trigger it (e.g. "fitness" fires on gym, workout, exercise, cardio, yoga, jogging, running, training or stretch) — seeded with 12 starter categories (work, bike, fitness, health, shopping, finance, travel, home, family, food, study, tech) curated from online thesaurus data. Settings → Auto-tag rules now edits a tag plus its whole word group in one dialog. Still on by default.

## [0.1.248] - 2026-08-22
- Fixed Todoist sync so a pull (a new task added in Todoist, a label/edit picked up from there, a completion) actually shows up in the app: the Home page's task list is now reloaded from storage after returning from Settings (where "Sync now" lives) and after the app resumes from a quit-triggered background sync, instead of only updating on-disk data that a stale in-memory list never picked up until a full app restart.

## [0.1.247] - 2026-08-22
- Pulling down on the home page's task list now runs a Todoist sync (two-way, same as the manual "Sync now" button) and reloads the list with whatever it pulled down; a no-op if Todoist sync isn't enabled.

## [0.1.246] - 2026-08-22
- Fixed a real bug where a Todoist sync run that failed partway through (a dropped/rate-limited API call, a disk write hiccup) could leave the sync bookkeeping out of step with what was actually saved, causing the *next* sync to mistake a just-added Todoist task for one you'd deleted locally — and delete it back on Todoist. A failed sync now rolls its bookkeeping back cleanly instead of carrying stray state into the next run.

## [0.1.245] - 2026-08-22
- New tasks and wishlist items can be auto-tagged: a small editable keyword → tag dictionary (Settings → Tasks → Auto-tag rules) scans the title on creation and adds any matching tags to the label automatically, with a handful of starter rules (work, bike, gym, shopping, ...) and an on/off switch ("Auto-tag new items")

## [0.1.244] - 2026-08-22
- Todoist sync: fixed label sync for real this time — pull now trusts Todoist's native `labels` field instead of a stale copy cached in the task description, so a label added or removed in Todoist's own UI actually shows up in BestToDo (and label fingerprinting is now order/case-insensitive, so pure re-ordering never causes a spurious sync). Also added Kanban project name sync: renaming a project on either side now renames it on the other (conflict rule matches everything else — local wins if both sides changed).

## [0.1.243] - 2026-08-22
- Todoist import (onboarding "Import from Todoist") now loads today's (and overdue) tasks first so the home screen opens right away, and finishes pulling everything else in the background — with a banner on the home page while it does. Web favicon now uses a crisper, correctly-sized copy of the real BestToDo logo.

## [0.1.242] - 2026-08-22
- A brand-new install now asks whether to start with an empty task list or import straight from a Todoist account (Settings → Todoist sync also still works any time later); added a manual "Build Windows Portable Exe" GitHub Actions workflow that packages a zip with BestToDo.exe and its dependencies — no installer needed, runs on Windows 10 and 11.

## [0.1.241] - 2026-08-21
- Todoist sync: labels now round-trip both ways as real Todoist labels (already worked, now covered end-to-end), wishlist items sync into a dedicated "Wishlist" Todoist project, and undated/unprojected tasks (the Future tab) sync into a dedicated "Future" project. Reassigning a task's Todoist project on an already-synced task (e.g. toggling wishlist status) now actually moves it there instead of only updating local bookkeeping.
- Local build: 2026-08-22 06:17

## [0.1.240] - 2026-08-21
- Local builds (`tool/build.sh`) now note when they finished as a "Local build" line in the changelog, so the Changelog page shows the previous build's build time

## [0.1.239] - 2026-08-21
- Fun stats on the Productivity Stats page are now tappable: each one that's backed by real items (completions, postponements, etc.) opens a sheet listing which items made it up and the day/time it happened

## [0.1.238] - 2026-08-21
- Todoist sync: fixed against Todoist's unified API v1 after the old REST v2/Sync v9 endpoints were sunset — the sync tab was failing with an endpoint-deprecated error. Also fixes reading Todoist due dates/times (their new API merged the separate date/datetime fields into one) and pages through more than one page of tasks or projects instead of silently stopping at the first.

## [0.1.237] - 2026-08-21
- Todoist sync: Settings → **Todoist sync** — a switch and an API token field keep your tasks synced both ways with a Todoist account. New/edited/completed/deleted tasks push to Todoist; tasks created, edited or completed in Todoist pull back in. "Test connection" and "Sync now" buttons, plus a status line showing the last run
- Fields Todoist has no room for — note, label, project and Kanban stage — are appended to the synced Todoist task's description as a readable summary so nothing is lost round-tripping; editing the description text above that summary in either app stays in sync
- Wishlist items and recurring tasks stay local-only (Todoist's recurrence engine doesn't map cleanly onto this app's recurring-task model)
- Runs in the background whenever you leave the app (same trigger as Synced mode) with its own App Logs "Todoist" tab; a failed sync lights the same drawer red dot as the folder sync

## [0.1.236] - 2026-08-21
- Every wishlist item now has a copy button that puts its title, description and labels on the clipboard
- The app-bar flame stops cycling once all three daily challenges are done for the day: it settles on one steady red flame showing the highest of the streak counts

## [0.1.235] - 2026-08-17
- Tier 3 of the Obsidian integration ships: checking a task off in Obsidian now flows back to the phone on its next resume, via a change journal (besttodo_changes.json) the app applies with last-writer-wins conflict rules

## [0.1.234] - 2026-08-17
- Streak challenges you have already earned now collect at the bottom of the list, under an "Earned" divider, so the card opens on what is still left to chase
- Productivity Stats gained a "Fun stats" section at the bottom: items completed and created, completion rate, busiest day, golden hour, favourite weekday, early-bird and night-owl finishes, weekend share, fastest finish, longest wait, oldest open item and how often things were postponed
- Double-tapping a task now also offers "Remind me in 5 / 10 / 20 minutes" next to "Start timer" — it only sends a notification, the task's own due date stays where it is
- The wishlist item asking for extra productivity stats ("when is the most productive day / time, which day do I postpone the most") ticks itself off with this release

## [0.1.233] - 2026-08-17
- The menu now opens with a Home entry: it closes whatever tool page you are on, clears an active search and takes you back to your start tab
- New tasks no longer have to land in the list you happen to be looking at: Settings → Tasks → "New tasks go to" pins them to one bucket (Today, Future, …), so an idea typed on Today can go straight to Future. The add row then names its target ("Add task · Future") so nothing disappears unexpectedly; the schedule view still adds to the day you highlighted
- The Notify bell on an opened task now asks when: in 5 minutes, 20 minutes, 1 hour, or the default delay from Settings. It only reminds you — the task's own due date stays where it is
- Three more wishlist items tick themselves off with this release: "add home to menu", "Default due bucket" and "have a way to sent a notification about that item in 5- 20 or 60 minutes"

## [0.1.232] - 2026-08-17
- Wishlist items now have permanent ids, so the app can tick them off itself: when a feature from the wishlist is actually built, the matching item completes on next launch, gets an "autocompleted" tag and a note saying which release delivered it — twelve already-built ideas (calendar view, Chronize, the Wishlist tab, Productivity Stats, Startup Times, simple/pro mode, the GitHub build and test workflows, the screenshot tests) are ticked off in this release
- Wishes you added yourself can be ticked off the same way, not just the ones imported from the old backlog — "autodetect URLs and make clickable" is the first, completed by the clickable links that landed in v0.1.148

## [0.1.231] - 2026-08-17
- Changelog text is now selectable (both the plain view and the update-heatmap day details), so you can copy entries out
- Android share-sheet entry is back: share a link, selected text or an email address from any app and it becomes a task on Today (first line as the title, the full shared text kept in the description) — re-implemented on the current code (ShareActivity is a translucent trampoline, not a second MainActivity, so it doesn't touch the widget black-screen investigation)

## [0.1.230] - 2026-08-17
- Ten of the features that went missing in the v0.1.157 revert are back, all of them re-implemented on the current code and none of them touching the widget/rendering path that the black-screen investigation is still about:
- Dice timer: a "Cancel timer" button ends a running, paused or ringing timer and drops its alarm with it — the task is left exactly as it was, neither done nor postponed (originally v0.1.127)
- Dice timer buttons sit in a compact grid so every control fits on one screen without scrolling (v0.1.134)
- Double-tap a task to start a timer for it straight away; double-tapping the task whose timer is already running returns to that countdown instead of restarting it (v0.1.132)
- Test Results now lists every test file and every test in it — pass, fail or skip, with per-test times — instead of only the totals; failing files sort to the top (v0.1.129)
- In-app self-update: "Check for updates" on the About page downloads the newest release APK and hands it to Android's installer, no browser detour (v0.1.133)
- Two-APK rollback: every release build stages its APK plus the previous one in `github_releases/`, so About also offers "Go back to ..." when a fresh build misbehaves (v0.1.146)
- Opt-in red dot on the menu icon when the latest test run failed, off by default and self-clearing once you have opened Test Results (v0.1.137)
- Settings → Sync & export got a "Sync now" tile showing the time and task count of the last sync; URLs in wishlist items and task descriptions are clickable; the wishlist dialog puts labels and quick-priority right under the title, description last (v0.1.148)
- Fix: first launch on a new phone seeds the three starter tasks even when a Todo.md import already filled the list (v0.1.138)
- Fix: "Check for updates" needs the Android INTERNET permission, which release builds did not declare — debug builds get it for free, which is why this only ever failed on a real release APK (v0.1.139)
- **Still missing versus the old `dev` tip (v0.1.156)**, each a real, already-designed feature waiting on the widget black-screen investigation or on its own port:
  - Upfront permission flow: ask for every permission at once when choosing the full experience, and again after an app update if one is missing (v0.1.140)
  - The widget-tap black-screen fix itself (task widget always opens the task list, `taskAffinity`/duplicate-launch handling, deferred plugin startup) — needs solving in a way that doesn't reintroduce a glitch; the native/Dart diagnostics instrumentation added to chase it (App Logs Device tab, render-surface heartbeat) is the leading suspect and should not simply be restored as-is

## [0.1.229] - 2026-08-17
- Streak flame: a challenge you have not done yet today stays grey and outlined and pulses white, so an unfinished day catches the eye.

## [0.1.228] - 2026-08-17
- No code change from 0.1.157 below — bumped straight to 0.1.228 so this build installs over the `fix/black-screen-restore` bisect APKs already on a test phone (the highest of those, rc11, is versionCode 227) without needing an uninstall first. Same reason 0.1.156 jumped its own gap; see that entry's note.

## [0.1.157] - 2026-08-17
- Reverted `dev` to the exact v0.1.126 code (the last build confirmed to open cleanly from the tasks widget every time), then re-implemented every feature below that has nothing to do with the widget/rendering path. v0.1.128 through v0.1.156 introduced a recurring "widget tap re-fronts the app as a black screen" bug; every attempted fix since — including a rebuild that deliberately dropped the suspected culprits (see the old 0.1.156 entry below) — has reglitched on real-device re-test, most recently traced to a native heartbeat/view-walk the black-screen diagnostics themselves run on every app resume. Until that investigation lands a fix that survives repeated on-device testing, `dev` goes without the widget-tap fix itself in exchange for a widget tap that reliably works. See `testbuilds/README.md` on `fix/black-screen-restore` for the full bisect/rc history.
- Settings has a new Backup section: choose a folder and the app writes a full backup of everything (tasks, settings, timers) there automatically - daily, weekly, or never; a "Back up now" button writes one on demand
- Synced mode: choose between fully offline (as before) and syncing your tasks to a folder of your choice — Settings → Sync & export, pick the folder once and you're set; runs in the background whenever you leave or quit the app, with its own App Logs "Sync" tab and a red-dot failure indicator
- Synced mode also writes an Obsidian-friendly Markdown checklist (`besttodo_tasks.md`) next to the JSON file - point your sync folder into an Obsidian vault and your tasks render as a native checklist
- New read-only Obsidian plugin (Tier 2 of the Obsidian integration, in `obsidian-plugin/`): a proper task view inside Obsidian rendering the synced `besttodo_tasks.json` - the six home tabs, checkboxes, due dates, label and project chips, open-first ordering, and an "as of ..." freshness line; it refreshes automatically when the sync file changes and never writes anything back
- Streak page: yearly calendar view + 26 Duolingo-style challenges, with completion times recorded to power them
- Three daily streaks instead of one: **finish a task** (the original), **create a task**, and **plan ahead** — a day counts for the last one when you move a task to another day or finish everything that was due today
- The flame in the app bar now cycles through the three streaks, each in its own colour (orange for finishing, green for creating, blue for planning), with its day count and a grey flame for whatever is still open today
- Tap the flame for the full picture: pick a streak with the new chips, see what is still open today per challenge, and get that streak's own stats and calendar
- Settings → Streak: switch each of the three challenges on or off (all three are on by default)
- Streak reminders are now a list — add as many times of day as you like, each either a silent notification or with sound and vibration, and each one can be switched off without losing its time
- Reminders now say what is still open ("Still open today: create a task, plan ahead")
- Settings opens with every section collapsed, so the page starts as a short list of headings; tapping a section, a chip or a search result opens it
- **Features still temporarily missing versus the previous `dev` tip (v0.1.156), to be re-implemented once the widget black-screen investigation is resolved** — each one is a real, already-designed feature, not speculative, just not yet ported back:
  - Dice timer: a "Cancel timer" button that ends a running/paused/ringing timer and drops its alarm without marking the task done or postponed (v0.1.127)
  - Test Results page: per-file/per-test pass-fail-skip detail instead of just a summary (v0.1.129)
  - Double-tap a task to start a timer for it straight away, returning to an already-running one instead of restarting (v0.1.132)
  - In-app self-update: "Check for updates" on the About page downloads and installs the newest GitHub release APK directly (v0.1.133)
  - Dice timer buttons laid out in a compact grid so every control fits one screen (v0.1.134)
  - Opt-in red dot on the menu icon for failed tests, self-clearing once you've looked (v0.1.137)
  - Fix: first launch on a new phone seeds the three starter tasks even when a Todo.md import already filled the list (v0.1.138)
  - Fix: "Check for updates" needs the Android INTERNET permission in release builds (v0.1.139)
  - Upfront permission flow: ask for every permission at once when choosing the full experience, and again after an app update if one is missing (v0.1.140)
  - Two-APK rollback: every release build stages its APK plus the previous one, so About → "Go back to ..." can downgrade one version (v0.1.146)
  - Settings → Sync & export "Sync now" tile, clickable URLs in descriptions, wishlist dialog field reorder (v0.1.148)
  - The widget-tap black-screen fix itself (task widget always opens the task list, `taskAffinity`/duplicate-launch handling, deferred plugin startup) — needs solving in a way that doesn't reintroduce a glitch; the native/Dart diagnostics instrumentation added to chase it (App Logs Device tab, render-surface heartbeat) is the leading suspect and should not simply be restored as-is

## [0.1.156] - 2026-08-15
- Rebuilt the app from the v0.1.114 snapshot and re-applied every feature shipped since then **except** the ones below, all of which touched app startup or the widget/resume rendering path and were the source (or an artifact) of the recurring "widget tap re-fronts the app as a black screen" bug. Everything else from v0.1.115 through v0.1.155 is included: the daily streak (incl. the yearly calendar and 26 challenges), the Obsidian sync integration, dice timer + its alarm-style ring, mode picker (simple/full), permission up-front flow, Settings collapse/search, automatic + on-demand backup, folder sync with an Obsidian Markdown export, self-update from GitHub releases with one-version rollback, the Android share-sheet entry, Sync-now tile, clickable description links, and the App Logs copy/export-to-.txt buttons (rebuilt without the black-screen-specific Device tab and native log watcher, which were dropped along with the rest of the diagnostics)
- **Skipped, on purpose** (see SPEC.md §3 and §8 for the restored behavior each one temporarily changed):
  - **v0.1.136** — "Fixed the occasional black screen when opening the app... startup no longer waits on the notification, alarm and home-widget plugins before showing the first frame." This deferred-first-frame rewrite of `main()` is the change most directly implicated in the bug reports that followed; this build keeps the original eager startup sequence instead
  - **v0.1.142** — "Fixed tapping the tasks home-screen widget showing a black screen... widget taps now always return to the existing app, and a stray duplicate closes itself." This build keeps the original `android:taskAffinity=""` and does not add the duplicate-instance `finish()` check in `MainActivity`
  - **v0.1.143** — switched the Android renderer from Impeller to Skia "to fix" the widget black screen; field testing later showed Skia was the actual cause. This build never opts out of Impeller in the first place
  - **v0.1.147** — reverted 0.1.143's renderer switch back to Impeller (moot here, since 0.1.143 was never applied) but also added a forced repaint on every foreground resume
  - **v0.1.149** — removed that forced repaint, having identified it as the real cause of a still-recurring black screen (also moot here, since it was never added)
  - **v0.1.150, v0.1.151, v0.1.152** — progressively deeper widget-tap/black-screen diagnostics: a native (Android) log watcher, a render-scheduler heartbeat, and process/isolate-startup breadcrumbs
  - **v0.1.155** — switched `MainActivity`'s render surface from `SurfaceView` to `TextureView` and added a render-surface heartbeat, the latest attempt at the same bug
- Bumped straight to 0.1.156 (there is no 0.1.149-0.1.155 in this line's own history) so the version number stays ahead of `dev`'s highest released build

## [0.1.148] - 2026-08-09
- Settings → Sync & export got a "Sync now" tile: run a sync by hand instead of waiting for the next app quit, with the time and task count of the last sync shown right on the tile
- Web links in descriptions are now clickable: URLs in wishlist items and on the task-details page open in the browser with a tap
- The wishlist add/edit dialog now puts labels and the quick-priority buttons right under the title, with the description at the bottom - quicker to file a wish with just a title and a priority

## [0.1.146] - 2026-08-08
- Updates now come from the two APKs the repo keeps in `github_releases/`: "Check for updates" offers the newest build as before, and a second button goes one version back - handy when a fresh build misbehaves (Android blocks downgrades, so the older build may need the current version uninstalled first; export a backup before doing that)
- Every release build now stages its APK into that folder and deletes the oldest one, so the app always has the latest build plus one to fall back to

## [0.1.145] - 2026-08-08
- BestToDo now appears in Android's share menu: share a link, selected text or an email address from any app and it instantly becomes a task on Today (first line as the title, the full shared text kept in the description)

## [0.1.144] - 2026-08-08
- Tapping "Longest streak ever" on the streak page now opens a yearly streak calendar: all twelve months of a year with the longest streak highlighted in flame orange (grace days outlined), every other active day in light orange, and a header naming the streak's exact first and last day - browse other years with the arrows
- The streak page got 26 Duolingo-style challenges with an earned counter and progress bars: time-of-day badges (complete a task before 8:00, before 6:00, after 22:00, over lunch), single-day counts (3/5/10/20 tasks in one day), streak lengths (7 up to 365 days), calendar patterns (weekend pair, a Monday, the 1st of a month, a full calendar month, a comeback after a broken streak) and lifetime totals (active days and completed tasks up to 1000)
- Completion times are now recorded alongside the daily counts (from this version on), powering the time-of-day challenges; untoggling a task removes its time again

## [0.1.132] - 2026-08-06
- Synced mode now also writes an Obsidian-friendly Markdown checklist (besttodo_tasks.md) next to the JSON file - point your sync folder into an Obsidian vault and your tasks render as a native checklist, grouped by the same tabs as the app
- Checkboxes and dates follow the Obsidian Tasks plugin format (📅 due date, ✅ completion date), so community plugins can query your list too
- The Markdown file is one-way for now: it is overwritten on every sync, so edits made in Obsidian stay in Obsidian

## [0.1.130] - 2026-08-06
- Settings has a new Backup section: choose a folder and the app writes a full backup of everything (tasks, settings, timers) there automatically - daily, weekly, or never
- Daily backs up the first time you open the app each day, weekly once seven days have passed; a "Back up now" button writes one on demand and the section shows when the last backup ran
- Each backup is a single timestamped file that the existing Import button can restore
- Synced mode: choose between fully offline (as before) and syncing your tasks to a folder of your choice — Settings → Sync & export, pick the folder once and you're set
- The sync runs in the background every time you leave or quit the app, so it never slows down startup or gets in your way
- App Logs got a "Sync" tab showing every sync: when it ran, how long it took and how many items it wrote — failures show up in red with the reason
- If a sync fails (folder deleted, drive unplugged, ...), a little red dot appears on App Logs in the main menu; opening the page clears it, and the next successful sync does too
- Sync writes are atomic: a crash or an unplugged drive mid-sync can never leave a half-written file behind

## [0.1.129] - 2026-08-05
- Test Results now shows detail even when everything passes: an "All tests" section lists every test file with its own pass/fail/skip counts and time, and expanding a file shows each test with a green/red/grey mark and how long it took
- Files with failures sort to the top, and the summary line now includes the total test time ("ran in 42.3 s")
- The CI job summary gets the same per-file table, so the app and CI always tell the same story; older reports without per-test details say so instead of showing nothing

## [0.1.128] - 2026-08-05
- Home-screen task widget: tapping the progress line, or a task row next to its checkbox, now always opens the app on the task list - even if the app was left on settings or another page
- Test Results now always shows the newest test run there is, whichever branch it came from — no more empty page because the branch you built from was not the one that last ran the tests
- The results are packaged into every build, so the page works with no network at all: a fresh checkout, a release APK on a plane, or the app running in the browser all show real numbers
- The page says how old the run is ("Ran 3 hours ago on dev"), where the numbers came from, and links straight to the CI run that produced them; refreshing pulls the latest and keeps it for the next offline start

## [0.1.127] - 2026-08-05
- Dice timer: a "Cancel timer" button ends a running, paused or ringing timer and drops its alarm with it — the task is left exactly as it was, neither done nor postponed
- Cancelling returns to the home page with a "Timer cancelled" note and the dice goes back to offering a fresh roll; leaving the page with the back arrow still keeps the countdown running, as before

## [0.1.126] - 2026-08-05
- Introduction: the welcome slides are back — the app no longer opens straight on the simple/full mode question, the three intro screens run first and the mode choice is now their closing page
- About → "Replay Introduction" now replays the whole thing, slides and the simple/full mode choice, instead of only the slides

## [0.1.125] - 2026-08-05
- Home-screen widget: a new setting lets you tick tasks off straight on the widget — Settings → Widget → "Check off tasks on the widget", off by default so the widget stays the plain text summary
- With it on, the widget lists today's tasks as rows with a checkbox: tapping the box completes (or un-completes) the task without opening the app, tapping the task name opens it
- Open tasks come first, finished ones stay underneath so a mis-tap is one tap away from being undone, and a "+N more" line shows what did not fit
- Ticking a task off on the widget counts toward your streak and shows up in the app the moment you open it again

## [0.1.124] - 2026-08-05
- Productivity Stats: the item activity heatmap no longer washes out — a single freakishly busy hour used to leave every other slot the same pale shade
- Colours now follow a logarithmic scale that tops out just above your normal range, so quiet, average and busy hours are told apart at a glance while the outlier simply maxes out
- Each activity tab gained a legend showing which count each shade means, plus a note of the busiest slot

## [0.1.123] - 2026-08-05
- Settings: every section now folds away — tap a title (or its chevron) to open and close it, so you only see the part you came for
- Settings: a "Collapse all" / "Expand all" button sits at the top of the page
- Settings: "Mode & features" starts collapsed, and jumping to a section from a chip or from the search opens it for you

## [0.1.122] - 2026-08-05
- Dice timer: when the countdown ends and you are not on the timer page, it now rings like a real alarm — the whole screen, one button to stop it, even with the app closed or the phone locked
- Stopping that alarm drops you straight back on the timer with Done, Postpone to tomorrow and +1/+5/+10 min ready
- Your alert choice decides how loud it is: the melody at your volume, vibration only, or a quiet takeover — Silent still stays completely out of the way
- Starting a timer asks once for the alarm permissions Android needs so the ring survives a closed app

## [0.1.121] - 2026-08-05
- Simple mode keeps the drawer's own pages: Deleted Items, About, Changelog, App Logs and Startup Times are all reachable again — simple mode only strips the tools and the extras off the task list

## [0.1.120] - 2026-08-05
- Dice timer settings: choose what happens at zero — the alarm melody (with its own melody and volume), vibration, a notification (the default) or completely silent, where the dial just shows 0:00
- With notifications switched off, the default dice timer alert stays quiet too: no fallback sound, just 0:00 on the dial
- An "Also vibrate" switch adds a buzz to the melody or notification alert, and the dial's pre-wound default length (20 min) is now yours to pick
- Reach all of it from the new "Dice timer" settings section or the gear on the timer page itself, melody preview included

## [0.1.119] - 2026-08-05
- Changelog page: a new button switches to an update heatmap — a GitHub-style calendar of every release, greener the more releases that day
- Tap any day in the heatmap to see exactly which versions shipped that day and what changed in them
- The heatmap's month labels show the year whenever it changes (e.g. "Dec 2025" → "Jan 2026"), so a multi-year history stays readable

## [0.1.118] - 2026-08-05
- First launch now asks whether you want simple mode (just the to-do list) or full mode (everything) — you can switch any time in Settings
- Simple mode keeps only the task list: no tools, no streak flame, no dice, no schedule view and no search — the drawer is down to Settings, Deleted Items and About
- New Settings section "Mode & features": switch between simple and full mode, bring the welcome picker back, and in full mode pick exactly which features you want (each tool, streak, dice timer, schedule view, task search, deleted items, changelog, app logs, startup times, daily SMS report)
- A feature you switch off disappears everywhere at once — drawer, app bar and its own settings section — and can no longer be the app's start page
- Settings: tapping a section chip now always lands on that section — jumping backwards (or far down a long settings page) used to do nothing

## [0.1.117] - 2026-08-05
- SMS report: recipients can be switched off individually instead of deleted — paused contacts stay in the list and are skipped by the daily report.

## [0.1.116] - 2026-08-05
- Demo builds (Chrome) now start with a 50-day streak so the flame and streak page have history to show.

## [0.1.115] - 2026-08-04
- streak: a flame next to the dice tracks your daily completion streak — it grows and gets hotter every day you complete at least one task, reaching maximum fire after a year
- streak: tapping the flame opens the streak page with a fun animated flame, fun stats (longest streak, best day, days until maximum fire, ...) and the streak settings
- streak: completing the first task of the day plays a short flame celebration (can be turned off)
- streak: existing completion history counts — your flame starts warm from day one
- Settings → Streak: hide the streak, choose a 24h or 48h grace period (48h forgives one missed day), and enable an evening reminder (default 22:00) that nudges you when no task is done yet that day

## [0.1.114] - 2026-07-25
- Local builds now pull the latest CI test report from GitHub so the in-app Test Results page shows real results offline

## [0.1.113] - 2026-07-17
- Updating never loses data, no matter which version you come from: before this version writes anything, it snapshots all your existing data files (tasks, deleted list, stats, wishlist, alarms, projects, labels, timers, settings) into a `pre_update_backup/` folder — once, kept forever, visible in App Logs ("Pre-update backup created")
- Every save of tasks, the deleted list, daily stats, timers and alarms is now atomic (written to a temp file, then swapped in) and keeps the previous version as a `.bak` — a crash or full disk mid-save can no longer corrupt a file
- If a data file is ever unreadable (torn write, bad migration), the app now restores the last good `.bak` instead of silently starting empty, and moves the unreadable file aside as `.corrupt-<timestamp>` for manual recovery — the old behavior would have overwritten your data on the next save
- The app records which version last wrote your data (`last_run_version.txt`) so future updates can take version-specific precautions
- Two saves of the same file landing at the same moment (e.g. deleting an item and tapping Undo right away) now queue up instead of tripping over each other's temp file — the last save always wins cleanly
- How to test: this is file-level safety, so Chrome (which has no files) can't exercise it — use the unit matrix and a desktop/Android drill. Units: `flutter test test/core/upgrade_safety_test.dart test/alarms/alarm_storage_recovery_test.dart` covers payload shapes from the earliest era (no uids) through the analytics, projects and wishlist eras to schema v2, plus corruption recovery and the snapshot. Manual drill (e.g. Windows): run any older build, add tasks/alarms/wishes, then run this build — everything is still there, App Logs shows "Pre-update backup created", and the documents folder contains `pre_update_backup/` with the original files plus `tasks.json.bak` after the first save. Corruption drill: close the app, mangle `tasks.json` in an editor, reopen — your tasks come back from the `.bak` and the mangled file sits next to it as `tasks.json.corrupt-<timestamp>`

## [0.1.112] - 2026-07-17
- Internal: all pages now access tasks, the deleted list, daily stats and item history through one repository interface, completing the item-model migration. A written decision record (docs/architecture/storage-decision.md) documents why storage stays on fast JSON files for now — startup speed is the top priority — and exactly what would trigger a move to a database later. No visible change
- How to test (dev build, `flutter run -d chrome`; behavior-preserving seam — testing = a regression sweep over everything the repository now carries): (1) tasks — add a task, check one off, swipe-delay one; the list updates and (on the Deleted Items page) the deleted list follows. (2) history — a board card's details still show its (dev-seeded) History timeline, now read through the repository. (3) the earlier walkthroughs (0.1.106–0.1.111 below) all still pass unchanged on this build — they are the acceptance test for the seam. Delegation itself is unit-tested in `test/core/item_repository_test.dart`; the storage trade-off rationale is in docs/architecture/storage-decision.md

## [0.1.111] - 2026-07-17
- Internal: every view of your items — home tabs, wishlist, project boards and cards — now runs through one shared query layer over the single task list, instead of each page filtering on its own. No visible change; behavior and speed are identical, and future custom filters/saved views become straightforward
- Dev builds seed one wishlist item ("Learn to sail", priority-medium) so the Wishlist view has data in the browser, where the one-time Todo.md import has no files to run from
- How to test (dev build, `flutter run -d chrome`; this release is a behavior-preserving refactor, so testing = confirming every view still shows the right items): (1) Home tabs — the seeded tasks appear on Today (incl. "Deep work block"), the spread-out dev tasks on Tomorrow through Next Month, undated/wish items on Future; search narrows every tab the same as before. (2) Wishlist — Tools → Wishlist shows "Learn to sail" (and it appears wish-tagged at the bottom of Future). (3) Boards — Tools → Projects: card counts match the tasks listed per project, and each board column holds exactly the tasks whose stage pill says To-Do/Ongoing/Closed; drag a card between columns and check the count and pills follow. All view membership logic is now unit-tested directly in `test/core/item_views_test.dart`

## [0.1.110] - 2026-07-17
- Alarms can now belong to a task: open a task's details and tap "Remind me 15 min before due" — one tap, done. The reminder then takes care of itself: rescheduling the task moves it, completing the task silences it, deleting the task removes it, and renaming the task renames it. Reminders ring through the same battle-tested alarm pipeline as regular alarms (escalation ladder, verification, watchdog); regular alarms are completely unaffected
- How to test (dev build, `flutter run -d chrome`): a fresh dev start attaches a reminder to the seeded "Deep work block" task (09:00–10:30 → fires 10:15). See it in two places: its task details (Tools → Projects → first board → tap the card) show "Reminder … 10:15" with a remove button, and the Alarms tool lists an alarm named "Deep work block". Now exercise the sync: check the task off on Today → the alarm's toggle switches off; rename the task (pencil on its tile) → the alarm renames; delete the task → the alarm disappears. Create your own: open any dated task's details → tap "Remind me 15 min before due". Actual ringing needs Android (notifications don't fire on web) — the scheduling pipeline itself is unchanged and covered by `test/alarms/`

## [0.1.109] - 2026-07-17
- Tasks can now carry a real time range (start and end) instead of only a single due moment — groundwork for showing durations on the timeline and calendar. Existing tasks upgrade automatically the first time they are read (deadline = start and end at the same moment); files are written with a version stamp plus the old due-date field, so older app versions and old backups keep working both ways
- Task details show Start / End / Duration for tasks that have a real range (deadline-style tasks keep just their Due line)
- How to test (dev build, `flutter run -d chrome`): a fresh dev start seeds "Deep work block" on the Today tab — a task scheduled 09:00–10:30. Open Tools → Projects → the first project's board → tap the "Deep work block" card → details show Start 09:00, End 10:30, Duration 1h 30m (the task is also visible on the Today tab at 09:00–10:30). Compare with any ordinary task: no range lines, just Due. Round-trip safety (v1 → v2 upgrade, dueDate mirror, partial payloads) is covered by `test/core/task_schedule_test.dart`

## [0.1.108] - 2026-07-17
- Labels are now tracked as first-class entries (in labels.json) with a kind — regular tag, wishlist priority, or app marker — and room for a colour, laying the groundwork for coloured tags and label filtering. Nothing changes in how you type or see labels: the registry fills itself in the background from the labels you already use, with no effect on startup or save speed
- Task details now annotate each label with its registry kind, e.g. "urgent (tag) · priority-high (priority)"
- How to test (dev build, `flutter run -d chrome`): a fresh dev start labels the first board task "urgent, priority-high" and the second "gift, old" — the labels show as tags on their home tiles (Future tab), and Tools → Projects → board → tap a card shows the kind annotations: urgent (tag), priority-high (priority), gift (tag), old (system). Add your own label to any task (pencil on its tile) and reopen its details — the new token is registered and annotated the same way

## [0.1.107] - 2026-07-17
- Task history timelines now reach back before the journal existed: on first launch after updating, the app reconstructs each task's past (created, rescheduled, completed, deleted, restored) from its stored timestamps, the deleted list and the daily stats — marked "(reconstructed)" in the timeline. The backfill runs once, a few seconds after startup, so launching stays as fast as before
- How to test (dev build, `flutter run -d chrome`): open Tools → Projects → a project board → tap the second card — its History shows entries suffixed "(reconstructed)" dated weeks back (dev-seeded, since the browser has no stored pre-journal data to backfill from), interleaved correctly before any live entries you create by editing the task. The real backfill (timestamps + deleted list + daily stats → seeded events, guarded by `item_events_seed_v1.txt`, run 3 s after launch) is exercised by `test/core/item_history_seeder_test.dart` and on an Android/desktop install with existing data

## [0.1.106] - 2026-07-17
- Every change to a task — edits, rescheduling, completing, project moves, label changes, deletes and restores — is now recorded in an on-device history journal; open a task's details (e.g. from a project board) to see its timeline. Recording happens in the background after each save and the journal is only read on demand, so app startup and list interactions are exactly as fast as before
- Exports now include the exact recorded history (`item_events`) alongside the reconstructed `task_events`
- How to test (dev build, `flutter run -d chrome`): a fresh dev start pre-seeds a ready-made history on the first project-board task — open Tools → Projects → tap a project's board button → tap the first card → the details page shows a History section ("Created", "Rescheduled to …", "Edited description"). Then verify live recording: back on the home list, rename any task, check one off, or swipe-delay it, and reopen its details from the board — each action appears as a new History line. On Chrome the journal lives in memory for the session (no files on web); on Android/desktop it persists in `item_events.jsonl`

## [0.1.105] - 2026-07-19
- Countdown: the # bell is now a full milestone menu — tap it on any timer to set as many notifications as you like, each at any number of any unit (seconds, minutes, hours, days, weeks, months or years), and choose whether each one fires before the event, after it, or both
- Countdown: months and years now follow the calendar, so "10 months before" lands on the same day of the month rather than 304 days out
- Countdown: new timers start with 10 years, 10 months, 10,000,000 seconds, 10 weeks, 100,000 minutes, 1,000 hours and 10 days — existing timers keep notifying and pick up the same defaults; "Defaults" in the menu restores them at any time

## [0.1.104] - 2026-07-19
- Dev builds: the wishlist backlog now repopulates even after the one-time import flag has been spent (idempotent, dev-only).

## [0.1.103] - 2026-07-17
- Countdown: new per-timer round-number bell (# icon next to the zero bell) — get a notification whenever the remaining time crosses a round number of seconds: 1,000,000,000 down to 1,000 in powers of ten (100,000 seconds is about 1.2 days before the event)
- Countdown: timers can now be set in the past — the date picker goes back to 1900, so you can track how long since your birthday or any other past event (past timers count up, and the expanded card shows the total in days, weeks, months and years)
- Countdown: the round-number bell also works for past timers counting up — get a notification when the elapsed time crosses a round number of seconds (e.g. 1,000,000,000 seconds since your birthday, about 31.7 years)

## [0.1.102] - 2026-07-10
- New minimalist mode in Settings → Appearance: a calm, monochrome ink-on-paper look with no accent colours, flat surfaces, and underlined (instead of highlighted) selections; works in both light and dark mode
- Wishlist rebuilt as a filtered view of your one task list: wish items now live with your tasks (old wishlist entries are moved over automatically), show up as normal editable tasks on the Future tab tagged "wish", and the Wishlist page looks like a to-do list — checkboxes, no due dates, and the same swipe gestures as home, except swiping right raises an item's priority (hold for one step up, or tap high/medium/low) and sorts it up the list, while swiping left moves it to the deleted list with Undo

## [0.1.100] - 2026-07-09
- Wishlist items now also show up at the bottom of the Future tab, tagged "wish" — read-only there, tap one to open the Wishlist tool; the home search filters them like tasks, and they stay out of your real task list
- One-time import: the still-open ideas from the old Todo.md backlog are added to your wishlist tagged "old"; items you already have (same title) are skipped, nothing existing is changed or removed, and re-deleting an imported item sticks

## [0.1.99] - 2026-07-09
- Test Results moved into the Tools menu; it now pulls the latest CI test results from the dev build online (the report bundled in your APK is used as an offline fallback) and clearly shows the app version you are running versus the version the tests were run against.

## [0.1.98] - 2026-07-09
- projects: dragging tasks onto projects (and cards between Kanban columns) now works with a plain mouse drag on desktop and in a desktop browser (e.g. Chrome on a laptop) — no long-press needed; touch devices keep the long-press drag so scrolling still works, and the hint text on the Projects page matches the input mode
- dev builds: the Projects tool comes prepopulated — nine of the dev-seeded future tasks are spread across the three seed projects, one per Kanban column each, so the project cards and boards have data to drag around right away (also on desktop/web); manual assignments are never reshuffled

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
