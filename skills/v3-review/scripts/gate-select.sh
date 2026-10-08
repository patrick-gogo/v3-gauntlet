#!/usr/bin/env bash
# Pick which gates to run for a change, from a file with a "## Gates" section (the project config or the lap RULES).
# Usage: gate-select.sh [--task | --all] <config> <base> [<head>]
# --task: only gates named in "task_gates:" (all gates when the key is absent). --all: every gate, no path filter.
# Default and --task drop a gate whose "gate_paths.<name>: <prefix>..." prefixes the change between <base> and <head> never touches.
# Prints gate names in the section's order, one per line. Exit: 0 ok, 2 bad input, 3 no "## Gates" section (use your recorded gates).
set -u
set -f
mode=full
case "${1:-}" in --task) mode=task; shift ;; --all) mode=all; shift ;; esac
cfg=${1:-}; base=${2:-}; head=${3:-HEAD}
[ -n "$cfg" ] && [ -n "$base" ] || { echo "usage: gate-select.sh [--task | --all] <config> <base> [<head>]" >&2; exit 2; }
[ -f "$cfg" ] || { echo "config not found: $cfg" >&2; exit 2; }
for rev in "$base" "$head"; do
  git rev-parse -q --verify "$rev^{commit}" >/dev/null || { echo "unknown revision: $rev" >&2; exit 2; }
done

key() { sed -n "s/^$1: *//p" "$cfg" | head -n 1 | tr -d '\r'; }
grep -q '^## Gates[[:space:]]*$' "$cfg" || { echo "no ## Gates section in $cfg: run every recorded gate" >&2; exit 3; }
names=$(awk '/^## /{ on = ($0 ~ /^## Gates[[:space:]]*$/); next } on && /^[A-Za-z0-9_.-]+:/ { sub(/:.*/, ""); print }' "$cfg")
changed=$(git diff --name-only "$base" "$head")
task_list=" $(key task_gates) "

for n in $names; do
  if [ "$mode" = task ] && [ "$task_list" != "  " ]; then
    case "$task_list" in *" $n "*) ;; *) continue ;; esac
  fi
  if [ "$mode" != all ]; then
    paths=$(key "gate_paths.$n")
    if [ -n "$paths" ]; then
      hit=""
      for p in $paths; do
        if printf '%s\n' "$changed" | grep -q "^$p"; then hit=1; break; fi
      done
      [ -n "$hit" ] || continue
    fi
  fi
  printf '%s\n' "$n"
done
