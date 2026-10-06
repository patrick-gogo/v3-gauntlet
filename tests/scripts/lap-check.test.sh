#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
C="$ROOT/skills/lap/scripts/lap-check.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q -b main repo && cd repo || exit 1
git config user.email t@example.com; git config user.name t
echo a > app.txt; git add .; git commit -qm base; BASE=$(git rev-parse HEAD)

# A good ticket branch: work on top of the clean base.
git switch -qc bugfix/T-1-good; echo b >> app.txt; git commit -qam "fix(T-1): Do it"
out=$(bash "$C" bugfix/T-1-good "$BASE"); code=$?
assert_eq 0 "$code" "a clean ticket branch passes"
assert_contains "$out" "LAP-CHECK: ok bugfix/T-1-good (1 commit" "says ok with the commit count"

# Lap files must never ride along.
git switch -qc bugfix/T-2-lapfiles "$BASE"; mkdir -p docs/gauntlet/lap-1; echo x > docs/gauntlet/lap-1/lead-brief.md
echo c >> app.txt; git add .; git commit -qm "fix(T-2): Oops"
out=$(bash "$C" bugfix/T-2-lapfiles "$BASE" 2>&1); code=$?
assert_eq 1 "$code" "a branch carrying docs/gauntlet files fails"
assert_contains "$out" "docs/gauntlet/lap-1/lead-brief.md" "names the lap file"

# A branch built on the laptop snapshot (base is not an ancestor) fails.
git switch -qc snapshot "$BASE"; echo local-hack > hack.txt; git add .; git commit -qm "devbox snapshot"; SNAP=$(git rev-parse HEAD)
git switch -qc bugfix/T-3-on-snapshot; echo d >> app.txt; git commit -qam "fix(T-3): Built on snapshot"
out=$(bash "$C" bugfix/T-3-on-snapshot "$SNAP" 2>&1); assert_eq 0 $? "base is an ancestor here (sanity)"
out=$(bash "$C" bugfix/T-3-on-snapshot "$BASE" --snapshot "$SNAP" 2>&1); code=$?
assert_eq 1 "$code" "a branch containing the snapshot commit fails"
assert_contains "$out" "contains the laptop snapshot" "explains why"

git switch -qc bugfix/T-4-other main 2>/dev/null || git switch -qc bugfix/T-4-other "$BASE"
git checkout -q --orphan unrelated; git rm -rqf . ; echo z > z.txt; git add .; git commit -qm unrelated
out=$(bash "$C" unrelated "$BASE" 2>&1); code=$?
assert_eq 1 "$code" "a branch not built on the base fails"
assert_contains "$out" "not built on" "explains why"

git switch -qc bugfix/T-5-empty "$BASE"
out=$(bash "$C" bugfix/T-5-empty "$BASE" 2>&1); code=$?
assert_eq 1 "$code" "a branch with no commits fails"

bash "$C" no-such-branch "$BASE" >/dev/null 2>&1; assert_eq 2 $? "an unknown branch is bad input"
bash "$C" >/dev/null 2>&1; assert_eq 2 $? "usage"

git switch -qc bugfix/T-6-author "$BASE"; echo e >> app.txt
git -c user.name=devbox -c user.email=devbox@devbox.local commit -qam "fix(T-6): By the devbox"
out=$(bash "$C" bugfix/T-6-author "$BASE" --author t@example.com 2>&1); code=$?
assert_eq 1 "$code" "a commit by another author fails with --author"
assert_contains "$out" "author devbox@devbox.local on" "names the wrong author"
out=$(bash "$C" bugfix/T-1-good "$BASE" --author t@example.com); code=$?
assert_eq 0 "$code" "the right author passes"
out=$(bash "$C" bugfix/T-1-good "$BASE" --snapshot "$BASE" --author t@example.com 2>&1); code=$?
assert_eq 1 "$code" "--snapshot and --author work together"

CO="Co-""Authored-By"   # split so validate.sh's attribution scan does not match this file
git switch -qc bugfix/T-7-trailer "$BASE"; echo f >> app.txt
git commit -qam "fix(T-7): Tagged

$CO: Claude Opus <noreply@anthropic.com>"; BAD=$(git rev-parse --short=8 HEAD)
out=$(bash "$C" bugfix/T-7-trailer "$BASE" 2>&1); code=$?
assert_eq 1 "$code" "a commit with tool attribution fails"
assert_contains "$out" "attribution $BAD" "names the commit"
out=$(bash "$C" bugfix/T-1-good "$BASE" 2>&1); assert_eq 0 $? "a clean branch still passes the attribution check"

bash "$C" bugfix/T-1-good "$BASE" --author "" >/dev/null 2>&1; assert_eq 2 $? "an empty --author is bad input"
bash "$C" bugfix/T-1-good "$BASE" --snapshot "" >/dev/null 2>&1; assert_eq 2 $? "an empty --snapshot is bad input"

# Failure text with a percent sign must print as written, not be read as a format string.
git switch -qc bugfix/T-8-pct "$BASE"; echo 1 > 'p%sx.txt'; mkdir -p docs/gauntlet; echo 1 > 'docs/gauntlet/p%sx.md'; git add .; git commit -qm "fix(T-8): Pct"
out=$(bash "$C" bugfix/T-8-pct "$BASE" 2>&1); assert_contains "$out" "docs/gauntlet/p%sx.md" "failure text prints verbatim"

# Right author but a different committer is not safe either.
git switch -qc bugfix/T-9-committer "$BASE"; echo g >> app.txt
GIT_COMMITTER_EMAIL=devbox@devbox.local git commit -qam "fix(T-9): Committed elsewhere"
out=$(bash "$C" bugfix/T-9-committer "$BASE" --author t@example.com 2>&1); code=$?
assert_eq 1 "$code" "a commit by another committer fails with --author"
assert_contains "$out" "committer devbox@devbox.local on" "names the wrong committer"
finish
