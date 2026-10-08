#!/usr/bin/env bash
# Keep the owner's lap lessons in one file that every lap is packed with.
# Usage: lap-lessons.sh add <file> <lap-id> "<one-line lesson>"
#        lap-lessons.sh list <file>
# add creates the file (and its folder) with a heading, skips a lesson already kept (case and spacing aside)
# and appends "- <lesson> (from <lap-id>)". Exit: 0 ok (added or already kept), 2 bad input.
set -u
cmd=${1:-}; f=${2:-}
usage="usage: lap-lessons.sh add <file> <lap-id> \"<lesson>\" | list <file>"
[ -n "$f" ] || { echo "$usage" >&2; exit 2; }
norm() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }
case $cmd in
  list)
    [ -f "$f" ] || exit 0
    grep '^- ' "$f" ;;
  add)
    lap=${3:-}; text=${4:-}
    [ -n "$lap" ] || { echo "$usage" >&2; exit 2; }
    case "$text" in *"
"*) echo "a lesson is one line" >&2; exit 2 ;; esac
    text=$(printf '%s' "$text" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$text" ] || { echo "empty lesson" >&2; exit 2; }
    mkdir -p "$(dirname "$f")" || exit 2
    [ -f "$f" ] || printf '# Lap lessons\n\nRules learned from earlier laps. Every lap is packed with this file; the lead follows them like house rules.\n\n' > "$f"
    want=$(norm "$text")
    while IFS= read -r line; do
      case "$line" in "- "*) ;; *) continue ;; esac
      kept=${line#- }; kept=${kept% (from *)}; kept=${kept% (lap *)}
      if [ "$(norm "$kept")" = "$want" ]; then echo "already kept: $kept"; exit 0; fi
    done < "$f"
    printf -- '- %s (from %s)\n' "$text" "$lap" >> "$f"
    echo "kept: $text" ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
