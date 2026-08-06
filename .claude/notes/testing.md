# Testing playbook

> How this project tests, why it tests that way, and every trap that has cost
> a session real time. The suite map (which files, which silo, which command)
> is canonical in `test/README.md`; the short form of the conventions is in
> `CLAUDE.md`. This file is the full version with reasoning.

## Philosophy

- **Tests are the executable half of the spec.** SPEC.md says what the app
  does; the suites prove it still does. A rebuild ports the tests alongside
  the code (see `rebuild-playbook.md`).
- **Siloed suites, core sacred.** `test/core/` (task model, persistence,
  bucketing, upgrade safety, smoke tests) runs for *every* change. Feature
  silos (`alarms`, `projects`, `home`, `streaks`, `sms`, `sync`, `update`,
  `tools`) run
  when their area is touched. Plain `flutter test` runs everything and is what
  CI uses. Cross-cutting changes (theme, navigation, pubspec) → full suite.
- **A failing suite is a feature, not just a gate.** Results are packaged into
  every build; the app shows a red dot and a Test Results page. `build-apk.yml`
  deliberately builds even when tests fail (the APK then *shows* the failures);
  `flutter_test.yml` is the workflow that goes red.
- **Local runs use `--timeout 60s`** so a hang fails fast instead of eating the
  10-minute per-test default.

## Conventions

- Plain `test()` for logic; `testWidgets` with `MaterialApp(home: ...)` for
  widgets.
- Anything touching persistence: `_FakePathProvider extends
  PathProviderPlatform` pointed at a temp dir, created in `setUp`.
- `ProjectService.instance.resetForTest()` between tests; same idea for other
  singletons (`TestReportService.resetForTest`, `SyncService.resetForTest`,
  `Config.resetVersionForTest`).
- `Config` flags are global statics — suites that flip them (simple mode,
  features) must restore them in `tearDown`.
- `Config.isDev` is true in tests → dev seed data appears when storage is
  empty. Widget tests needing deterministic lists pre-save tasks via
  `StorageService` first; streak tests write an empty `streak.json` up front
  to opt out of seeding.
- `find.byType` matches exact runtimeType — `FilledButton.icon(...)` builds a
  private subtype; find its label text instead. Icon buttons are findable by
  tooltip by convention ("Save", "Edit project", "Clear search", "Open
  navigation menu").
- Never dispose `TextEditingController`s right after `showDialog` returns —
  the exit animation still builds the fields. Give the dialog its own
  StatefulWidget that owns the controllers (`_ProjectEditDialog` pattern).

## Trap #1 — real file I/O inside `testWidgets` hangs

The fake-async zone never services `dart:io` completions — locally AND on CI.
The unmitigated pattern kept `flutter_test.yml` red from 0.1.87 until 0.1.90.

- **I/O you control** (temp dirs, pre-saved files): do it in `setUp` (outside
  the fake zone) or wrap in `await tester.runAsync(() => ...)`.
- **I/O started inside the widget** (initState loads, save-on-tap): one
  `runAsync` delay only advances ~one I/O hop. Loop rounds of
  `runAsync(delay 5ms)` + `pump()`:
  - *condition-driven* for loads — loop until a marker widget appears;
  - *FIXED count (~60 rounds)* after taps whose handler awaits a write before
    `setState` — in-memory state updates before the write ends, so polling for
    the UI change exits too early. See `home_search_test` /
    `project_board_page_test`.
- Disk-cache reads count too: Test Results page tests default every report
  layer to "no data" in `setUp` precisely because the cache read is real I/O.

## Trap #2 — animations that never settle

`pumpAndSettle` never returns on pages with endless animations: the alarm ring
page (pulse) and the streak page (flicker). Use fixed `pump()` calls.

## Trap #3 — settings-page scrolling

Every section chip is built even when off-screen, so
`scrollUntilVisible`/`dragUntilVisible` skip their drag and run
`ensureVisible` on a chip inside the *pinned* header — dragging the settings
list to the very bottom. Drag the chip row by rect instead (see
`streak_ui_test.dart`). Related production logic: `_jumpToSection` must walk
*towards* the target and only stop when a hop changes neither offset nor
`maxScrollExtent` (which grows as children lay out).

## Integration / screenshot tests

`flutter test integration_test/home_page_screenshot_test.dart -d windows` →
PNGs in `build/e2e_screenshots/`. Windows desktop needs Developer Mode
(plugin symlinks). CI archives every PNG found, so adding a capture to the
test needs no workflow edit. There's also
`integration_test/create_task_screenshot_test.dart` (manual proof-of-concept).

## The machine-report pipeline (test results as data)

One `flutter test --machine` run feeds everything; the parser lives *in the
app* (`models/test_report.dart`, `fromMachineJsonLines`) so CI summaries and
the in-app page can never disagree.

- Generate from a run: `dart run tool/generate_test_report.dart --input
  machine.jsonl --output report.json --commit … --branch … --version …
  --run-url …`
- Package newest-known into the build:
  `dart run tool/sync_test_report.dart` (fetches `ci-reports/latest.json`
  unless `--no-fetch`; newest `generatedAt` wins via `TestReport.newest`).
- Local refresh of `assets/test_report.json`:
  - from CI: `dart run tool/sync_test_report.dart`
  - from your own run: `flutter test --machine > build/ci/machine.jsonl` then
    `dart run tool/sync_test_report.dart --no-fetch --candidate-machine
    build/ci/machine.jsonl`
- CI-side wiring and the `ci-reports` branch: `notes/automation.md`.

## Known coverage gaps (deliberate)

Hardware-verified instead of unit-tested: Kotlin widget PendingIntent wiring,
most alarm/SMS runtime delivery paths (the alarm log is the verification
tool), stats/usage page rendering details. The on-device verification pattern
is in `notes/environment.md`.
