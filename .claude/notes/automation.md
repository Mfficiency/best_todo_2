# Automation & CI map

> Everything that runs without a human: the three GitHub workflows, the
> `ci-reports` store, the tool scripts, and the release flow — plus the loop
> protections and the reasons behind the non-obvious choices. The workflow
> files and scripts are themselves commented; this is the connected overview.

## Branch model

Feature branches (`claude/*`, historically `codex/*`) → `dev` → `staging` →
`main`. Releases are built from dev after a version bump. dev is the working
branch; staging/main promote by merge.

## The three workflows (`.github/workflows/`)

| Workflow | Triggers | Runner | Does |
|---|---|---|---|
| `flutter_test.yml` | push + PR on main/staging/dev | ubuntu | The blocking test run. One `flutter test --machine --coverage` feeds: report JSON (`generate_test_report.dart`), job summary + artifact (`render_test_report_summary.dart`), newest-wins packaging into `assets/test_report.json` (`sync_test_report.dart`), publish to `ci-reports` (`publish_test_report.sh`). On **dev pushes only**, commits the packaged report back (`assets/` + a `docs/ci/` copy for app versions < 0.1.128), rebase-retried 3×. Fails the job if tests failed. |
| `build-apk.yml` | push + PR on main/staging/dev, manual | ubuntu (Java 17) | Runs tests **non-blocking** (a red suite still ships — the APK then shows its own failures on the Test Results page), packages the newest report, publishes to `ci-reports`, builds the release APK, uploads artifact `besttodo-<version>` (30-day retention) with a download link in the job summary. |
| `screenshot_changelog.yml` | push on main/staging/dev, manual | **windows-2022** | Runs the screenshot integration test, archives every `build/e2e_screenshots/*.png` to `docs/screenshots/home/<timestamp>-<sha>/`, prepends `SCREENSHOT_CHANGELOG.md` (`update_screenshot_changelog.dart`), commits. On failure it commits the test output to `docs/ci/screenshot_capture_failure.txt` (readable without GitHub auth; a later green run deletes it). |

All three pin **Flutter 3.29.2** — keep them in sync, and match locally.

### Loop protections (bot commits must not retrigger workflows)

- `paths-ignore` on the outputs each workflow writes:
  `assets/test_report.json` + `docs/ci/**` (test/apk), plus
  `SCREENSHOT_CHANGELOG.md` + `docs/screenshots/home/**` (screenshots).
- Bot commit messages carry `[skip-screenshot-changelog]`; the screenshot job
  skips on that marker and on actor `github-actions[bot]`.
- The `ci-reports` branch holds no app code, so pushing to it triggers nothing.

### Why dev is the single writer of the packaged report

Only dev's history carries `assets/test_report.json` commits, so
dev → staging → main merges carry the report along instead of conflicting on
it — and a plain checkout of dev shows real results offline
(`flutter run -d chrome` works with no network and no build step).

### Runner pins that will bite again

- `windows-2022`, not `windows-latest`: the June 2026 image moved to VS 2026;
  Flutter < 3.35 only knows the VS 2022 CMake generator.
- `docs/ci/screenshot_capture_failure.txt` is `.txt` because the repo
  gitignores `*.log` (a `git add` of a `.log` was once a silent no-op).

## The `ci-reports` orphan branch

Machine-written store, no app code: `latest.json` (newest run across all
branches) + `branches/<branch>.json`. Written by
`tool/ci/publish_test_report.sh` (clone-or-create, newest-wins merge through
`sync_test_report.dart`, 3 push attempts, **never fails a build** — every
error path exits 0). Read by `TestReportService.onlineReportUrl` (the app's
online refresh) and by `sync_test_report.dart` (build packaging).

## Tool scripts (`tool/`)

| Script | Purpose |
|---|---|
| `bump_version.dart` | `dart run tool/bump_version.dart <x.y.z[+build]> ["entry"]` — updates pubspec + prepends a dated CHANGELOG section. A bare `x.y.z` carries the build number forward and increments it, so `+build` (Android versionCode) can never be dropped — without it the APK is rejected as a downgrade. |
| `build.sh` | Local release build: pulls latest CI report (`pull_test_report.dart`) → smoke-test gate (`test/core/build_smoke_test.dart`) → `flutter build $@` → renames artifacts with the version. With `PUBLISH_APK=1` it also runs `publish_apk.dart`. |
| `publish_apk.dart` | Uploads a locally built release APK to a GitHub release `v<x.y.z>-<build>` with asset `BestToDo-<x.y.z+build>.apk` and the newest CHANGELOG section as release notes — exactly where the app's About → "Check for updates" (`UpdateService`) looks. Token from `GITHUB_TOKEN`/`GH_TOKEN` or a logged-in `gh` CLI. |
| `generate_test_report.dart` | machine.jsonl → report JSON (one run, with commit/branch/version/run-url). |
| `sync_test_report.dart` | Newest-wins merge of output/candidates/machine-run/`ci-reports latest.json` into `assets/test_report.json`. Everything non-fatal — offline keeps the existing report. |
| `pull_test_report.dart` | Local-build helper: fetch the latest published report (network-failure-safe). |
| `render_test_report_summary.dart` | Report JSON → CI job-summary markdown (same parser as the app — they can't disagree). |
| `update_screenshot_changelog.dart` | Prepends `SCREENSHOT_CHANGELOG.md`, one section per PNG found. |
| `ci/publish_test_report.sh` | See `ci-reports` above. |
| `update_app_logo.py`, `update_icons.sh` | Icon regeneration from the source logo. |

## Release flow ("bump, sync and build")

1. `dart run tool/bump_version.dart <version> "<changelog entry>"` — every
   feature batch gets a version + user-facing CHANGELOG bullets.
2. Commit to `dev`, push. CI then: tests (blocking), APK artifact, screenshot
   changelog, report packaging — all automatic.
3. A local `flutter build apk --release` is signed with the committed debug
   keystore, so it installs over any CI build (identical signature —
   deliberate; see SPEC §9).
4. To feed the in-app updater, publish the APK as a GitHub release:
   `PUBLISH_APK=1 sh tool/build.sh apk --release` (or
   `dart run tool/publish_apk.dart` after any release build).
5. Promote by merging dev → staging → main when asked.

## In-app automation (runs on the user's device)

For completeness — the app itself automates: self-re-arming SMS report chain,
alarm watchdog re-rings, midnight widget refresh, day-rollover sweep,
scheduled auto-backups (daily/weekly), background folder sync on app quit,
once-per-install migrations/seeders. All specified in SPEC §4–§8.
