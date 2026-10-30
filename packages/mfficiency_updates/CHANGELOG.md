# Changelog

## 1.8.0 - 2026-10-30

- **Other apps:** `OtherAppsLink` (the row at the bottom of About) opens
  `OtherAppsPage`: every other Mfficiency Android app (`mfficiencyApps`,
  this one left out) with whether it is installed, its newest release
  (highest build of any channel, its own tag scheme) and Install / Update /
  Open. The download is silent like an update's (own folder
  `<cache>/other_apps`, then moved to `<cache>/updates` for the
  installer), then Android asks. Private repos need a token with Contents:
  Read-only (the page's key icon, or the app's `fallbackToken`, e.g. the
  problem-report token); without one, or off a phone, Open on GitHub.
  Native: `packageInfo`, `launchApp`; the manifest's `<queries>` lists the
  apps. `OtherAppsStrings` (English defaults).
- The problem-report token help mentions adding Contents: Read-only so one
  token serves both.

## 1.7.0 - 2026-10-29

- **Problem reports to Claude:** `ProblemReporter` sends the user's
  description, the app's facts and its logs as a GitHub issue labelled
  `claude-fix` (body marked `<!-- mfficiency-problem-report -->`), which
  the repo's `claude-fix.yml` workflow hands to Claude to fix and merge
  into dev. With a fine-grained token (Issues: read and write) straight
  from the app; without one GitHub's new-issue page opens filled in.
  `ProblemReportTrigger` (double tap on the version in the menu),
  `showProblemReport` (the sheet), `ProblemReportSettingsTile` (the token
  and how to get it), `ProblemReportStrings` (English defaults).

## 1.6.3 - 2026-10-24

- A public repo with a token downloads through the asset API too, so an
  app with a token keeps updating when its repo turns private.

## 1.6.2 - 2026-10-23

- The new-install check skips `excluded` folders again (1.6.1 compared
  paths wrongly, so e.g. an early log made an install look used).

## 1.6.1 - 2026-10-23

- A new install is one with no SharedPreferences **and** no file in the
  app's folders (apps that keep everything in files no longer offer a
  restore after an update).
- The restore confirmation no longer claims every token stays out: only
  those the app keeps in secure storage do.

## 1.6.0 - 2026-10-23

- **Full backup:** `FullBackup` writes everything the app keeps (its
  documents, support and external folders, SharedPreferences, `extras`)
  to one `.tar.gz` in `Download/<appName>/Backups/`, which survives
  uninstalling; `beforeUpdate` for `beforeInstall` makes one before every
  update. Restore picks a file, checks the applicationId, backs up the
  current data first and restarts the app. `FullBackupTiles` for
  Settings, `offerRestore` once on a new install, `FullBackupStrings`
  (English defaults). Native: `appId`, `saveToDownloads` (MediaStore),
  `pickFile`, `restartApp`; `WRITE_EXTERNAL_STORAGE` up to Android 9 only.

## 1.5.0 - 2026-10-15

- **Build facts per version:** `ReleaseBuildInfo(controller:, version:)`
  shows under a changelog entry when that version was built, how long the
  build took and the APK's size ("Built 15.10.2026 14:02", "Build time
  3m 12s", "APK 19.4 MB"), read from its GitHub release (the highest
  build of that x.y.z, from the same cached list as the older-versions
  sheet). `fallback:` for the app's own CHANGELOG.md build lines while
  the list loads or when the release says nothing.
- `UpdateResult.builtAt` / `buildDuration` / `apkSize`: the release notes'
  build footer in every app's variant ("Built: 2026-10-15 14:02 in 3m
  12s, APK 19.4 MB", "Built: … UTC+02:00" + "Build duration: …",
  Vesta Immo's "… | built 2026-10-15 14:02 in 3m 12s | APK …"), else
  the release's publish time; the size is the APK asset's. Pure helpers
  `buildTime`, `buildDuration`, `parseBuildDuration`,
  `formatBuildDuration`, `formatApkSize`. New strings `releaseBuilt`,
  `releaseBuildTime`, `releaseApkSize` (English defaults).

## 1.4.0 - 2026-10-15

- **Time remaining:** a download that takes more than 30 s gets a second
  line under its progress, "00:01:23 remaining" (`UpdateStrings.remaining`),
  extrapolated from the progress so far; only an indication.
- **`RemainingTime` / `formatHms`** (exported, pure): the same estimate
  for the apps' own long work (uploads, syncs, imports). `start()`, then
  `label(done)` with 0..1 (or `typical:` for work without a fraction);
  nothing for work that looks no longer than 30 s in total
  (`longerThan`), nor during the first 3 s while it settles.

## 1.3.0 - 2026-10-14

- **Status card, easier to read:** the changelog's header card shows the
  version and channel on top ("Version 1.2.0 (5) · dev", every channel
  including main), then the times in two aligned columns (Downloaded:,
  Installed:, Last check:). No icon and no "Pull down to check" hint any
  more; a status line only appears when there is news (checking, an
  update, a problem), "Up to date" is not repeated. New strings
  `downloadedLabel`, `installedLabel`, `lastCheckLabel` (English
  defaults); `pullToCheck` is no longer shown (kept for compatibility).

## 1.2.0 - 2026-10-12

- **Open after updating:** installs go through Android's installer app
  again (`ACTION_INSTALL_PACKAGE`, addressed to that app directly, so no
  chooser), which ends with "App updated" and an Open button. The APK is
  shared read-only from `cache/updates/` by the plugin's `ApkProvider`
  (authority `<applicationId>.mfficiency_updates.apk`); the manifest adds
  a `<queries>` entry so the installer is visible on Android 11+. The
  PackageInstaller session stays as the fallback. No Dart API change.

## 1.1.0 - 2026-10-12

Everything the apps' adapters still did on their own is now the package's,
so every app behaves the same:

- **Check on resume:** back in the foreground, a check runs (silently, like
  the poll) when the last one is older than `UpdateConfig.dueAfter`
  (`pollInterval`, or `checkInterval` without polling). On by default
  (`checkOnResume`).
- **Automatic switch:** `UpdateController.autoCheckChanged()` or
  `UpdateConfig.autoCheckChanges` (any `Listenable`): turned on, polling
  starts, a due check runs and an update found meanwhile downloads; turned
  off, polling stops. No second `start()` needed.
- **GitHub rate limit:** a 429, or a 403 with `x-ratelimit-remaining: 0` /
  `retry-after` (or any 403 without a token), gives
  `UpdateStatus.rateLimited` ("GitHub is limiting update checks right now —
  try again later.", `UpdateStrings.rateLimited`) and pauses automatic
  checks until the reset GitHub names, else `rateLimitPause` (30 min); kept
  across restarts (`pausedUntil`). Taps still check. `UpdateHttpException`
  carries the rate-limit headers.
- **User-Agent:** the default dart:io HTTP and downloader send
  `UpdateConfig.userAgent` (default `<appName without spaces>-update-check`).
- **Links off Android:** `UpdatePlatform(openUrl: …)` takes the app's opener
  (desktop, web); off a phone Install opens a private asset's signed link,
  else its github.com link (`UpdateResult.browserUrl`).
- **Tag formats:** `buildPrefix` (`vesta-immo-v0.1.19-b3600000-dev`),
  `strictTags` (only the exact format; CI-era tags are never offered) and
  `tagPattern` (a RegExp with named groups `version`, `build`, `channel`);
  `TagFormat` does the parsing.
- **Equal build numbers:** main before staging before dev.
- **Releases without an APK** are skipped (`requireApk`, default true): a
  release whose APK is still uploading is never offered as a release page.
- **Pre-install hook:** `UpdateController(beforeInstall: …)` runs before
  Android's installer opens (e.g. a backup); a throw is logged and the
  install goes on.
- **Hold back the install prompt:** `UpdateController(promptAllowed: …)`
  (a `ValueListenable<bool>`); while false Android's dialog doesn't open by
  itself, it opens when it turns true. Taps always open it.
- **Legacy state:** `migrateLegacyUpdateState` + `LegacyUpdateRecords` +
  `parseLegacyVersion` move an app's pre-package records into the package's
  keys once and delete the old APKs.

## 1.0.0 - 2026-10-12

- First shared version: GitHub Releases or a manifest, silent resumable
  download, PackageInstaller install, banner, changelog card, older
  versions, records.
