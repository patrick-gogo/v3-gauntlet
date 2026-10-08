#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
P="$ROOT/skills/lap/scripts/lap-pack.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# A planned ticket workspace with every file PLAN writes.
mkws() { # <dir> <id> <phase>
  mkdir -p "$1"
  printf 'ticket: %s\ntitle: Fix %s total\nphase: %s\nbranch: bugfix/%s-fix\nbase: abc1234\ndepth: standard\ntasks_total: 3\n' "$2" "$2" "$3" "$2" > "$1/state.md"
  for f in ticket.md bar.md context.md design.md plan.md rulings.md scope.txt; do echo "$f of $2" > "$1/$f"; done
  echo "secret log" > "$1/ledger.md"
}
proj="$tmp/proj"; mkdir -p "$proj"
mkws "$tmp/ws/V3-1" V3-1 approved
mkws "$tmp/ws/V3-2" V3-2 approved

out=$(bash "$P" "$proj" lap-20261005-2040 "$tmp/ws/V3-1" "$tmp/ws/V3-2"); code=$?
assert_eq 0 "$code" "packs two planned tickets"
L="$proj/docs/gauntlet/lap-20261005-2040"
assert_file "$L/tickets/V3-1/plan.md" "plan copied"
assert_file "$L/tickets/V3-2/rulings.md" "rulings copied"
assert_file "$L/tickets/V3-1/state.md" "state copied"
assert_eq "plan.md of V3-1" "$(cat "$L/tickets/V3-1/plan.md")" "copied verbatim"
[ -e "$L/tickets/V3-1/ledger.md" ] && _ko "ledger must not be packed" || _ok
assert_eq "id	branch	depth	tasks	title
V3-1	bugfix/V3-1-fix	standard	3	Fix V3-1 total
V3-2	bugfix/V3-2-fix	standard	3	Fix V3-2 total" "$(cat "$L/tickets.tsv")" "manifest in the given order, no planning-time base (the lap has one base)"
assert_file "$L/tools/scoped-tests.sh" "the scoped test lister travels with the lap"
assert_file "$L/tools/gate-select.sh" "the gate picker travels with the lap"
assert_contains "$out" "$L" "prints the lap folder"

# Optional files may be missing; required ones may not.
mkws "$tmp/ws/V3-3" V3-3 approved; rm "$tmp/ws/V3-3/context.md"
bash "$P" "$proj" lap-b "$tmp/ws/V3-3" >/dev/null; assert_eq 0 $? "context.md is optional"
mkws "$tmp/ws/V3-4" V3-4 approved; rm "$tmp/ws/V3-4/plan.md"
out=$(bash "$P" "$proj" lap-c "$tmp/ws/V3-4" 2>&1); code=$?
assert_eq 2 "$code" "a ticket without a plan is refused"
assert_contains "$out" "V3-4: missing plan.md" "names the missing file"
[ -e "$proj/docs/gauntlet/lap-c" ] && _ko "nothing is written when refused" || _ok

mkws "$tmp/ws/V3-5" V3-5 planned
out=$(bash "$P" "$proj" lap-d "$tmp/ws/V3-5" 2>&1); code=$?
assert_eq 2 "$code" "a ticket that is not Planned (phase approved) is refused"
assert_contains "$out" "V3-5: phase planned, not approved" "names the phase"

out=$(bash "$P" "$proj" lap-20261005-2040 "$tmp/ws/V3-1" 2>&1); code=$?
assert_eq 2 "$code" "an existing lap folder is never overwritten"

bash "$P" "$proj" "../evil" "$tmp/ws/V3-1" >/dev/null 2>&1; assert_eq 2 $? "a lap id with a path is refused"
bash "$P" "$proj" lap-e >/dev/null 2>&1; assert_eq 2 $? "at least one ticket is required"
bash "$P" "$tmp/nope" lap-f "$tmp/ws/V3-1" >/dev/null 2>&1; assert_eq 2 $? "the project folder must exist"
[ -e "$L/tickets/V3-1/prior-art" ] && _ko "no prior art without --vault" || _ok

# --vault adds each ticket's prior art and every learning (not the learnings index).
V="$tmp/vault"; mkdir -p "$V/tickets/V3-9" "$V/learnings"
printf '### Don'"'"'t repeat\nscope.txt of V3-1 is not a real path.\n' > "$V/tickets/V3-9/handoff.md"
printf '%s\n' '---' 'type: learning' '---' '# A trap' > "$V/learnings/a-trap.md"
printf '# index\n' > "$V/learnings/Learnings.md"
bash "$P" --vault "$V" "$proj" lap-v "$tmp/ws/V3-1" >/dev/null 2>&1; assert_eq 0 $? "packs with a vault"
assert_file "$proj/docs/gauntlet/lap-v/tickets/V3-1/prior-art/prior-art.md" "prior-art index per ticket"
assert_file "$proj/docs/gauntlet/lap-v/learnings/a-trap.md" "learnings copied"
[ -e "$proj/docs/gauntlet/lap-v/learnings/Learnings.md" ] && _ko "the learnings index is not copied" || _ok
out=$(bash "$P" --vault "$tmp/novault" "$proj" lap-w "$tmp/ws/V3-1" 2>&1); code=$?
assert_eq 2 "$code" "a missing vault is refused"
assert_contains "$out" "no vault" "names the vault problem"
[ -e "$proj/docs/gauntlet/lap-w" ] && _ko "nothing is written for a missing vault" || _ok

# --resume packs an unfinished ticket branch as a bundle the lead can fetch, measured from the lap's base.
g="$tmp/git"; mkdir -p "$g"; (cd "$g" && git init -q . && git config user.email t@example.com && git config user.name t && echo a > a && git add a && git commit -qm base)
GB=$(git -C "$g" rev-parse HEAD)
git -C "$g" checkout -q -b devbox/lap-old/bugfix/V3-1-fix
for i in 1 2; do echo $i > "$g/f$i"; git -C "$g" add -A; git -C "$g" commit -qm "task $i"; done
TIP=$(git -C "$g" rev-parse HEAD); git -C "$g" checkout -q --detach "$GB"
out=$(bash "$P" --resume V3-1=refs/heads/devbox/lap-old/bugfix/V3-1-fix "$g" lap-r "$tmp/ws/V3-1" 2>&1); code=$?
assert_eq 0 "$code" "packs with a resume branch"
RB="$g/docs/gauntlet/lap-r/resume"
assert_file "$RB/V3-1.bundle" "the branch is bundled"
assert_eq "id	ref	tip	commits
V3-1	refs/heads/devbox/lap-old/bugfix/V3-1-fix	$TIP	2" "$(cat "$RB/resume.tsv")" "resume manifest names ref, tip and commit count"
c="$tmp/clone"; git clone -q "$g" "$c" 2>/dev/null; git -C "$c" checkout -q --detach "$GB" 2>/dev/null
git -C "$c" fetch -q "$RB/V3-1.bundle" "refs/heads/devbox/lap-old/bugfix/V3-1-fix:refs/heads/devbox/lap-r/bugfix/V3-1-fix"
assert_eq "$TIP" "$(git -C "$c" rev-parse devbox/lap-r/bugfix/V3-1-fix)" "the lead can fetch the bundle into its ticket branch"

git -C "$g" checkout -q -b elsewhere "$GB"; echo z > "$g/z"; git -C "$g" add z; git -C "$g" commit -qm other; git -C "$g" checkout -q --detach HEAD
out=$(bash "$P" --resume V3-1=refs/heads/devbox/lap-old/bugfix/V3-1-fix "$g" lap-s "$tmp/ws/V3-1" 2>&1); code=$?
assert_eq 2 "$code" "a resume branch not built on the lap's base is refused"
assert_contains "$out" "V3-1: resume branch is not built on the lap base" "names why"
[ -e "$g/docs/gauntlet/lap-s" ] && _ko "nothing written when a resume is refused" || _ok
out=$(bash "$P" --resume V3-7=refs/heads/nope "$proj" lap-t "$tmp/ws/V3-1" 2>&1); code=$?
assert_eq 2 "$code" "a resume for a ticket not in the lap, or an unknown ref, is refused"
finish
