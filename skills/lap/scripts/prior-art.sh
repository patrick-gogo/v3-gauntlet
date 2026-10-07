#!/usr/bin/env bash
# Find a ticket's prior art in the owner's notes vault, so a devbox lap (which has no vault) starts from what was already learned.
# Usage: prior-art.sh <vault> <ticket-workspace> <out-dir> [--cap N]
# Keys: the workspace's scope.txt "allow:" paths (globs skipped) plus the vault overview's components; the overview's feature.
# Writes <out>/prior-art.md (index) and at most N (default 3) extracts <k>-<ticket>-<kind>.md: a handoff's
# "Don't repeat" sections, an investigation's root cause, a review's TL;DR and finding titles. Never whole files.
# Exit: 0 written (an empty search included), 2 bad input (nothing written).
set -u
usage() { echo "usage: prior-art.sh <vault> <ticket-workspace> <out-dir> [--cap N]" >&2; exit 2; }
[ $# -ge 3 ] || usage
vault=${1%/}; ws=$2; out=$3; cap=3
shift 3
while [ $# -gt 0 ]; do
  case $1 in
    --cap) cap=${2:-}; shift 2 || usage ;;
    *) usage ;;
  esac
done
printf '%s' "$cap" | grep -Eq '^[0-9]+$' || { echo "bad --cap: $cap" >&2; exit 2; }
[ -d "$vault/tickets" ] || { echo "no vault tickets folder: $vault/tickets" >&2; exit 2; }
[ -f "$ws/state.md" ] || { echo "no ticket workspace: $ws" >&2; exit 2; }
if [ -e "$out" ] && [ -n "$(ls -A "$out" 2>/dev/null)" ]; then echo "out folder not empty, not overwritten: $out" >&2; exit 2; fi
T=$(printf '\t')

# Frontmatter of many files at once: "F<TAB>file<TAB>feature" and "C<TAB>file<TAB>component" lines.
FM='FNR==1{f=($0=="---");l=0;next} f&&$0=="---"{f=0;next} !f{next}
  /^feature: /{print "F\t" FILENAME "\t" substr($0,10);next}
  /^components:$/{l=1;next} l&&/^ *- /{sub(/^ *- */,"");print "C\t" FILENAME "\t" $0;next} {l=0}'

id=$(sed -n 's/^ticket: //p' "$ws/state.md" | head -n 1); [ -n "$id" ] || id=$(basename "$ws")
own="$vault/tickets/$id/overview.md"
ownfm=$([ -f "$own" ] && awk "$FM" "$own")
feature=$(printf '%s\n' "$ownfm" | awk -F "$T" '$1=="F"{print $3;exit}')
keys=$( { [ -f "$ws/scope.txt" ] && sed -n 's/^allow: *//p' "$ws/scope.txt" | grep -v '[*?[]'; printf '%s\n' "$ownfm" | awk -F "$T" '$1=="C"{print $3}'; } | sed 's#/*$##' | awk 'NF&&!s[$0]++')
searched=$(printf '%s\n' "$keys" | awk 'NF' | paste -sd, - | sed 's/,/, /g')
[ -n "$feature" ] && searched="$searched${searched:+; }feature $feature"

# Score every other ticket folder and every learning in one pass: one point per key it mentions or that sits
# inside one of its components, two for the same feature. Only folders with notes to extract count.
cands=$( { find "$vault/tickets" -mindepth 2 -maxdepth 2 -type f \( -name overview.md -o -name handoff.md -o -name 'investigation-*.md' -o -name 'review-mine-*.md' \)
  [ -d "$vault/learnings" ] && find "$vault/learnings" -maxdepth 1 -type f -name '*.md' ! -name Learnings.md; } 2>/dev/null)
scored=""
if [ -n "$cands" ]; then
  scored=$( {
    printf '%s\n' "$keys" | awk 'NF{print "K\t" NR "\t" $0}'
    printf '%s\n' "$cands" | awk '{print "E\t" $0}'
    i=0
    while IFS= read -r k; do
      [ -n "$k" ] || continue; i=$((i + 1))
      # Only file keys are searched as text: a folder name like backend/app/services is in almost every note.
      case ${k##*/} in *.*) ;; *) continue ;; esac
      printf '%s\n' "$cands" | tr '\n' '\0' | xargs -0 grep -lF -- "$k" 2>/dev/null | awk -v i=$i '{print "H\t" i "\t" $0}'
    done <<EOF
$keys
EOF
    fmfiles=$(printf '%s\n' "$cands" | grep -E '/overview\.md$|/learnings/[^/]+$')
    [ -n "$fmfiles" ] && printf '%s\n' "$fmfiles" | tr '\n' '\0' | xargs -0 awk "$FM" | awk -F "$T" -v OFS="$T" '{print $1,"-",$2,$3}'
  } | awk -F "$T" -v v="$vault/" -v own="$id" -v feat="$feature" '
    function unit(p,  a) { split(substr(p, length(v) + 1), a, "/"); return (a[1] == "tickets" ? "T" : "L") "\t" a[2] }
    function rel(k, c) { return k == c || index(k "/", c "/") == 1 }
    $1 == "K" { key[$2] = $3; nk = $2; next }
    $1 == "E" { u = unit($2); seen[u] = 1; if ($2 !~ /\/overview\.md$/) has[u] = 1; next }
    $1 == "H" { hit[unit($3), $2] = 1; next }
    $1 == "F" { fe[unit($3)] = $4; next }
    $1 == "C" { u = unit($3); cc[u, ++ncc[u]] = $4; next }
    END {
      for (u in seen) {
        split(u, p, "\t"); if (!has[u] || (p[1] == "T" && p[2] == own)) continue
        s = 0
        for (k = 1; k <= nk; k++) {
          h = hit[u, k]
          for (c = 1; !h && c <= ncc[u]; c++) if (rel(key[k], cc[u, c])) h = 1
          s += h
        }
        if (feat != "" && fe[u] == feat) s += 2
        n = p[2]; gsub(/[^0-9]/, "", n)
        if (s > 0) print u "\t" s "\t" (n == "" ? 0 : n)
      }
    }' | sort -t "$T" -k3,3nr -k4,4nr -k2,2)
fi

handoff_x() { awk 'function lvl(l){match(l,/^#+/);return RLENGTH} /^#+ /{n=lvl($0); if(on&&n<=d)on=0; t=tolower($0); if(!on&&(t~/don.?t repeat|traps|dead.?end|ruled out/)){on=1;d=n}} on' "$1"; }
inv_x() { awk '/^## /{on=(tolower($0)~/^## root cause/)} on' "$1"; }
review_x() { awk '/^## /{s=tolower($0)} s~/^## tl;dr/{print;next} s~/^## bugs/&&/^### /{print;next} s~/^## concerns/&&match($0,/^- \*\*[^*]+\*\*/){print substr($0,1,RLENGTH)}' "$1"; }

mkdir -p "$out" || exit 2
n=0; lines=""
add() { # <ticket> <kind> <file> <what> <score> <extract>; fails when there is nothing to extract
  [ -n "$6" ] || return 1
  n=$((n + 1)); f="$n-$1-$2.md"
  printf 'Source: tickets/%s/%s (%s)\n\n%s\n' "$1" "$(basename "$3")" "$4" "$6" > "$out/$f"
  lines="$lines- $f: tickets/$1/$(basename "$3") ($4), score $5
"
}
while IFS="$T" read -r kind t s _; do
  [ "$kind" = T ] || continue
  [ $n -lt "$cap" ] || break
  # One extract per ticket so a single busy ticket cannot fill the cap: the handoff's lessons first.
  d="$vault/tickets/$t"
  [ -f "$d/handoff.md" ] && add "$t" handoff "$d/handoff.md" "Don't repeat" "$s" "$(handoff_x "$d/handoff.md")" && continue
  i=$(ls "$d"/investigation-*.md 2>/dev/null | sort | tail -n 1)
  [ -n "$i" ] && add "$t" investigation "$i" "root cause" "$s" "$(inv_x "$i")" && continue
  r=$(ls "$d"/review-mine-*.md 2>/dev/null | sort | tail -n 1)
  [ -n "$r" ] && add "$t" review "$r" "TL;DR and finding titles" "$s" "$(review_x "$r")"
done <<EOF
$scored
EOF
learn=$(printf '%s\n' "$scored" | awk -F "$T" '$1=="L"{print "- learnings/" $2}' | sort)

{
  printf '# Prior art for %s\n\n' "$id"
  if [ -z "$lines" ] && [ -z "$learn" ]; then
    printf 'None found (searched: %s)\n' "${searched:-nothing}"
  else
    printf 'Searched: %s\n\n## Extracts\n%s\n## Learnings (full copies in the lap'"'"'s learnings/ folder)\n%s\n' "$searched" "${lines:-none
}" "${learn:-none}"
  fi
} > "$out/prior-art.md"
printf '%s\n' "$out/prior-art.md"
