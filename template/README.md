# App Template

A reusable Flutter app scaffold generalised from **BestToDo**. It preserves the
app's look-and-feel, technical pages and testing/screenshot routines, and hides
all app-specific choices behind a single config file so a new app is mostly a
rename.

- **`app_template/`** — the template package (copy this to start a new app).
- **`TEMPLATE_GUIDE.md`** — the rebranding checklist (name, icon, colours,
  intro, settings, start pages, notification defaults, backups, menu entries).

## What's included

| Feature | Where |
| --- | --- |
| Main menu with app title + **dynamic** version at the top | `ui/main_menu_page.dart`, `ui/widgets/version_banner.dart` |
| Searchable, single-page **Settings** with scroll-to-section chips | `ui/settings_page.dart` |
| Theme options: **system / light / dark** + a **minimalist** variant (incl. minimalist-dark) | `app_settings.dart`, `theme/app_theme.dart` |
| Configurable **date & time** formats | `app_settings.dart`, `util/date_time_format.dart` |
| Selectable **default start page** | `app_config.dart` (`startPages`), `models/start_page.dart` |
| **Notification** settings: quiet hours + default delay | `ui/settings_page.dart`, `app_settings.dart` |
| **About** page: details, version, replay intro, update-app | `ui/about_page.dart` |
| **Changelog** page (newest first) | `ui/changelog_page.dart`, `CHANGELOG.md` |
| **App Logs**, **Startup Times**, **Test Results** pages | `ui/app_logs_page.dart`, `ui/startup_times_page.dart`, `ui/test_results_page.dart` |
| **Versioned backup** export/import of all data + settings | `services/backup_service.dart` |
| Colour scheme, reusable components, spacing, typography | `theme/`, `ui/widgets/` |

The one file you edit to rebrand: **`app_template/lib/src/app_config.dart`**.

## Commands (run from `app_template/`)

```sh
flutter pub get                       # resolve dependencies
flutter test                          # unit + widget tests
flutter analyze                       # static analysis (clean)

# Automated screenshots (headless, no device):
flutter test test/screenshots/capture_screens_test.dart
dart run tool/screenshot_report.dart  # file by version+date, update gallery

# End-to-end navigation (on a device/desktop; add platforms first):
flutter test integration_test/app_flow_test.dart -d windows

# Version + changelog bump:
dart run tool/bump_version.dart 1.2.3+45 "What changed"

# Bundle CI test results into the app (from --machine output):
dart run tool/generate_test_report.dart --input machine.jsonl \
  --output assets/test_report.json --version 1.2.3+45 --branch main --commit <sha>
```

## Design principles carried over from BestToDo

- **No hard-coded version strings** — runtime via `package_info_plus`
  (`AppVersion`), tooling via `pubspec.yaml`.
- **No fabricated data** — logs, startup times and test results reflect real
  measurements; the bundled test report is `available: false` until CI writes a
  real one.
- **Tolerant persistence** — settings and backups apply partial/older maps
  without crashing, so upgrades and imports are safe.
