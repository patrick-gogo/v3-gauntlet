#!/usr/bin/env bash
# lap-lessons.sh keeps one file of lessons from earlier laps; every lap is packed with it.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
S="$ROOT/skills/lap/scripts/lap-lessons.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
f="$tmp/notes dir/gauntlet/lap-lessons.md"

bash "$S" add "$f" lap-1 "Scope the backend suite; the full one never finishes."; assert_eq 0 $? "adds to a new file"
assert_file "$f" "creates the file and its folder"
assert_contains "$(cat "$f")" "# Lap lessons" "the file has a heading"
assert_contains "$(cat "$f")" "- Scope the backend suite; the full one never finishes. (from lap-1)" "the lesson names its lap"

out=$(bash "$S" add "$f" lap-2 "  scope the backend suite; THE full one never finishes.  "); assert_eq 0 $? "a duplicate is not an error"
assert_contains "$out" "already kept" "a duplicate (case and spaces aside) is reported"
assert_eq 1 "$(grep -c 'Scope the backend suite' "$f")" "and not added twice"

bash "$S" add "$f" lap-2 "Lint new test files before the commit."
assert_eq 2 "$(grep -c '^- ' "$f")" "a second lesson is appended"

bash "$S" add "$f" lap-3 "" 2>/dev/null; assert_eq 2 $? "an empty lesson is refused"
bash "$S" add "$f" "" "x" 2>/dev/null; assert_eq 2 $? "a lap id is required"
bash "$S" add "$f" lap-3 "two
lines" 2>/dev/null; assert_eq 2 $? "a lesson is one line"
bash "$S" list "$f" | grep -c '^- ' > "$tmp/n"; assert_eq 2 "$(cat "$tmp/n")" "list prints the kept lessons"
bash "$S" bogus "$f" 2>/dev/null; assert_eq 2 $? "unknown command refused"
finish
