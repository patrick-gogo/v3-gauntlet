#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
S="$ROOT/skills/lap/scripts/drift.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q -b main repo && cd repo || exit 1
git config user.email t@example.com; git config user.name t
printf 'one\ntwo\nthree\n' > a.txt; printf 'x\n' > b.txt; git add .; git commit -qm base
git branch feat/clean
git switch -qc feat/over; printf 'one\ntwo\nthree\nfour\n' > a.txt; git commit -qam "feat: append"
git switch -qc feat/conf main; printf 'ONE\ntwo\nthree\n' > a.txt; git commit -qam "feat: upper"
git switch -q main; git update-ref refs/remotes/origin/main main

out=$(bash "$S" feat/clean origin/main); code=$?
assert_eq "0:behind 0|overlap none|conflict no" "$code:$(printf '%s' "$out" | tr '\n' '|')" "clean and up to date"

# Base moves: touches a.txt at the top, plus an unrelated file.
printf 'zero\none\ntwo\nthree\n' > a.txt; echo y > c.txt; git add .; git commit -qm "base moves"
git update-ref refs/remotes/origin/main main
out=$(bash "$S" feat/over origin/main); code=$?
assert_eq "0:behind 1|overlap a.txt|conflict no" "$code:$(printf '%s' "$out" | tr '\n' '|')" "behind with overlap, no conflict"
out=$(bash "$S" feat/clean origin/main); code=$?
assert_eq "0:behind 1|overlap none|conflict no" "$code:$(printf '%s' "$out" | tr '\n' '|')" "behind without overlap"
out=$(bash "$S" feat/conf origin/main); code=$?
assert_eq "1:behind 1|overlap a.txt|conflict yes" "$code:$(printf '%s' "$out" | tr '\n' '|')" "real conflict"

bash "$S" no-such origin/main >/dev/null 2>&1; assert_eq 2 $? "unknown branch is bad input"
bash "$S" feat/clean origin/nope >/dev/null 2>&1; assert_eq 2 $? "unknown base is bad input"
bash "$S" feat/clean >/dev/null 2>&1; assert_eq 2 $? "usage"
finish
