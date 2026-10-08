#!/usr/bin/env bash
# List the Python test files a change touches, so a gate runs those instead of the whole suite.
# Usage: scoped-tests.sh [--root <dir>] [--tests <dir>] [--scope <scope.txt>] [--exist-at <rev>] [--hub-max <n>] <base> [<head>]
# A file counts when it changed between <base> and <head> (default HEAD) or matches an "allow:" line of --scope.
# Listed: changed test files, tests that import a changed module, tests named after it (test_<stem>*),
# and the folder of a changed conftest.py. A module more than --hub-max tests import (default 25) is a hub:
# its importers are skipped and named on stderr, so a change to an app entry point does not list the suite.
# Only files present at <head> (and at --exist-at when given).
# Paths print relative to --root (default "."), sorted, one per line.
# Exit: 0 listed, 1 no test touches the change (nothing printed), 2 bad input.
set -u
set -f
usage="usage: scoped-tests.sh [--root <dir>] [--tests <dir>] [--scope <file>] [--exist-at <rev>] [--hub-max <n>] <base> [<head>]"
root=.; tests=tests; scope=""; at=""; hubmax=25
while [ $# -gt 0 ]; do
  case "$1" in
    --root|--tests|--scope|--exist-at|--hub-max)
      [ $# -ge 2 ] && [ -n "$2" ] || { echo "$usage" >&2; exit 2; }
      case "$1" in --root) root=$2 ;; --tests) tests=$2 ;; --scope) scope=$2 ;; --exist-at) at=$2 ;; --hub-max) hubmax=$2 ;; esac
      shift 2 ;;
    -*) echo "$usage" >&2; exit 2 ;;
    *) break ;;
  esac
done
base=${1:-}; head=${2:-HEAD}
[ -n "$base" ] || { echo "$usage" >&2; exit 2; }
case "$hubmax" in ""|*[!0-9]*) echo "$usage" >&2; exit 2 ;; esac
for rev in "$base" "$head" ${at:+"$at"}; do
  git rev-parse -q --verify "$rev^{commit}" >/dev/null || { echo "unknown revision: $rev" >&2; exit 2; }
done
[ -z "$scope" ] || [ -f "$scope" ] || { echo "scope file not found: $scope" >&2; exit 2; }
[ -z "$scope" ] || scope="$(cd "$(dirname "$scope")" && pwd)/$(basename "$scope")"
# git paths are repo-relative, so work from the top whatever folder the caller is in.
cd "$(git rev-parse --show-toplevel)" || exit 2
# Split lists on newlines only: test paths may hold spaces.
IFS='
'

root=${root%/}; tests=${tests%/}
if [ "$root" = . ]; then pre=""; else pre="$root/"; fi
tdir="$pre$tests"
NL='
'
exists() { git cat-file -e "$1:$2" 2>/dev/null; }
is_test() { case "$1" in "$tdir"/*) ;; *) return 1 ;; esac; case "${1##*/}" in test_*.py|*_test.py) return 0 ;; esac; return 1; }

all=$(git ls-tree -r --name-only "$head" -- "${root}")
changed=$(git diff --name-only "$base" "$head" -- "$root")
if [ -n "$scope" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%%#*}
    case $line in allow:*) ;; *) continue ;; esac
    g=$(printf '%s' "${line#allow:}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [ -n "$g" ] || continue
    for f in $all; do
      # shellcheck disable=SC2254
      case $f in $g) changed="$changed$NL$f" ;; esac
    done
  done < "$scope"
fi

out=""
add() { out="$out$NL$1"; }
for f in $(printf '%s\n' "$changed" | sort -u); do
  case "$f" in *.py) ;; *) continue ;; esac
  case "$f" in "$tdir"/*)
    if [ "${f##*/}" = conftest.py ]; then exists "$head" "$f" && add "${f%/*}"
    elif is_test "$f" && exists "$head" "$f"; then add "$f"; fi
    continue ;;
  esac
  case "$f" in "$pre"*) ;; *) continue ;; esac
  rel=${f#"$pre"}; mod=$(printf '%s' "${rel%.py}" | tr / .); mod=${mod%.__init__}
  last=${mod##*.}; parent=${mod%.*}; [ "$parent" = "$mod" ] && parent=""
  esc() { printf '%s' "$1" | sed 's/\./\\./g'; }
  pat="^[[:space:]]*(from $(esc "$mod")[ .]|import $(esc "$mod")([ .,]|\$))"
  [ -z "$parent" ] || pat="$pat|^[[:space:]]*from $(esc "$parent") import (.*[^A-Za-z0-9_])?$last([^A-Za-z0-9_]|\$)"
  imp=""
  for t in $(git grep -l -E "$pat" "$head" -- "$tdir" 2>/dev/null | sed "s|^$head:||"); do
    is_test "$t" && imp="$imp$NL$t"
  done
  n=$(printf '%s\n' "$imp" | sed '/^$/d' | wc -l | tr -d ' ')
  if [ "$n" -gt "$hubmax" ]; then echo "$mod: $n importing tests, skipped (hub module)" >&2; else out="$out$imp"; fi
  stem=${rel##*/}; stem=${stem%.py}
  [ "$stem" = __init__ ] && continue
  for t in $all; do
    is_test "$t" || continue
    case "${t##*/}" in "test_$stem.py"|"test_${stem}_"*.py|"${stem}_test.py") add "$t" ;; esac
  done
done

# Drop files already covered by a listed folder, then anything missing at --exist-at.
list=$(printf '%s\n' "$out" | sed '/^$/d' | sort -u)
dirs=$(printf '%s\n' "$list" | grep -v '\.py$')
final=""
for p in $list; do
  skip=""
  for d in $dirs; do case "$p" in "$d"/*) skip=1 ;; esac; done
  [ -z "$skip" ] || continue
  [ -z "$at" ] || exists "$at" "$p" || continue
  final="$final$NL${p#"$pre"}"
done
final=$(printf '%s\n' "$final" | sed '/^$/d')
[ -n "$final" ] || exit 1
printf '%s\n' "$final"
