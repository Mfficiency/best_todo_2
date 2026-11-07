#!/bin/sh
# Stop hook (.claude/settings.json): a request is only finished when its work
# is merged into dev and pushed (see CLAUDE.md, "Every request ends on dev").
# Blocks Claude from stopping while this repo has uncommitted changes to
# tracked files, or commits that are on none of origin/dev, origin/staging,
# origin/main. A repo without a dev branch uses main. Asks once per stop: if
# the merge is impossible (e.g. a push is refused), Claude says why instead.
input=$(cat)
case "$input" in
  *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
git remote get-url origin >/dev/null 2>&1 || exit 0

target=dev
if ! git ls-remote --exit-code --heads origin dev >/dev/null 2>&1; then
  target=main
fi
git fetch -q origin 2>/dev/null

refs=""
for b in dev staging main; do
  if git rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null; then
    refs="$refs origin/$b"
  fi
done
[ -n "$refs" ] || exit 0

# shellcheck disable=SC2086
unmerged=$(git rev-list --count HEAD --not $refs 2>/dev/null || echo 0)
dirty=$(git status --porcelain --untracked-files=no | head -n 1)
[ "$unmerged" = 0 ] && [ -z "$dirty" ] && exit 0

why=""
[ -n "$dirty" ] && why="uncommitted changes"
if [ "$unmerged" != 0 ]; then
  [ -n "$why" ] && why="$why and "
  why="${why}$unmerged commit(s) not in origin/$target"
fi
printf '{"decision":"block","reason":"This repo has %s. Every request ends on %s: commit, merge origin/%s into your branch, run the checks, merge the branch into %s and push %s (git push origin %s). Only staging/main when asked."}\n' \
  "$why" "$target" "$target" "$target" "$target" "$target"
