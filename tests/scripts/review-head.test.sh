#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
S="$ROOT/skills/lap/scripts/review-head.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q -b main repo && cd repo || exit 1
git config user.email t@example.com; git config user.name t
echo a > app.txt; git add .; git commit -qm base
git switch -qc feat/t-1; echo b >> app.txt; git commit -qam "feat: b"; OLD=$(git rev-parse HEAD)
# Same tree, different author and message: the commit was re-authored.
git -c user.name=other -c user.email=o@example.com commit -q --amend --reset-author -m "feat: b again"; TIP=$(git rev-parse HEAD)
git switch -qc feat/t-2 main; echo c >> app.txt; git commit -qam "feat: c"; C1=$(git rev-parse HEAD)
echo d >> app.txt; git commit -qam "feat: d"

rev() { printf -- '---\nhead_sha: %s\n%s---\nBody\n' "$1" "${2:-}" > "$tmp/review.md"; }

rev "$TIP"; out=$(bash "$S" "$tmp/review.md" feat/t-1); code=$?
assert_eq "0:ok" "$code:$out" "tip match is ok"
rev "$(printf '%s' "$TIP" | cut -c1-12)"; out=$(bash "$S" "$tmp/review.md" feat/t-1); code=$?
assert_eq "0:ok" "$code:$out" "a short head_sha prefix is ok"
rev "$OLD"; out=$(bash "$S" "$tmp/review.md" feat/t-1); code=$?
assert_eq "0:same-tree $(printf '%s' "$TIP" | cut -c1-8)" "$code:$out" "re-authored commit with the same tree"
rev "$C1"; out=$(bash "$S" "$tmp/review.md" feat/t-2); code=$?
assert_eq "1:stale" "$code:$out" "changed code is stale"
rev "$C1" "rereviewed_head: $(git rev-parse feat/t-2 | cut -c1-10)
"; out=$(bash "$S" "$tmp/review.md" feat/t-2); code=$?
assert_eq "0:ok" "$code:$out" "rereviewed_head match is ok"
rev "$C1" "rereviewed_head: ${C1}
"; out=$(bash "$S" "$tmp/review.md" feat/t-2); code=$?
assert_eq "1:stale" "$code:$out" "an old rereviewed_head is stale"

bash "$S" "$tmp/none.md" feat/t-1 >/dev/null 2>&1; assert_eq 2 $? "missing file is bad input"
printf -- '---\ntitle: x\n---\n' > "$tmp/nohead.md"
bash "$S" "$tmp/nohead.md" feat/t-1 >/dev/null 2>&1; assert_eq 2 $? "no head_sha is bad input"
rev "$TIP"; bash "$S" "$tmp/review.md" no-such >/dev/null 2>&1; assert_eq 2 $? "unknown branch is bad input"
bash "$S" >/dev/null 2>&1; assert_eq 2 $? "usage"
finish
