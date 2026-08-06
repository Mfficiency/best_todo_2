# Environments — local, CI, sandbox, device

> How to get from a bare machine to building/testing BestToDo, and what each
> environment can and cannot do.

## Versions (keep in lockstep)

- **Flutter 3.29.2** (stable) — pinned in all three workflows; use the same
  locally so analyzer/test behavior matches CI.
- Java 17 (Temurin) for Android builds. Dart SDK constraint `>=3.0.0 <4.0.0`.
- `pubspec.lock` is gitignored (`*.lock`) — versions resolve from pubspec
  constraints.

## Local dev machine (the maintainer's is Windows)

```bash
flutter pub get
flutter run -d chrome            # fastest inner loop; swipe fallback buttons appear
flutter test --timeout 60s test/core test/<area>   # suites per test/README.md
flutter analyze --no-pub         # pre-existing infos/warnings exist; add none
flutter build apk --release      # needs Android SDK; signed with committed debug keystore
bash tool/build.sh apk           # gated build with versioned artifact names
```

- Windows desktop target is used for integration/screenshot tests:
  `flutter test integration_test/home_page_screenshot_test.dart -d windows`
  → PNGs in `build/e2e_screenshots/`. Requires **Developer Mode** enabled
  (Flutter plugins use symlinks).
- Chrome runs show real CI test results on the Test Results page because
  `assets/test_report.json` is committed on dev — no build step needed.
- Historic build unsticker (from README): `flutter clean && flutter pub get &&
  flutter create . && flutter run`.

## CI runners

See `notes/automation.md`. ubuntu-latest for tests/APK; **windows-2022**
(pinned, not -latest) for screenshots. `GITHUB_TOKEN` with `contents: write`
is all the publishing needs.

## Remote AI sandbox (Claude sessions and similar)

Flutter is NOT preinstalled. Recipe (used successfully in past sessions):

1. Download `flutter_linux_3.29.2-stable.tar.xz` from
   `storage.googleapis.com/flutter_infra_release/releases/stable/linux/`,
   extract into the session scratchpad.
2. `git config --global --add safe.directory <extracted flutter path>`
3. Add `<path>/flutter/bin` to PATH, then `flutter pub get` in the repo.

Constraints:
- **No Android SDK** → no local APK builds; native packaging is covered by
  `build-apk.yml` on push. Dart-side `flutter analyze` / `flutter test` work.
- Network may be proxied; downloads outside allowed hosts can fail — if
  Flutter can't be installed, rely on CI for test runs and say so rather than
  guessing.

## Real devices (where the truth lives)

- The maintainer's device is **Samsung / One UI**: always consider "Sleeping
  apps" / battery optimization when alarms "don't work" — a normal app must
  request the exemption the stock Clock gets for free.
- **Verification pattern the maintainer uses:** set an alarm/report a few
  minutes ahead, lock the phone, then check the on-device logs — the SMS
  report log's "Alarm fired" diag entry or the ringing alarm itself. The
  in-app logs (alarm log + doctor, SMS log, App Logs, sync tab) are the
  debugging surface; design fixes so they leave evidence there.
- Release builds behave differently from debug (R8/ProGuard — see
  `principles.md`): reliability fixes must be verified on a **release** APK
  on hardware.
- Force-stop (system settings) drops all OS alarms until the next app launch —
  Android platform rule, unfixable app-side; don't chase it as a bug.
