# CLAUDE.md — AI working guide for BestToDo

## Every request ends on `dev` (standing rule from the owner)

Any request that changes files is finished only when the work is **merged into
`dev` and pushed**, without being asked: commit on the working branch, merge
`origin/dev` into it (resolve conflicts, keep both sides' intent), run the repo's
checks, then merge the branch into `dev` and `git push origin dev`. Report the
`dev` commit. `staging`/`main` only when the request says so. If the merge or
push can't be done, say exactly why. `.claude/hooks/require-merged-to-dev.sh` (a Stop
hook in `.claude/settings.json`) blocks stopping while commits or tracked changes
are not on `dev`.

Flutter to-do app (Android-first, Windows desktop used for tests/screenshots).
Best Music, once a second app built from this repo, lives in its own repo
since 0.2.111: `Mfficiency/BestMusic` (`D:\Code\BestMusic`).
Read `SPEC.md` for the full rebuild-grade spec and development history — this
file is the short operational guide.

## Commands

- Analyze: `flutter analyze --no-pub` (pre-existing infos/warnings exist; add none)
- Tests: `flutter test` runs everything (CI does this). Locally, run only the
  suites your change touches — `test/core/` always, plus the matching silo:
  `flutter test test/core test/<area>` where `<area>` is `alarms`, `projects`,
  `home`, `share`, `sync`, `update`, `tools` or `recurrence`. See `test/README.md` for the file→suite map. Cross-cutting
  changes (theme, navigation, pubspec) → full `flutter test`.
- Smart test runner: `dart run tool/smart_test.dart` figures the above out for
  you — it looks at what's changed (working tree, or the last commit if
  nothing's pending) and runs only the matching `test/<area>` suite(s), per
  the same map as `test/README.md`. A change it can't confidently map (a new
  file, `pubspec.yaml`, ...) falls back to a full `flutter test`; so does
  every 10th targeted run and anything past 7 days since the last full run,
  so the shortcut can't silently drift out of sync with the real suite.
  `--dry-run` prints the decision without running anything; `--full` forces a
  full run now. State (mods since the last full run) lives in the gitignored
  `.smart_test_state.json`.
- Screenshots: `flutter test integration_test/home_page_screenshot_test.dart -d windows`
  → PNGs in `build/e2e_screenshots/` (CI archives them to `docs/screenshots/home/` and
  prepends `SCREENSHOT_CHANGELOG.md` on push to dev/staging/main). `docs/screenshots/music/`
  is the archive of Best Music's screenshots from before it moved out.
- **Releases come from the laptop builder only** (SPEC.md §11 "Laptop channel builds"):
  every push to `dev`/`staging`/`main` dispatches `laptop-build.yml` → the laptop runs
  `powershell -File tool\build.ps1 release` with `BUILD_CHANNEL` (dev/staging/main),
  `BUILD_NUMBER` and `PUBLISH=1`: BestToDo's APK for that channel, signed
  with the upload key (`android/key.properties`, required), as a GitHub release
  (tag `v<x.y.z>-<build>[-dev|-staging]`), after committing the APK to
  `github_releases/<channel>/` and pushing that commit (`[skip ci]`, so it doesn't trigger
  another build). A HEAD that only changes `github_releases/` builds the commit below it
  (released already → nothing to do). Before building, `build.ps1 release` compares the source with the newest 20 `v…` releases, on every channel (`Find-ReleaseWithSameCode`: a fingerprint of all tracked files except the APK folders, screenshots, `.github/`, build history, test report and build-time changelog lines); the same code released already (a dev → staging → main merge) builds and publishes nothing, so the phone is never offered the same update twice. `FORCE_RELEASE=1` skips that check. All channels build the **same app** (one
  applicationId and name; the About page shows the channel next to the version), and
  the updater takes the highest build number over the releases of all channels.
  `BUILD_NUMBER` = minutes since 2020-01-01 UTC of the source commit's committer time
  (computed by the builder, already skipping APK commits; used as is). Local test build without publishing: set `BUILD_CHANNEL=dev`,
  `BUILD_NUMBER=12345`, leave `PUBLISH` unset, run the same command. GitHub CI only builds
  (artifacts) — it no longer publishes or commits builds.
- Release APK: `flutter build apk --release --flavor todo` (signed with the committed debug
  keystore unless `android/key.properties` exists). `android/app/build.gradle.kts` defines one
  flavor, `todo` (`tool/build.sh` defaults to it when `--flavor` is omitted; the `music`
  flavor is gone with Best Music). The rename to `best_todo_<version>.apk` is done by Gradle's
  `createVersionedTodoReleaseApk` task, wired to `assembleTodoRelease` and reading that
  flavor's own `app-todo-release.apk` (`build/app/outputs/flutter-apk/` is never cleaned
  between builds, so guessing from whatever APK sits there once picked up a leftover).
- Build everything + ship: `sh tool/build.sh all --release` (alias for
  `sh tool/build_all.sh --release`), or on Windows without Git Bash/WSL:
  `powershell -ExecutionPolicy Bypass -File tool\build.ps1 all --release`.
  Builds the APK **and** the Windows exe, stages the APK into `github_releases/`, then
  commits and pushes the current branch.
  Switches: `SYNC=0` (no git), `PUSH=0` (commit only), `WINDOWS=0`/`ANDROID=0`
  (one target), `REQUIRE_WINDOWS=1` (a failing
  Windows build aborts instead of warning).
- **Legacy:** `github_releases/` (last 2 APKs) is only read by installs older
  than 0.2.101; current apps read GitHub releases. Keep the folder, don't rely on it.
  `dart run tool/stage_local_release.dart` after a
  release build (`tool/build.sh` does it automatically). Copies the APK to
  `github_releases/` and deletes the older ones; commit the folder. The current updater
  never reads it (only GitHub releases); installs older than 0.2.101 did.
- Build time, duration & size: `tool/build.sh`/`tool/build.ps1` time the
  `flutter build` call and, on success, run
  `dart run tool/append_build_time.dart --duration <secs> --target <apk|windows|...> --artifact <apk or Release dir>`,
  writing/updating a "Local build: <time>" line, a per-target
  "Build duration (<target>): <time>" line and an "APK size: <MB>" line (or
  "Build size (<target>)") in that version's CHANGELOG.md entry, and appending
  `{version, app, target, durationSeconds, sizeBytes, source, finishedAt, os}` to
  `build_history.json` (committed, capped at the newest 1000 entries) so build times and
  app size are tracked over time. (CI used to record its builds the same way with
  `--source ci` and commit them to `dev`; it no longer commits anything, and the laptop's
  `build.ps1 release` puts build time/duration/size in the release notes instead.)
  Since CHANGELOG.md is bundled as an asset by that same build, the Changelog page
  only ever shows the *previous* build's time/duration — expected, not a bug.
- Publish APK to GitHub: `dart run tool/publish_apk.dart
  [--channel main|staging|dev] [--build-number N] [--apk <path>]` (what `build.ps1 release`
  calls). Creates release `v<x.y.z>-<build>` (`-dev`/`-staging`
  suffix + prerelease for those channels); the About page "Check for updates" button
  downloads and installs it in-app. Token from `GITHUB_TOKEN`/`GH_TOKEN` or a logged-in `gh` CLI.
- In-app updates (SPEC.md §11 "Shared updates package") are the shared
  `mfficiency_updates` package, **vendored** from flutter_app_template into
  `packages/mfficiency_updates` (path dependency; its README.md is the reference). **Never
  edit that copy**: change the package in the template, run its tests, then run the
  template's `tool/sync_updates_package.sh <this repo>` (`.ps1` on Windows), which rewrites
  the copy + its `ORIGIN`; `test/updates_package_vendored_test.dart` fails on a hand edit.
  The behaviour is the package's defaults (same in every Mfficiency app); don't work around
  it in the app. `lib/services/app_updates.dart` (`AppUpdates`) only passes app-specific
  config: one `UpdateController` (`AppUpdates.controllerFor`) made in `main()`
  (`UpdatesApp.todo`, tag prefix `v`; public repo `Mfficiency/best_todo_2`, `privateRepo` false;
  optional read-only token from Settings → Updates in `flutter_secure_storage` via
  `AppUpdates.readToken`/`saveToken` = `tokenProvider` + `reloadToken()`, so a repo turned
  private keeps updating; checks
  every 15 minutes, also on resume when due; the "Automatically update" switch =
  `UpdateConfig.autoCheck`, Settings calls the controller's `autoCheckChanged()`; `music-v…`
  releases here are Best Music's bridge releases, never offered), started after the first
  frame; `promptAllowed` (`AppUpdates.promptAllowed`, false while the
  intro/pickers are open) and `beforeInstall` = the package's `FullBackup.beforeUpdate`
  (`AppUpdates.backup`, made first thing in `main()` by `AppUpdates.createBackup`: every
  file in the app's folders + SharedPreferences to `Download/BestToDo/Backups/*.tar.gz`,
  kept across uninstalls, `pre_update_backup/` excluded; Settings → Backup shows
  `FullBackupTiles`, a new install gets `offerRestore` after the first frame); the old update
  prefs through the package's `migrateLegacyUpdateState`. GitHub's rate limit pauses the
  automatic checks (package). Releases without an APK are never offered. Behaviour: **every** download is silent (into the app cache; one SnackBar for a
  tap, progress only as passive text on the Changelog's `UpdateStatusCard` and the Check for
  updates tile); when complete, Android's installer app (the plugin's `installApk`:
  `ACTION_INSTALL_PACKAGE` to the installer, a PackageInstaller session as fallback) asks
  the only question and ends with "App updated" + Open — in the foreground, once per build and start; a
  cancel leaves the slim `UpdateBanner` ("Update ready" + Install), a failed download one
  with Try again. Pull-down on the Changelog checks; tapping a version there offers it
  (older = rollback). `MainActivity`/the manifest have no update code (the plugin brings
  `REQUEST_INSTALL_PACKAGES`, its receiver and channel; registered by Flutter). Tests fake
  it with `test/update/update_fakes.dart` (`fakeController` = `controllerFor` on fakes; the
  full backup only when a `FullBackup` is passed as `backup:`).
- Test results shown in-app come from `assets/test_report.json`, packaged into every
  build. CI keeps it current; locally refresh it with
  `dart run tool/sync_test_report.dart` (pulls the newest CI run from the `ci-reports`
  branch), or from your own run:
  `flutter test --machine > build/ci/machine.jsonl` then
  `dart run tool/sync_test_report.dart --no-fetch --candidate-machine build/ci/machine.jsonl`
- Version bump: `dart run tool/bump_version.dart <version> "<changelog entry>"`
  or edit `pubspec.yaml` (`x.y.z+build`, both parts increment) + prepend `CHANGELOG.md`.
- Wear OS companion (`wear/`, own Gradle build, never part of `android/`): see
  `wear/README.md` (sync paths `/todo/today`, `/todo/alarms`, `/todo/command/complete`;
  phone side `lib/services/wear_sync_service.dart`, `WearSync.kt`, `WearCommandService.kt`;
  watch commands are queued natively and applied by the home page, never written to
  tasks.json from Kotlin). `build.ps1 release` builds it after the phone (`WEAR=0` skips) and
  publishes `wear-v…` releases. Pure watch logic: `./gradlew -p wear test`.
- Obsidian plugin (`obsidian-plugin/`, own npm package — not part of the Flutter
  build): `npm ci && npm test && npm run build` there; CI job `obsidian_plugin.yml`

## Workflow ("bump, sync and build")

1. Bump version + CHANGELOG entry for every feature batch.
2. Commit to `dev`, push (`sync`). Branch flow: feature → dev → staging → main.
3. `flutter build apk --release` when a release is asked for.
4. Keep `SPEC.md` updated when adding/changing features (it must stay
   rebuild-grade). Deep-dive docs live in `.claude/` — `.claude/README.md` is
   the index (rebuild playbook, testing, CI/automation, environment,
   engineering principles, alarm-work history).

## Architecture in one minute

- `lib/models/` — plain mutable models with `toJson`/`fromJson` (tolerant of
  missing keys). `Task` is the core; tasks live in one list, bucketed into
  tabs by `dueDate` distance (Today/Tomorrow/Day after/Next week/Next
  month/Future).
- `lib/services/` — singletons or small classes persisting JSON files in the
  app documents dir (`flush: true`, errors swallowed so web/tests keep
  working). Examples: `StorageService` (tasks), `AlarmService`+storage,
  `ProjectService` (`projects.json`, seeded with 3 placeholder projects).
- `lib/ui/` — pages; `home_page.dart` is the hub (drawer, tabs, search,
  add-task row). Subpages use `buildSubpageAppBar`.
- Alarms are the reliability showpiece (escalation ladder + watchdog +
  `alarm_log.txt`); do not touch scheduling paths without reading SPEC §5.
- Android widgets: `android/.../AlarmsWidgetProvider.kt` (alarms list; taps
  route via `besttodoalarm://` URIs handled in `main.dart`) and
  `SimpleWidgetProvider.kt` (today's tasks).

## Conventions

- Tests live in per-area suites (`test/core|alarms|projects|home|tools/`);
  add new tests to the suite matching the feature, new directory for a new
  feature area. Core is reserved for task model/persistence/bucketing + smoke
  tests.
- Tests mirror existing style: plain `test()` for logic, `testWidgets` with
  `MaterialApp(home: ...)` for widgets, `_FakePathProvider extends
  PathProviderPlatform` + temp dir for anything touching persistence.
  `ProjectService.instance.resetForTest()` between tests.
- **Real file I/O hangs inside `testWidgets`** (the fake-async zone never
  services dart:io completions — locally AND on CI; the unmitigated pattern in
  startup_times_page_test kept `flutter_test.yml` red from 0.1.87 until fixed):
  - Create temp dirs / pre-save files in `setUp` (outside the fake zone) or
    wrap in `await tester.runAsync(() => ...)`.
  - I/O started inside the widget (initState loads, save-on-tap): a single
    runAsync delay only advances ~one I/O hop. Loop rounds of
    `runAsync(delay 5ms)` + `pump()` — condition-driven for loads (until a
    marker widget appears), FIXED count (~60) after taps whose handler awaits
    a write before setState (in-memory state updates before the write ends,
    so polling exits too early). See home_search_test / project_board_page_test.
  - Always run with `--timeout 60s` locally so hangs fail fast.
- `find.byType` matches exact runtimeType: `FilledButton.icon(...)` builds a
  private subtype, so find its label text instead.
- Never dispose `TextEditingController`s right after `showDialog` returns —
  the exit animation still builds the fields; give the dialog its own
  StatefulWidget owning the controllers (see `_ProjectEditDialog`).
- `Config.isDev` is true in debug/tests → dev seed data appears when storage
  is empty; widget tests that need deterministic lists should pre-save tasks
  via `StorageService` first.
- UI text findable by tooltip is the norm for icon buttons ("Save", "Edit
  project", "Clear search", "Open navigation menu").
- Don't introduce new deprecation warnings; existing `withOpacity`/
  `onWillAccept` infos are legacy and get cleaned opportunistically.
- Changelog entries are user-facing bullet points under `## [x.y.z] - date`.
- **Standing rule — MLR (and Lemmon) items stay out of the main views**:
  any task tagged/labeled `mlr` shows inside the Worklist tool and, only when
  the drawer's Home row has its **MLR** toggle switched on (default off), in
  the regular home tabs and schedule view — never in the Wishlist,
  Projects/board, the home-screen widget, Wear or the Markdown export. The
  `lemmon` tag works the same way (Tools ▸ Lemmon, **Lemmon** toggle). The
  owner asked for the MLR rule once and for the toggles in 0.2.123; neither
  needs to be requested again. Enforced structurally in
  `ItemViews.isVisibleInMainViews` (`lib/services/item_views.dart`), the same
  gate Food Diary/Research/Groceries use, via `worklistToken`/`lemmonToken`
  in `lib/utils/label_utils.dart`; the toggles (`HomeContexts`,
  `Config.homeContexts`) are a parameter of `ItemViews.isOnHomeScreen`, not a
  second filter. When touching task-visibility filtering (home tabs, schedule
  view, wishlist, projects, the home-screen widget), preserve this gate rather
  than reintroducing a path that reads `_tasks`/the task list unfiltered.
  Both home bodies must go through `ItemViews.isOnHomeScreen` — the tabs via
  `homeBucket`, the schedule view via `homeVisible` — so the Home filter
  rules, the context toggles and the demo gate can never apply to one and not
  the other (that leak was 0.2.46's bug).
