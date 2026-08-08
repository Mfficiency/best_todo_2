#!/bin/sh
# Bump version and run flutter build with given arguments, then
# rename the resulting artifact to include the version number.

# Update version numbers in pubspec.yaml and other files.
dart run tool/bump_version.dart

# Pull the latest CI test report from GitHub into assets/test_report.json so
# this local build bundles real test results the app can show offline. Network
# failures are non-fatal (keeps the existing asset), so offline builds still work.
dart run tool/pull_test_report.dart

# Run one small unit test as a build gate.
flutter test test/core/build_smoke_test.dart

# Extract the new version string from pubspec.yaml
VERSION=$(grep '^version:' pubspec.yaml | cut -d ' ' -f2)

# Build using Flutter with any arguments passed to this script.
flutter build "$@"

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

# Windows executable
rename_if_exists "build/windows/runner/Release/best_todo_2.exe" \
  "build/windows/runner/Release/best_todo_2-${VERSION}.exe"

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
