#!/usr/bin/env bash
# Publishes a test report to the `ci-reports` branch — the one place the app and
# every build look for "the latest test run", whichever branch produced it.
#
# `ci-reports` is an orphan branch holding only JSON:
#   latest.json            newest run across all branches (newest-wins merge)
#   branches/<branch>.json newest run per branch
# It carries no app code, so writing to it never triggers a workflow, and it
# never shows up in the history of dev/staging/main.
#
# Usage: tool/ci/publish_test_report.sh [report.json] [branch]
# Needs GITHUB_TOKEN + GITHUB_REPOSITORY in the environment, and to be run from
# the repo root (it reuses tool/sync_test_report.dart for the newest-wins merge).
#
# Publishing must never fail a build: every error path exits 0 with a note.
set -uo pipefail

REPORT="${1:-assets/test_report.json}"
BRANCH="${2:-${GITHUB_REF_NAME:-unknown}}"
STORE_BRANCH="ci-reports"
WORK=".ci-reports"
SHORT_SHA="${GITHUB_SHA:0:9}"

if [ ! -f "$REPORT" ]; then
  echo "No report at $REPORT; nothing to publish."
  exit 0
fi
if [ -z "${GITHUB_TOKEN:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "GITHUB_TOKEN/GITHUB_REPOSITORY not set; skipping publish."
  exit 0
fi

REMOTE="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
SLUG="$(echo "$BRANCH" | tr '/ ' '--')"

publish() {
  rm -rf "$WORK"
  if git ls-remote --exit-code --heads "$REMOTE" "$STORE_BRANCH" >/dev/null 2>&1; then
    git clone --quiet --branch "$STORE_BRANCH" "$REMOTE" "$WORK" || return 1
  else
    echo "Creating the $STORE_BRANCH report store."
    mkdir -p "$WORK" || return 1
    git -C "$WORK" init --quiet || return 1
    git -C "$WORK" checkout --quiet -b "$STORE_BRANCH" || return 1
    git -C "$WORK" remote add origin "$REMOTE" || return 1
    cat > "$WORK/README.md" <<'EOF'
# CI test reports

Machine-written store, no app code lives here.

- `latest.json` — the newest `flutter test` run across all branches.
- `branches/<branch>.json` — the newest run per branch.

The app fetches `latest.json` (`TestReportService.onlineReportUrl`) and builds
package it into `assets/test_report.json` via `tool/sync_test_report.dart`, so
the Test Results page shows the latest run offline and on any branch.
Written by `tool/ci/publish_test_report.sh`.
EOF
  fi

  # Newest-wins, so an out-of-order or re-run job can never replace a newer run.
  dart run tool/sync_test_report.dart --no-fetch \
    --output "$WORK/latest.json" --candidate "$REPORT" || return 1
  dart run tool/sync_test_report.dart --no-fetch \
    --output "$WORK/branches/$SLUG.json" --candidate "$REPORT" || return 1

  git -C "$WORK" add -A || return 1
  if git -C "$WORK" diff --cached --quiet; then
    echo "Report store already up to date."
    return 0
  fi
  git -C "$WORK" \
    -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit --quiet -m "ci: test report from $BRANCH ($SHORT_SHA)" || return 1
  git -C "$WORK" push --quiet origin "HEAD:$STORE_BRANCH" || return 1
  echo "Published test report to $STORE_BRANCH (branch $BRANCH)."
}

for attempt in 1 2 3; do
  if publish; then
    rm -rf "$WORK"
    exit 0
  fi
  echo "Publish attempt $attempt failed; retrying."
  sleep $((attempt * 3))
done

echo "Could not publish the test report; continuing anyway."
rm -rf "$WORK"
exit 0
