# mfficiency_updates

In-app updates from GitHub Releases for the Mfficiency Flutter apps, one
implementation for all of them (template, Hally Remote, BestCollage, BestToDo +
Best Music, Vesta Immo). A Flutter plugin: Dart core + widgets, and the
Android installer (other platforms: checks only, no install).

## What it does

- **Source:** the GitHub Releases of one repo (`owner/repo`), all channels
  (tags `<prefix><x.y.z>-<build>[-dev|-staging]`, pre-releases included unless
  turned off, drafts never), filtered by the app's tag prefix (`v`,
  `music-v`, …). The release with the **highest build number** is offered when
  it is above the running build (Android's versionCode), whatever its x.y.z.
  Private repos: a token (`Authorization: Bearer`, asset download through a
  short-lived signed link). Or a JSON manifest
  `{"version", "build", "url", "notes"}`.
- **When:** on the first frame if the last check is older than
  `checkInterval`, every `pollInterval` while in the foreground, on pull-down
  in the changelog (`refresh`), from "Check for updates" (`checkNow`).
- **Download:** always silent, in-app (`HttpClient`) into
  `<cache>/updates/` as `<App>-<x.y.z>-<build>.apk.part`, renamed when
  complete, reused after a restart, and **continued with a Range request**
  after an interruption (`If-Range`, so a replaced file starts over). No
  dialog, sheet, notification or progress popup; progress only as state
  (`downloading`, `downloadProgress`) for passive text. A tap that starts a
  download shows one SnackBar.
- **Install:** when complete, a PackageInstaller session; Android's "Update
  this app?" is the only confirm. By itself only while the app is in the
  foreground and once per build per start; always after a tap. Without the
  "install unknown apps" switch it opens that switch, explains it in a
  SnackBar and installs when the app is back. Cancelled: a slim "Update ready
  · <version>" banner with Install until installed. A failed download: a
  banner with Try again (silent again).
- **Records** (in the app's store): when an APK completed (`downloaded`),
  when the running build was installed (`installedAt`: Android's
  `lastUpdateTime`, else the first start of the build), `lastCheck`.
- **Older versions:** tapping a version in the changelog lists the highest
  build of that x.y.z; its download is silent, then Android asks (rollback).

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
    pollInterval: const Duration(minutes: 15),
  ),
  store: SharedPreferencesUpdateStore(prefs),
  strings: (context) => UpdateStrings(install: context.l10n.updateInstall /* … */),
  log: (level, event, data) => Log.i(event, data: data),
);
await updates.init();                 // before the first frame (no network)
// after the first frame, with a context above every screen:
updates.start(context);
```

Then show it:

| Where | What |
|---|---|
| above the screens | `UpdateBanner(controller: updates)` |
| changelog header | `UpdateStatusCard(controller: updates)`; pull-down → `updates.refresh()` |
| changelog version tap | `updates.onVersionTap(context, '1.2.0')` (older-versions sheet) |
| settings / about | `UpdateCheckTile(controller: updates)`, or your own tile with `checkTileTitle(context)`, `checkTileSubtitle(context)`, `checkSummary(context)` and `checkNow(context)` |
| token saved/removed | `updates.reloadToken()` |

State to listen to: the controller itself (a `ChangeNotifier`) or
`result`, `checking`, `downloading`, `downloadProgress`, `ready`, `failed`,
`downloaded`, `installedAt`; `statusLabel(strings)`, `progressLabel(strings)`.

Seams (all optional): `http:` (`UpdateHttp.from(...)` for the app's own client
with cache/offline handling; the default uses dart:io), `downloader:`
(`ApkDownloader`), `platform:` (`UpdatePlatform`, e.g. `supported: false` in
tests), `showMessage:` (default: a SnackBar), `clock:`. Strings default to
English; pass the app's translations and region date formats through
`UpdateStrings`. Store keys stay `state.updates.lastCheck`,
`state.updates.downloaded`, `state.updates.installedBuild`,
`state.updates.installedAt`.

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
tool/sync_updates_package.sh <app folder>        # in the template
powershell -ExecutionPolicy Bypass -File tool\sync_updates_package.ps1 <app folder>
```

It replaces the app's copy (stale files deleted), writes `ORIGIN` (template
commit, date, the sha256 of every file with CR bytes removed) and
`test/updates_package_vendored_test.dart`, which fails when a vendored file
was edited, added or deleted by hand. **Never edit an app's copy:** change
the template's package, run its tests, then sync every app.

## Tests

`flutter test` in this folder: release parsing and selection, the
controller's flow (silent download, install once, token, manifest, older
versions, records), the widgets, the downloader against a local server
(Range resume, If-Range, 416) and the vendoring check. Dart 3.0 compatible
(the lowest constraint of the apps).
