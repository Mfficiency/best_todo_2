#!/bin/sh
# Bump version and run flutter build with given arguments.
dart run tool/bump_version.dart
flutter build "$@"
