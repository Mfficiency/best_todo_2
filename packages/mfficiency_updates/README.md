# mfficiency_updates

In-app updates from GitHub Releases for the Mfficiency Flutter apps, one
implementation for all of them (template, Hally Remote, BestCollage, BestToDo +
Best Music, Vesta Immo). A Flutter plugin: Dart core + widgets, and the
Android installer (other platforms: checks only, no install).

## What it does

- **Source:** the GitHub Releases of one repo (`owner/repo`), all channels
  (tags `<prefix><x.y.z>-<buildPrefix><build>[-dev|-staging]`, pre-releases
  included unless turned off, drafts never), filtered by the app's tag
  format (`v`, `music-v`, `vesta-immo-v` + `b`, …; `strictTags` drops tags
  of another scheme). Only releases **with an APK asset** count
  (`requireApk`). The release with the **highest build number** is offered
  when it is above the running build (Android's versionCode), whatever its
  x.y.z; equal numbers: main before staging before dev.
  Private repos: a token (`Authorization: Bearer`, asset download through a
  short-lived signed link). Or a JSON manifest
  `{"version", "build", "url", "notes"}`.
- **When:** on the first frame if the last check is older than
  `checkInterval`, every `pollInterval` while in the foreground, **when the
  app comes back to the foreground** and the last check is older than
  `dueAfter` (`pollInterval`, or `checkInterval` without polling), when the
  "check automatically" switch is **turned on** (`autoCheckChanges` /
  `autoCheckChanged()`; off stops polling), on pull-down in the changelog
  (`refresh`), from "Check for updates" (`checkNow`). Automatic checks only
  on a phone, with the switch on.
- **GitHub's rate limit** (429, or 403 with `x-ratelimit-remaining: 0` /
  `retry-after`, or any 403 without a token): status `rateLimited` ("GitHub
  is limiting update checks right now — try again later."), automatic
  checks pause until the reset GitHub names, else `rateLimitPause`
  (30 min), also across restarts (`pausedUntil`). Taps still check.
- **Download:** always silent, in-app (`HttpClient`) into
  `<cache>/updates/` as `<App>-<x.y.z>-<build>.apk.part`, renamed when
  complete, reused after a restart, and **continued with a Range request**
  after an interruption (`If-Range`, so a replaced file starts over). No
  dialog, sheet, notification or progress popup; progress only as state
  (`downloading`, `downloadProgress`) for passive text. A tap that starts a
  download shows one SnackBar.
- **Install:** when complete, Android's installer app gets the APK
  (`ACTION_INSTALL_PACKAGE` addressed to that app, so never a chooser or a
  browser; the plugin's `ApkProvider` shares `cache/updates/` read-only).
  Its "Update this app?" is the only confirm, and when the update is done
  it shows "App updated" with **Open**, so the user is back in the app with
  one more tap. Where no installer app takes the intent, a PackageInstaller
  session asks the same question (no Open step). By itself only while the app is in the
  foreground, once per build per start and while `promptAllowed` (onboarding
  done, …) lets it, else as soon as it does; always after a tap.
  `beforeInstall` runs first (a backup; a throw doesn't stop the install). Without the
  "install unknown apps" switch it opens that switch, explains it in a
  SnackBar and installs when the app is back. Cancelled: a slim "Update ready
  · <version>" banner with Install until installed. A failed download: a
  banner with Try again (silent again).
- **Records** (in the app's store): when an APK completed (`downloaded`),
  when the running build was installed (`installedAt`: Android's
  `lastUpdateTime`, else the first start of the build), `lastCheck`.
- **Build facts:** `ReleaseBuildInfo` shows under a changelog entry when
  that version was built, how long the build took and the APK size, from
  its GitHub release (the notes' "Built:" footer and the asset's size).
- **Older versions:** tapping a version in the changelog lists the highest
  build of that x.y.z; its download is silent, then Android asks (rollback).
- **Off a phone** (desktop, web): Install opens the APK link with the
  app's opener (`UpdatePlatform(openUrl: …)`): a private asset's signed
  link, else its github.com link.

## Problem reports to Claude

A **double tap on the version** in the app's menu opens "Report a problem
to Claude": a field to describe it, the app's logs on/off, Send. The report
becomes a GitHub issue in the app's repo (labelled `claude-fix`, body marked
`<!-- mfficiency-problem-report -->`, logs cut from the oldest end to fit
GitHub's 65 536 characters, the token blanked out of them). The repo's
`.github/workflows/claude-fix.yml` hands issues the owner wrote with that
marker to Claude (claude-code-action), which fixes the code, merges it into
`dev` and pushes; the laptop builds that push as the next dev update.

- **With a token** (Settings › Problem reports to Claude: a fine-grained
  token, the app's repo or all app repos, *Issues: Read and write* only;
  the tile explains the steps) the issue is created from the app.
- **Without one** (or in a browser build) GitHub's new-issue page opens
  with the report filled in (logs shortened to fit the URL); the user taps
  Create.
- **Once per repo:** the secret `CLAUDE_CODE_OAUTH_TOKEN` (`claude
  setup-token`) or `ANTHROPIC_API_KEY`, for the workflow.

```dart
final reporter = ProblemReporter(
  config: ProblemReportConfig(
    appName: 'BestToDo', version: AppConfig.version, build: AppConfig.buildNumber,
    channel: AppConfig.channel, githubRepo: 'Mfficiency/best_todo_2',
  ),
  collectLogs: () async => Log.recent.join('\n'), // the app's logs, newest last
  openUrl: openInBrowser,                         // the browser fallback
  // readToken/writeToken: default SharedPreferences `problem_report.github_token`
);
// Menu header:  ProblemReportTrigger(reporter: reporter, child: versionText)
// Settings:     ProblemReportSettingsTile(reporter: reporter)
```

## Other apps

The row **Other apps** at the bottom of About (`OtherAppsLink`) opens
`OtherAppsPage`: every other Mfficiency Android app from `mfficiencyApps`
(name, appId, repo, tag scheme, private or not; the running app is left
out), whether it is installed (`UpdatePlatform.packageInfo`; Android 11+
only answers for the packages in the plugin manifest's `<queries>`, so a
new app goes in both places), its newest release with an APK (highest
build of any channel) and **Install** / **Update** / **Open**. Install
downloads silently like an update (`<cache>/other_apps`, resumed), moves
the APK into `<cache>/updates` (the folder the plugin shares) and hands
it to Android's installer. Private repos need a token that can read them
(fine-grained, Contents: Read-only): the page's key icon (SharedPreferences
`other_apps.github_token`) or the app's `fallbackToken` (e.g. the
problem-report token; one token with Contents: Read-only + Issues: Read
and write serves both). Without one, off a phone or for a release without
APK, **Open on GitHub** shows its releases in the browser. Pull down asks
again; coming back from the installer re-reads what is installed.

```dart
final otherApps = OtherAppsController(
  fallbackToken: reporter.token,          // optional
  platform: UpdatePlatform(openUrl: openInBrowser),
);
// At the bottom of About:  OtherAppsLink(controller: otherApps)
```

## Full backup (before every update, and before a reinstall)

`FullBackup` puts **everything the app keeps on the phone** into one file in
the public Downloads folder, `Download/<appName>/Backups/<App>-<date>-<x.y.z>+<build>.tar.gz`,
which **stays when the app is uninstalled** (MediaStore on Android 10+, no
permission; Android 9 and older: the storage permission, `maxSdkVersion 28`).

- **In it:** every file in the app's documents (`app_flutter`), support
  (`files`) and app-specific external folders, its SharedPreferences
  (typed), and the app's `extras` (data kept elsewhere, e.g.
  `SharedPreferencesAsync`, as JSON). A plain gzip'd tar with
  `manifest.json` (app, applicationId, version, build, time, reason):
  `tar -xzf` opens it on a PC.
- **Not in it:** secrets kept natively (Android Keystore, secure storage),
  caches, `excluded` paths, `excludedPrefixes` keys, the update state.
- **When:** `beforeInstall: backup.beforeUpdate` makes one before every
  update; "Back up everything" in Settings any time; and automatically
  (`schedule`: off, daily, weekly — `defaultSchedule`, weekly unless the
  app says otherwise): `startSchedule()` after the first frame backs up
  when the newest backup of any kind is older than that, then again on
  every return to the foreground.
  The newest `keep` (10) of this install's files are kept.
- **Restore:** "Restore from a backup" (or the one-time offer on a new
  install, `offerRestore`) picks a file with Android's picker, checks it is
  this app's (applicationId), backs up the current data first, replaces
  the folders and preferences, restores the extras and restarts the app.

```dart
final backup = FullBackup(
  config: const FullBackupConfig(
    appName: 'BestToDo',                  // Download/BestToDo/Backups
    excluded: {'pre_update_backup'},      // below every root
  ),
  version: AppConfig.version,
  build: AppConfig.buildNumber,
  prefs: prefs,
  platform: updatePlatform,               // the controller's
);
await backup.init();                       // before the app writes prefs
final updates = UpdateController(/* … */ beforeInstall: backup.beforeUpdate);
// Settings:     FullBackupTiles(backup: backup)
// First frame:  backup.offerRestore(context)
```

## Wiring an app

```yaml
# pubspec.yaml
dependencies:
  mfficiency_updates:
    path: packages/mfficiency_updates
```

```dart
import 'package:mfficiency_updates/mfficiency_updates.dart';

final updates = UpdateController(
  config: UpdateConfig(
    appName: 'Hally Remote',             // APK file name
    version: AppConfig.version,          // running x.y.z
    build: AppConfig.buildNumber,        // running versionCode
    channel: AppConfig.channel,          // shown as "· dev"; default main
    githubRepo: 'Mfficiency/hally_remote',
    tagPrefix: 'v',                      // 'music-v' for a second app
    privateRepo: true,                   // optional
    tokenProvider: () => secrets.read('updates.github_token'),
    autoCheck: () => settings.autoCheck, // the user's switch
    autoCheckChanges: settings,          // a Listenable; or autoCheckChanged()
    pollInterval: const Duration(minutes: 15),
  ),
  store: SharedPreferencesUpdateStore(prefs),
  platform: UpdatePlatform(openUrl: openInBrowser), // desktop / web links
  promptAllowed: onboardingDone,       // ValueListenable<bool>, optional
  beforeInstall: (update, apk) => backup.snapshot(), // optional
  strings: (context) => UpdateStrings(install: context.l10n.updateInstall /* … */),
  log: (level, event, data) => Log.i(event, data: data),
);
await updates.init();                 // before the first frame (no network)
// after the first frame, with a context above every screen:
updates.start(context);
```

### Config

| `UpdateConfig` | Default | |
|---|---|---|
| `appName`, `version`, `build` | required | APK file name, running x.y.z and versionCode |
| `channel` | `'main'` | shown as " · dev"; every channel is the same app |
| `provider` | `github` | or `manifest` (`manifestUrl`) |
| `githubRepo` | `''` | "owner/repo"; empty = not configured |
| `tagPrefix` | `'v'` | `'music-v'` for a second app in the repo |
| `buildPrefix` | `''` | `'b'` for `…-b3600000` |
| `strictTags` | `false` | only `<prefix><x.y.z>[-+]<buildPrefix><build>[-dev\|-staging]`, nothing else |
| `tagPattern` | null | own RegExp, named groups `version`, `build`, `channel` |
| `assetPattern` | first `.apk` | which asset is the APK |
| `requireApk` | `true` | releases without an APK are never offered; false = offered with the release page |
| `privateRepo`, `tokenProvider` | `false`, null | token for a private repo; a public one with a token also downloads with it (ready to turn private) |
| `autoCheck` | always on | the user's switch |
| `autoCheckChanges` | null | `Listenable` that fires when the switch may have changed |
| `includePrereleases` | on | |
| `legacyBuildLimit` | `0` | staging/dev builds below it are never offered |
| `checkInterval` | 24 h | the start check runs when the last one is older |
| `pollInterval` | zero (off) | checks while in the foreground |
| `checkOnResume` | `true` | check when back in the app and older than `dueAfter` |
| `firstCheckDelay` | 3 s | after the first frame |
| `rateLimitPause` | 30 min | pause when GitHub names no reset |
| `userAgent` | `<appName>-update-check` | default dart:io HTTP + downloader (spaces removed) |
| `releasesPerPage`, `releaseListCache` | 30, 1 h | |

| `UpdateController(…)` | |
|---|---|
| `http`, `downloader`, `platform` | seams; `UpdatePlatform(supported:, openUrl:)` |
| `strings`, `showMessage`, `log`, `clock` | texts, SnackBar, log events, time |
| `promptAllowed` | `ValueListenable<bool>`: Android's dialog only opens by itself while true |
| `beforeInstall` | `Future<void> Function(UpdateResult, String apkPath)` before the installer |

Then show it:

| Where | What |
|---|---|
| above the screens | `UpdateBanner(controller: updates)` |
| changelog header | `UpdateStatusCard(controller: updates)`; pull-down → `updates.refresh()` |
| changelog version tap | `updates.onVersionTap(context, '1.2.0')` (older-versions sheet) |
| settings / about | `UpdateCheckTile(controller: updates)`, or your own tile with `checkTileTitle(context)`, `checkTileSubtitle(context)`, `checkSummary(context)` and `checkNow(context)` |
| token saved/removed | `updates.reloadToken()` |
| app's own long work | `RemainingTime()..start()`, then `label(done)` under its progress: "00:01:23 remaining" for work over 30 s |

State to listen to: the controller itself (a `ChangeNotifier`) or
`result`, `checking`, `downloading`, `downloadProgress`, `ready`, `failed`,
`downloaded`, `installedAt`; `statusLabel(strings)`, `progressLabel(strings)`,
`rateLimited` / `pausedUntil`.

Seams (all optional): `http:` (`UpdateHttp.from(...)` for the app's own client
with cache/offline handling; the default uses dart:io), `downloader:`
(`ApkDownloader`), `platform:` (`UpdatePlatform`, e.g. `supported: false` in
tests), `showMessage:` (default: a SnackBar), `clock:`. Strings default to
English; pass the app's translations and region date formats through
`UpdateStrings`. Store keys stay `state.updates.lastCheck`,
`state.updates.downloaded`, `state.updates.installedBuild`,
`state.updates.installedAt`, plus `state.updates.pausedUntil`.

### Moving an app's old update state

An app that had its own updater carries its records over once, in `main`
before `UpdateController.init` (it does nothing once the old keys are gone):

```dart
await migrateLegacyUpdateState(
  prefs,
  legacyKeys: const ['update_last_checked', 'update_last_download', 'update_apk'],
  deleteExternalUpdatesFolder: true, // DownloadManager's <external files>/updates
  read: (p) {
    final d = jsonDecode(p.getString('update_last_download') ?? 'null');
    final v = d is Map ? parseLegacyVersion('${d['version']}') : null; // "0.2.106+414"
    return LegacyUpdateRecords(
      lastCheck: DateTime.fromMillisecondsSinceEpoch(p.getInt('update_last_checked') ?? 0),
      downloaded: v == null ? null : (version: v.version, build: v.build,
          at: DateTime.fromMillisecondsSinceEpoch(d['at'] as int)),
      installedBuild: null, installedAt: null, // the first start of a build, if kept
      files: [if (p.getString('update_apk') case final f?) f],
    );
  },
);
```

`read` is the app's own parsing (each app stored other keys and formats);
the helper writes only package keys that are still empty, removes every
`legacyKeys` entry (also when `read` throws) and deletes the old APKs. An
update downloaded but not yet installed isn't carried over: it downloads
once more, silently.

**Android:** nothing in the app. The plugin brings `REQUEST_INSTALL_PACKAGES`,
the install receiver and the channel `mfficiency_updates` (`installApk`,
`canInstallApks`, `openInstallSettings`, `installTime`, `openUrl`). Remove any
`ApkInstaller`/`installApk` code and the permission from the app's own
`MainActivity` and manifest. Every build must be signed with the same key to
install over the previous one.

## Vendoring rule

The package lives in `flutter_app_template/packages/mfficiency_updates`.
The template repo is private, so apps don't reference it by git: each app
keeps an exact copy in `<app>/packages/mfficiency_updates`, refreshed from
the template with

```
sh tool/sync_updates_package.sh <app folder>     # in the template (any POSIX sh)
powershell -ExecutionPolicy Bypass -File tool\sync_updates_package.ps1 <app folder>
```

It replaces the app's copy (stale files deleted), writes `ORIGIN` (template
commit, date, the sha256 of every file with CR bytes removed) and
`test/updates_package_vendored_test.dart`, which fails when a vendored file
was edited, added or deleted by hand. **Never edit an app's copy:** change
the template's package, run its tests, then sync every app.

## Tests

`flutter test` in this folder: release parsing and selection (tag formats,
channel order, APK-less releases, rate-limit answers), the controller's flow
(silent download, install once, token, manifest, older versions, records),
the shared behaviour (resume check, the switch, rate-limit pause, opener,
pre-install hook, held-back prompt; `behaviour_test.dart`), the widgets, the
default HTTP's User-Agent and headers and the downloader against a local
server (Range resume, If-Range, 416), the legacy migration and the vendoring
check. Changes: CHANGELOG.md. Dart 3.0 compatible
(the lowest constraint of the apps).

## Settings rows (the same in every app)

Every Mfficiency app shows these rows in this order (docs/CONCEPT.md §5 in
the template); each is a plain `ListTile` widget the app puts into its own
settings list, with its strings:

| Section | Rows |
|---|---|
| Debugging | `ProblemReportSendTile` (Send a report) · `ProblemReportSettingsTile` (GitHub token) |
| Updates | the app's "check automatically" switch · `UpdateCheckTile` · `UpdateTokenTile` (GitHub token: `readToken`/`writeToken`, then `controller.reloadToken()`; pair it with `UpdateConfig.tokenProvider`) |
| Backup & data | `FullBackupNowTile` · `FullBackupRestoreTile` · `FullBackupLocationTile` · `FullBackupScheduleTile` (Off/Daily/Weekly) · `FullBackupLastTile` — or `FullBackupTiles`, all five in that order |

All three GitHub tokens (problem reports, updates, other apps) open the same
`GithubTokenDialog`: field first (show, copy), one short line, the steps
folded under "How to get a token", Close always visible, saved as typed.
The rows only say "Token set" or "No token".
