#!/usr/bin/env bash
# PLAN's rulings batch asks only product and business rulings; obvious technical ones are accepted on their own.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
plan=$(cat "$ROOT/skills/ticket-plan/SKILL.md")
ws=$(cat "$ROOT/skills/ticket-workspace/SKILL.md")
assert_contains "$plan" "listing only the T2 and T3 rulings" "the batch lists T2 and T3 only"
assert_contains "$plan" "source: auto" "T1 rulings are recorded as accepted automatically"
assert_contains "$plan" "No T2 or T3 ruling" "a batch with nothing to ask does not stop"
assert_contains "$plan" "show T1" "the user can still ask to see the T1 rulings"
assert_not_contains "$plan" "**2. <short title>** · T1" "the batch template has no T1 block"
assert_contains "$ws" "auto" "the ruling format allows source auto"
finish
