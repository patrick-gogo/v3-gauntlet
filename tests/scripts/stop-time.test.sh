#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
out=$(node --test "$ROOT/tests/node/stop-time.test.mjs" 2>&1); code=$?
assert_eq 0 "$code" "stop-time node tests pass"
[ "$code" -eq 0 ] || echo "$out" | tail -40
node "$ROOT/skills/lap/scripts/stop-time.mjs" 25:00 Asia/Manila >/dev/null 2>&1; assert_eq 2 "$?" "bad time exits 2"
node "$ROOT/skills/lap/scripts/stop-time.mjs" 06:30 Not/AZone >/dev/null 2>&1; assert_eq 2 "$?" "bad zone exits 2"
got=$(node "$ROOT/skills/lap/scripts/stop-time.mjs" 06:30 Asia/Manila)
case "$got" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ 06:30) assert_eq ok ok "cli prints a dated stop";; *) assert_eq "YYYY-MM-DD 06:30" "$got" "cli prints a dated stop";; esac
err=$(node "$ROOT/skills/lap/scripts/stop-time.mjs" 06:30 2>&1 >/dev/null); assert_eq 2 "$?" "missing zone exits 2"
assert_contains "$err" "usage" "missing zone prints usage"
finish
