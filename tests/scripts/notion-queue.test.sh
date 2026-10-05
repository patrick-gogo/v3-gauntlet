#!/usr/bin/env bash
# Runs the Node tests for notion-queue.mjs (Node ships with Claude Code, so it is always present).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
out=$(node --test "$ROOT/tests/node/notion-queue.test.mjs" 2>&1); code=$?
assert_eq 0 "$code" "notion-queue node tests pass"
[ "$code" -eq 0 ] || echo "$out" | tail -40
finish
