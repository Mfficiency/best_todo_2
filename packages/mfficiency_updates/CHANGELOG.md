# Changelog

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
