#!/bin/sh
# Bump version and run flutter build with given arguments, then
# rename the resulting artifact to include the version number.

# Update version numbers in pubspec.yaml and other files.
dart run tool/bump_version.dart

# Run one small unit test as a build gate.
flutter test test/build_smoke_test.dart

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

# Android APK
rename_if_exists "build/app/outputs/flutter-apk/app-release.apk" \
  "build/app/outputs/flutter-apk/app-release-${VERSION}.apk"

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
