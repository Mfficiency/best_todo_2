#!/bin/sh
# Bump version and run flutter build with given arguments, then
# rename the resulting artifact to include the version number.

# `all` is not a flutter target: it means "everything this project ships"
# (Android APK + Windows exe, staged into github_releases/ and pushed).
# `sh tool/build.sh all --release` hands over to tool/build_all.sh, which
# calls back into this script once per real target.
if [ "$1" = "all" ]; then
  shift
  exec sh tool/build_all.sh "$@"
fi

# No version bump here: tool/bump_version.dart requires an explicit
# `<version> [changelog entry]` (see the "bump, sync and build" workflow), so
# calling it argument-less only printed its usage line on every build. Bump
# first, then build:  dart run tool/bump_version.dart 0.1.258 "what changed"

# Extract the version string from pubspec.yaml. Versioned release artifact names
# are the cache key for deciding whether this build already exists.
VERSION=$(grep '^version:' pubspec.yaml | cut -d ' ' -f2)

is_cacheable_release_build() {
  [ "$#" -gt 0 ] || return 1
  shift

  for arg in "$@"; do
    case "$arg" in
      --release)
        ;;
      *)
        return 1
        ;;
    esac
  done
  return 0
}

existing_build_artifact() {
  version="$1"
  shift

  [ "$FORCE_BUILD" = "1" ] && return 1
  is_cacheable_release_build "$@" || return 1

  target="$1"
  case "$target" in
    apk)
      for path in \
        "github_releases/best_todo_${version}.apk" \
        "build/app/outputs/flutter-apk/best_todo_${version}.apk"
      do
        [ -e "$path" ] && printf '%s\n' "$path" && return 0
      done
      ;;
    web)
      [ -d "build/web-${version}" ] &&
        printf '%s\n' "build/web-${version}" &&
        return 0
      ;;
    windows)
      [ -e "build/windows/x64/runner/Release/BestToDo-${version}.exe" ] &&
        printf '%s\n' "build/windows/x64/runner/Release/BestToDo-${version}.exe" &&
        return 0
      ;;
    macos)
      [ -d "build/macos/Build/Products/Release/best_todo_2-${version}.app" ] &&
        printf '%s\n' "build/macos/Build/Products/Release/best_todo_2-${version}.app" &&
        return 0
      ;;
    linux)
      [ -d "build/linux-${version}" ] &&
        printf '%s\n' "build/linux-${version}" &&
        return 0
      ;;
  esac

  return 1
}

EXISTING_ARTIFACT=$(existing_build_artifact "$VERSION" "$@")
if [ -n "$EXISTING_ARTIFACT" ]; then
  echo "==> existing release build found: $EXISTING_ARTIFACT"
  echo "    skipping flutter build (set FORCE_BUILD=1 to rebuild)"

  case "$1:$EXISTING_ARTIFACT" in
    apk:build/app/outputs/flutter-apk/*)
      dart run tool/stage_local_release.dart --apk "$EXISTING_ARTIFACT"
      ;;
  esac

  if [ "$PUBLISH_APK" = "1" ]; then
    case "$EXISTING_ARTIFACT" in
      *.apk)
        dart run tool/publish_apk.dart --apk "$EXISTING_ARTIFACT"
        ;;
      *)
        dart run tool/publish_apk.dart
        ;;
    esac
  fi

  exit 0
fi

# Pull the latest CI test report from GitHub into assets/test_report.json so
# this local build bundles real test results the app can show offline. Network
# failures are non-fatal (keeps the existing asset), so offline builds still work.
# SKIP_PREFLIGHT=1 skips the report pull and the test gate -- set by
# tool/build_all.sh for its second and later targets, which already ran both.
if [ "$SKIP_PREFLIGHT" != "1" ]; then
  dart run tool/pull_test_report.dart

  # Run one small unit test as a build gate.
  flutter test test/core/build_smoke_test.dart
fi

# Build using Flutter with any arguments passed to this script, timing it so
# the duration can be recorded alongside the finish time.
BUILD_START=$(date +%s)
flutter build "$@"
BUILD_STATUS=$?
BUILD_DURATION=$(( $(date +%s) - BUILD_START ))

# Record when this build finished (and how long it took) in CHANGELOG.md: a
# "- Local build: <time>" line plus a "- Build duration (<target>): <time>"
# line in the newest version's section, each updated in place on repeat
# builds. Also appends a record to build_history.json (committed, so build
# times are tracked across builds/machines over time). CHANGELOG.md is
# bundled as an app asset by the `flutter build` above, so this build's own
# asset already froze the old text -- only the *next* build will show this
# timestamp/duration. That's expected.
if [ "$BUILD_STATUS" -eq 0 ]; then
  dart run tool/append_build_time.dart --duration "$BUILD_DURATION" --target "$1"
else
  # Don't rename or stage artifacts left over from an earlier build.
  echo "flutter build $* failed (status $BUILD_STATUS)" >&2
  exit "$BUILD_STATUS"
fi

# Helper to rename a file if it exists.
rename_if_exists() {
  if [ -e "$1" ]; then
    mv "$1" "$2"
    echo "Renamed $1 -> $2"
  fi
}

# Android APK -> best_todo_<version>.apk
rename_if_exists "build/app/outputs/flutter-apk/app-release.apk" \
  "build/app/outputs/flutter-apk/best_todo_${VERSION}.apk"

# Keep the last two APKs in github_releases/ (newest + one version back): the
# app's About page reads that folder for both its "Download & install" and its
# "Go back to …" button. Commit the folder for the build to reach the app.
if [ -e "build/app/outputs/flutter-apk/best_todo_${VERSION}.apk" ]; then
  dart run tool/stage_local_release.dart \
    --apk "build/app/outputs/flutter-apk/best_todo_${VERSION}.apk"
fi

# Web build directory
if [ -d build/web ]; then
  mv build/web "build/web-${VERSION}"
  echo "Renamed build/web -> build/web-${VERSION}"
fi

# Windows executable (stays inside its bundle -- the exe locates data/
# by directory, not by name, so the renamed copy still runs).
rename_if_exists "build/windows/x64/runner/Release/BestToDo.exe" \
  "build/windows/x64/runner/Release/BestToDo-${VERSION}.exe"

# macOS application bundle
rename_if_exists "build/macos/Build/Products/Release/best_todo_2.app" \
  "build/macos/Build/Products/Release/best_todo_2-${VERSION}.app"

# Linux bundle directory
if [ -d build/linux/outputs/flutter-linux-x64/release/bundle ]; then
  mv build/linux/outputs/flutter-linux-x64/release/bundle \
     "build/linux-${VERSION}"
  echo "Renamed linux bundle"
fi

# Optionally publish the APK to a GitHub release, where the app's About page
# "Check for updates" button looks for new versions. Opt-in:
#   PUBLISH_APK=1 sh tool/build.sh apk --release
# Needs a GitHub token (GITHUB_TOKEN / GH_TOKEN, or a logged-in gh CLI).
if [ "$PUBLISH_APK" = "1" ]; then
  dart run tool/publish_apk.dart
fi

exit "$BUILD_STATUS"
