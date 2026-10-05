#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
out=$(node --test "$ROOT/tests/node/notion-page.test.mjs" 2>&1); code=$?
assert_eq 0 "$code" "notion-page node tests pass"
[ "$code" -eq 0 ] || echo "$out" | tail -40
finish
