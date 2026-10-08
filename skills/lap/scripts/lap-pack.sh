#!/usr/bin/env bash
# Copy Planned tickets into a lap folder inside the work project, so a devbox job (which sees only the repo) can read them.
# Usage: lap-pack.sh [--vault <dir>] [--lessons <file>] [--resume <id>=<ref>]... <project-root> <lap-id> <ticket-workspace>...
# Writes <root>/docs/gauntlet/<lap-id>/tickets/<id>/{state,ticket,bar,context,design,plan,rulings,scope}, tickets.tsv
# and tools/ (scripts the lead runs). With --vault, also each ticket's prior-art/ (prior-art.sh) and the vault's
# learnings/ notes. With --resume, the ticket's unfinished branch <ref> (built on the root's HEAD, the lap base)
# goes in resume/<id>.bundle, listed in resume/resume.tsv, so a resumed lap keeps the work a lost lap finished.
# With --lessons, the owner's kept lap lessons go in lap-lessons.md (a missing file means none kept yet).
# Exit: 0 packed, 2 bad input (nothing written).
set -u
usage="usage: lap-pack.sh [--vault <dir>] [--lessons <file>] [--resume <id>=<ref>]... <project-root> <lap-id> <ticket-workspace>..."
vault=""; resumes=""; lessons=""
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) [ $# -ge 2 ] && [ -n "$2" ] || { echo "$usage" >&2; exit 2; }; vault=$2; shift 2 ;;
    --lessons) [ $# -ge 2 ] && [ -n "$2" ] || { echo "$usage" >&2; exit 2; }; lessons=$2; shift 2 ;;
    --resume)
      case "${2:-}" in ?*=?*) ;; *) echo "$usage" >&2; exit 2 ;; esac
      resumes="$resumes $2"; shift 2 ;;
    -*) echo "$usage" >&2; exit 2 ;;
    *) break ;;
  esac
done
root=${1:-}; lap=${2:-}
[ -n "$root" ] && [ -n "$lap" ] && [ $# -ge 3 ] || { echo "$usage" >&2; exit 2; }
shift 2
[ -d "$root" ] || { echo "no such project folder: $root" >&2; exit 2; }
[ -z "$vault" ] || [ -d "$vault/tickets" ] || { echo "no vault tickets folder: $vault/tickets" >&2; exit 2; }
printf '%s' "$lap" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || { echo "bad lap id: $lap" >&2; exit 2; }
dest="$root/docs/gauntlet/$lap"
[ ! -e "$dest" ] || { echo "lap folder exists, not overwritten: $dest" >&2; exit 2; }

REQUIRED="state.md ticket.md bar.md design.md plan.md rulings.md scope.txt"
OPTIONAL="context.md"
get() { sed -n "s/^$1: //p" "$2/state.md" 2>/dev/null | head -n 1; }

# Check every ticket and resume branch before writing anything.
errs=""; ids=" "
for ws in "$@"; do
  id=$(basename "$ws")
  [ -d "$ws" ] || { errs="$errs$id: no such workspace\n"; continue; }
  for f in $REQUIRED; do [ -f "$ws/$f" ] || errs="$errs$id: missing $f\n"; done
  [ -f "$ws/state.md" ] || continue
  t=$(get ticket "$ws"); ids="$ids${t:-$id} "
  ph=$(get phase "$ws")
  [ "$ph" = approved ] || errs="$errs$id: phase ${ph:-none}, not approved (Planned)\n"
done
lapbase=$(git -C "$root" rev-parse -q --verify HEAD 2>/dev/null)
for r in $resumes; do
  rid=${r%%=*}; ref=${r#*=}
  case "$ids" in *" $rid "*) ;; *) errs="$errs$rid: resume for a ticket not in this lap\n"; continue ;; esac
  [ -n "$lapbase" ] || { errs="$errs$rid: the project folder is not a git checkout\n"; continue; }
  git -C "$root" rev-parse -q --verify "$ref^{commit}" >/dev/null || { errs="$errs$rid: unknown resume ref $ref\n"; continue; }
  if ! git -C "$root" merge-base --is-ancestor "$lapbase" "$ref"; then
    errs="$errs$rid: resume branch is not built on the lap base\n"
  elif [ "$(git -C "$root" rev-list --count "$lapbase..$ref")" = 0 ]; then
    errs="$errs$rid: resume branch has no commits on the lap base\n"
  fi
done
[ -z "$errs" ] || { printf '%b' "$errs" >&2; exit 2; }

mkdir -p "$dest/tickets" || exit 2
# No base column: the lap has one base, the brief's (RULES rail 3).
printf 'id\tbranch\tdepth\ttasks\ttitle\n' > "$dest/tickets.tsv"
for ws in "$@"; do
  id=$(get ticket "$ws"); [ -n "$id" ] || id=$(basename "$ws")
  mkdir -p "$dest/tickets/$id"
  for f in $REQUIRED $OPTIONAL; do [ -f "$ws/$f" ] && cp "$ws/$f" "$dest/tickets/$id/$f"; done
  # Prior art never blocks a lap: a failed search leaves a note instead.
  if [ -n "$vault" ] && ! bash "$(dirname "$0")/prior-art.sh" "$vault" "$ws" "$dest/tickets/$id/prior-art" >/dev/null; then
    mkdir -p "$dest/tickets/$id/prior-art"
    echo "Prior art search failed on the laptop; none packed." > "$dest/tickets/$id/prior-art/prior-art.md"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$(get branch "$ws")" "$(get depth "$ws")" "$(get tasks_total "$ws")" "$(get title "$ws")" >> "$dest/tickets.tsv"
done
if [ -n "$vault" ] && [ -d "$vault/learnings" ]; then
  mkdir -p "$dest/learnings"
  for l in "$vault/learnings"/*.md; do [ -f "$l" ] && [ "$(basename "$l")" != Learnings.md ] && cp "$l" "$dest/learnings/"; done
fi
mkdir -p "$dest/tools" && cp "$(dirname "$0")/../../v3-review/scripts/scoped-tests.sh" "$(dirname "$0")/../../v3-review/scripts/gate-select.sh" "$dest/tools/" || exit 2
[ -z "$lessons" ] || [ ! -f "$lessons" ] || cp "$lessons" "$dest/lap-lessons.md" || exit 2
if [ -n "$resumes" ]; then
  mkdir -p "$dest/resume"
  printf 'id\tref\ttip\tcommits\n' > "$dest/resume/resume.tsv"
  for r in $resumes; do
    rid=${r%%=*}; ref=${r#*=}
    git -C "$root" bundle create -q "$dest/resume/$rid.bundle" "^$lapbase" "$ref" 2>/dev/null || { echo "$rid: could not bundle $ref" >&2; exit 2; }
    printf '%s\t%s\t%s\t%s\n' "$rid" "$ref" "$(git -C "$root" rev-parse "$ref")" "$(git -C "$root" rev-list --count "$lapbase..$ref")" >> "$dest/resume/resume.tsv"
  done
fi
printf '%s\n' "$dest"
