#!/usr/bin/env bash
# Tell whether a review file still describes the current tip of a branch.
# Usage: review-head.sh <review-file> <branch>
# Reads head_sha: and the optional rereviewed_head: (8+ hex chars) from the YAML frontmatter.
# Prints: ok | same-tree <first 8 of the tip> (exit 0) | stale (exit 1). Bad input: message on stderr, exit 2.
set -u
usage="usage: review-head.sh <review-file> <branch>"
file=${1:-}; br=${2:-}
[ -n "$file" ] && [ -n "$br" ] || { echo "$usage" >&2; exit 2; }
[ -f "$file" ] || { echo "no review file: $file" >&2; exit 2; }
tip=$(git rev-parse -q --verify "$br^{commit}") || { echo "unknown branch: $br" >&2; exit 2; }

# fm <key>: the value of a top-level key in the first frontmatter block.
fm() {
  awk -v k="$1" '
    NR == 1 { if ($0 ~ /^---[ \t\r]*$/) { inside = 1; next } else exit }
    inside && /^---[ \t\r]*$/ { exit }
    inside { n = index($0, ":"); if (n && substr($0, 1, n - 1) == k) { v = substr($0, n + 1); gsub(/^[ \t]+|[ \t\r"\047]+$/, "", v); gsub(/^["\047]/, "", v); print v; exit } }
  ' "$file"
}
head_sha=$(fm head_sha)
[ -n "$head_sha" ] || { echo "no head_sha in $file" >&2; exit 2; }
rereviewed=$(fm rereviewed_head)

# prefix_of_tip <value>: 8+ hex chars that start the tip sha.
prefix_of_tip() {
  case $1 in *[!0-9a-fA-F]*|"") return 1 ;; esac
  [ "${#1}" -ge 8 ] || return 1
  case $tip in "$(printf '%s' "$1" | tr 'A-F' 'a-f')"*) return 0 ;; esac
  return 1
}
if prefix_of_tip "$head_sha" || { [ -n "$rereviewed" ] && prefix_of_tip "$rereviewed"; }; then
  echo ok; exit 0
fi
old_tree=$(git rev-parse -q --verify "$head_sha^{tree}" 2>/dev/null) || old_tree=""
if [ -n "$old_tree" ] && [ "$old_tree" = "$(git rev-parse "$tip^{tree}")" ]; then
  echo "same-tree $(printf '%s' "$tip" | cut -c1-8)"; exit 0
fi
echo stale; exit 1
