#!/usr/bin/env bash
# Report how far a ticket branch has drifted from the latest base. Never fetches: the caller does.
# Usage: drift.sh <branch> <base-ref>   (base-ref such as origin/main)
# Prints: behind <n> / overlap <files changed on both sides, or none> / conflict yes|no|unknown
# Exit: 0 no conflict (or unknown), 1 conflict, 2 bad input.
set -u
usage="usage: drift.sh <branch> <base-ref>"
br=${1:-}; base=${2:-}
[ -n "$br" ] && [ -n "$base" ] || { echo "$usage" >&2; exit 2; }
git rev-parse -q --verify "$br^{commit}" >/dev/null || { echo "unknown branch: $br" >&2; exit 2; }
git rev-parse -q --verify "$base^{commit}" >/dev/null || { echo "unknown base: $base" >&2; exit 2; }

echo "behind $(git rev-list --count "$br..$base")"

mb=$(git merge-base "$br" "$base" 2>/dev/null) || mb=""
overlap=none
if [ -n "$mb" ]; then
  mine=$(git diff --name-only "$mb" "$br")
  theirs=$(git diff --name-only "$mb" "$base")
  both=$(printf '%s\n' "$mine" | while IFS= read -r f; do
    [ -n "$f" ] && printf '%s\n' "$theirs" | grep -qxF -e "$f" && printf '%s\n' "$f"
  done | tr '\n' ' ' | sed 's/ $//')
  [ -z "$both" ] || overlap=$both
fi
echo "overlap $overlap"

git merge-tree --write-tree --name-only "$base" "$br" >/dev/null 2>&1
case $? in
  0) echo "conflict no" ;;
  1) echo "conflict yes"; exit 1 ;;
  *) echo "conflict unknown"; echo "drift.sh: this git cannot run merge-tree --write-tree (needs git 2.38+)" >&2 ;;
esac
exit 0
