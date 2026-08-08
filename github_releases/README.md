# Kept builds

The last two release APKs, so the app can update itself and roll back without a store.

- Filled by `dart run tool/stage_local_release.dart` (run automatically by
  `tool/build.sh`): it copies the freshly built APK in as
  `best_todo_<x.y.z+build>.apk` and deletes everything older than the newest two.
- The app's About page → "Check for updates" reads this folder over the public
  contents API (`UpdateService.folderContentsUrl`, branch `dev`): the newest APK is the
  "Download & install" target, the other one is "Go back to <version>".
- So a build only reaches the app once this folder is committed and pushed.
- Going back a version is a downgrade, which Android's package installer refuses for
  release builds — uninstall the current app first if the install is rejected.
