#!/bin/sh
# Build everything this project ships, in one command:
#
#   sh tool/build.sh all --release      (or: sh tool/build_all.sh --release)
#
#   1. Android APK  -> renamed best_todo_<version>.apk and copied into
#                      github_releases/ (keeping the newest two), which is
#                      where the app's About page looks for updates.
#   2. Windows exe  -> build/windows/x64/runner/Release/BestToDo-<version>.exe
#   3. git sync     -> commits github_releases/ + CHANGELOG.md and pushes the
#                      current branch, so the staged APK is actually reachable
#                      by the app (it downloads over HTTPS from the branch).
#
# Every argument is forwarded to `flutter build <target>`, so pass --release
# (or --debug, --profile, --split-per-abi ...) exactly as you would normally.
#
# Environment switches:
#   SYNC=0             build only, leave git alone
#   PUSH=0             commit the release folder but don't push
#   WINDOWS=0          skip the Windows build (APK only)
#   ANDROID=0          skip the Android build (exe only)
#   REQUIRE_WINDOWS=1  treat a failing Windows build as fatal instead of a
#                      warning (the default is lenient: a broken local Visual
#                      Studio toolchain shouldn't block shipping the APK)
#   PUBLISH_APK=1      also publish the APK to a GitHub release (see build.sh)

set -e

cd "$(dirname "$0")/.."

BUILD_ARGS="$*"
[ -n "$BUILD_ARGS" ] || BUILD_ARGS="--release"

WINDOWS_STATUS="skipped"
ANDROID_STATUS="skipped"

# --- 0. Pull latest from origin ----------------------------------------
BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "==> pulling latest from origin/$BRANCH"
git pull --rebase --autostash origin "$BRANCH"

# --- 1. Android APK -----------------------------------------------------
# The first target pays for the preflight (test-report pull + smoke test);
# later ones reuse it.
if [ "$ANDROID" != "0" ]; then
  echo "==> flutter build apk $BUILD_ARGS"
  sh tool/build.sh apk $BUILD_ARGS
  ANDROID_STATUS="ok"
  export SKIP_PREFLIGHT=1
fi

# --- 2. Windows exe -----------------------------------------------------
if [ "$WINDOWS" != "0" ]; then
  echo "==> flutter build windows $BUILD_ARGS"
  # `set -e` must not kill the run here: a missing/broken Visual Studio
  # toolchain is a local-machine problem, not a reason to drop the APK.
  if sh tool/build.sh windows $BUILD_ARGS; then
    WINDOWS_STATUS="ok"
  else
    WINDOWS_STATUS="FAILED"
    if [ "$REQUIRE_WINDOWS" = "1" ]; then
      echo "Windows build failed and REQUIRE_WINDOWS=1 -- stopping." >&2
      exit 1
    fi
    echo "Windows build failed -- continuing with the Android artifacts." >&2
  fi
  export SKIP_PREFLIGHT=1
fi

VERSION=$(grep '^version:' pubspec.yaml | cut -d ' ' -f2)

# --- 3. Sync ------------------------------------------------------------
# tool/build.sh already staged the APK into github_releases/ via
# stage_local_release.dart; committing and pushing is what makes it
# downloadable from the app.
if [ "$SYNC" = "0" ]; then
  echo "==> SYNC=0: skipping git commit/push"
else
  echo "==> syncing github_releases/ + CHANGELOG.md on $BRANCH"

  git add github_releases CHANGELOG.md

  if git diff --cached --quiet; then
    echo "    nothing to commit (github_releases/ already up to date)"
  else
    git commit -m "chore: release build $VERSION"
    echo "    committed release build $VERSION"
  fi

  if [ "$PUSH" = "0" ]; then
    echo "    PUSH=0: not pushing"
  else
    # Rebase onto the remote first so a push from another machine doesn't
    # turn this into a rejected push; --autostash keeps unrelated work.
    git pull --rebase --autostash origin "$BRANCH"
    git push origin "$BRANCH"
    echo "    pushed $BRANCH to origin"
  fi

  # The rebase above checks out the pre-commit tree for a moment, which
  # re-creates the APK stage_local_release.dart had just pruned -- now
  # untracked, so it lingers as ~60MB of dead weight and makes the summary
  # below claim it is still staged. Anything untracked in here after the
  # commit is by definition a pruned build, so drop it again.
  for stale in $(git ls-files --others --exclude-standard github_releases); do
    rm -f "$stale" && echo "    removed pruned leftover $stale"
  done
fi

# --- Summary ------------------------------------------------------------
echo ""
echo "=== build all ($VERSION) ==="
echo "  android : $ANDROID_STATUS"
echo "  windows : $WINDOWS_STATUS"
ls github_releases/*.apk 2>/dev/null | sed 's/^/  staged  : /'
if [ -e "build/windows/x64/runner/Release/BestToDo-${VERSION}.exe" ]; then
  echo "  exe     : build/windows/x64/runner/Release/BestToDo-${VERSION}.exe"
fi

if [ "$WINDOWS_STATUS" = "FAILED" ]; then
  exit 1
fi
exit 0
