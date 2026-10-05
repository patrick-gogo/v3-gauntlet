#!/usr/bin/env bash
# Derive a branch name "<type>/<ticket-id>-<slug>" from a ticket.
# Usage: branch-name.sh [--prefix <p>] [--keep-id-case] <type> <ticket-id> [title words...]
# --prefix replaces "<type>/" (a project may use bugfix/ for fix); --keep-id-case keeps V3-12 as V3-12.
set -u
prefix=""; keep_case=no
while [ $# -gt 0 ]; do
  case $1 in
    --prefix) prefix=${2:-}; shift 2 ;;
    --keep-id-case) keep_case=yes; shift ;;
    *) break ;;
  esac
done
type=${1:-}; id=${2:-}
[ -n "$type" ] && [ -n "$id" ] || { echo "usage: branch-name.sh [--prefix p] [--keep-id-case] <type> <ticket-id> [title...]" >&2; exit 2; }
shift 2
case $type in feat|fix|chore|docs|refactor|test|perf) ;; *) echo "unknown type: $type" >&2; exit 2 ;; esac
if [ -n "$prefix" ]; then
  printf '%s' "$prefix" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || { echo "bad prefix: $prefix" >&2; exit 2; }
else
  prefix=$type
fi
slug() { printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
if [ "$keep_case" = yes ]; then
  idslug=$(printf '%s' "$id" | LC_ALL=C sed -E 's/[^A-Za-z0-9]+/-/g; s/^-+//; s/-+$//')
else
  idslug=$(slug "$id")
fi
[ -n "$idslug" ] || { echo "ticket ID has no usable characters: $id (use a Latin ID such as T-1)" >&2; exit 2; }
name="$prefix/$idslug"
t=$(slug "$*")
[ -n "$t" ] && name="$name-$t"
name=$(printf '%s' "$name" | cut -c1-60 | sed -E 's/-+$//')
git check-ref-format --branch "$name" >/dev/null 2>&1 || { echo "cannot form a valid branch name from: $id $*" >&2; exit 2; }
printf '%s\n' "$name"
