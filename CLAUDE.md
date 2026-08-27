# CLAUDE.md — AI working guide for BestToDo

Flutter to-do app (Android-first, Windows desktop used for tests/screenshots).
Read `SPEC.md` for the full rebuild-grade spec and development history — this
file is the short operational guide.

## Commands

- Analyze: `flutter analyze --no-pub` (pre-existing infos/warnings exist; add none)
- Tests: `flutter test` runs everything (CI does this). Locally, run only the
  suites your change touches — `test/core/` always, plus the matching silo:
  `flutter test test/core test/<area>` where `<area>` is `alarms`, `projects`,
  `home`, `share`, `sync`, `update`, `tools` or `recurrence`. See `test/README.md` for the file→suite map. Cross-cutting
  changes (theme, navigation, pubspec) → full `flutter test`.
- Screenshots: `flutter test integration_test/home_page_screenshot_test.dart -d windows`
  → PNGs in `build/e2e_screenshots/` (CI archives them to `docs/screenshots/home/` and
  prepends `SCREENSHOT_CHANGELOG.md` on push to dev/staging/main)
- Release APK: `flutter build apk --release` (signed with the committed debug keystore)
- Keep the last 2 APKs in the repo: `dart run tool/stage_local_release.dart` after a
  release build (`tool/build.sh` does it automatically). Copies the APK to
  `github_releases/` and deletes the older ones; commit the folder — the app's About page
  downloads the newest from there ("Download & install") and the other one for
  "Go back to <version>" (`UpdateService.releasesRef` = the `dev` branch)
- Publish APK to GitHub: `dart run tool/publish_apk.dart` after a release build
  (or `PUBLISH_APK=1 sh tool/build.sh apk --release` to build + publish). Creates
  release `v<x.y.z>-<build>` with asset `BestToDo-<x.y.z+build>.apk`; the About
  page "Check for updates" button downloads and installs it in-app. Token from
  `GITHUB_TOKEN`/`GH_TOKEN` or a logged-in `gh` CLI.
- Test results shown in-app come from `assets/test_report.json`, packaged into every
  build. CI keeps it current; locally refresh it with
  `dart run tool/sync_test_report.dart` (pulls the newest CI run from the `ci-reports`
  branch), or from your own run:
  `flutter test --machine > build/ci/machine.jsonl` then
  `dart run tool/sync_test_report.dart --no-fetch --candidate-machine build/ci/machine.jsonl`
- Version bump: `dart run tool/bump_version.dart <version> "<changelog entry>"`
  or edit `pubspec.yaml` (`x.y.z+build`, both parts increment) + prepend `CHANGELOG.md`
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
