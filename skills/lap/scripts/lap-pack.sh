#!/usr/bin/env bash
# Copy Planned tickets into a lap folder inside the work project, so a devbox job (which sees only the repo) can read them.
# Usage: lap-pack.sh <project-root> <lap-id> <ticket-workspace>...
# Writes <root>/docs/gauntlet/<lap-id>/tickets/<id>/{state,ticket,bar,context,design,plan,rulings,scope} and tickets.tsv.
# Exit: 0 packed, 2 bad input (nothing written).
set -u
root=${1:-}; lap=${2:-}
[ -n "$root" ] && [ -n "$lap" ] && [ $# -ge 3 ] || { echo "usage: lap-pack.sh <project-root> <lap-id> <ticket-workspace>..." >&2; exit 2; }
shift 2
[ -d "$root" ] || { echo "no such project folder: $root" >&2; exit 2; }
printf '%s' "$lap" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || { echo "bad lap id: $lap" >&2; exit 2; }
dest="$root/docs/gauntlet/$lap"
[ ! -e "$dest" ] || { echo "lap folder exists, not overwritten: $dest" >&2; exit 2; }

REQUIRED="state.md ticket.md bar.md design.md plan.md rulings.md scope.txt"
OPTIONAL="context.md"
get() { sed -n "s/^$1: //p" "$2/state.md" | head -n 1; }

# Check every ticket before writing anything.
errs=""
for ws in "$@"; do
  id=$(basename "$ws")
  [ -d "$ws" ] || { errs="$errs$id: no such workspace\n"; continue; }
  for f in $REQUIRED; do [ -f "$ws/$f" ] || errs="$errs$id: missing $f\n"; done
  [ -f "$ws/state.md" ] || continue
  ph=$(get phase "$ws")
  [ "$ph" = approved ] || errs="$errs$id: phase ${ph:-none}, not approved (Planned)\n"
done
[ -z "$errs" ] || { printf "$errs" >&2; exit 2; }

mkdir -p "$dest/tickets" || exit 2
printf 'id\tbranch\tbase\tdepth\ttasks\ttitle\n' > "$dest/tickets.tsv"
for ws in "$@"; do
  id=$(get ticket "$ws"); [ -n "$id" ] || id=$(basename "$ws")
  mkdir -p "$dest/tickets/$id"
  for f in $REQUIRED $OPTIONAL; do [ -f "$ws/$f" ] && cp "$ws/$f" "$dest/tickets/$id/$f"; done
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$(get branch "$ws")" "$(get base "$ws")" "$(get depth "$ws")" "$(get tasks_total "$ws")" "$(get title "$ws")" >> "$dest/tickets.tsv"
done
printf '%s\n' "$dest"
