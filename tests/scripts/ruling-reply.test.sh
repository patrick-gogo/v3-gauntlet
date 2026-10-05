#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
S="$ROOT/skills/ticket-workspace/scripts/ruling-reply.sh"

out=$(bash "$S" 3 "1 keep 2 keep 3 keep"); code=$?
assert_eq 0 "$code" "all keep by number"
assert_eq "1 keep
2 keep
3 keep" "$out" "one line per ruling"

out=$(bash "$S" 3 "all keep"); assert_eq "1 keep
2 keep
3 keep" "$out" "all keep shorthand"

out=$(bash "$S" 4 "1 keep 2 change: reuse the existing modal 3 keep 4 change: drop the label"); code=$?
assert_eq 0 "$code" "mixed keep and change"
assert_eq "1 keep
2 change reuse the existing modal
3 keep
4 change drop the label" "$out" "change text kept, up to the next number"

out=$(bash "$S" 2 "1. Keep, 2. change: use 2 columns"); code=$?
assert_eq 0 "$code" "dots, commas and capitals are fine"
assert_eq "1 keep
2 change use 2 columns" "$out" "a number inside change text is not a new ruling"

out=$(bash "$S" 3 "1 keep 3 keep" 2>&1); code=$?
assert_eq 2 "$code" "a missing ruling is refused"
assert_contains "$out" "no answer for: 2" "names the missing ruling"

out=$(bash "$S" 2 "1 keep 2 keep 5 keep" 2>&1); code=$?
assert_eq 2 "$code" "an unknown number is refused"
assert_contains "$out" "no ruling 5" "names the unknown number"

out=$(bash "$S" 2 "1 keep 2 maybe" 2>&1); code=$?
assert_eq 2 "$code" "an unclear answer is refused"
assert_contains "$out" "ruling 2: say keep or change" "asks for keep or change"

out=$(bash "$S" 2 "1 keep 2 change:" 2>&1); code=$?
assert_eq 2 "$code" "change needs text"
assert_contains "$out" "ruling 2: change needs what to change" "asks for the change"

out=$(bash "$S" 2 "1 keep 1 change: x 2 keep" 2>&1); code=$?
assert_eq 2 "$code" "a ruling answered twice is refused"

bash "$S" 0 "x" >/dev/null 2>&1; assert_eq 2 $? "count must be positive"

out=$(bash "$S" 7 "1-5 keep. 6 yes 7 no"); code=$?
assert_eq 0 "$code" "ranges and yes/no answers"
assert_eq "1 keep
2 keep
3 keep
4 keep
5 keep
6 yes
7 no" "$out" "a range expands, yes/no pass through"

out=$(bash "$S" 3 "1-2 change: use the modal 3 keep"); code=$?
assert_eq 0 "$code" "a range with change text"
assert_eq "1 change use the modal
2 change use the modal
3 keep" "$out" "change text applies to the whole range"

out=$(bash "$S" 3 "2-5 keep 1 keep" 2>&1); code=$?
assert_eq 2 "$code" "a range past the last ruling is refused"
assert_contains "$out" "no ruling 4" "names the first unknown number"

out=$(bash "$S" 2 "1 yes please 2 no" 2>&1); code=$?
assert_eq 2 "$code" "yes/no take no text"

out=$(bash "$S" 5 "5-2 keep" 2>&1); code=$?
assert_eq 2 "$code" "a reversed range is refused"
assert_contains "$out" "bad range 5-2" "names the reversed range"
finish
