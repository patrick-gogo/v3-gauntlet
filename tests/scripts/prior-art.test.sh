#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
P="$ROOT/skills/lap/scripts/prior-art.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# A ticket workspace: state plus the scope PLAN writes.
ws="$tmp/ws/T-10"; mkdir -p "$ws"
printf 'ticket: T-10\nphase: approved\n' > "$ws/state.md"
printf 'allow: app/orders/tax.py\nallow: app/orders/test_*.py\nforbid: app/main.py\n' > "$ws/scope.txt"

# A small vault.
V="$tmp/vault"; mkdir -p "$V/tickets" "$V/learnings"
ov() { # <id> <feature> <component>...
  local id=$1 f=$2; shift 2; mkdir -p "$V/tickets/$id"
  { printf -- '---\nkey: %s\nfeature: %s\ncomponents:\n' "$id" "$f"; for c in "$@"; do printf '  - %s\n' "$c"; done; printf -- '---\n'; } > "$V/tickets/$id/overview.md"
}
ov T-10 orders app/orders
ov T-3 orders app/orders/tax.py
cat > "$V/tickets/T-3/handoff.md" <<'EOF'
# Handoff
## 2026-09-01
### Status
Building.
### Don't repeat
- The tax rounding in app/orders/tax.py is per line, not per order. Ruled in T-1.
### Next move
Ship it.
EOF
cat > "$V/tickets/T-3/review-mine-2026-09-02.md" <<'EOF'
---
key: T-3
---
## TL;DR
1 bug, 1 concern.
## Bugs
### Important: tax.py:12 rounds twice
**Issue:** long body that must not be copied.
## Concerns
- **tax.py:40 no guard** for a zero total. Long tail that must not be copied.
## Nits
- whitespace
EOF
ov T-4 payments app/payments/card.py
cat > "$V/tickets/T-4/investigation-2026-08-01.md" <<'EOF'
## Symptom
Card fails.
## Root cause
The card token expires after 10 minutes.
## Proposed fix (NOT applied)
Refresh it.
EOF
ov T-5 delivery app/delivery
printf '## TL;DR\nNothing about orders.\n' > "$V/tickets/T-5/review-mine-2026-08-03.md"
printf '%s\n' '---' 'type: learning' 'feature: orders' 'components:' '  - app/orders' '---' '# Orders total is computed twice' > "$V/learnings/orders-total.md"
printf '%s\n' '---' 'type: learning' 'feature: delivery' 'components:' '  - app/delivery' '---' '# Delivery note' > "$V/learnings/delivery-note.md"
printf '# Learnings index\n' > "$V/learnings/Learnings.md"
# Inside a broad component of the ticket, but another feature: not prior art.
printf '%s\n' '---' 'type: learning' 'feature: billing' 'components:' '  - app/orders/billing/invoice.py' '---' '# Invoice note about app/orders' > "$V/learnings/invoice-note.md"
ov T-6 reports app/orders/tax.py
cp "$V/tickets/T-3/review-mine-2026-09-02.md" "$V/tickets/T-6/review-mine-2026-09-05.md"

out="$tmp/out"
bash "$P" "$V" "$ws" "$out" >/dev/null; assert_eq 0 $? "writes prior art"
I="$out/prior-art.md"
assert_file "$I" "index written"
idx=$(cat "$I")
assert_contains "$idx" "app/orders/tax.py" "names the search keys"
assert_not_contains "$idx" "app/main.py" "forbid lines are not search keys"
assert_contains "$idx" "T-3" "a ticket sharing a component is found"
assert_not_contains "$idx" "T-5" "an unrelated ticket is not found"
assert_not_contains "$idx" "tickets/T-10/" "the ticket's own folder is skipped"
assert_contains "$idx" "learnings/orders-total.md" "a matching learning is listed"
assert_not_contains "$idx" "delivery-note" "an unrelated learning is not listed"
assert_not_contains "$idx" "invoice-note" "a directory key does not pull in everything inside it"
assert_not_contains "$idx" "T-3-review" "one extract per ticket, the handoff first"

h=$(cat "$out"/*-T-3-handoff.md 2>/dev/null)
assert_contains "$h" "per line, not per order" "the Don't repeat section is copied"
assert_not_contains "$h" "Ship it." "other handoff sections are not copied"
assert_contains "$h" "Source: tickets/T-3/handoff.md" "each extract names its source"
r=$(cat "$out"/*-T-6-review.md 2>/dev/null)
assert_contains "$r" "1 bug, 1 concern." "the review TL;DR is copied"
assert_contains "$r" "rounds twice" "finding titles are copied"
assert_contains "$r" "tax.py:40 no guard" "concern titles are copied"
assert_not_contains "$r" "must not be copied" "finding bodies are not copied"

# The cap holds, newest-scored first, and an empty search says so.
bash "$P" "$V" "$ws" "$tmp/out2" --cap 1 >/dev/null
assert_eq 1 "$(ls "$tmp/out2" | grep -vc '^prior-art.md$')" "--cap limits the extracts"
ws2="$tmp/ws/T-11"; mkdir -p "$ws2"; printf 'ticket: T-11\n' > "$ws2/state.md"; printf 'allow: lib/none.py\n' > "$ws2/scope.txt"
bash "$P" "$V" "$ws2" "$tmp/out3" >/dev/null; assert_eq 0 $? "no match is not an error"
assert_contains "$(cat "$tmp/out3/prior-art.md")" "None found (searched: lib/none.py)" "an empty search says what it searched"

# An investigation is found by a feature match alone and gives its root cause.
ws3="$tmp/ws/T-12"; mkdir -p "$ws3"; printf 'ticket: T-12\n' > "$ws3/state.md"; printf 'allow: app/payments/refund.py\n' > "$ws3/scope.txt"
ov T-12 payments app/payments/refund.py
bash "$P" "$V" "$ws3" "$tmp/out4" >/dev/null
inv=$(cat "$tmp/out4"/*-T-4-investigation.md 2>/dev/null)
assert_contains "$inv" "expires after 10 minutes" "the root cause is copied"
assert_not_contains "$inv" "Refresh it." "the proposed fix is not copied"

bash "$P" "$tmp/nope" "$ws" "$tmp/out5" >/dev/null 2>&1; assert_eq 2 $? "a missing vault is refused"
bash "$P" "$V" "$tmp/nows" "$tmp/out6" >/dev/null 2>&1; assert_eq 2 $? "a missing workspace is refused"
mkdir -p "$tmp/out7"; echo x > "$tmp/out7/keep"
bash "$P" "$V" "$ws" "$tmp/out7" >/dev/null 2>&1; assert_eq 2 $? "a non-empty out folder is refused"
finish
