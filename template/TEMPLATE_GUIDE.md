# Template Guide

How to turn `app_template/` into a new app. Almost everything lives in **one
file** — `lib/src/app_config.dart` — plus `pubspec.yaml` for the name and
version. No version string is ever hard-coded; the app reads it at runtime and
the tooling reads it from `pubspec.yaml`.

> Quick start: copy the `app_template/` folder, rename it, then work down this
> checklist.

## 1. App name

- `pubspec.yaml` → `name:` (the Dart package name, lowercase_with_underscores)
  and `description:`.
- `lib/src/app_config.dart` → `AppConfig.appName` (shown on the menu header,
  About page, window title) and `AppConfig.tagline`.
- Find/replace the package import prefix `package:app_template/` if you renamed
  the package.

## 2. App icon

- Drop your icon into `assets/` and wire it up per platform (Android
  `mipmap`s, iOS `AppIcon`), or add the `flutter_launcher_icons` package and
  point it at your asset. The template ships no launcher icon so you can't ship
  someone else's by accident.

## 3. Colour scheme

- `AppConfig.seedColor` — one colour seeds the entire Material 3 palette
  (light **and** dark). That's usually the only change you need.
- The **minimalist** theme is intentionally monochrome and ignores the seed.
  Tune its greys in `lib/src/theme/app_theme.dart` if desired.
- Shared spacing lives in `lib/src/ui/widgets/spacing.dart` (`AppSpacing`);
  reusable pieces: `SettingsSection`, `VersionBanner`, `buildSubpageAppBar`.

## 4. Introduction

- `AppConfig.introSlides` — a list of `IntroSlide(icon, title, body)`. Add,
  remove or reorder. Shown on first launch and via About → "Replay
  introduction".

## 5. Settings

- Toggle/adjust defaults in `AppConfig` and the initial values in
  `lib/src/app_settings.dart`.
- To **add a setting**: add a field + `toMap`/`applyMap` line in
  `AppSettings`, add the control to the matching section in
  `lib/src/ui/settings_page.dart`, and add a `_SearchEntry(...)` so search can
  find it. Because backups serialise `AppSettings.toMap()`, new settings are
  exported/imported automatically.
- Date/time formats are in `AppSettings.dateFormats` and rendered by
  `lib/src/util/date_time_format.dart`.

## 6. Start pages

- `AppConfig.startPages` — the launch-screen choices offered in
  Settings → Startup. Each `StartPage(key, label, builder)`; `builder: null`
  means "open on the main menu". The main menu is always the nav root, so
  backing out of a start page returns to it. Keys are persisted — never rename
  an existing one.

## 7. Notification defaults

- `AppConfig.defaultNotificationDelaySeconds`, `quietHoursEnabledByDefault`,
  `quietHoursStartMinutes`, `quietHoursEndMinutes`. The template stores
  notification **preferences**; wire an actual notifications plugin where those
  values are read (see `AppSettings` fields) — the UI and persistence are done.

## 8. Exported data (backups)

- `AppConfig.backupAppId` (stamped into every backup so one app can't import
  another's) and `AppConfig.backupSchemaVersion` (bump when the shape changes).
- Register each of your data stores at startup so it's included in
  "Export Everything" and restored on import:

  ```dart
  BackupService.instance.registerSection(BackupSection(
    key: 'tasks',                       // stable JSON key, never rename
    export: () => myStore.toJsonList(), // Object? at export time
    import: (json) => myStore.replaceFrom(json), // restore
  ));
  ```

  Settings are always included. The importer refuses a different app's file,
  warns (but still tries) on a newer schema, and skips unknown sections.

## 9. Menu entries

- `AppConfig.customMenuEntries` — app-specific rows added **above** the built-in
  technical pages (Settings, About, Changelog, App Logs, Startup Times, Test
  Results). Each `MenuEntry(icon, label, routeBuilder, subtitle?)`.

## 10. Versioning, changelog, releases

- `dart run tool/bump_version.dart 1.2.3+45 "What changed"` — updates
  `pubspec.yaml` and prepends a dated `CHANGELOG.md` entry (newest first). The
  Changelog page renders that file; the About page and menu show the version
  live.

## 11. Screenshots

- `flutter test test/screenshots/capture_screens_test.dart` → PNGs in
  `build/e2e_screenshots/` (headless, no device).
- `dart run tool/screenshot_report.dart` → copies them to
  `docs/screenshots/v<version>/<date>_<time>/` (each run preserved) and prepends
  a newest-first section to `docs/screenshots/SCREENSHOTS.md` with screen names,
  version, date and image links.

## 12. Test results page (optional online source)

- `TestReportService.onlineReportUrl` — set to a raw URL your CI publishes to
  show the freshest results on old installs. Empty by default (bundled report
  only). CI writes the bundled report with `tool/generate_test_report.dart`.

## What NOT to change to get going

You do **not** need to touch `lib/src/ui/*`, `lib/src/services/*`, the theme, or
the tooling to launch a rebranded app — only `app_config.dart` and `pubspec.yaml`.
Everything else is the reusable machinery.
