# CLAUDE.md — AI working guide for BestToDo

Flutter to-do app (Android-first, Windows desktop used for tests/screenshots).
Read `SPEC.md` for the full rebuild-grade spec and development history — this
file is the short operational guide.

## Commands

- Analyze: `flutter analyze --no-pub` (pre-existing infos/warnings exist; add none)
- Tests: `flutter test` (unit + widget tests in `test/`)
- Screenshots: `flutter test integration_test/home_page_screenshot_test.dart -d windows`
  → PNGs in `build/e2e_screenshots/` (CI archives them to `docs/screenshots/home/` and
  prepends `SCREENSHOT_CHANGELOG.md` on push to dev/staging/main)
- Release APK: `flutter build apk --release` (signed with the committed debug keystore)
- Version bump: `dart run tool/bump_version.dart <version> "<changelog entry>"`
  or edit `pubspec.yaml` (`x.y.z+build`, both parts increment) + prepend `CHANGELOG.md`

## Workflow ("bump, sync and build")

1. Bump version + CHANGELOG entry for every feature batch.
2. Commit to `dev`, push (`sync`). Branch flow: feature → dev → staging → main.
3. `flutter build apk --release` when a release is asked for.
4. Keep `SPEC.md` updated when adding/changing features (it must stay
   rebuild-grade). Deep-dive notes live in `.claude/notes/`.

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

- Tests mirror existing style: plain `test()` for logic, `testWidgets` with
  `MaterialApp(home: ...)` for widgets, `_FakePathProvider extends
  PathProviderPlatform` + temp dir for anything touching persistence.
  `ProjectService.instance.resetForTest()` between tests.
- `Config.isDev` is true in debug/tests → dev seed data appears when storage
  is empty; widget tests that need deterministic lists should pre-save tasks
  via `StorageService` first.
- UI text findable by tooltip is the norm for icon buttons ("Save", "Edit
  project", "Clear search", "Open navigation menu").
- Don't introduce new deprecation warnings; existing `withOpacity`/
  `onWillAccept` infos are legacy and get cleaned opportunistically.
- Changelog entries are user-facing bullet points under `## [x.y.z] - date`.
