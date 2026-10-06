#!/usr/bin/env bash
# Check a ticket branch is safe to push: built on the clean base, has commits, carries no lap files, no laptop snapshot, no tool attribution in commit messages and (with --author) only commits by the expected author.
# Usage: lap-check.sh <branch> <clean-base> [--snapshot <sha>] [--author <email>]
# Exit: 0 ok, 1 not safe (reasons printed), 2 bad input.
set -u
usage="usage: lap-check.sh <branch> <clean-base> [--snapshot <sha>] [--author <email>]"
br=${1:-}; base=${2:-}; snap=""; author=""
[ -n "$br" ] && [ -n "$base" ] || { echo "$usage" >&2; exit 2; }
shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --snapshot) [ $# -ge 2 ] && [ -n "$2" ] || { echo "$usage" >&2; exit 2; }; snap=$2; shift 2 ;;
    --author) [ $# -ge 2 ] && [ -n "$2" ] || { echo "$usage" >&2; exit 2; }; author=$2; shift 2 ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
git rev-parse -q --verify "$br^{commit}" >/dev/null || { echo "unknown branch: $br" >&2; exit 2; }
git rev-parse -q --verify "$base^{commit}" >/dev/null || { echo "unknown base: $base" >&2; exit 2; }
[ -z "$snap" ] || git rev-parse -q --verify "$snap^{commit}" >/dev/null || { echo "unknown snapshot: $snap" >&2; exit 2; }
CC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/check-commits.sh"

NL='
'
fail=""
if ! git merge-base --is-ancestor "$base" "$br"; then
  fail="${fail}not built on the clean base $base${NL}"
else
  n=$(git rev-list --count "$base..$br")
  [ "$n" -gt 0 ] || fail="${fail}no commits on top of the base${NL}"
  lapfiles=$(git diff --name-only "$base" "$br" -- docs/gauntlet)
  [ -z "$lapfiles" ] || fail="${fail}carries lap files (never push them):${NL}$(printf '%s\n' "$lapfiles" | sed 's/^/  /')${NL}"
  if [ -n "$author" ]; then
    wrong=$(git log --format='%ae %h' "$base..$br" | awk -v a="$author" '$1 != a { print "author " $1 " on " $2 }')
    [ -z "$wrong" ] || fail="${fail}${wrong}${NL}"
    wrongc=$(git log --format='%ce %h' "$base..$br" | awk -v a="$author" '$1 != a { print "committer " $1 " on " $2 }')
    [ -z "$wrongc" ] || fail="${fail}${wrongc}${NL}"
  fi
  # The attribution patterns live in scripts/check-commits.sh; it names each offending commit.
  if [ -f "$CC" ]; then
    bad=$(bash "$CC" "$base..$br" 2>/dev/null | sed -n 's/^attribution trailer in \([0-9a-f]*\) .*/\1/p')
    for h in $bad; do
      fail="${fail}attribution $(git rev-parse --short=8 "$h") (tool attribution in the commit message)${NL}"
    done
  else
    fail="${fail}attribution check unavailable: $CC is missing${NL}"
  fi
fi
if [ -n "$snap" ] && git merge-base --is-ancestor "$snap" "$br"; then
  fail="${fail}contains the laptop snapshot commit $snap (local uncommitted edits)${NL}"
fi
if [ -n "$fail" ]; then
  printf 'LAP-CHECK: not safe %s\n%s' "$br" "$fail" >&2
  exit 1
fi
printf 'LAP-CHECK: ok %s (%s commit%s on %s)\n' "$br" "$n" "$([ "$n" = 1 ] || echo s)" "$(git rev-parse --short "$base")"
